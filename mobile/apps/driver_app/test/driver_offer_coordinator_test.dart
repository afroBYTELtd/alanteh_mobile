import 'dart:async';

import 'package:driver_app/driver_duty_trips.dart';
import 'package:driver_app/offers/driver_offer_coordinator.dart';
import 'package:driver_app/offers/driver_pending_offer_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _CountingSource source;
  late _ManualClock clock;
  late _FakeTimers timers;
  late DriverOfferCoordinator coordinator;

  setUp(() {
    source = _CountingSource();
    clock = _ManualClock();
    timers = _FakeTimers();
    coordinator = DriverOfferCoordinator(
      store: DriverPendingOfferStore(source: source, clock: clock),
      periodicTimer: timers.create,
    );
  });

  group('polling', () {
    test(
      'polls every 12 s only on duty, in front, with no card open',
      () async {
        coordinator.setForeground(true);
        expect(coordinator.polling, isFalse);

        coordinator.setOnDuty(true);
        expect(coordinator.polling, isTrue);
        expect(timers.intervals.last, const Duration(seconds: 12));
        await pumpEventQueue();
        final afterStart = source.calls;
        expect(afterStart, 1, reason: 'going on duty fetches at once');

        timers.tick();
        await pumpEventQueue();
        expect(source.calls, afterStart + 1);
      },
    );

    test('pauses in the background and fetches at once on return', () async {
      coordinator
        ..setForeground(true)
        ..setOnDuty(true);
      await pumpEventQueue();
      coordinator.setForeground(false);
      expect(coordinator.polling, isFalse);
      final before = source.calls;

      coordinator.setForeground(true);
      expect(coordinator.polling, isTrue);
      await pumpEventQueue();
      expect(source.calls, before + 1, reason: 'resume fetches at once');
    });

    // B5: a card left open while the app was away may show an offer that
    // ended meanwhile; the poll is paused for it, so ask at once.
    test('back in front: fetches at once even with a card open', () async {
      coordinator
        ..setForeground(true)
        ..setOnDuty(true)
        ..cardOpened();
      await pumpEventQueue();
      coordinator.setForeground(false);
      final before = source.calls;

      coordinator.setForeground(true);
      await pumpEventQueue();

      expect(source.calls, before + 1);
      expect(coordinator.polling, isFalse, reason: 'paused for the card');
    });

    test('returning to the front off duty fetches nothing', () async {
      coordinator.setForeground(false);
      final before = source.calls;

      coordinator.setForeground(true);
      await pumpEventQueue();

      expect(source.calls, before);
    });

    test('pauses while a card is open', () async {
      coordinator
        ..setForeground(true)
        ..setOnDuty(true)
        ..cardOpened();
      expect(coordinator.polling, isFalse);
      coordinator.cardClosed();
      expect(coordinator.polling, isTrue);
    });

    test('stops off duty', () {
      coordinator
        ..setForeground(true)
        ..setOnDuty(true)
        ..setOnDuty(false);
      expect(coordinator.polling, isFalse);
      expect(timers.active, 0);
    });

    test('an offer push fetches even off duty or with a card open', () async {
      coordinator.cardOpened();
      await coordinator.offerPushed();
      expect(source.calls, 1);
    });
  });

  group('a push tap before sign-in', () {
    test('is kept for about 2 minutes, then dropped', () {
      clock.value = const Duration(seconds: 10);
      coordinator.queueTap('TRIP-1');
      clock.value = const Duration(seconds: 10 + 119);
      expect(coordinator.takeTap()?.tripReference, 'TRIP-1');
      expect(coordinator.takeTap(), isNull, reason: 'taken only once');

      coordinator.queueTap('TRIP-2');
      clock.value += const Duration(minutes: 2, seconds: 1);
      expect(coordinator.takeTap(), isNull);
    });

    test('is dropped by clear()', () {
      coordinator.queueTap('TRIP-1');
      coordinator.clear();
      expect(coordinator.takeTap(), isNull);
    });
  });

  test('clear() forgets offers and the cached driver', () async {
    final identity = DriverIdentityCachingDutyGateway(_Duty());
    coordinator = DriverOfferCoordinator(
      store: DriverPendingOfferStore(source: source, clock: clock),
      identity: identity,
      periodicTimer: timers.create,
    );
    await identity.fetchDuty();
    await coordinator.offerPushed();
    expect(coordinator.store.snapshot, isNotNull);
    expect(identity.driverReference, 'DRV-1');

    coordinator.clear();
    expect(coordinator.store.snapshot, isNull);
    expect(identity.driverReference, isNull);
  });
}

final class _CountingSource implements DriverPendingOffersSource {
  var calls = 0;

  @override
  Future<DriverPendingOffersFetch> fetch() async {
    calls += 1;
    return const DriverPendingOffersFetched(<String, Object?>{
      'server_time': '2026-10-09T10:00:00+00:00',
      'offers': <Object?>[],
    });
  }
}

final class _ManualClock implements DriverMonotonicClock {
  Duration value = Duration.zero;

  @override
  Duration get now => value;
}

final class _FakeTimers {
  final intervals = <Duration>[];
  final _timers = <_FakeTimer>[];

  int get active => _timers.where((t) => t.isActive).length;

  Timer create(Duration interval, void Function(Timer) onTick) {
    intervals.add(interval);
    final timer = _FakeTimer(onTick);
    _timers.add(timer);
    return timer;
  }

  void tick() {
    for (final timer in List.of(_timers)) {
      if (timer.isActive) {
        timer.onTick(timer);
      }
    }
  }
}

final class _FakeTimer implements Timer {
  _FakeTimer(this.onTick);

  final void Function(Timer) onTick;
  var _active = true;

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;

  @override
  void cancel() => _active = false;
}

final class _Duty implements DriverDutyGateway {
  @override
  Future<DriverDutySummary> fetchDuty() async =>
      const DriverDutySummary(driverReference: 'DRV-1', dutyStatus: 'online');

  @override
  Future<List<DriverAssignedTrip>> fetchTrips() async => const [];

  @override
  Future<DriverAssignedTrip> fetchTripDetail(String tripReference) =>
      throw UnimplementedError();
}
