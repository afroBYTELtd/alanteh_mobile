import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_auth/asm_auth.dart';

import 'driver_access_token_refresh_guard.dart';
import 'driver_trip_action_gateway.dart';
import 'ghana_network_resilience.dart';

const driverOfferAcceptResponse = 'accept';
const driverOfferAcceptanceFailureMessage =
    'Could not confirm acceptance. Check your connection and try again.';
const driverOfferConflictMessage =
    'There was a conflict with this request. Please contact support.';
const driverOfferSafeClientFailureMessage =
    'Could not accept this offer. Please review the trip and try again.';
const driverOfferSessionExpiredMessage =
    'Your session has expired. Please sign in again.';
const driverOfferTokenRefreshThreshold = driverAccessTokenRefreshThreshold;

enum DriverOfferSubmissionTelemetryStage {
  submitStart,
  tokenCheck,
  requestSent,
  httpStatusClass,
  retryAttemptN,
  queueState,
  receiptCheck,
}

extension DriverOfferSubmissionTelemetryStageCode
    on DriverOfferSubmissionTelemetryStage {
  String get code => switch (this) {
    DriverOfferSubmissionTelemetryStage.submitStart => 'SUBMIT_START',
    DriverOfferSubmissionTelemetryStage.tokenCheck => 'TOKEN_CHECK',
    DriverOfferSubmissionTelemetryStage.requestSent => 'REQUEST_SENT',
    DriverOfferSubmissionTelemetryStage.httpStatusClass => 'HTTP_STATUS_CLASS',
    DriverOfferSubmissionTelemetryStage.retryAttemptN => 'RETRY_ATTEMPT_N',
    DriverOfferSubmissionTelemetryStage.queueState => 'QUEUE_STATE',
    DriverOfferSubmissionTelemetryStage.receiptCheck => 'RECEIPT_CHECK',
  };
}

enum DriverOfferSubmissionHttpStatusClass {
  success2xx,
  client4xx,
  server5xx,
  timeout,
}

extension DriverOfferSubmissionHttpStatusClassValue
    on DriverOfferSubmissionHttpStatusClass {
  String get value => switch (this) {
    DriverOfferSubmissionHttpStatusClass.success2xx => '2xx',
    DriverOfferSubmissionHttpStatusClass.client4xx => '4xx',
    DriverOfferSubmissionHttpStatusClass.server5xx => '5xx',
    DriverOfferSubmissionHttpStatusClass.timeout => 'timeout',
  };
}

enum DriverOfferSubmissionRetryAttempt { one, two, three }

extension DriverOfferSubmissionRetryAttemptValue
    on DriverOfferSubmissionRetryAttempt {
  int get value => switch (this) {
    DriverOfferSubmissionRetryAttempt.one => 1,
    DriverOfferSubmissionRetryAttempt.two => 2,
    DriverOfferSubmissionRetryAttempt.three => 3,
  };

  static DriverOfferSubmissionRetryAttempt fromRetryNumber(int retryNumber) {
    return switch (retryNumber) {
      1 => DriverOfferSubmissionRetryAttempt.one,
      2 => DriverOfferSubmissionRetryAttempt.two,
      3 => DriverOfferSubmissionRetryAttempt.three,
      _ => throw RangeError.range(retryNumber, 1, 3, 'retryNumber'),
    };
  }
}

enum DriverOfferSubmissionTokenCheckOutcome {
  tokenValid,
  tokenRefreshed,
  tokenRefreshFailed,
}

extension DriverOfferSubmissionTokenCheckOutcomeValue
    on DriverOfferSubmissionTokenCheckOutcome {
  String get value => switch (this) {
    DriverOfferSubmissionTokenCheckOutcome.tokenValid => 'TOKEN_VALID',
    DriverOfferSubmissionTokenCheckOutcome.tokenRefreshed => 'TOKEN_REFRESHED',
    DriverOfferSubmissionTokenCheckOutcome.tokenRefreshFailed =>
      'TOKEN_REFRESH_FAILED',
  };
}

enum DriverOfferSubmissionQueueState { queued, dequeued, pending, failed }

