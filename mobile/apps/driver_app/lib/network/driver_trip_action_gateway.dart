import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_auth/asm_auth.dart';

enum DriverTripAction {
  arrivedPickup,
  startTrip,
  completeTrip;

  String get eventType {
    return switch (this) {
      DriverTripAction.arrivedPickup => 'arrived-pickup',
      DriverTripAction.startTrip => 'start-trip',
      DriverTripAction.completeTrip => 'complete-trip',
    };
  }

  String get expectedStatus {
    return switch (this) {
      DriverTripAction.arrivedPickup => 'arrived_at_pickup',
      DriverTripAction.startTrip => 'in_progress',
      DriverTripAction.completeTrip => 'completed_pending_review',
    };
  }

  String endpointPath(String tripReference) {
    final normalizedReference = tripReference.trim();
    if (normalizedReference.isEmpty) {
      throw ArgumentError.value(
        tripReference,
        'tripReference',
        'must not be blank',
      );
    }

    return '/api/driver/trips/'
        '${Uri.encodeComponent(normalizedReference)}/'
        'actions/$eventType/';
  }

  static DriverTripAction fromEventIdentity(String identity) {
    final normalizedIdentity = identity.trim();

    for (final action in DriverTripAction.values) {
      if (normalizedIdentity == action.eventType ||
          normalizedIdentity.endsWith('/actions/${action.eventType}/')) {
        return action;
      }
    }

    throw ArgumentError.value(
      identity,
      'identity',
      'is not an accepted Driver trip action identity',
    );
  }

  static DriverTripAction fromEventType(String eventType) {
    return fromEventIdentity(eventType);
  }
}

enum DriverTokenRefreshOutcome {
  refreshed,
  sessionExpired,
  temporarilyUnavailable,
}

typedef DriverAccessTokenRefresh = Future<DriverTokenRefreshOutcome> Function();

abstract interface class DriverTripActionApiGateway {
  Future<ApiResponse<T>> post<T>(
    String path, {
    Object? data,
    Map<String, String>? headers,
    JsonDecoder<T>? decoder,
  });
}

final class AsmDriverTripActionApiGateway
    implements DriverTripActionApiGateway {
  const AsmDriverTripActionApiGateway(this.client);

  final AsmApiClient client;

  @override
  Future<ApiResponse<T>> post<T>(
    String path, {
    Object? data,
    Map<String, String>? headers,
    JsonDecoder<T>? decoder,
  }) {
    return client.post<T>(path, data: data, headers: headers, decoder: decoder);
  }
}

final class DriverTripActionReceipt {
  const DriverTripActionReceipt({
    required this.tripReference,
    required this.status,
    required this.message,
    required this.duplicate,
  });

  factory DriverTripActionReceipt.fromJson(Object? json) {
    if (json is! Map) {
      throw const FormatException(
        'Driver trip action response was not a JSON object.',
      );
    }

    final normalized = json.map(
      (key, value) => MapEntry(key.toString(), value),
    );
    final tripReference = normalized['trip_reference'];
    final status = normalized['status'];
    final message = normalized['message'];
    final duplicate = normalized['duplicate'];

    if (tripReference is! String ||
        tripReference.trim().isEmpty ||
        status is! String ||
        status.trim().isEmpty ||
        message is! String ||
        message.trim().isEmpty ||
        duplicate is! bool) {
      throw const FormatException(
        'Driver trip action response was incomplete.',
      );
    }

    return DriverTripActionReceipt(
      tripReference: tripReference.trim(),
      status: status.trim(),
      message: message.trim(),
      duplicate: duplicate,
    );
  }

  final String tripReference;
  final String status;
  final String message;
  final bool duplicate;

  bool confirms({
    required String expectedTripReference,
    required DriverTripAction action,
    required int? statusCode,
  }) {
    final validStatusCode =
        (statusCode == 201 && !duplicate) || (statusCode == 200 && duplicate);
    return validStatusCode &&
        tripReference == expectedTripReference &&
        status == action.expectedStatus;
  }
}

