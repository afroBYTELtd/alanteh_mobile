import 'package:asm_offline_queue/asm_offline_queue.dart';

import 'driver_offer_response_gateway.dart';
import 'driver_trip_action_resilience.dart';

const driverOfferAcceptanceEventIdentity = 'driver-offer-accept';

final class DriverOfferVerifiedTrip {
  const DriverOfferVerifiedTrip({
    required this.tripReference,
    required this.status,
    this.source,
  });

  final String tripReference;
  final String status;
  final Object? source;
}

typedef DriverOfferServerStateVerifier =
    Future<DriverOfferVerifiedTrip> Function(
      DriverOfferResponseReceipt receipt,
    );

typedef DriverOfferResponseControllerFactory =
    Future<DriverOfferResponseResilienceController> Function(
      String tripReference,
    );

enum DriverOfferPreparationFailureCode {
  factoryUnavailable,
  driverDutyFetchFailed,
  driverReferenceMissing,
  persistentQueueOpenOrReadFailed,
  conflictingOfferRecord,
  invalidOfferRecord,
  queueEnqueueFailed,
}

extension DriverOfferPreparationFailureCodeValue
    on DriverOfferPreparationFailureCode {
  String get value => switch (this) {
    DriverOfferPreparationFailureCode.factoryUnavailable =>
      'factory_unavailable',
    DriverOfferPreparationFailureCode.driverDutyFetchFailed =>
      'driver_duty_fetch_failed',
    DriverOfferPreparationFailureCode.driverReferenceMissing =>
      'driver_reference_missing',
    DriverOfferPreparationFailureCode.persistentQueueOpenOrReadFailed =>
      'persistent_queue_open_or_read_failed',
    DriverOfferPreparationFailureCode.conflictingOfferRecord =>
      'conflicting_offer_record',
    DriverOfferPreparationFailureCode.invalidOfferRecord =>
      'invalid_offer_record',
    DriverOfferPreparationFailureCode.queueEnqueueFailed =>
      'queue_enqueue_failed',
  };
}

final class DriverOfferPreparationException implements Exception {
  const DriverOfferPreparationException(this.code);

  final DriverOfferPreparationFailureCode code;

  @override
  String toString() => 'DriverOfferPreparationException(code=${code.value})';
}

enum DriverOfferAcceptanceDisposition {
  accepted,
  duplicateRecovered,
  retryableFailure,
  conflict,
  rejected,
}

final class DriverOfferAcceptanceResult {
  const DriverOfferAcceptanceResult({
    required this.disposition,
    required this.event,
    this.receipt,
    this.refreshedTrip,
    this.error,
  });

  final DriverOfferAcceptanceDisposition disposition;
  final QueuedEvent event;
  final DriverOfferResponseReceipt? receipt;
  final DriverOfferVerifiedTrip? refreshedTrip;
  final DriverOfferResponseException? error;

  bool get accepted =>
      disposition == DriverOfferAcceptanceDisposition.accepted ||
      disposition == DriverOfferAcceptanceDisposition.duplicateRecovered;

  bool get permitsManualRetry =>
      disposition == DriverOfferAcceptanceDisposition.retryableFailure ||
      error?.permitsManualRetry == true;

  String? get message => error?.message;
}

final class DriverOfferResponseResilienceController {
  DriverOfferResponseResilienceController({
    required this.queue,
    required this.gateway,
    required this.tripReference,
    required this.driverId,
    required this.verifyServerState,
    DateTime Function()? utcNow,
  }) : _utcNow = utcNow ?? (() => DateTime.now().toUtc());

  final DriverTripActionPersistentQueue queue;
  final DriverOfferResponseGateway gateway;
  final String tripReference;
  final String driverId;
  final DriverOfferServerStateVerifier verifyServerState;
  final DateTime Function() _utcNow;

  Future<DriverOfferAcceptanceResult>? _inFlight;
  DriverOfferResponseReceipt? _confirmedReceipt;
  QueuedEvent? _confirmedEvent;

