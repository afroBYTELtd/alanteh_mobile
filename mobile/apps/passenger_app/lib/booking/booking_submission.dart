import 'dart:math';

import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_auth/asm_auth.dart';

import 'booking_draft.dart';

enum BookingSubmissionStatus { idle, submitting, success, failure }

abstract interface class PassengerRideRequestSubmitter {
  Future<PassengerRideRequestResult> submit(
    BookingDraft draft, {
    required String idempotencyKey,
  });
}

final RegExp _passengerRideRequestReferencePattern = RegExp(
  r'^RR-APP-[A-Z0-9]+$',
);

bool hasValidPassengerRideRequestReceipt(PassengerRideRequestResult result) {
  final reference = result.requestReference?.trim();
  return reference != null &&
      _passengerRideRequestReferencePattern.hasMatch(reference) &&
      result.status.trim().isNotEmpty &&
      result.message.trim().isNotEmpty;
}

class ApiPassengerRideRequestSubmitter
    implements PassengerRideRequestSubmitter {
  const ApiPassengerRideRequestSubmitter(
    this.client, {
    this.tokenStore,
    this.authService,
    this.connectionConfigured = true,
  });

  factory ApiPassengerRideRequestSubmitter.withDefaultClient({
    AuthTokenStore? tokenStore,
    String? baseUrl,
  }) {
    final store = tokenStore ?? SecureAuthTokenStore();
    final connectionConfigured = AsmApiBaseUrl.isUsable(baseUrl);
    final resolvedBaseUrl = connectionConfigured
        ? baseUrl!.trim()
        : 'http://127.0.0.1:8000';

    return ApiPassengerRideRequestSubmitter(
      AsmApiClient(
        baseUrl: resolvedBaseUrl,
        tokenProvider: _AuthTokenProvider(store),
      ),
      tokenStore: store,
      authService: connectionConfigured
          ? AuthService.withApiClient(
              client: AsmApiClient(baseUrl: resolvedBaseUrl),
              tokenStore: store,
            )
          : null,
      connectionConfigured: connectionConfigured,
    );
  }

  final AsmApiClient client;
  final AuthTokenStore? tokenStore;
  final AuthService? authService;
  final bool connectionConfigured;

  @override
  Future<PassengerRideRequestResult> submit(
    BookingDraft draft, {
    required String idempotencyKey,
  }) async {
    final storedAccessToken = (await tokenStore?.readAccessToken())?.trim();
    if (tokenStore != null &&
        (storedAccessToken == null || storedAccessToken.isEmpty)) {
      throw const PassengerRideRequestSubmissionException.signInRequired();
    }

    if (!connectionConfigured) {
      throw const PassengerRideRequestSubmissionException.connectionNotConfigured();
    }

    final response = await _submitRideRequest(
      draft,
      idempotencyKey: idempotencyKey,
    );

    if (response.isSuccess && response.data != null) {
      final result = response.data!;
      if (hasValidPassengerRideRequestReceipt(result)) {
        return result;
      }
      throw const PassengerRideRequestSubmissionException.unknown();
    }

    if (response.statusCode == 401 && tokenStore != null) {
      final refreshError = await _refreshAccessToken();
      if (refreshError != null) {
        throw refreshError;
      }

      final retryResponse = await _submitRideRequest(
        draft,
        idempotencyKey: idempotencyKey,
      );

      if (retryResponse.isSuccess && retryResponse.data != null) {
        final result = retryResponse.data!;
        if (hasValidPassengerRideRequestReceipt(result)) {
          return result;
        }
        throw const PassengerRideRequestSubmissionException.unknown();
      }

      if (retryResponse.statusCode == 401) {
        await tokenStore?.clearTokens();
      }

      throw PassengerRideRequestSubmissionException.fromResponse(retryResponse);
    }

    throw PassengerRideRequestSubmissionException.fromResponse(response);
  }

  Future<ApiResponse<PassengerRideRequestResult>> _submitRideRequest(
    BookingDraft draft, {
    required String idempotencyKey,
  }) {
    return client.submitPassengerRideRequest(
      PassengerRideRequestSubmission(
        idempotencyKey: idempotencyKey,
        pickupLocation: draft.pickupDescription.value,
        destination: draft.destinationDescription.value,
        passengerCount: draft.passengerCount.value,
        assistanceNote: draft.assistanceNote?.value,
      ),
    );
  }

  Future<PassengerRideRequestSubmissionException?> _refreshAccessToken() async {
    final storedRefreshToken = (await tokenStore?.readRefreshToken())?.trim();
    if (storedRefreshToken == null || storedRefreshToken.isEmpty) {
      await tokenStore?.clearTokens();
      return const PassengerRideRequestSubmissionException.signInRequired();
    }

    final service = authService;
    if (service == null) {
      await tokenStore?.clearTokens();
      return const PassengerRideRequestSubmissionException.signInRequired();
    }

    try {
      final state = await service.refresh();
      if (state.isAuthenticated) {
        return null;
      }

      await tokenStore?.clearTokens();
      return PassengerRideRequestSubmissionException.fromAuthError(state.error);
    } catch (_) {
      await tokenStore?.clearTokens();
      return const PassengerRideRequestSubmissionException.unknown();
    }
  }
}

