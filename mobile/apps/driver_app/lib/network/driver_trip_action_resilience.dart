import 'package:asm_offline_queue/asm_offline_queue.dart';

import 'driver_trip_action_gateway.dart';

enum DriverTripActionDisposition {
  onlineVisualOnly,
  acknowledged,
  duplicateAcknowledged,
  queuedOffline,
  rejected,
}

final class DriverTripActionRecordResult {
  const DriverTripActionRecordResult({
    required this.disposition,
    this.queuedEvent,
    this.receipt,
    this.error,
  });

  final DriverTripActionDisposition disposition;
  final QueuedEvent? queuedEvent;
  final DriverTripActionReceipt? receipt;
  final DriverTripActionException? error;

  bool get queuedOffline =>
      disposition == DriverTripActionDisposition.queuedOffline;

  bool get canAdvance =>
      disposition == DriverTripActionDisposition.onlineVisualOnly ||
      disposition == DriverTripActionDisposition.acknowledged ||
      disposition == DriverTripActionDisposition.duplicateAcknowledged;
}

abstract interface class DriverTripActionQueue {
  Future<QueuedEvent> enqueue(QueuedEvent event);
}

abstract interface class DriverTripActionPersistentQueue
    implements DriverTripActionQueue {
  Future<List<QueuedEvent>> pendingEvents();
  Future<QueuedEvent?> eventById(String id);
  Future<void> markSynced(String id);
  Future<void> markFailed(String id);
  Future<void> markPermanentlyFailed(String id);
}

final class PersistentDriverTripActionQueue
    implements DriverTripActionPersistentQueue {
  PersistentDriverTripActionQueue({
    Future<QueueManager> Function()? managerFactory,
  }) : _managerFactory = managerFactory ?? (() => QueueManager.open());

  final Future<QueueManager> Function() _managerFactory;
  Future<QueueManager>? _manager;

  Future<QueueManager> _openManager() {
    return _manager ??= _managerFactory();
  }

  @override
  Future<QueuedEvent> enqueue(QueuedEvent event) async {
    final manager = await _openManager();
    return manager.enqueue(event);
  }

  @override
  Future<QueuedEvent?> eventById(String id) async {
    final manager = await _openManager();
    return manager.eventById(id);
  }

  @override
  Future<List<QueuedEvent>> pendingEvents() async {
    final manager = await _openManager();
    return manager.pendingEvents();
  }

  @override
  Future<void> markSynced(String id) async {
    final manager = await _openManager();
    await manager.markSynced(id);
  }

  @override
  Future<void> markFailed(String id) async {
    final manager = await _openManager();
    await manager.markFailed(id);
  }

  @override
  Future<void> markPermanentlyFailed(String id) async {
    final manager = await _openManager();
    await manager.markPermanentlyFailed(id);
  }

  Future<void> close() async {
    final managerFuture = _manager;
    if (managerFuture == null) {
      return;
    }

    final manager = await managerFuture;
    await manager.close();
  }
}

typedef DriverTripActionStateVerifier =
    Future<bool> Function(
      DriverTripAction action,
      DriverTripActionReceipt receipt,
    );

typedef DriverTripActionControllerFactory =
    Future<DriverTripActionResilienceController> Function(String tripReference);

final class DriverTripActionResilienceController {
  DriverTripActionResilienceController({
    required this.queue,
    required this.tripReference,
    required this.driverId,
    this.gateway,
    this.verifyServerState,
    Future<bool> Function()? isOnline,
  }) : _legacyIsOnline = isOnline;

  final DriverTripActionQueue queue;
  final String tripReference;
  final String driverId;
  final DriverTripActionGateway? gateway;
  final DriverTripActionStateVerifier? verifyServerState;
  final Future<bool> Function()? _legacyIsOnline;

  final Map<String, Future<DriverTripActionRecordResult>> _inFlight =
      <String, Future<DriverTripActionRecordResult>>{};

  Future<DriverTripActionRecordResult> recordAction({
    required String eventType,
    required Map<String, Object?> payload,
  }) {
    final action = DriverTripAction.fromEventIdentity(eventType);
    final endpointIdentity = action.endpointPath(tripReference);
    final existing = _inFlight[endpointIdentity];
    if (existing != null) {
      return existing;
    }

    final operation = _recordAction(
      action: action,
      endpointIdentity: endpointIdentity,
      payload: payload,
    );
    _inFlight[endpointIdentity] = operation;
    operation.whenComplete(() {
      if (identical(_inFlight[endpointIdentity], operation)) {
        _inFlight.remove(endpointIdentity);
      }
    });
    return operation;
  }