  String get _normalizedTripReference {
    final normalized = tripReference.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(
        tripReference,
        'tripReference',
        'must not be blank',
      );
    }
    return normalized;
  }

  String get _normalizedDriverId {
    final normalized = driverId.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(driverId, 'driverId', 'must not be blank');
    }
    return normalized;
  }

  String get _eventType =>
      '${driverOfferResponsePath(_normalizedTripReference)}'
      '$driverOfferAcceptanceEventIdentity';

  String get _recordId =>
      'driver-offer-accept:${_normalizedTripReference.toLowerCase()}';

  String get _keyPrefix => 'DRIVER-OFFER-$_normalizedTripReference-';

  Future<QueuedEvent> prepareWhenOfferDisplayed() async {
    final normalizedTripReference = _normalizedTripReference;
    final normalizedDriverId = _normalizedDriverId;
    final recordId = _recordId;
    final eventType = _eventType;
    final keyPrefix = _keyPrefix;

    QueuedEvent? persisted;
    List<QueuedEvent> pending;

    try {
      persisted = await queue.eventById(recordId);
      pending = await queue.pendingEvents();
    } on DriverOfferPreparationException {
      rethrow;
    } on Object {
      throw const DriverOfferPreparationException(
        DriverOfferPreparationFailureCode.persistentQueueOpenOrReadFailed,
      );
    }

    final conflictingMatches = pending
        .where(
          (event) =>
              event.id != recordId &&
              event.tripReference == normalizedTripReference &&
              event.driverId == normalizedDriverId &&
              event.eventType == eventType,
        )
        .toList(growable: false);

    if (conflictingMatches.isNotEmpty) {
      throw const DriverOfferPreparationException(
        DriverOfferPreparationFailureCode.conflictingOfferRecord,
      );
    }

    if (persisted != null) {
      _validateExistingEvent(persisted);
      return persisted;
    }

    final seed = QueuedEvent(
      id: recordId,
      eventType: eventType,
      tripReference: normalizedTripReference,
      driverId: normalizedDriverId,
      payloadJson: const <String, Object?>{
        'response': driverOfferAcceptResponse,
      },
    );

    final prepared = QueuedEvent(
      id: seed.id,
      eventType: seed.eventType,
      tripReference: seed.tripReference,
      driverId: seed.driverId,
      payloadJson: seed.payloadJson,
      idempotencyKey: '$keyPrefix${seed.idempotencyKey}',
      deviceTimestamp: seed.deviceTimestamp,
      syncStatus: QueueSyncStatus.pending,
      retryCount: seed.retryCount,
      createdAt: seed.createdAt,
      updatedAt: seed.updatedAt,
    );

    try {
      await queue.enqueue(prepared);
    } on DriverOfferPreparationException {
      rethrow;
    } on Object {
      throw const DriverOfferPreparationException(
        DriverOfferPreparationFailureCode.queueEnqueueFailed,
      );
    }

    return prepared;
  }

  Future<DriverOfferAcceptanceResult> accept() {
    final existing = _inFlight;
    if (existing != null) {
      return existing;
    }

    final operation = _confirmedReceipt == null
        ? _acceptPersistedRequest()
        : _verifyConfirmedReceipt();
    _inFlight = operation;
    operation.whenComplete(() {
      if (identical(_inFlight, operation)) {
        _inFlight = null;
      }
    });
    return operation;
  }

  Future<DriverOfferAcceptanceResult> retry() {
    return accept();
  }

  Future<DriverOfferAcceptanceResult> _acceptPersistedRequest() async {
    var event = await prepareWhenOfferDisplayed();
    event = await _persistFirstTapTimestamp(event);

    try {
      final timestamp = _persistedTimestamp(event);
      final receipt = await gateway.accept(
        tripReference: event.tripReference,
        idempotencyKey: event.idempotencyKey,
        deviceTimestamp: timestamp,
      );

      await queue.markSynced(event.id);
      _confirmedReceipt = receipt;
      _confirmedEvent = event;

      return _verifyConfirmedReceipt();
    } on DriverOfferResponseException catch (error) {
      return DriverOfferAcceptanceResult(
        disposition: switch (error.type) {
          DriverOfferResponseFailureType.temporarilyUnavailable =>
            DriverOfferAcceptanceDisposition.retryableFailure,
          DriverOfferResponseFailureType.clientFailure =>
            DriverOfferAcceptanceDisposition.retryableFailure,
          DriverOfferResponseFailureType.conflict =>
            DriverOfferAcceptanceDisposition.conflict,
          _ => DriverOfferAcceptanceDisposition.rejected,
        },
        event: event,
        error: error,
      );
    }
  }

  Future<DriverOfferAcceptanceResult> _verifyConfirmedReceipt() async {
    final receipt = _confirmedReceipt;
    final event = _confirmedEvent;

    if (receipt == null || event == null) {
      throw StateError('No confirmed offer response is available.');
    }

    DriverOfferVerifiedTrip refreshedTrip;
    try {
      refreshedTrip = await verifyServerState(receipt);
    } on Object {
      return DriverOfferAcceptanceResult(
        disposition: DriverOfferAcceptanceDisposition.retryableFailure,
        event: event,
        receipt: receipt,
        error: const DriverOfferResponseException(
          type: DriverOfferResponseFailureType.temporarilyUnavailable,
          message: driverOfferAcceptanceFailureMessage,
        ),
      );
    }

    if (refreshedTrip.tripReference.trim() != event.tripReference ||
        refreshedTrip.status.trim() != 'driver_accepted') {
      return DriverOfferAcceptanceResult(
        disposition: DriverOfferAcceptanceDisposition.retryableFailure,
        event: event,
        receipt: receipt,
        refreshedTrip: refreshedTrip,
        error: const DriverOfferResponseException(
          type: DriverOfferResponseFailureType.temporarilyUnavailable,
          message: driverOfferAcceptanceFailureMessage,
        ),
      );
    }

    return DriverOfferAcceptanceResult(
      disposition: receipt.duplicate
          ? DriverOfferAcceptanceDisposition.duplicateRecovered
          : DriverOfferAcceptanceDisposition.accepted,
      event: event,
      receipt: receipt,
      refreshedTrip: refreshedTrip,
    );
  }

  Future<QueuedEvent> _persistFirstTapTimestamp(QueuedEvent event) async {
    final existingTimestamp = event.payloadJson['device_timestamp'];
    if (existingTimestamp is String &&
        existingTimestamp.trim().isNotEmpty &&
        DateTime.tryParse(existingTimestamp.trim()) != null) {
      return event;
    }

    final timestamp = _utcNow().toUtc();
    final persisted = QueuedEvent(
      id: event.id,
      eventType: event.eventType,
      tripReference: event.tripReference,
      driverId: event.driverId,
      payloadJson: <String, Object?>{
        'response': driverOfferAcceptResponse,
        'device_timestamp': timestamp.toIso8601String(),
      },
      idempotencyKey: event.idempotencyKey,
      deviceTimestamp: timestamp,
      syncStatus: QueueSyncStatus.pending,
      retryCount: event.retryCount,
      createdAt: event.createdAt,
      updatedAt: timestamp,
    );

    await queue.enqueue(persisted);
    return persisted;
  }

  String _persistedTimestamp(QueuedEvent event) {
    final rawTimestamp = event.payloadJson['device_timestamp'];
    if (rawTimestamp is! String || rawTimestamp.trim().isEmpty) {
      throw StateError(
        'Offer acceptance timestamp was not persisted before submission.',
      );
    }

    final normalized = rawTimestamp.trim();
    final parsed = DateTime.tryParse(normalized);
    if (parsed == null || parsed.timeZoneOffset != Duration.zero) {
      throw StateError(
        'Offer acceptance timestamp was not a valid UTC ISO-8601 value.',
      );
    }

    return normalized;
  }

  void _validateExistingEvent(QueuedEvent event) {
    final rawTimestamp = event.payloadJson['device_timestamp'];
    final parsedTimestamp = rawTimestamp is String
        ? DateTime.tryParse(rawTimestamp.trim())
        : null;
    final timestampIsValid =
        rawTimestamp == null ||
        (rawTimestamp is String &&
            rawTimestamp.trim().isNotEmpty &&
            parsedTimestamp != null &&
            parsedTimestamp.timeZoneOffset == Duration.zero);

    if (event.id != _recordId ||
        event.eventType != _eventType ||
        event.tripReference != _normalizedTripReference ||
        event.driverId != _normalizedDriverId ||
        event.idempotencyKey.isEmpty ||
        !event.idempotencyKey.startsWith(_keyPrefix) ||
        event.idempotencyKey.length <= _keyPrefix.length ||
        event.payloadJson['response'] != driverOfferAcceptResponse ||
        !timestampIsValid) {
      throw const DriverOfferPreparationException(
        DriverOfferPreparationFailureCode.invalidOfferRecord,
      );
    }
  }
}
