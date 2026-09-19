import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_auth/asm_auth.dart';

import '../ride_requests/ride_request_history.dart'
    show ApiPassengerRideRequestHistoryRepository;
import 'ghana_network_resilience.dart';

export '../booking/booking_submission.dart' show PassengerRideRequestIdempotencyKey;

/// Mirrors the backend's PASSENGER_CANCELLATION_REASON_CHOICES allowlist
/// exactly (backend/dashboard/api_rides.py), shared by both the
/// RideRequest-cancel and Trip-cancel endpoints.
enum PassengerCancellationReason {
  wrongAddress,
  driverTooFarOrDelayed,
  noLongerNeeded,
  foundAnotherWay,
  priceOrFareConcern,
  other,
}

extension PassengerCancellationReasonDetails on PassengerCancellationReason {
  String get code => switch (this) {
    PassengerCancellationReason.wrongAddress => 'wrong_address',
    PassengerCancellationReason.driverTooFarOrDelayed =>
      'driver_too_far_or_delayed',
    PassengerCancellationReason.noLongerNeeded => 'no_longer_needed',
    PassengerCancellationReason.foundAnotherWay => 'found_another_way',
    PassengerCancellationReason.priceOrFareConcern => 'price_or_fare_concern',
    PassengerCancellationReason.other => 'other',
  };

  String get label => switch (this) {
    PassengerCancellationReason.wrongAddress => 'Wrong pickup address',
    PassengerCancellationReason.driverTooFarOrDelayed =>
      'Driver too far or delayed',
    PassengerCancellationReason.noLongerNeeded => 'No longer needed',
    PassengerCancellationReason.foundAnotherWay => 'Found another way',
    PassengerCancellationReason.priceOrFareConcern => 'Concerned about the fare',
    PassengerCancellationReason.other => 'Other',
  };

  bool get requiresNote => this == PassengerCancellationReason.other;
}

const passengerCancellationReasonNoteLimit = 500;

final class PassengerCancellationResult {
  const PassengerCancellationResult({
    required this.reference,
    required this.status,
    required this.duplicate,
  });

  final String reference;
  final String status;
  final bool duplicate;

  static PassengerCancellationResult fromJson(
    Object? json, {
    required String referenceKey,
    required String statusKey,
  }) {
    if (json is! Map) {
      throw const FormatException(
        'Cancellation response was not a JSON object.',
      );
    }

    final normalized = json.map((key, value) => MapEntry('$key', value));
    final reference = normalized[referenceKey];
    final status = normalized[statusKey];
    final duplicate = normalized['duplicate'];

    if (reference is! String ||
        reference.trim().isEmpty ||
        status is! String ||
        status.trim().isEmpty ||
        duplicate is! bool) {
      throw const FormatException('Cancellation response was incomplete.');
    }

    return PassengerCancellationResult(
      reference: reference.trim(),
      status: status.trim(),
      duplicate: duplicate,
    );
  }
}

enum PassengerCancellationFailureType {
  signInRequired,
  passengerRequired,
  notEligible,
  conflict,
  clientFailure,
  temporarilyUnavailable,
  badResponse,
}

final class PassengerCancellationException implements Exception {
  const PassengerCancellationException({
    required this.type,
    required this.message,
  });

  const PassengerCancellationException.signInRequired()
    : type = PassengerCancellationFailureType.signInRequired,
      message = signInRequiredMessage;

  const PassengerCancellationException.notEligible()
    : type = PassengerCancellationFailureType.notEligible,
      message = notEligibleMessage;

  const PassengerCancellationException.connectionNotConfigured()
    : type = PassengerCancellationFailureType.badResponse,
      message = AsmApiClient.connectionNotConfiguredMessage;

  const PassengerCancellationException.network()
    : type = PassengerCancellationFailureType.temporarilyUnavailable,
      message = networkErrorMessage;

  const PassengerCancellationException.serverUnavailable()
    : type = PassengerCancellationFailureType.temporarilyUnavailable,
      message = serverUnavailableMessage;

  const PassengerCancellationException.unknown()
    : type = PassengerCancellationFailureType.badResponse,
      message = unknownErrorMessage;

  static const signInRequiredMessage = 'Please sign in to cancel this trip.';
  static const passengerRequiredMessage = 'Passenger account required.';
  static const networkErrorMessage =
      'Cannot reach the server. Check your connection and try again.';
  static const serverUnavailableMessage =
      'Service is temporarily unavailable. Please try again later.';
  static const conflictMessage =
      'This cancellation was already used with different details. Please review and try again.';
  // Intentionally does not include a "contact support" clause in the same
  // sentence - a separate, secondary affordance carries that instead.
  static const notEligibleMessage =
      'This trip has already started and can no longer be cancelled here.';
  static const unknownErrorMessage = 'Something went wrong. Please try again.';