  Future<List<DriverTripActionReceipt>> recoverPendingActions() async {
    final persistentQueue = queue;
    final liveGateway = gateway;
    if (persistentQueue is! DriverTripActionPersistentQueue ||
        liveGateway == null) {
      return const <DriverTripActionReceipt>[];
    }

    final receipts = <DriverTripActionReceipt>[];
    final pending = await persistentQueue.pendingEvents();

    for (final event in pending) {
      if (event.tripReference != tripReference || event.driverId != driverId) {
        continue;
      }

      final action = _storedAction(event);
      if (action == null) {
        continue;
      }

      final result = await _submitStoredEvent(
        event: event,
        action: action,
        persistentQueue: persistentQueue,
        liveGateway: liveGateway,
      );

      if (result.canAdvance && result.receipt != null) {
        receipts.add(result.receipt!);
      }

      if (!result.canAdvance) {
        break;
      }
    }

    return List<DriverTripActionReceipt>.unmodifiable(receipts);
  }

  Future<DriverTripActionRecordResult> _recordAction({
    required DriverTripAction action,
    required String endpointIdentity,
    required Map<String, Object?> payload,
  }) async {
    final liveGateway = gateway;
    if (liveGateway == null) {
      final online = await (_legacyIsOnline?.call() ?? Future.value(true));
      if (online) {
        return const DriverTripActionRecordResult(
          disposition: DriverTripActionDisposition.onlineVisualOnly,
        );
      }

      final queued = await queue.enqueue(
        QueuedEvent(
          eventType: endpointIdentity,
          tripReference: tripReference,
          driverId: driverId,
          payloadJson: _acceptedBody(payload),
        ),
      );

      return DriverTripActionRecordResult(
        disposition: DriverTripActionDisposition.queuedOffline,
        queuedEvent: queued,
      );
    }

    final persistentQueue = queue;
    if (persistentQueue is! DriverTripActionPersistentQueue) {
      throw StateError(
        'Live Driver trip actions require persistent queue support.',
      );
    }

    final existing = await _existingPendingEvent(persistentQueue, action);
    final event =
        existing ??
        await persistentQueue.enqueue(
          QueuedEvent(
            eventType: endpointIdentity,
            tripReference: tripReference,
            driverId: driverId,
            payloadJson: _acceptedBody(payload),
          ),
        );

    return _submitStoredEvent(
      event: event,
      action: action,
      persistentQueue: persistentQueue,
      liveGateway: liveGateway,
    );
  }

  Future<QueuedEvent?> _existingPendingEvent(
    DriverTripActionPersistentQueue persistentQueue,
    DriverTripAction action,
  ) async {
    final events = await persistentQueue.pendingEvents();
    for (final event in events) {
      if (event.tripReference == tripReference &&
          event.driverId == driverId &&
          _storedAction(event) == action) {
        return event;
      }
    }
    return null;
  }

  DriverTripAction? _storedAction(QueuedEvent event) {
    try {
      final action = DriverTripAction.fromEventIdentity(event.eventType);
      final identity = event.eventType.trim();

      if (identity.contains('/actions/') &&
          identity != action.endpointPath(event.tripReference)) {
        return null;
      }

      return action;
    } on ArgumentError {
      return null;
    }
  }

  Future<DriverTripActionRecordResult> _submitStoredEvent({
    required QueuedEvent event,
    required DriverTripAction action,
    required DriverTripActionPersistentQueue persistentQueue,
    required DriverTripActionGateway liveGateway,
  }) async {
    try {
      final receipt = await liveGateway.submit(
        action: action,
        tripReference: event.tripReference,
        idempotencyKey: event.idempotencyKey,
        body: event.payloadJson,
      );

      if (receipt.duplicate) {
        final verifier = verifyServerState;
        if (verifier == null) {
          return DriverTripActionRecordResult(
            disposition: DriverTripActionDisposition.rejected,
            queuedEvent: event,
            error: const DriverTripActionException(
              type: DriverTripActionFailureType.badResponse,
              message:
                  'The saved action still needs refreshed trip verification.',
            ),
          );
        }

        try {
          final verified = await verifier(action, receipt);
          if (!verified) {
            return DriverTripActionRecordResult(
              disposition: DriverTripActionDisposition.rejected,
              queuedEvent: event,
              error: const DriverTripActionException(
                type: DriverTripActionFailureType.badResponse,
                message:
                    'The refreshed trip state did not confirm this action.',
              ),
            );
          }
        } on Object {
          return DriverTripActionRecordResult(
            disposition: DriverTripActionDisposition.queuedOffline,
            queuedEvent: event,
            error: const DriverTripActionException(
              type: DriverTripActionFailureType.temporarilyUnavailable,
              message:
                  'The action response was received, but the trip state '
                  'could not be verified yet.',
            ),
          );
        }
      }

      await persistentQueue.markSynced(event.id);

      return DriverTripActionRecordResult(
        disposition: receipt.duplicate
            ? DriverTripActionDisposition.duplicateAcknowledged
            : DriverTripActionDisposition.acknowledged,
        queuedEvent: event,
        receipt: receipt,
      );
    } on DriverTripActionException catch (error) {
      return DriverTripActionRecordResult(
        disposition: error.retryable
            ? DriverTripActionDisposition.queuedOffline
            : DriverTripActionDisposition.rejected,
        queuedEvent: event,
        error: error,
      );
    }
  }

  Map<String, Object?> _acceptedBody(Map<String, Object?> payload) {
    return const <String, Object?>{};
  }
}