enum DriverTripActionFailureType {
  signInRequired,
  invalidTransition,
  forbidden,
  notFound,
  idempotencyConflict,
  rateLimited,
  temporarilyUnavailable,
  badResponse,
}

final class DriverTripActionException implements Exception {
  const DriverTripActionException({required this.type, required this.message});

  final DriverTripActionFailureType type;
  final String message;

  bool get requiresSignIn => type == DriverTripActionFailureType.signInRequired;

  bool get retryable =>
      type == DriverTripActionFailureType.temporarilyUnavailable ||
      type == DriverTripActionFailureType.rateLimited;

  @override
  String toString() => message;
}

abstract interface class DriverTripActionGateway {
  Future<DriverTripActionReceipt> submit({
    required DriverTripAction action,
    required String tripReference,
    required String idempotencyKey,
    Map<String, Object?> body = const <String, Object?>{},
  });
}

final class ApiDriverTripActionGateway implements DriverTripActionGateway {
  const ApiDriverTripActionGateway({
    required this.apiGateway,
    required this.tokenStore,
    this.refreshAccessToken,
    this.connectionConfigured = true,
  });

  final DriverTripActionApiGateway apiGateway;
  final AuthTokenStore tokenStore;
  final DriverAccessTokenRefresh? refreshAccessToken;
  final bool connectionConfigured;

  @override
  Future<DriverTripActionReceipt> submit({
    required DriverTripAction action,
    required String tripReference,
    required String idempotencyKey,
    Map<String, Object?> body = const <String, Object?>{},
  }) async {
    final normalizedReference = tripReference.trim();
    final normalizedKey = idempotencyKey.trim();

    if (normalizedReference.isEmpty || normalizedKey.isEmpty) {
      throw const DriverTripActionException(
        type: DriverTripActionFailureType.badResponse,
        message: 'The trip action could not be prepared safely.',
      );
    }

    if (!connectionConfigured) {
      throw const DriverTripActionException(
        type: DriverTripActionFailureType.badResponse,
        message: AsmApiClient.connectionNotConfiguredMessage,
      );
    }

    final accessToken = (await tokenStore.readAccessToken())?.trim();
    if (accessToken == null || accessToken.isEmpty) {
      throw const DriverTripActionException(
        type: DriverTripActionFailureType.signInRequired,
        message: 'Session expired. Please sign in again to continue.',
      );
    }

    final firstResponse = await _post(
      action: action,
      tripReference: normalizedReference,
      idempotencyKey: normalizedKey,
      accessToken: accessToken,
      body: const <String, Object?>{},
    );

    final firstReceipt = _validatedReceipt(
      response: firstResponse,
      action: action,
      tripReference: normalizedReference,
    );
    if (firstReceipt != null) {
      return firstReceipt;
    }

    if (firstResponse.statusCode == 401) {
      final refresh = refreshAccessToken;
      if (refresh == null) {
        throw const DriverTripActionException(
          type: DriverTripActionFailureType.signInRequired,
          message: 'Session expired. Please sign in again to continue.',
        );
      }

      final outcome = await refresh();
      switch (outcome) {
        case DriverTokenRefreshOutcome.refreshed:
          final refreshedAccessToken = (await tokenStore.readAccessToken())
              ?.trim();
          if (refreshedAccessToken == null || refreshedAccessToken.isEmpty) {
            throw const DriverTripActionException(
              type: DriverTripActionFailureType.signInRequired,
              message: 'Session expired. Please sign in again to continue.',
            );
          }

          final retryResponse = await _post(
            action: action,
            tripReference: normalizedReference,
            idempotencyKey: normalizedKey,
            accessToken: refreshedAccessToken,
            body: const <String, Object?>{},
          );
          final retryReceipt = _validatedReceipt(
            response: retryResponse,
            action: action,
            tripReference: normalizedReference,
          );
          if (retryReceipt != null) {
            return retryReceipt;
          }
          throw _exceptionFromResponse(retryResponse);
        case DriverTokenRefreshOutcome.sessionExpired:
          throw const DriverTripActionException(
            type: DriverTripActionFailureType.signInRequired,
            message: 'Session expired. Please sign in again to continue.',
          );
        case DriverTokenRefreshOutcome.temporarilyUnavailable:
          throw const DriverTripActionException(
            type: DriverTripActionFailureType.temporarilyUnavailable,
            message:
                'Cannot confirm this action. Check your connection and try again.',
          );
      }
    }

    throw _exceptionFromResponse(firstResponse);
  }