extension DriverOfferSubmissionQueueStateValue
    on DriverOfferSubmissionQueueState {
  String get value => switch (this) {
    DriverOfferSubmissionQueueState.queued => 'queued',
    DriverOfferSubmissionQueueState.dequeued => 'dequeued',
    DriverOfferSubmissionQueueState.pending => 'pending',
    DriverOfferSubmissionQueueState.failed => 'failed',
  };
}

final class DriverOfferSubmissionTelemetryEvent {
  const DriverOfferSubmissionTelemetryEvent.submitStart()
    : stage = DriverOfferSubmissionTelemetryStage.submitStart,
      tokenCheckOutcome = null,
      httpStatusClass = null,
      retryAttempt = null,
      queueState = null;

  const DriverOfferSubmissionTelemetryEvent.tokenCheck(this.tokenCheckOutcome)
    : stage = DriverOfferSubmissionTelemetryStage.tokenCheck,
      httpStatusClass = null,
      retryAttempt = null,
      queueState = null;

  const DriverOfferSubmissionTelemetryEvent.requestSent()
    : stage = DriverOfferSubmissionTelemetryStage.requestSent,
      tokenCheckOutcome = null,
      httpStatusClass = null,
      retryAttempt = null,
      queueState = null;

  const DriverOfferSubmissionTelemetryEvent.httpStatusClass(
    this.httpStatusClass,
  ) : stage = DriverOfferSubmissionTelemetryStage.httpStatusClass,
      tokenCheckOutcome = null,
      retryAttempt = null,
      queueState = null;

  const DriverOfferSubmissionTelemetryEvent.retryAttempt(this.retryAttempt)
    : stage = DriverOfferSubmissionTelemetryStage.retryAttemptN,
      tokenCheckOutcome = null,
      httpStatusClass = null,
      queueState = null;

  const DriverOfferSubmissionTelemetryEvent.queueState(this.queueState)
    : stage = DriverOfferSubmissionTelemetryStage.queueState,
      tokenCheckOutcome = null,
      httpStatusClass = null,
      retryAttempt = null;

  const DriverOfferSubmissionTelemetryEvent.receiptCheck()
    : stage = DriverOfferSubmissionTelemetryStage.receiptCheck,
      tokenCheckOutcome = null,
      httpStatusClass = null,
      retryAttempt = null,
      queueState = null;

  final DriverOfferSubmissionTelemetryStage stage;
  final DriverOfferSubmissionTokenCheckOutcome? tokenCheckOutcome;
  final DriverOfferSubmissionHttpStatusClass? httpStatusClass;
  final DriverOfferSubmissionRetryAttempt? retryAttempt;
  final DriverOfferSubmissionQueueState? queueState;

  String get qaDisplayText => switch (stage) {
    DriverOfferSubmissionTelemetryStage.submitStart => 'SUBMIT_START',
    DriverOfferSubmissionTelemetryStage.tokenCheck =>
      'TOKEN_CHECK: ${tokenCheckOutcome!.value}',
    DriverOfferSubmissionTelemetryStage.requestSent => 'REQUEST_SENT',
    DriverOfferSubmissionTelemetryStage.httpStatusClass =>
      'HTTP_STATUS_CLASS: ${httpStatusClass!.value}',
    DriverOfferSubmissionTelemetryStage.retryAttemptN =>
      'RETRY_ATTEMPT_N: ${retryAttempt!.value}',
    DriverOfferSubmissionTelemetryStage.queueState =>
      'QUEUE_STATE: ${queueState!.value}',
    DriverOfferSubmissionTelemetryStage.receiptCheck => 'RECEIPT_CHECK',
  };
}

typedef DriverOfferSubmissionTelemetrySink =
    void Function(DriverOfferSubmissionTelemetryEvent event);