class PassengerRideRequestSubmissionException implements Exception {
  const PassengerRideRequestSubmissionException(
    this.message, {
    this.requiresSignIn = false,
  });

  const PassengerRideRequestSubmissionException.signInRequired()
    : message = signInRequiredMessage,
      requiresSignIn = true;

  const PassengerRideRequestSubmissionException.connectionNotConfigured()
    : message = AsmApiClient.connectionNotConfiguredMessage,
      requiresSignIn = false;

  const PassengerRideRequestSubmissionException.network()
    : message = networkErrorMessage,
      requiresSignIn = false;

  const PassengerRideRequestSubmissionException.serverUnavailable()
    : message = serverUnavailableMessage,
      requiresSignIn = false;

  const PassengerRideRequestSubmissionException.unknown()
    : message = unknownErrorMessage,
      requiresSignIn = false;

  static const signInRequiredMessage = 'Please sign in to request a ride.';
  static const networkErrorMessage =
      'Cannot reach the server. Check your connection and try again.';
  static const serverUnavailableMessage =
      'Service is temporarily unavailable. Please try again later.';
  static const passengerRequiredMessage = 'Passenger account required.';
  static const idempotencyConflictMessage =
      'This ride request was already used with different details. Please review and try again.';
  static const unknownErrorMessage = 'Something went wrong. Please try again.';

  final String message;
  final bool requiresSignIn;

  factory PassengerRideRequestSubmissionException.fromAuthError(
    AuthException? error,
  ) {
    final cause = error?.cause;
    if (cause is AsmApiException) {
      if (cause.type == AsmApiExceptionType.network ||
          cause.type == AsmApiExceptionType.timeout) {
        return const PassengerRideRequestSubmissionException.network();
      }

      if (cause.statusCode == 503 || cause.type == AsmApiExceptionType.server) {
        return const PassengerRideRequestSubmissionException.serverUnavailable();
      }
    }

    return const PassengerRideRequestSubmissionException.signInRequired();
  }

  factory PassengerRideRequestSubmissionException.fromResponse(
    ApiResponse<PassengerRideRequestResult> response,
  ) {
    final statusCode = response.statusCode;
    final apiError = response.error;

    if (response.isClientException) {
      if (apiError?.type == AsmApiExceptionType.network ||
          apiError?.type == AsmApiExceptionType.timeout) {
        return const PassengerRideRequestSubmissionException.network();
      }

      if (statusCode == 503 || apiError?.type == AsmApiExceptionType.server) {
        return const PassengerRideRequestSubmissionException.serverUnavailable();
      }

      return const PassengerRideRequestSubmissionException.unknown();
    }

    if (statusCode == 401) {
      return const PassengerRideRequestSubmissionException.signInRequired();
    }

    if (statusCode == 403) {
      return const PassengerRideRequestSubmissionException(
        passengerRequiredMessage,
      );
    }

    if (statusCode == 409) {
      return const PassengerRideRequestSubmissionException(
        idempotencyConflictMessage,
      );
    }

    if (statusCode == 503 || apiError?.type == AsmApiExceptionType.server) {
      return const PassengerRideRequestSubmissionException.serverUnavailable();
    }

    if (statusCode == 400) {
      final detail = _safeDetailFromCause(apiError?.cause);
      return PassengerRideRequestSubmissionException(
        detail ?? unknownErrorMessage,
      );
    }

    return const PassengerRideRequestSubmissionException.unknown();
  }

  @override
  String toString() => message;

  static String? _safeDetailFromCause(Object? cause) {
    if (cause is! Map) {
      return null;
    }

    final detail = cause['detail'];
    if (detail is! String) {
      return null;
    }

    final normalized = detail.trim();
    if (normalized.isEmpty || normalized.length > 160) {
      return null;
    }

    final lower = normalized.toLowerCase();
    final blockedFragments = <String>[
      'exception',
      'stacktrace',
      'traceback',
      'socketexception',
      'formatexception',
      'clientexception',
      'django',
      '<html',
    ];

    for (final fragment in blockedFragments) {
      if (lower.contains(fragment)) {
        return null;
      }
    }

    return normalized;
  }
}

class PassengerRideRequestIdempotencyKey {
  PassengerRideRequestIdempotencyKey._();

  static final Random _random = Random.secure();

  static String generate() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    String hex(int value) => value.toRadixString(16).padLeft(2, '0');
    final parts = <String>[
      bytes.sublist(0, 4).map(hex).join(),
      bytes.sublist(4, 6).map(hex).join(),
      bytes.sublist(6, 8).map(hex).join(),
      bytes.sublist(8, 10).map(hex).join(),
      bytes.sublist(10, 16).map(hex).join(),
    ];

    return 'APP-${parts.join('-')}';
  }
}

class _AuthTokenProvider implements TokenProvider {
  const _AuthTokenProvider(this.tokenStore);

  final AuthTokenStore tokenStore;

  @override
  Future<String?> getAccessToken() => tokenStore.readAccessToken();
}