  Future<ApiResponse<DriverTripActionReceipt>> _post({
    required DriverTripAction action,
    required String tripReference,
    required String idempotencyKey,
    required String accessToken,
    required Map<String, Object?> body,
  }) {
    return apiGateway.post<DriverTripActionReceipt>(
      action.endpointPath(tripReference),
      data: body,
      headers: <String, String>{
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
        'Idempotency-Key': idempotencyKey,
      },
      decoder: DriverTripActionReceipt.fromJson,
    );
  }

  DriverTripActionReceipt? _validatedReceipt({
    required ApiResponse<DriverTripActionReceipt> response,
    required DriverTripAction action,
    required String tripReference,
  }) {
    final receipt = response.data;
    if (!response.isSuccess || receipt == null) {
      return null;
    }

    if (!receipt.confirms(
      expectedTripReference: tripReference,
      action: action,
      statusCode: response.statusCode,
    )) {
      throw const DriverTripActionException(
        type: DriverTripActionFailureType.badResponse,
        message: 'The server response could not confirm this action.',
      );
    }

    return receipt;
  }

  DriverTripActionException _exceptionFromResponse(
    ApiResponse<DriverTripActionReceipt> response,
  ) {
    final statusCode = response.statusCode;
    final error = response.error;
    final backendCode = _backendCode(error?.cause);

    if (error?.type == AsmApiExceptionType.network ||
        error?.type == AsmApiExceptionType.timeout) {
      return const DriverTripActionException(
        type: DriverTripActionFailureType.temporarilyUnavailable,
        message:
            'Cannot confirm this action. Check your connection and try again.',
      );
    }

    if (statusCode == 400 && backendCode == 'invalid_transition') {
      return const DriverTripActionException(
        type: DriverTripActionFailureType.invalidTransition,
        message:
            'This action is no longer allowed for the current trip state. '
            'Refresh the trip and try again.',
      );
    }

    if (statusCode == 401) {
      return const DriverTripActionException(
        type: DriverTripActionFailureType.signInRequired,
        message: 'Session expired. Please sign in again to continue.',
      );
    }

    if (statusCode == 403) {
      return const DriverTripActionException(
        type: DriverTripActionFailureType.forbidden,
        message: 'This Driver account cannot update this trip.',
      );
    }

    if (statusCode == 404) {
      return const DriverTripActionException(
        type: DriverTripActionFailureType.notFound,
        message: 'This assigned trip could not be found.',
      );
    }

    if (statusCode == 409) {
      return const DriverTripActionException(
        type: DriverTripActionFailureType.idempotencyConflict,
        message:
            'This action conflicts with an earlier request. '
            'Refresh the trip before trying again.',
      );
    }

    if (statusCode == 429) {
      return const DriverTripActionException(
        type: DriverTripActionFailureType.rateLimited,
        message: 'Too many action attempts. Wait a moment and try again.',
      );
    }

    if (statusCode == 502 ||
        statusCode == 503 ||
        statusCode == 504 ||
        error?.type == AsmApiExceptionType.server) {
      return const DriverTripActionException(
        type: DriverTripActionFailureType.temporarilyUnavailable,
        message:
            'Service is temporarily unavailable. The action was not confirmed.',
      );
    }

    return const DriverTripActionException(
      type: DriverTripActionFailureType.badResponse,
      message: 'The trip action could not be confirmed.',
    );
  }

  String? _backendCode(Object? cause) {
    if (cause is! Map) {
      return null;
    }
    final value = cause['code'];
    return value is String ? value.trim() : null;
  }
}
