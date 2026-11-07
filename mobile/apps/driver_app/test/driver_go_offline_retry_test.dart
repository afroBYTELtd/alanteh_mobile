import 'dart:async';
import 'dart:io';

import 'package:asm_design_system/asm_design_system.dart';
import 'package:asm_offline_queue/asm_offline_queue.dart';
import 'package:driver_app/driver_duty_trips.dart';
import 'package:driver_app/driver_shell.dart';
import 'package:driver_app/duty/driver_go_offline_retry.dart';
import 'package:driver_app/network/driver_trip_action_resilience.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Sign-in build A3 (the lead's addendum): a failed GO OFFLINE is queued and
// retried until it lands, also after the app restarts, and cancelled if the
// driver goes online meanwhile. Only the signed-in driver's is sent.

const _me = 'user:7';

const _noAnswer = DriverDutyApiException(
  DriverDutyApiFailureType.unavailable,
  'Driver information is temporarily unavailable.',
  noAnswer: true,
);

const _expired = DriverDutyApiException(
  DriverDutyApiFailureType.sessionExpired,
  driverSessionExpiredMessage,
);

void main() {
  group('DriverGoOfflineRetry', () {
    late _Queue queue;
    late _Status status;
    late List<Duration> waits;
    late DriverGoOfflineRetry retry;

    setUp(() {
      queue = _Queue();
      status = _Status();
      waits = <Duration>[];
      retry = DriverGoOfflineRetry(
        queue: queue,
        driverTag: () async => _me,
        wait: (delay) async => waits.add(delay),
      );
    });

    test('remembered once, tagged with the driver', () async {
      await retry.remember();
      await retry.remember();

      expect(await retry.isPending(), isTrue);
      expect(queue.events.values.single.driverId, _me);
      expect(queue.events.values.single.payloadJson, {'status': 'offline'});
    });

    test('retried until it lands, on the backoff, then forgotten', () async {
      status.answers.addAll([_noAnswer, _noAnswer, null]);
      await retry.remember();
      DriverDutyTransition? landed;

      await retry.runUntilLanded(
        status,
        onLanded: (transition) => landed = transition,
        onSessionEnded: () {},
      );

      expect(status.calls, 3);
      expect(waits, driverGoOfflineRetryDelays.take(2).toList());
      expect(landed?.dutyStatus, 'offline');
      expect(await retry.isPending(), isFalse);
    });

    test('after the listed delays it keeps trying every last delay', () async {
      status.answers.addAll([
        for (var i = 0; i < driverGoOfflineRetryDelays.length + 2; i += 1)
          _noAnswer,
        null,
      ]);
      await retry.remember();

      await retry.runUntilLanded(
        status,
        onLanded: (_) {},
        onSessionEnded: () {},
      );

      expect(waits.last, driverGoOfflineRetryDelays.last);
      expect(status.calls, driverGoOfflineRetryDelays.length + 3);
    });

    test('right after a failure: the first delay comes first', () async {
      status.answers.add(null);
      await retry.remember();

      await retry.runUntilLanded(
        status,
        onLanded: (_) {},
        onSessionEnded: () {},
        waitFirst: true,
      );

      expect(waits, [driverGoOfflineRetryDelays.first]);
      expect(status.calls, 1);
    });

    test('the delays', () {
      expect(driverGoOfflineRetryDelays, const [
        Duration(seconds: 5),
        Duration(seconds: 15),
        Duration(seconds: 30),
        Duration(seconds: 60),
      ]);
    });

    test('cancelled meanwhile: no more tries, forgotten', () async {
      status.answers.addAll([_noAnswer, null]);
      await retry.remember();
      retry = DriverGoOfflineRetry(
        queue: queue,
        driverTag: () async => _me,
        wait: (delay) async {
          waits.add(delay);
          await retry.cancel();
        },
      );

      await retry.runUntilLanded(
        status,
        onLanded: (_) => fail('must not land'),
        onSessionEnded: () {},
      );

      expect(status.calls, 1);
      expect(await retry.isPending(), isFalse);
    });

    test('another kind of failure (a timeout) is retried too', () async {
      final status = _ThrowingOnce(TimeoutException('no answer'));
      await retry.remember();

      await retry.runUntilLanded(
        status,
        onLanded: (_) {},
        onSessionEnded: () {},
      );

      expect(status.calls, 2);
      expect(await retry.isPending(), isFalse);
    });

    test('a queue that cannot delete: cancelled stays cancelled', () async {
      final plain = _PlainQueue();
      final kept = DriverGoOfflineRetry(
        queue: plain,
        driverTag: () async => _me,
      );
      await kept.remember();

      await kept.cancel();
      await kept.runUntilLanded(
        status,
        onLanded: (_) => fail('must not land'),
        onSessionEnded: () {},
      );

      expect(await kept.isPending(), isFalse);
      expect(status.calls, 0);
    });

    test('stopped (Work went away): tries end, the record stays', () async {
      status.answers.addAll([_noAnswer, _noAnswer, _noAnswer]);
      await retry.remember();
      retry = DriverGoOfflineRetry(
        queue: queue,
        driverTag: () async => _me,
        wait: (delay) async => retry.stop(),
      );

      await retry.runUntilLanded(
        status,
        onLanded: (_) => fail('must not land'),
        onSessionEnded: () {},
      );

      expect(status.calls, 1);
      expect(await retry.isPending(), isTrue);
    });

    test('nothing pending: nothing sent', () async {
      await retry.runUntilLanded(
        status,
        onLanded: (_) => fail('must not land'),
        onSessionEnded: () {},
      );

      expect(status.calls, 0);
    });

    test("another driver's is never sent", () async {
      final theirs = DriverGoOfflineRetry(
        queue: queue,
        driverTag: () async => 'user:8',
      );
      await theirs.remember();

      await retry.runUntilLanded(
        status,
        onLanded: (_) => fail('must not land'),
        onSessionEnded: () {},
      );

      expect(status.calls, 0);
      expect(await theirs.isPending(), isTrue);
    });

    test('the session ended: stops, forgotten, sign-in', () async {
      status.answers.add(_expired);
      await retry.remember();
      var ended = 0;

      await retry.runUntilLanded(
        status,
        onLanded: (_) => fail('must not land'),
        onSessionEnded: () => ended += 1,
      );

      expect(ended, 1);
      expect(status.calls, 1);
      expect(await retry.isPending(), isFalse);
    });
  });

  test("the app gives Work a retry on its own queue", () {
    final source = File('lib/main.dart').readAsStringSync();

    expect(source, contains('goOfflineRetry: widget.goOfflineRetry'));
    expect(
      source.replaceAll(RegExp(r'\s+'), ' '),
      contains('DriverGoOfflineRetry( queue: sharedPersistentQueue,'),
    );
  });

  group('Work', () {
    final now = DateTime(2026, 11, 7, 9);

    Future<_Duty> pumpShell(
      WidgetTester tester, {
      required bool online,
      required _Queue queue,
    }) async {
      final duty = _Duty(online: online, now: now);
      await tester.pumpWidget(
        MaterialApp(
          theme: AsmThemes.driver,
          home: DriverShell(
            driverDutyGateway: duty,
            deviceNow: () => now,
            goOfflineRetry: DriverGoOfflineRetry(
              queue: queue,
              driverTag: () async => _me,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();
      return duty;
    }

    testWidgets('a failed GO OFFLINE lands by itself later', (tester) async {
      final queue = _Queue();
      final duty = await pumpShell(tester, online: true, queue: queue);
      duty.answers.addAll([_noAnswer, null]);

      await tester.tap(find.text('GO OFFLINE'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('driver-go-offline-error')), findsOneWidget);

      await tester.pump(driverGoOfflineRetryDelays.first);
      await tester.pumpAndSettle();

      expect(duty.offlineCalls, 2);
      expect(find.byKey(const Key('driver-go-offline-error')), findsNothing);
      expect(find.text('GO OFFLINE'), findsNothing);
      expect(queue.events, isEmpty);
    });

    testWidgets('after a restart, a remembered GO OFFLINE is sent', (
      tester,
    ) async {
      final queue = _Queue();
      await DriverGoOfflineRetry(
        queue: queue,
        driverTag: () async => _me,
      ).remember();

      final duty = await pumpShell(tester, online: true, queue: queue);

      expect(duty.offlineCalls, 1);
      expect(find.text('GO OFFLINE'), findsNothing);
      expect(queue.events, isEmpty);
    });

    testWidgets('going online meanwhile cancels it', (tester) async {
      final queue = _Queue();
      await DriverGoOfflineRetry(
        queue: queue,
        driverTag: () async => _me,
      ).remember();
      final duty = _Duty(online: false, now: now)
        ..answers.addAll([_noAnswer, _noAnswer, _noAnswer]);
      await tester.pumpWidget(
        MaterialApp(
          theme: AsmThemes.driver,
          home: DriverShell(
            driverDutyGateway: duty,
            deviceNow: () => now,
            goOfflineRetry: DriverGoOfflineRetry(
              queue: queue,
              driverTag: () async => _me,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();
      expect(duty.offlineCalls, 1);

      await tester.tap(find.text('GO ONLINE'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(minutes: 5));
      await tester.pumpAndSettle();

      expect(duty.onlineCalls, 1);
      expect(duty.offlineCalls, 1);
      expect(queue.events, isEmpty);
    });
  });
}

final class _Status implements DriverDutyStatusGateway {
  /// One per call: an error to throw, or null for success.
  final answers = <DriverDutyApiException?>[];
  int calls = 0;

  @override
  Future<DriverDutyTransition> updateDutyStatus(
    DriverOperationalDutyStatus status,
  ) async {
    calls += 1;
    final error = answers.isEmpty ? null : answers.removeAt(0);
    if (error != null) {
      throw error;
    }
    return DriverDutyTransition(
      dutyStatus: status.wireValue,
      since: DateTime.utc(2026, 11, 7, 9),
    );
  }
}

final class _Duty implements DriverDutyGateway, DriverDutyStatusGateway {
  _Duty({required this.online, required this.now});

  bool online;
  final DateTime now;

  /// Answers for GO OFFLINE, one per call: an error, or null for success.
  final answers = <DriverDutyApiException?>[];
  int offlineCalls = 0;
  int onlineCalls = 0;

  @override
  Future<DriverDutySummary> fetchDuty() async => DriverDutySummary(
    driverReference: 'DRV-001',
    dutyStatus: online ? 'online' : 'offline',
    dutySince: now.subtract(const Duration(hours: 1)),
    shiftCheckToday: true,
  );

  @override
  Future<List<DriverAssignedTrip>> fetchTrips() async =>
      const <DriverAssignedTrip>[];

  @override
  Future<DriverAssignedTrip> fetchTripDetail(String tripReference) =>
      throw StateError('not used');

  @override
  Future<DriverDutyTransition> updateDutyStatus(
    DriverOperationalDutyStatus status,
  ) async {
    if (status == DriverOperationalDutyStatus.online) {
      onlineCalls += 1;
      online = true;
    } else {
      offlineCalls += 1;
      final error = answers.isEmpty ? null : answers.removeAt(0);
      if (error != null) {
        throw error;
      }
      online = false;
    }
    return DriverDutyTransition(dutyStatus: status.wireValue, since: now);
  }
}

class _PlainQueue implements DriverTripActionPersistentQueue {
  final events = <String, QueuedEvent>{};

  @override
  Future<QueuedEvent> enqueue(QueuedEvent event) async =>
      events[event.id] = event;

  @override
  Future<QueuedEvent?> eventById(String id) async => events[id];

  @override
  Future<List<QueuedEvent>> pendingEvents() async => events.values
      .where(
        (e) =>
            e.syncStatus == QueueSyncStatus.pending ||
            e.syncStatus == QueueSyncStatus.failed,
      )
      .toList();

  @override
  Future<void> markSynced(String id) async {
    events[id] = events[id]!.copyWith(syncStatus: QueueSyncStatus.synced);
  }

  @override
  Future<void> markFailed(String id) async {
    events[id] = events[id]!.copyWith(syncStatus: QueueSyncStatus.failed);
  }

  @override
  Future<void> markPermanentlyFailed(String id) async {
    events[id] = events[id]!.copyWith(
      syncStatus: QueueSyncStatus.permanentlyFailed,
    );
  }
}

final class _Queue extends _PlainQueue implements DriverQueueCleanup {
  @override
  Future<int> removeWhere(bool Function(QueuedEvent event) test) async {
    final ids = events.values.where(test).map((e) => e.id).toList();
    ids.forEach(events.remove);
    return ids.length;
  }
}

final class _ThrowingOnce implements DriverDutyStatusGateway {
  _ThrowingOnce(this.error);

  final Object error;
  int calls = 0;

  @override
  Future<DriverDutyTransition> updateDutyStatus(
    DriverOperationalDutyStatus status,
  ) async {
    calls += 1;
    if (calls == 1) {
      throw error;
    }
    return DriverDutyTransition(
      dutyStatus: status.wireValue,
      since: DateTime.utc(2026, 11, 7, 9),
    );
  }
}
