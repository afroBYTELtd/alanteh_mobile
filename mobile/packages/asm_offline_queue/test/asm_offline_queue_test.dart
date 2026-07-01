import 'package:asm_offline_queue/asm_offline_queue.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('QueuedEvent', () {
    test('requires eventType', () {
      expect(
        () => testEvent(eventType: ' '),
        throwsA(
          isA<QueueValidationException>().having(
            (error) => error.field,
            'field',
            QueueValidationField.eventType,
          ),
        ),
      );
    });

    test('requires tripReference', () {
      expect(
        () => testEvent(tripReference: ' '),
        throwsA(
          isA<QueueValidationException>().having(
            (error) => error.field,
            'field',
            QueueValidationField.tripReference,
          ),
        ),
      );
    });

    test('requires driverId', () {
      expect(
        () => testEvent(driverId: ' '),
        throwsA(
          isA<QueueValidationException>().having(
            (error) => error.field,
            'field',
            QueueValidationField.driverId,
          ),
        ),
      );
    });

    test('rejects payload data that is not JSON-compatible', () {
      expect(
        () => testEvent(payloadJson: {'sentAt': DateTime.utc(2026)}),
        throwsA(
          isA<QueueValidationException>().having(
            (error) => error.field,
            'field',
            QueueValidationField.payloadJson,
          ),
        ),
      );
    });

    test('creates or preserves idempotencyKey', () {
      final generated = testEvent();
      final preserved = testEvent(idempotencyKey: ' existing-key ');

      expect(generated.idempotencyKey, isNotEmpty);
      expect(preserved.idempotencyKey, 'existing-key');
    });

    test('new event starts as pending', () {
      expect(testEvent().syncStatus, QueueSyncStatus.pending);
    });
  });

  group('QueueManager', () {
    late QueueManager manager;

    setUp(() async {
      manager = await QueueManager.openInMemory();
    });

    tearDown(() async {
      await manager.close();
    });

    test('enqueue stores event', () async {
      final event = testEvent();

      await manager.enqueue(event);

      expect((await manager.pendingEvents()).single.id, event.id);
    });

    test(
      'pendingEvents returns only pending/failed retryable events',
      () async {
        final pending = testEvent(id: 'pending');
        final retryableFailed = testEvent(
          id: 'failed',
          syncStatus: QueueSyncStatus.failed,
          retryCount: 2,
        );
        final synced = testEvent(
          id: 'synced',
          syncStatus: QueueSyncStatus.synced,
        );
        final permanentlyFailed = testEvent(
          id: 'permanent',
          syncStatus: QueueSyncStatus.permanentlyFailed,
          retryCount: 3,
        );

        await manager.enqueue(pending);
        await manager.enqueue(retryableFailed);
        await manager.enqueue(synced);
        await manager.enqueue(permanentlyFailed);

        expect((await manager.pendingEvents()).map((event) => event.id), [
          'failed',
          'pending',
        ]);
      },
    );

    test('events are returned in FIFO order', () async {
      await manager.enqueue(testEvent(id: 'third', createdAt: timestamp(3)));
      await manager.enqueue(testEvent(id: 'first', createdAt: timestamp(1)));
      await manager.enqueue(testEvent(id: 'second', createdAt: timestamp(2)));

      expect((await manager.pendingEvents()).map((event) => event.id), [
        'first',
        'second',
        'third',
      ]);
    });

    test('markSyncing updates status', () async {
      final event = await manager.enqueue(testEvent());

      await manager.markSyncing(event.id);

      expect(
        (await manager.eventById(event.id))?.syncStatus,
        QueueSyncStatus.syncing,
      );
      expect(await manager.pendingEvents(), isEmpty);
    });

    test('markSynced updates status', () async {
      final event = await manager.enqueue(testEvent());

      await manager.markSynced(event.id);

      expect(
        (await manager.eventById(event.id))?.syncStatus,
        QueueSyncStatus.synced,
      );
      expect(await manager.pendingEvents(), isEmpty);
    });

    test('markFailed increments retry count', () async {
      final event = await manager.enqueue(testEvent());

      await manager.markFailed(event.id);
      final retryable = await manager.pendingEvents();

      expect(retryable.single.retryCount, 1);
      expect(retryable.single.syncStatus, QueueSyncStatus.failed);
    });

    test('third failure marks permanentlyFailed', () async {
      final event = await manager.enqueue(testEvent());

      await manager.markFailed(event.id);
      await manager.markFailed(event.id);
      await manager.markFailed(event.id);

      final storedEvent = await manager.eventById(event.id);
      expect(storedEvent?.syncStatus, QueueSyncStatus.permanentlyFailed);
      expect(storedEvent?.retryCount, 3);
      expect(await manager.pendingEvents(), isEmpty);
    });

    test('successful fake sync marks event synced', () async {
      final event = await manager.enqueue(testEvent());
      final client = RecordingSyncClient();

      await manager.syncPending(client);

      expect(client.syncedIds, [event.id]);
      expect(
        (await manager.eventById(event.id))?.syncStatus,
        QueueSyncStatus.synced,
      );
      expect(await manager.pendingEvents(), isEmpty);
    });

    test('failed fake sync leaves event retryable until retry limit', () async {
      final event = await manager.enqueue(testEvent());
      final client = FailingSyncClient();

      await manager.syncPending(client);
      expect((await manager.pendingEvents()).single.retryCount, 1);

      await manager.syncPending(client);
      expect((await manager.pendingEvents()).single.retryCount, 2);

      await manager.syncPending(client);
      final storedEvent = await manager.eventById(event.id);
      expect(storedEvent?.syncStatus, QueueSyncStatus.permanentlyFailed);
      expect(storedEvent?.retryCount, 3);
      expect(await manager.pendingEvents(), isEmpty);
      expect(client.attempts, 3);
    });

    test('statusSummary counts queue statuses and exposes helpers', () async {
      await manager.enqueue(testEvent(id: 'pending'));
      await manager.enqueue(
        testEvent(id: 'syncing', syncStatus: QueueSyncStatus.syncing),
      );
      await manager.enqueue(
        testEvent(id: 'synced', syncStatus: QueueSyncStatus.synced),
      );
      await manager.enqueue(
        testEvent(
          id: 'failed',
          syncStatus: QueueSyncStatus.failed,
          retryCount: 2,
        ),
      );
      await manager.enqueue(
        testEvent(
          id: 'permanent',
          syncStatus: QueueSyncStatus.permanentlyFailed,
          retryCount: 3,
        ),
      );

      final summary = await manager.statusSummary();

      expect(summary.pendingCount, 1);
      expect(summary.syncingCount, 1);
      expect(summary.syncedCount, 1);
      expect(summary.failedRetryableCount, 1);
      expect(summary.permanentlyFailedCount, 1);
      expect(summary.totalCount, 5);
      expect(summary.hasPendingWork, isTrue);
      expect(summary.hasRetryableFailures, isTrue);
      expect(summary.hasPermanentFailures, isTrue);
      expect(summary.isClear, isFalse);
    });

    test(
      'statusSummary is clear when no pending or failed work exists',
      () async {
        expect((await manager.statusSummary()).isClear, isTrue);

        final synced = await manager.enqueue(
          testEvent(id: 'synced', syncStatus: QueueSyncStatus.synced),
        );

        expect((await manager.statusSummary()).isClear, isTrue);

        final pending = await manager.enqueue(testEvent(id: 'pending'));

        expect((await manager.statusSummary()).isClear, isFalse);

        await manager.markSynced(pending.id);
        await manager.clearSynced();

        expect(await manager.eventById(synced.id), isNull);
        expect((await manager.statusSummary()).isClear, isTrue);
      },
    );

    test('pendingBadgeCount includes attention items only', () async {
      await manager.enqueue(testEvent(id: 'pending'));
      await manager.enqueue(
        testEvent(
          id: 'retryable',
          syncStatus: QueueSyncStatus.failed,
          retryCount: 1,
        ),
      );
      await manager.enqueue(
        testEvent(
          id: 'permanent',
          syncStatus: QueueSyncStatus.permanentlyFailed,
          retryCount: 3,
        ),
      );
      await manager.enqueue(
        testEvent(id: 'synced', syncStatus: QueueSyncStatus.synced),
      );

      expect(await manager.pendingBadgeCount(), 3);
    });

    test('offline connectivity prevents sync attempt', () async {
      await manager.enqueue(testEvent(id: 'pending', createdAt: timestamp(2)));
      await manager.enqueue(
        testEvent(
          id: 'failed',
          syncStatus: QueueSyncStatus.failed,
          retryCount: 1,
          createdAt: timestamp(1),
        ),
      );
      final client = RecordingSyncClient();
      final connectivity = FakeConnectivity.offline();

      final attempted = await manager.syncPendingWhenOnline(
        client,
        connectivity,
      );

      expect(attempted, isFalse);
      expect(client.syncedIds, isEmpty);
      expect((await manager.pendingEvents()).map((event) => event.id), [
        'failed',
        'pending',
      ]);
    });

    test('online connectivity allows fake sync and preserves FIFO', () async {
      await manager.enqueue(testEvent(id: 'third', createdAt: timestamp(3)));
      await manager.enqueue(testEvent(id: 'first', createdAt: timestamp(1)));
      await manager.enqueue(testEvent(id: 'second', createdAt: timestamp(2)));
      final client = RecordingSyncClient();
      final connectivity = FakeConnectivity.online();

      final attempted = await manager.syncPendingWhenOnline(
        client,
        connectivity,
      );

      expect(attempted, isTrue);
      expect(client.syncedIds, ['first', 'second', 'third']);
      expect(await manager.pendingEvents(), isEmpty);
    });

    test('clearSynced removes synced events only', () async {
      final pending = await manager.enqueue(testEvent(id: 'pending'));
      final synced = await manager.enqueue(testEvent(id: 'synced'));
      await manager.markSynced(synced.id);

      await manager.clearSynced();

      expect((await manager.pendingEvents()).map((event) => event.id), [
        pending.id,
      ]);
    });
  });
}

