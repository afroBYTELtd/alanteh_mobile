import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_auth/asm_auth.dart';

import 'driver_trip_action_gateway.dart';
import 'ghana_network_resilience.dart';

const driverOfferAcceptResponse = 'accept';
const driverOfferAcceptanceFailureMessage =
    'Could not confirm acceptance. Check your connection and try again.';
const driverOfferConflictMessage =
    'There was a conflict with this request. Please contact support.';
const driverOfferSafeClientFailureMessage =
    'Could not accept this offer. Please review the trip and try again.';

String driverOfferResponsePath(String tripReference) {
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
      'response/';
}

abstract interface class DriverOfferResponseApiGateway {
  Future<ApiResponse<T>> post<T>(
    String path, {
    Object? data,
    Map<String, String>? headers,
    JsonDecoder<T>? decoder,
  });
}

final class AsmDriverOfferResponseApiGateway
    implements DriverOfferResponseApiGateway {
  const AsmDriverOfferResponseApiGateway(this.client);

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

final class DriverOfferResponseReceipt {
  const DriverOfferResponseReceipt({
    required this.tripStatus,
    required this.duplicate,
    this.tripReference,
  });

  factory DriverOfferResponseReceipt.fromJson(Object? json) {
    if (json is! Map) {
      throw const FormatException(
        'Driver offer response was not a JSON object.',
      );
    }

    final normalized = json.map(
      (key, value) => MapEntry(key.toString(), value),
    );
    final rawReference = normalized['trip_reference'];
    final rawStatus = normalized['trip_status'];
    final rawDuplicate = normalized['duplicate'];

    String? tripReference;
    if (rawReference != null) {
      if (rawReference is! String || rawReference.trim().isEmpty) {
        throw const FormatException(
          'Driver offer response Trip reference was invalid.',
        );
      }
      tripReference = rawReference.trim();
    }

    if (rawStatus is! String ||
        rawStatus.trim().isEmpty ||
        rawDuplicate is! bool) {
      throw const FormatException('Driver offer response was incomplete.');
    }

    return DriverOfferResponseReceipt(
      tripReference: tripReference,
      tripStatus: rawStatus.trim(),
      duplicate: rawDuplicate,
    );
  }

  final String? tripReference;
  final String tripStatus;
  final bool duplicate;

  bool confirms({
    required String expectedTripReference,
    required int? statusCode,
  }) {
    final expectedDuplicate = switch (statusCode) {
      201 => false,
      200 => true,
      _ => null,
    };

    if (expectedDuplicate == null ||
        duplicate != expectedDuplicate ||
        tripStatus != 'driver_accepted') {
      return false;
    }

    final returnedReference = tripReference;
    return returnedReference == null ||
        returnedReference == expectedTripReference;
  }
}

enum DriverOfferResponseFailureType {
  signInRequired,
  conflict,
  clientFailure,
  temporarilyUnavailable,
  badResponse,
}

final class DriverOfferResponseException implements Exception {
  const DriverOfferResponseException({
    required this.type,
    required this.message,
  });

  final DriverOfferResponseFailureType type;
  final String message;

  bool get automaticRetryExhausted =>
      type == DriverOfferResponseFailureType.temporarilyUnavailable;

  bool get permitsManualRetry =>
      type == DriverOfferResponseFailureType.temporarilyUnavailable ||
      type == DriverOfferResponseFailureType.clientFailure;

  @override
  String toString() => 'DriverOfferResponseException(type=$type)';
}

abstract interface class DriverOfferResponseGateway {
  Future<DriverOfferResponseReceipt> accept({
    required String tripReference,
    required String idempotencyKey,
    required String deviceTimestamp,
  });
}

final class ApiDriverOfferResponseGateway
    implements DriverOfferResponseGateway {
  ApiDriverOfferResponseGateway({
    required this.apiGateway,
    required this.tokenStore,
    this.refreshAccessToken,
    GhanaRetryPolicy? retryPolicy,
    this.connectionConfigured = true,
  }) : _retryPolicy = retryPolicy ?? const GhanaRetryPolicy();

  final DriverOfferResponseApiGateway apiGateway;
  final AuthTokenStore tokenStore;
  final DriverAccessTokenRefresh? refreshAccessToken;
  final GhanaRetryPolicy _retryPolicy;
  final bool connectionConfigured;

  @override
  Future<DriverOfferResponseReceipt> accept({
    required String tripReference,
    required String idempotencyKey,
    required String deviceTimestamp,
  }) async {
    final normalizedReference = tripReference.trim();
    final normalizedKey = idempotencyKey.trim();
    final normalizedTimestamp = deviceTimestamp.trim();
    final parsedTimestamp = DateTime.tryParse(normalizedTimestamp);

    if (normalizedReference.isEmpty ||
        normalizedKey.isEmpty ||
        parsedTimestamp == null ||
        parsedTimestamp.timeZoneOffset != Duration.zero) {
      throw const DriverOfferResponseException(
        type: DriverOfferResponseFailureType.badResponse,
        message: 'The offer acceptance could not be prepared safely.',
      );
    }

    if (!connectionConfigured) {
      throw const DriverOfferResponseException(
        type: DriverOfferResponseFailureType.badResponse,
        message: AsmApiClient.connectionNotConfiguredMessage,
      );
    }

    final accessToken = (await tokenStore.readAccessToken())?.trim();
    if (accessToken == null || accessToken.isEmpty) {
      throw const DriverOfferResponseException(
        type: DriverOfferResponseFailureType.signInRequired,
        message: 'Session expired. Please sign in again to continue.',
      );
    }

    final firstResponse = await _postWithBoundedRetry(
      tripReference: normalizedReference,
      idempotencyKey: normalizedKey,
      deviceTimestamp: normalizedTimestamp,
      accessToken: accessToken,
    );

    final firstReceipt = _validatedReceipt(
      response: firstResponse,
      tripReference: normalizedReference,
    );
    if (firstReceipt != null) {
      return firstReceipt;
    }

    if (firstResponse.statusCode == 401) {
      final refresh = refreshAccessToken;
      if (refresh == null) {
        throw const DriverOfferResponseException(
          type: DriverOfferResponseFailureType.signInRequired,
          message: 'Session expired. Please sign in again to continue.',
        );
      }

      final outcome = await refresh();
      switch (outcome) {
        case DriverTokenRefreshOutcome.refreshed:
          final refreshedAccessToken = (await tokenStore.readAccessToken())
              ?.trim();
          if (refreshedAccessToken == null || refreshedAccessToken.isEmpty) {
            throw const DriverOfferResponseException(
              type: DriverOfferResponseFailureType.signInRequired,
              message: 'Session expired. Please sign in again to continue.',
            );
          }

          final retryResponse = await _postWithBoundedRetry(
            tripReference: normalizedReference,
            idempotencyKey: normalizedKey,
            deviceTimestamp: normalizedTimestamp,
            accessToken: refreshedAccessToken,
          );
          final retryReceipt = _validatedReceipt(
            response: retryResponse,
            tripReference: normalizedReference,
          );
          if (retryReceipt != null) {
            return retryReceipt;
          }
          throw _exceptionFromResponse(retryResponse);

        case DriverTokenRefreshOutcome.sessionExpired:
          throw const DriverOfferResponseException(
            type: DriverOfferResponseFailureType.signInRequired,
            message: 'Session expired. Please sign in again to continue.',
          );

        case DriverTokenRefreshOutcome.temporarilyUnavailable:
          throw const DriverOfferResponseException(
            type: DriverOfferResponseFailureType.temporarilyUnavailable,
            message: driverOfferAcceptanceFailureMessage,
          );
      }
    }

    throw _exceptionFromResponse(firstResponse);
  }

  Future<ApiResponse<DriverOfferResponseReceipt>> _postWithBoundedRetry({
    required String tripReference,
    required String idempotencyKey,
    required String deviceTimestamp,
    required String accessToken,
  }) {
    return _retryPolicy.execute<DriverOfferResponseReceipt>(
      safeToRetry: true,
      operation: () => apiGateway.post<DriverOfferResponseReceipt>(
        driverOfferResponsePath(tripReference),
        data: <String, Object?>{
          'response': driverOfferAcceptResponse,
          'device_timestamp': deviceTimestamp,
        },
        headers: <String, String>{
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
          'Idempotency-Key': idempotencyKey,
        },
        decoder: DriverOfferResponseReceipt.fromJson,
      ),
    );
  }

  DriverOfferResponseReceipt? _validatedReceipt({
    required ApiResponse<DriverOfferResponseReceipt> response,
    required String tripReference,
  }) {
    final receipt = response.data;
    if (!response.isSuccess || receipt == null) {
      return null;
    }

    if (!receipt.confirms(
      expectedTripReference: tripReference,
      statusCode: response.statusCode,
    )) {
      throw const DriverOfferResponseException(
        type: DriverOfferResponseFailureType.badResponse,
        message: 'The server response could not confirm offer acceptance.',
      );
    }

    return receipt;
  }

  DriverOfferResponseException _exceptionFromResponse(
    ApiResponse<DriverOfferResponseReceipt> response,
  ) {
    final statusCode = response.statusCode;
    final error = response.error;

    if (error?.type == AsmApiExceptionType.network ||
        error?.type == AsmApiExceptionType.timeout ||
        error?.type == AsmApiExceptionType.server ||
        statusCode == 502 ||
        statusCode == 503 ||
        statusCode == 504) {
      return const DriverOfferResponseException(
        type: DriverOfferResponseFailureType.temporarilyUnavailable,
        message: driverOfferAcceptanceFailureMessage,
      );
    }

    if (statusCode == 401 ||
        error?.type == AsmApiExceptionType.authentication) {
      return const DriverOfferResponseException(
        type: DriverOfferResponseFailureType.signInRequired,
        message: 'Session expired. Please sign in again to continue.',
      );
    }

    if (statusCode == 409) {
      return const DriverOfferResponseException(
        type: DriverOfferResponseFailureType.conflict,
        message: driverOfferConflictMessage,
      );
    }

    if (statusCode != null && statusCode >= 400 && statusCode < 500) {
      return const DriverOfferResponseException(
        type: DriverOfferResponseFailureType.clientFailure,
        message: driverOfferSafeClientFailureMessage,
      );
    }

    return const DriverOfferResponseException(
      type: DriverOfferResponseFailureType.badResponse,
      message: 'The offer acceptance could not be confirmed.',
    );
  }
}