const driverOfferSubmissionTelemetryRegisteredStages =
    <DriverOfferSubmissionTelemetryStage>[
      DriverOfferSubmissionTelemetryStage.submitStart,
      DriverOfferSubmissionTelemetryStage.tokenCheck,
      DriverOfferSubmissionTelemetryStage.requestSent,
      DriverOfferSubmissionTelemetryStage.httpStatusClass,
      DriverOfferSubmissionTelemetryStage.retryAttemptN,
      DriverOfferSubmissionTelemetryStage.queueState,
      DriverOfferSubmissionTelemetryStage.receiptCheck,
    ];

final class DriverOfferSubmissionTelemetryInitializationResult {
  const DriverOfferSubmissionTelemetryInitializationResult();

  List<String> get hookCodes => List<String>.unmodifiable(
    driverOfferSubmissionTelemetryRegisteredStages.map((stage) => stage.code),
  );

  bool get allHooksRegistered =>
      hookCodes.length == DriverOfferSubmissionTelemetryStage.values.length &&
      hookCodes.toSet().length ==
          DriverOfferSubmissionTelemetryStage.values.length;

  String get qaDisplayText =>
      'TELEMETRY_INIT_ONLY: ALL_7_HOOKS_REGISTERED '
      '[${hookCodes.join(', ')}]';
}

DriverOfferSubmissionTelemetryInitializationResult
initializeDriverOfferSubmissionTelemetryHooks() {
  return const DriverOfferSubmissionTelemetryInitializationResult();
}

void emitDriverOfferSubmissionTelemetry(
  DriverOfferSubmissionTelemetrySink? sink,
  DriverOfferSubmissionTelemetryEvent event,
) {
  sink?.call(event);
}

void _emitDriverOfferSubmissionHttpStatusClass<T>(
  DriverOfferSubmissionTelemetrySink? sink,
  ApiResponse<T> response,
) {
  final statusCode = response.statusCode;
  DriverOfferSubmissionHttpStatusClass? value;

  if (statusCode != null && statusCode >= 200 && statusCode < 300) {
    value = DriverOfferSubmissionHttpStatusClass.success2xx;
  } else if (statusCode != null && statusCode >= 400 && statusCode < 500) {
    value = DriverOfferSubmissionHttpStatusClass.client4xx;
  } else if (statusCode != null && statusCode >= 500 && statusCode < 600) {
    value = DriverOfferSubmissionHttpStatusClass.server5xx;
  } else if (response.error?.type == AsmApiExceptionType.timeout) {
    value = DriverOfferSubmissionHttpStatusClass.timeout;
  }

  if (value != null) {
    emitDriverOfferSubmissionTelemetry(
      sink,
      DriverOfferSubmissionTelemetryEvent.httpStatusClass(value),
    );
  }
}

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
    DriverOfferSubmissionTelemetrySink? telemetrySink,
  });
}

