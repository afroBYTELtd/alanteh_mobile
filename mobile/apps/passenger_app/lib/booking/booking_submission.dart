import 'dart:math';

import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_auth/asm_auth.dart';

import '../network/ghana_network_resilience.dart';
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
      GhanaResilientApiClient(
        baseUrl: resolvedBaseUrl,
        tokenProvider: _AuthTokenProvider(store),
      ),
      tokenStore: store,
      authService: connectionConfigured
          ? AuthService.withApiClient(
              client: GhanaResilientApiClient(baseUrl: resolvedBaseUrl),
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
        pickupLatitude: draft.pickupLatitude,
        pickupLongitude: draft.pickupLongitude,
        destination: draft.destinationDescription.value,
        passengerCount: draft.passengerCount.value,
        assistanceNote: draft.assistanceNote?.value,
        passengerNote: draft.passengerNote,
        requestedPickupTime: draft.requestedPickupTime,
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
    this.code,
  });

  const PassengerRideRequestSubmissionException.signInRequired()
    : message = signInRequiredMessage,
      requiresSignIn = true,
      code = null;

  const PassengerRideRequestSubmissionException.connectionNotConfigured()
    : message = AsmApiClient.connectionNotConfiguredMessage,
      requiresSignIn = false,
      code = null;

  const PassengerRideRequestSubmissionException.network()
    : message = networkErrorMessage,
      requiresSignIn = false,
      code = null;

  const PassengerRideRequestSubmissionException.serverUnavailable()
    : message = serverUnavailableMessage,
      requiresSignIn = false,
      code = null;

  const PassengerRideRequestSubmissionException.unknown()
    : message = unknownErrorMessage,
      requiresSignIn = false,
      code = null;

  static const signInRequiredMessage = 'Please sign in to request a ride.';
  static const networkErrorMessage =
      'Cannot reach the server. Check your connection and try again.';
  static const serverUnavailableMessage =
      'Service is temporarily unavailable. Please try again later.';
  static const passengerRequiredMessage = 'Passenger account required.';
  static const idempotencyConflictMessage =
      'This ride request was already used with different details. Please review and try again.';
  static const unknownErrorMessage = 'Something went wrong. Please try again.';

  // Scheduled-ride errors. The backend's own detail is shown where it is
  // written for passengers; these are the fallbacks.
  static const pickupTimeUnreadableMessage =
      "We couldn't read that pickup time. Please choose it again.";
  static const pickupTooSoonMessage =
      "Scheduled rides need at least an hour's notice. Pick a later time, "
      'or choose Now.';
  static const pickupTooFarMessage =
      'You can schedule up to 7 days ahead. Pick an earlier date.';
  static const slotFullMessage =
      'That time is fully booked. Try a time at least an hour earlier or '
      'later.';
  static const scheduledRideLimitMessage =
      'You already have 3 upcoming scheduled rides.';
  static const pickupTimeRequiredMessage = 'Choose a pickup time.';
  static const pickupNotConfirmedMessage =
      "We couldn't confirm your pickup time. Your request may have been "
      'booked for now. Check it in My Ride Requests.';

  static const pickupInvalidCode = 'requested_pickup_time_invalid';
  static const pickupTimezoneCode = 'requested_pickup_time_timezone_required';
  static const pickupTooSoonCode = 'requested_pickup_time_too_soon';
  static const pickupTooFarCode = 'requested_pickup_time_too_far';
  static const slotFullCode = 'scheduled_slot_full';
  static const scheduledRideLimitCode = 'scheduled_ride_limit_reached';

  final String message;
  final bool requiresSignIn;

  /// The backend's error code, when it sent one (scheduled-ride errors).
  final String? code;

  bool get isScheduledPickupError => code != null;

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

    // Branch on the backend's code before the status: every 409 used to be
    // an idempotency conflict, but capacity limits are 409s too.
    final scheduledError = _scheduledPickupError(apiError?.cause);
    if (scheduledError != null) {
      return scheduledError;
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

  static PassengerRideRequestSubmissionException? _scheduledPickupError(
    Object? cause,
  ) {
    if (cause is! Map) {
      return null;
    }
    final code = cause['code'];
    if (code is! String) {
      return null;
    }
    final detail = _safeDetailFromCause(cause);
    final message = switch (code) {
      pickupInvalidCode || pickupTimezoneCode => pickupTimeUnreadableMessage,
      pickupTooSoonCode => detail ?? pickupTooSoonMessage,
      pickupTooFarCode => detail ?? pickupTooFarMessage,
      slotFullCode => detail ?? slotFullMessage,
      scheduledRideLimitCode => detail ?? scheduledRideLimitMessage,
      _ => null,
    };
    if (message == null) {
      return null;
    }
    return PassengerRideRequestSubmissionException(message, code: code);
  }

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