QueuedEvent testEvent({
  String? id,
  String eventType = 'driver_trip_note',
  String tripReference = 'ASM-TRIP-001',
  String driverId = 'driver-001',
  Map<String, Object?> payloadJson = const {'action': 'arrived'},
  String? idempotencyKey,
  QueueSyncStatus syncStatus = QueueSyncStatus.pending,
  int retryCount = 0,
  DateTime? createdAt,
}) {
  return QueuedEvent(
    id: id,
    eventType: eventType,
    tripReference: tripReference,
    driverId: driverId,
    payloadJson: payloadJson,
    idempotencyKey: idempotencyKey,
    deviceTimestamp: DateTime.utc(2026, 1, 1, 12),
    syncStatus: syncStatus,
    retryCount: retryCount,
    createdAt: createdAt ?? timestamp(1),
  );
}

DateTime timestamp(int second) => DateTime.utc(2026, 1, 1, 12, 0, second);

final class RecordingSyncClient implements OfflineQueueSyncClient {
  final syncedIds = <String>[];

  @override
  Future<void> syncEvent(QueuedEvent event) async {
    syncedIds.add(event.id);
  }
}

final class FailingSyncClient implements OfflineQueueSyncClient {
  int attempts = 0;

  @override
  Future<void> syncEvent(QueuedEvent event) async {
    attempts += 1;
    throw StateError('fake sync failure');
  }
}

final class FakeConnectivity implements OfflineQueueConnectivity {
  const FakeConnectivity({required this.isOnlineValue});

  FakeConnectivity.online() : isOnlineValue = true;

  FakeConnectivity.offline() : isOnlineValue = false;

  final bool isOnlineValue;

  @override
  Future<bool> get isOnline async => isOnlineValue;
}
