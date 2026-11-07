import 'dart:async';
import 'dart:io';

import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_auth/asm_auth.dart';
import 'package:driver_app/main.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:asm_offline_queue/asm_offline_queue.dart';
import 'package:driver_app/driver_duty_trips.dart';
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

  // Lead, 7 Nov: stop() must not be permanent, and a run left over from a
  // disposed Work must neither keep sending nor send beside the new run.
  group('a run left over from a Work that went away', () {
    test(
      'waiting on its delay: it ends, and the new run sends alone',
      () async {
        final queue = _Queue();
        final waits = <Completer<void>>[];
        final retry = DriverGoOfflineRetry(
          queue: queue,
          driverTag: () async => _me,
          wait: (_) {
            final wait = Completer<void>();
            waits.add(wait);
            return wait.future;
          },
        );
        final status = _Status()..answers.addAll([_noAnswer, null]);
        await retry.remember();
        final landedBy = <String>[];

        final oldRun = retry.runUntilLanded(
          status,
          onLanded: (_) => landedBy.add('old'),
          onSessionEnded: () {},
        );
        await pumpEventQueue();
        expect(status.calls, 1);
        expect(waits, hasLength(1));

        retry.stop();
        final newRun = retry.runUntilLanded(
          status,
          onLanded: (_) => landedBy.add('new'),
          onSessionEnded: () {},
        );
        await oldRun;
        await newRun;

        expect(waits.single.isCompleted, isFalse);
        expect(status.calls, 2);
        expect(landedBy, ['new']);
        expect(await retry.isPending(), isFalse);
      },
    );

    test(
      'after stop, a late landing never calls the Work that went away',
      () async {
        final queue = _Queue();
        final retry = DriverGoOfflineRetry(
          queue: queue,
          driverTag: () async => _me,
          wait: (_) async {},
        );
        final status = _HeldStatus();
        await retry.remember();
        final calledBack = <String>[];

        final oldRun = retry.runUntilLanded(
          status,
          onLanded: (_) => calledBack.add('landed'),
          onSessionEnded: () => calledBack.add('session ended'),
        );
        await pumpEventQueue();
        retry.stop();
        status.answer(null);
        await oldRun;

        expect(calledBack, isEmpty);
        expect(await retry.isPending(), isFalse);
        expect(queue.removals, 1);
      },
    );

    test(
      'after stop, a late "session ended" never calls the Work that went away',
      () async {
        final queue = _Queue();
        final retry = DriverGoOfflineRetry(
          queue: queue,
          driverTag: () async => _me,
          wait: (_) async {},
        );
        final status = _HeldStatus();
        await retry.remember();
        final calledBack = <String>[];

        final oldRun = retry.runUntilLanded(
          status,
          onLanded: (_) => calledBack.add('landed'),
          onSessionEnded: () => calledBack.add('session ended'),
        );
        await pumpEventQueue();
        retry.stop();
        status.answer(_expired);
        await oldRun;

        expect(calledBack, isEmpty);
      },
    );

    test('a second failure while a run waits: the next try waits the first '
        'delay', () async {
      final queue = _Queue();
      final waits = <Completer<void>>[];
      final retry = DriverGoOfflineRetry(
        queue: queue,
        driverTag: () async => _me,
        wait: (_) {
          final wait = Completer<void>();
          waits.add(wait);
          return wait.future;
        },
      );
      final status = _Status()..answers.add(null);
      await retry.remember();

      final first = retry.runUntilLanded(
        status,
        onLanded: (_) {},
        onSessionEnded: () {},
        waitFirst: true,
      );
      await pumpEventQueue();
      // GO OFFLINE (Retry button) failed again: Work starts a new run.
      final second = retry.runUntilLanded(
        status,
        onLanded: (_) {},
        onSessionEnded: () {},
        waitFirst: true,
      );
      await pumpEventQueue();

      expect(status.calls, 0, reason: 'nothing sent at once');
      expect(waits, hasLength(2));
      waits.last.complete();
      await first;
      await second;
      expect(status.calls, 1);
      expect(await retry.isPending(), isFalse);
    });

    test('a request in flight: no second request beside it', () async {
      final queue = _Queue();
      final retry = DriverGoOfflineRetry(
        queue: queue,
        driverTag: () async => _me,
        // Waits end only when a run is cut short: an old run that waited
        // after its failure would hold up the new run.
        wait: (_) => Completer<void>().future,
      );
      final status = _HeldStatus();
      await retry.remember();
      final landedBy = <String>[];

      final oldRun = retry.runUntilLanded(
        status,
        onLanded: (_) => landedBy.add('old'),
        onSessionEnded: () {},
      );
      await pumpEventQueue();
      expect(status.calls, 1);

      retry.stop();
      final newRun = retry.runUntilLanded(
        status,
        onLanded: (_) => landedBy.add('new'),
        onSessionEnded: () {},
      );
      await pumpEventQueue();
      expect(status.calls, 1, reason: 'no request beside the one in flight');

      status.answer(_noAnswer);
      await pumpEventQueue();
      expect(status.calls, 2, reason: 'the new run sends after the old ends');
      status.answer(null);
      await oldRun;
      await newRun;

      expect(landedBy, ['new']);
      expect(await retry.isPending(), isFalse);
    });

    test(
      'its request lands after the new Work started: the new Work is told',
      () async {
        final queue = _Queue();
        final retry = DriverGoOfflineRetry(
          queue: queue,
          driverTag: () async => _me,
          wait: (_) async {},
        );
        final status = _HeldStatus();
        await retry.remember();
        final landedBy = <String>[];

        final oldRun = retry.runUntilLanded(
          status,
          onLanded: (_) => landedBy.add('old'),
          onSessionEnded: () {},
        );
        await pumpEventQueue();
        retry.stop();
        final newRun = retry.runUntilLanded(
          status,
          onLanded: (_) => landedBy.add('new'),
          onSessionEnded: () {},
        );
        status.answer(null);
        await oldRun;
        await newRun;

        expect(status.calls, 1);
        expect(landedBy, ['new']);
        expect(await retry.isPending(), isFalse);
        expect(queue.removals, 1, reason: 'the record goes exactly once');
      },
    );

    // Lead, 7 Nov (delta 8): an older run that fails (here its queue
    // throws) neither stops nor fails the new run, and nothing is left as
    // an uncaught async error (that would fail this test by itself).
    test('it fails: its own caller gets the error, the new run still '
        'sends', () async {
      final queue = _FailingReadQueue();
      final retry = DriverGoOfflineRetry(
        queue: queue,
        driverTag: () async => _me,
        wait: (_) async {},
      );
      final status = _Status();
      await retry.remember();
      final hold = Completer<void>();
      queue
        ..failNextRead = true
        ..hold = hold;
      final landedBy = <String>[];

      final oldRun = retry.runUntilLanded(
        status,
        onLanded: (_) => landedBy.add('old'),
        onSessionEnded: () {},
      );
      final oldFailed = expectLater(oldRun, throwsA(isA<StateError>()));
      await pumpEventQueue();
      final newRun = retry.runUntilLanded(
        status,
        onLanded: (_) => landedBy.add('new'),
        onSessionEnded: () {},
      );
      hold.complete();
      await oldFailed;
      await newRun;

      expect(status.calls, 1);
      expect(landedBy, ['new']);
      expect(await retry.isPending(), isFalse);
    });
  });

  // Lead, 7 Nov (a): through the real DriverApp, the same retry serves the
  // Work of a second sign-in in the same app process.
  testWidgets('after sign-out and a new sign-in, a failed GO OFFLINE is '
      'retried again', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    final tokens = MemoryAuthTokenStore();
    final queue = _Queue();
    final duty = _AppDuty();
    await tester.pumpWidget(
      DriverApp(
        showLoginShell: true,
        authService: AuthService(
          apiGateway: _AuthApi(),
          tokenStore: tokens,
          appContext: AuthAppContext.driver,
        ),
        authTokenStore: tokens,
        driverDutyGateway: duty,
        goOfflineRetry: DriverGoOfflineRetry(
          queue: queue,
          driverTag: () async => _me,
        ),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> signIn() async {
      await tester.enterText(
        find.byKey(const Key('driver-phone-field')),
        '+233000000001',
      );
      await tester.enterText(find.byKey(const Key('driver-pin-field')), '9876');
      await tester.tap(find.byKey(const Key('driver-sign-in')));
      await tester.pumpAndSettle();
    }

    Future<void> goOfflineFailsThenRetryLands() async {
      duty.offlineAnswers.addAll([_noAnswer, null]);
      await tester.tap(find.text('GO OFFLINE'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('driver-go-offline-error')), findsOneWidget);
      await tester.pump(driverGoOfflineRetryDelays.first);
      await tester.pumpAndSettle();
    }

    await signIn();
    await goOfflineFailsThenRetryLands();
    expect(duty.offlineCalls, 2);
    expect(find.text('GO OFFLINE'), findsNothing);

    await tester.tap(find.text('GO ONLINE'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Account'));
    await tester.pumpAndSettle();
    final signOut = find.byKey(const Key('driver-account-sign-out'));
    await tester.ensureVisible(signOut);
    await tester.pumpAndSettle();
    await tester.tap(signOut);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('driver-sign-in')), findsOneWidget);

    duty.online = true;
    await signIn();
    await goOfflineFailsThenRetryLands();

    expect(duty.offlineCalls, 4);
    expect(find.text('GO OFFLINE'), findsNothing);
    expect(queue.events, isEmpty);
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

    // Lead, 7 Nov (delta 8): Work starts runs without waiting for them; a
    // run that fails must not become an uncaught error in the app (that
    // would fail this test by itself), and the next GO OFFLINE retries.
    testWidgets('a run that fails is no uncaught error; the next GO OFFLINE '
        'still retries', (tester) async {
      final queue = _FailingReadQueue()..failNextRead = true;
      final duty = await pumpShell(tester, online: true, queue: queue);
      expect(queue.failNextRead, isFalse, reason: 'the start run read it');
      duty.answers.addAll([_noAnswer, null]);

      await tester.tap(find.text('GO OFFLINE'));
      await tester.pumpAndSettle();
      await tester.pump(driverGoOfflineRetryDelays.first);
      await tester.pumpAndSettle();

      expect(duty.offlineCalls, 2);
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
  /// How many times anything was deleted.
  int removals = 0;

  @override
  Future<int> removeWhere(bool Function(QueuedEvent event) test) async {
    removals += 1;
    final ids = events.values.where(test).map((e) => e.id).toList();
    ids.forEach(events.remove);
    return ids.length;
  }
}

/// A queue whose next read throws (after [hold] completes, when set).
final class _FailingReadQueue extends _Queue {
  bool failNextRead = false;
  Completer<void>? hold;

  @override
  Future<QueuedEvent?> eventById(String id) async {
    if (!failNextRead) {
      return super.eventById(id);
    }
    failNextRead = false;
    final wait = hold;
    hold = null;
    if (wait != null) {
      await wait.future;
    }
    throw StateError('the queue could not be read');
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

/// GO OFFLINE requests held until the test answers each one.
final class _HeldStatus implements DriverDutyStatusGateway {
  int calls = 0;
  final _pending = <Completer<DriverDutyTransition>>[];

  void answer(DriverDutyApiException? error) {
    final next = _pending.removeAt(0);
    if (error == null) {
      next.complete(
        DriverDutyTransition(
          dutyStatus: 'offline',
          since: DateTime.utc(2026, 11, 7, 9),
        ),
      );
    } else {
      next.completeError(error);
    }
  }

  @override
  Future<DriverDutyTransition> updateDutyStatus(
    DriverOperationalDutyStatus status,
  ) {
    calls += 1;
    final pending = Completer<DriverDutyTransition>();
    _pending.add(pending);
    return pending.future;
  }
}

/// Duty for the whole-app test: online until GO OFFLINE lands.
final class _AppDuty implements DriverDutyGateway, DriverDutyStatusGateway {
  bool online = true;
  final offlineAnswers = <DriverDutyApiException?>[];
  int offlineCalls = 0;

  @override
  Future<DriverDutySummary> fetchDuty() async => DriverDutySummary(
    driverReference: 'DRV-001',
    dutyStatus: online ? 'online' : 'offline',
    dutySince: DateTime(2026, 11, 7, 8),
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
    if (status == DriverOperationalDutyStatus.offline) {
      offlineCalls += 1;
      final error = offlineAnswers.isEmpty ? null : offlineAnswers.removeAt(0);
      if (error != null) {
        throw error;
      }
    }
    online = status == DriverOperationalDutyStatus.online;
    return DriverDutyTransition(
      dutyStatus: status.wireValue,
      since: DateTime(2026, 11, 7, 9),
    );
  }
}

final class _AuthApi implements AuthApiGateway {
  @override
  Future<ApiResponse<Map<String, Object?>>> post(
    String path, {
    required Map<String, Object?> body,
  }) async => ApiResponse<Map<String, Object?>>.success(
    path == AuthService.logoutPath
        ? <String, Object?>{'detail': 'Signed out.'}
        : <String, Object?>{
            'access': 'driver-access',
            'refresh': 'driver-refresh',
            'account_type': 'driver',
            'account': <String, Object?>{},
          },
    statusCode: 200,
  );
}
