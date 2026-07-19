import 'package:asm_offline_queue/asm_offline_queue.dart';

enum DriverTripActionDisposition { onlineVisualOnly, queuedOffline }

final class DriverTripActionRecordResult {
  const DriverTripActionRecordResult({
    required this.disposition,
    this.queuedEvent,
  });

  final DriverTripActionDisposition disposition;
  final QueuedEvent? queuedEvent;

  bool get queuedOffline =>
      disposition == DriverTripActionDisposition.queuedOffline;
}

abstract interface class DriverTripActionQueue {
  Future<QueuedEvent> enqueue(QueuedEvent event);
}

final class PersistentDriverTripActionQueue implements DriverTripActionQueue {
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

  Future<void> close() async {
    final managerFuture = _manager;
    if (managerFuture == null) {
      return;
    }

    final manager = await managerFuture;
    await manager.close();
  }
}

final class DriverTripActionResilienceController {
  const DriverTripActionResilienceController({
    required this.isOnline,
    required this.queue,
    required this.tripReference,
    required this.driverId,
  });

  final Future<bool> Function() isOnline;
  final DriverTripActionQueue queue;
  final String tripReference;
  final String driverId;

  Future<DriverTripActionRecordResult> recordAction({
    required String eventType,
    required Map<String, Object?> payload,
  }) async {
    if (await isOnline()) {
      return const DriverTripActionRecordResult(
        disposition: DriverTripActionDisposition.onlineVisualOnly,
      );
    }

    final queued = await queue.enqueue(
      QueuedEvent(
        eventType: eventType,
        tripReference: tripReference,
        driverId: driverId,
        payloadJson: payload,
      ),
    );

    return DriverTripActionRecordResult(
      disposition: DriverTripActionDisposition.queuedOffline,
      queuedEvent: queued,
    );
  }
}