  final PassengerCancellationFailureType type;
  final String message;

  bool get isNotEligible => type == PassengerCancellationFailureType.notEligible;

  factory PassengerCancellationException.fromAuthError(AuthException? error) {
    final cause = error?.cause;
    if (cause is AsmApiException) {
      if (cause.type == AsmApiExceptionType.network ||
          cause.type == AsmApiExceptionType.timeout) {
        return const PassengerCancellationException.network();
      }

      if (cause.statusCode == 503 || cause.type == AsmApiExceptionType.server) {
        return const PassengerCancellationException.serverUnavailable();
      }
    }

    return const PassengerCancellationException.signInRequired();
  }

  factory PassengerCancellationException.fromResponse(
    ApiResponse<PassengerCancellationResult> response,
  ) {
    final statusCode = response.statusCode;
    final apiError = response.error;

    if (response.isClientException) {
      if (apiError?.type == AsmApiExceptionType.network ||
          apiError?.type == AsmApiExceptionType.timeout) {
        return const PassengerCancellationException.network();
      }

      if (statusCode == 503 || apiError?.type == AsmApiExceptionType.server) {
        return const PassengerCancellationException.serverUnavailable();
      }

      return const PassengerCancellationException.unknown();
    }

    if (statusCode == 401) {
      return const PassengerCancellationException.signInRequired();
    }

    if (statusCode == 403) {
      return const PassengerCancellationException(
        type: PassengerCancellationFailureType.passengerRequired,
        message: passengerRequiredMessage,
      );
    }

    if (statusCode == 409) {
      return const PassengerCancellationException(
        type: PassengerCancellationFailureType.conflict,
        message: conflictMessage,
      );
    }

    if (statusCode == 503 || apiError?.type == AsmApiExceptionType.server) {
      return const PassengerCancellationException.serverUnavailable();
    }

    if (statusCode == 400) {
      final code = _safeCodeFromCause(apiError?.cause);
      if (code == 'cancellation_not_eligible') {
        return const PassengerCancellationException.notEligible();
      }

      final detail = _safeDetailFromCause(apiError?.cause);
      return PassengerCancellationException(
        type: PassengerCancellationFailureType.clientFailure,
        message: detail ?? unknownErrorMessage,
      );
    }

    return const PassengerCancellationException.unknown();
  }

  @override
  String toString() => message;