final class ApiDriverOfferResponseGateway
    implements DriverOfferResponseGateway {
  ApiDriverOfferResponseGateway({
    required this.apiGateway,
    required this.tokenStore,
    this.refreshAccessToken,
    GhanaRetryPolicy? retryPolicy,
    DateTime Function()? utcNow,
    this.connectionConfigured = true,
  }) : _retryPolicy = retryPolicy ?? const GhanaRetryPolicy(),
       _tokenGuard = DriverAccessTokenRefreshGuard(
         tokenStore: tokenStore,
         refreshAccessToken: refreshAccessToken,
         utcNow: utcNow,
       );

  final DriverOfferResponseApiGateway apiGateway;
  final AuthTokenStore tokenStore;
  final DriverAccessTokenRefresh? refreshAccessToken;
  final GhanaRetryPolicy _retryPolicy;
  final DriverAccessTokenRefreshGuard _tokenGuard;
  final bool connectionConfigured;

  @override
  Future<DriverOfferResponseReceipt> accept({
    required String tripReference,
    required String idempotencyKey,
    required String deviceTimestamp,
    DriverOfferSubmissionTelemetrySink? telemetrySink,
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

    final accessToken = await _accessTokenForSubmission(
      telemetrySink: telemetrySink,
    );

    final firstResponse = await _postWithBoundedRetry(
      tripReference: normalizedReference,
      idempotencyKey: normalizedKey,
      deviceTimestamp: normalizedTimestamp,
      accessToken: accessToken,
      telemetrySink: telemetrySink,
    );

    final firstReceipt = _validatedReceipt(
      response: firstResponse,
      tripReference: normalizedReference,
    );
    if (firstReceipt != null) {
      return firstReceipt;
    }

    if (firstResponse.statusCode == 401) {
      final refreshedAccessToken = await _refreshAccessTokenForSubmission(
        telemetrySink: telemetrySink,
      );

      final retryResponse = await _postWithBoundedRetry(
        tripReference: normalizedReference,
        idempotencyKey: normalizedKey,
        deviceTimestamp: normalizedTimestamp,
        accessToken: refreshedAccessToken,
        telemetrySink: telemetrySink,
      );
      final retryReceipt = _validatedReceipt(
        response: retryResponse,
        tripReference: normalizedReference,
      );
      if (retryReceipt != null) {
        return retryReceipt;
      }
      throw _exceptionFromResponse(retryResponse);
    }

    throw _exceptionFromResponse(firstResponse);
  }

  Future<String> _accessTokenForSubmission({
    DriverOfferSubmissionTelemetrySink? telemetrySink,
  }) async {
    try {
      final resolution = await _tokenGuard.resolve();

      emitDriverOfferSubmissionTelemetry(
        telemetrySink,
        DriverOfferSubmissionTelemetryEvent.tokenCheck(
          resolution.refreshed
              ? DriverOfferSubmissionTokenCheckOutcome.tokenRefreshed
              : DriverOfferSubmissionTokenCheckOutcome.tokenValid,
        ),
      );

      return resolution.accessToken;
    } on DriverAccessTokenRefreshException {
      _throwTokenRefreshFailed(telemetrySink);
    }
  }

  Future<String> _refreshAccessTokenForSubmission({
    DriverOfferSubmissionTelemetrySink? telemetrySink,
  }) async {
    try {
      final resolution = await _tokenGuard.resolve(forceRefresh: true);

      emitDriverOfferSubmissionTelemetry(
        telemetrySink,
        const DriverOfferSubmissionTelemetryEvent.tokenCheck(
          DriverOfferSubmissionTokenCheckOutcome.tokenRefreshed,
        ),
      );

      return resolution.accessToken;
    } on DriverAccessTokenRefreshException {
      _throwTokenRefreshFailed(telemetrySink);
    }
  }

  Never _throwTokenRefreshFailed(
    DriverOfferSubmissionTelemetrySink? telemetrySink,
  ) {
    emitDriverOfferSubmissionTelemetry(
      telemetrySink,
      const DriverOfferSubmissionTelemetryEvent.tokenCheck(
        DriverOfferSubmissionTokenCheckOutcome.tokenRefreshFailed,
      ),
    );

    throw const DriverOfferResponseException(
      type: DriverOfferResponseFailureType.signInRequired,
      message: driverOfferSessionExpiredMessage,
    );
  }

  Future<ApiResponse<DriverOfferResponseReceipt>> _postWithBoundedRetry({
    required String tripReference,
    required String idempotencyKey,
    required String deviceTimestamp,
    required String accessToken,
    DriverOfferSubmissionTelemetrySink? telemetrySink,
  }) {
    var transportInvocation = 0;

    return _retryPolicy.execute<DriverOfferResponseReceipt>(
      safeToRetry: true,
      operation: () async {
        if (transportInvocation > 0) {
          final retryAttempt =
              DriverOfferSubmissionRetryAttemptValue.fromRetryNumber(
                transportInvocation,
              );
          emitDriverOfferSubmissionTelemetry(
            telemetrySink,
            DriverOfferSubmissionTelemetryEvent.retryAttempt(retryAttempt),
          );
        }

        transportInvocation += 1;
        emitDriverOfferSubmissionTelemetry(
          telemetrySink,
          const DriverOfferSubmissionTelemetryEvent.requestSent(),
        );

        final response = await apiGateway.post<DriverOfferResponseReceipt>(
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
        );

        _emitDriverOfferSubmissionHttpStatusClass(telemetrySink, response);
        return response;
      },
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
        message: driverOfferSessionExpiredMessage,
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