  static String? _safeCodeFromCause(Object? cause) {
    if (cause is! Map) {
      return null;
    }

    final code = cause['code'];
    return code is String ? code.trim() : null;
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

abstract interface class PassengerCancellationGateway {
  Future<PassengerCancellationResult> cancelRideRequest({
    required String requestReference,
    required PassengerCancellationReason reason,
    String? reasonNote,
    required String idempotencyKey,
  });

  Future<PassengerCancellationResult> cancelTripBooking({
    required String tripReference,
    required PassengerCancellationReason reason,
    String? reasonNote,
    required String idempotencyKey,
  });
}

final class ApiPassengerCancellationGateway
    implements PassengerCancellationGateway {
  const ApiPassengerCancellationGateway(
    this.client, {
    this.tokenStore,
    this.authService,
    this.connectionConfigured = true,
  });

  factory ApiPassengerCancellationGateway.withDefaultClient({
    AuthTokenStore? tokenStore,
    String? baseUrl,
  }) {
    final store = tokenStore ?? SecureAuthTokenStore();
    final connectionConfigured = AsmApiBaseUrl.isUsable(baseUrl);
    final resolvedBaseUrl = connectionConfigured
        ? baseUrl!.trim()
        : 'http://127.0.0.1:8000';

    return ApiPassengerCancellationGateway(
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
  Future<PassengerCancellationResult> cancelRideRequest({
    required String requestReference,
    required PassengerCancellationReason reason,
    String? reasonNote,
    required String idempotencyKey,
  }) {
    final normalizedReference = requestReference.trim();
    return _cancel(
      path: '${ApiPassengerRideRequestHistoryRepository.listPath}'
          '${Uri.encodeComponent(normalizedReference)}/cancel/',
      reason: reason,
      reasonNote: reasonNote,
      idempotencyKey: idempotencyKey,
      referenceKey: 'request_reference',
      statusKey: 'request_status',
    );
  }

  @override
  Future<PassengerCancellationResult> cancelTripBooking({
    required String tripReference,
    required PassengerCancellationReason reason,
    String? reasonNote,
    required String idempotencyKey,
  }) {
    final normalizedReference = tripReference.trim();
    return _cancel(
      path: '${ApiPassengerRideRequestHistoryRepository.tripPath}'
          '${Uri.encodeComponent(normalizedReference)}/cancel/',
      reason: reason,
      reasonNote: reasonNote,
      idempotencyKey: idempotencyKey,
      referenceKey: 'trip_reference',
      statusKey: 'trip_status',
    );
  }

  Future<PassengerCancellationResult> _cancel({
    required String path,
    required PassengerCancellationReason reason,
    required String? reasonNote,
    required String idempotencyKey,
    required String referenceKey,
    required String statusKey,
  }) async {
    final normalizedKey = idempotencyKey.trim();
    final normalizedNote = reasonNote?.trim() ?? '';

    if (normalizedKey.isEmpty) {
      throw const PassengerCancellationException(
        type: PassengerCancellationFailureType.badResponse,
        message: 'The cancellation could not be prepared safely.',
      );
    }

    if (reason.requiresNote && normalizedNote.isEmpty) {
      throw const PassengerCancellationException(
        type: PassengerCancellationFailureType.badResponse,
        message: 'A note is required when cancelling for another reason.',
      );
    }

    if (reason.requiresNote &&
        normalizedNote.length > passengerCancellationReasonNoteLimit) {
      throw const PassengerCancellationException(
        type: PassengerCancellationFailureType.badResponse,
        message:
            'The note must be at most '
            '$passengerCancellationReasonNoteLimit characters.',
      );
    }

    final storedAccessToken = (await tokenStore?.readAccessToken())?.trim();
    if (tokenStore != null &&
        (storedAccessToken == null || storedAccessToken.isEmpty)) {
      throw const PassengerCancellationException.signInRequired();
    }

    if (!connectionConfigured) {
      throw const PassengerCancellationException.connectionNotConfigured();
    }

    final data = <String, Object?>{
      'reason': reason.code,
      if (reason.requiresNote) 'reason_note': normalizedNote,
    };

    final response = await _post(
      path,
      data: data,
      idempotencyKey: normalizedKey,
      referenceKey: referenceKey,
      statusKey: statusKey,
    );

    if (response.isSuccess && response.data != null) {
      return response.data!;
    }

    if (response.statusCode == 401 && tokenStore != null) {
      final refreshError = await _refreshAccessToken();
      if (refreshError != null) {
        throw refreshError;
      }

      final retryResponse = await _post(
        path,
        data: data,
        idempotencyKey: normalizedKey,
        referenceKey: referenceKey,
        statusKey: statusKey,
      );

      if (retryResponse.isSuccess && retryResponse.data != null) {
        return retryResponse.data!;
      }

      if (retryResponse.statusCode == 401) {
        await tokenStore?.clearTokens();
      }

      throw PassengerCancellationException.fromResponse(retryResponse);
    }

    throw PassengerCancellationException.fromResponse(response);
  }

  Future<ApiResponse<PassengerCancellationResult>> _post(
    String path, {
    required Object? data,
    required String idempotencyKey,
    required String referenceKey,
    required String statusKey,
  }) {
    return client.post<PassengerCancellationResult>(
      path,
      data: data,
      headers: <String, String>{'Idempotency-Key': idempotencyKey},
      decoder: (json) => PassengerCancellationResult.fromJson(
        json,
        referenceKey: referenceKey,
        statusKey: statusKey,
      ),
    );
  }

  Future<PassengerCancellationException?> _refreshAccessToken() async {
    final storedRefreshToken = (await tokenStore?.readRefreshToken())?.trim();
    if (storedRefreshToken == null || storedRefreshToken.isEmpty) {
      await tokenStore?.clearTokens();
      return const PassengerCancellationException.signInRequired();
    }

    final service = authService;
    if (service == null) {
      await tokenStore?.clearTokens();
      return const PassengerCancellationException.signInRequired();
    }

    try {
      final state = await service.refresh();
      if (state.isAuthenticated) {
        return null;
      }

      await tokenStore?.clearTokens();
      return PassengerCancellationException.fromAuthError(state.error);
    } catch (_) {
      await tokenStore?.clearTokens();
      return const PassengerCancellationException.unknown();
    }
  }
}

class _AuthTokenProvider implements TokenProvider {
  const _AuthTokenProvider(this.tokenStore);

  final AuthTokenStore tokenStore;

  @override
  Future<String?> getAccessToken() => tokenStore.readAccessToken();
}
