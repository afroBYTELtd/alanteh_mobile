import 'dart:async';

import 'package:driver_app/driver_duty_trips.dart';
import 'package:driver_app/network/driver_offer_response_resilience.dart';
import 'package:driver_app/offers/driver_offer_coordinator.dart';
import 'package:driver_app/offers/driver_pending_offer_card.dart';
import 'package:driver_app/offers/driver_pending_offer_store.dart';
import 'package:driver_app/trip_progress/driver_live_trip_check.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Phone session, 24 Oct: dispatch cancelled TRIP-E706AB2E12C1 while the
// driver had its "Assigned trip detail" screen open. The cancel push reached
// the app, but that screen still said "Driver accepted" with "Continue live
// trip". And on 23 Oct an offer card prepared an Accept for
// TRIP-4F5837A6421D half an hour after the trip had ended: the card trusted
// an old list of pending offers.
void main() {
  group('the open trip screen when the trip ends', () {
    late _TripGateway gateway;

    setUp(() => gateway = _TripGateway('driver_accepted'));

    Future<void> open(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: DriverTripDetailScreen(
            gateway: gateway,
            tripReference: 'TRIP-1',
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('Driver accepted'), findsOneWidget);
    }

    testWidgets('a cancel push makes the open screen show the cancel', (
      tester,
    ) async {
      await open(tester);
      gateway.status = 'cancelled_by_operations';

      expect(DriverLiveTripScreens.instance.checkNow('TRIP-1'), isTrue);
      await tester.pump();
      await tester.pump();

      expect(find.text('Trip cancelled'), findsOneWidget);
      expect(find.text('Continue live trip'), findsNothing);
      expect(find.text('Driver accepted'), findsNothing);
    });

    testWidgets('a missed push is caught by the 12 s re-check', (tester) async {
      await open(tester);
      gateway.status = 'cancelled_by_operations';

      await tester.pump(const Duration(seconds: 11));
      expect(find.text('Driver accepted'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      expect(find.text('Trip cancelled'), findsOneWidget);
      expect(find.text('Continue live trip'), findsNothing);
    });

    testWidgets('the re-check keeps going while the trip is live', (
      tester,
    ) async {
      await open(tester);
      final loads = gateway.calls;

      await tester.pump(const Duration(seconds: 36));

      expect(gateway.calls, loads + 3);
      expect(find.text('Driver accepted'), findsOneWidget);
    });

    testWidgets('the re-check stops once the trip has ended', (tester) async {
      await open(tester);
      gateway.status = 'cancelled_by_passenger';
      await tester.pump(const Duration(seconds: 12));
      await tester.pump();
      final loads = gateway.calls;

      await tester.pump(const Duration(seconds: 60));

      expect(gateway.calls, loads);
    });

    testWidgets('a failed re-check keeps the screen as it was', (tester) async {
      await open(tester);
      gateway.fail = true;

      await tester.pump(const Duration(seconds: 12));
      await tester.pump();

      expect(find.text('Driver accepted'), findsOneWidget);
      expect(find.text('Trip detail could not be loaded.'), findsNothing);
    });

    testWidgets('closing the screen stops the re-check and the push hook', (
      tester,
    ) async {
      await open(tester);
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      final loads = gateway.calls;

      await tester.pump(const Duration(seconds: 30));

      expect(gateway.calls, loads);
      expect(DriverLiveTripScreens.instance.checkNow('TRIP-1'), isFalse);
    });
  });

  group('one cancel push reaches every open screen for the trip', () {
    test('a second screen for the same trip does not replace the first', () {
      var detail = 0;
      var live = 0;
      void onDetail() => detail += 1;
      void onLive() => live += 1;
      final screens = DriverLiveTripScreens.instance
        ..register('TRIP-2', onDetail)
        ..register('trip-2 ', onLive);

      expect(screens.checkNow('TRIP-2'), isTrue);
      expect((detail, live), (1, 1));

      screens.unregister('TRIP-2', onLive);
      expect(screens.checkNow('TRIP-2'), isTrue);
      expect((detail, live), (2, 1));

      screens.unregister('TRIP-2', onDetail);
      expect(screens.checkNow('TRIP-2'), isFalse);
    });
  });

  group('a list of pending offers goes stale', () {
    late _ManualClock clock;
    late DateTime wall;
    late _ControlledSource source;
    late DriverPendingOfferStore store;

    setUp(() {
      clock = _ManualClock();
      wall = DateTime.utc(2026, 10, 23, 1, 21, 56);
      source = _ControlledSource();
      store = DriverPendingOfferStore(
        source: source,
        clock: clock,
        wallClock: () => wall,
      );
    });

    Future<void> deliver(List<Map<String, Object?>> offers) async {
      final refreshing = store.refresh();
      source.complete(<String, Object?>{
        'server_time': '2026-10-23T01:21:56+00:00',
        'offers': offers,
      });
      await refreshing;
    }

    test('fresh right after a successful fetch', () async {
      await deliver([_offer()]);

      expect(store.isFresh, isTrue);
      expect(store.listedFresh(_ref), isTrue);
    });

    test('stale once older than one poll and a bit', () async {
      await deliver([_offer()]);

      clock.value += DriverOfferCardTiming.listingFreshFor;
      wall = wall.add(DriverOfferCardTiming.listingFreshFor);
      expect(store.isFresh, isTrue);

      clock.value += const Duration(seconds: 1);
      wall = wall.add(const Duration(seconds: 1));
      expect(store.isFresh, isFalse);
      expect(store.listedFresh(_ref), isFalse);
      // Still listed: the card keeps what it shows until a fetch answers.
      expect(store.offerFor(_ref), isNotNull);
    });

    test('stale after the phone slept, though the monotonic clock did not '
        'move', () async {
      await deliver([_offer()]);

      wall = wall.add(const Duration(minutes: 35));

      expect(store.isFresh, isFalse);
    });

    test('stale when the phone clock is set back, as the monotonic clock '
        'still counts', () async {
      await deliver([_offer()]);

      clock.value += const Duration(minutes: 5);
      wall = wall.subtract(const Duration(minutes: 30));

      expect(store.isFresh, isFalse);
    });

    test('stale while the last fetch failed', () async {
      await deliver([_offer()]);
      final refreshing = store.refresh();
      source.fail();
      await refreshing;

      expect(store.isFresh, isFalse);
      expect(store.listedFresh(_ref), isFalse);
    });

    test('a pushed or tapped offer opens only from a fresh listing', () async {
      final offers = DriverOfferCoordinator(store: store);
      await deliver([_offer()]);
      expect(offers.canOpen(_ref), isTrue);
      expect(offers.canOpen('TRIP-OTHER'), isFalse);

      wall = wall.add(const Duration(minutes: 35));
      expect(offers.canOpen(_ref), isFalse);
      offers.dispose();
    });
  });

  group('an offer card shown from a stale list', () {
    late _ManualClock clock;
    late DateTime wall;
    late _ControlledSource source;
    late DriverPendingOfferStore store;
    late List<String> prepared;

    setUp(() {
      clock = _ManualClock();
      wall = DateTime.utc(2026, 10, 23, 0, 42);
      source = _ControlledSource();
      store = DriverPendingOfferStore(
        source: source,
        clock: clock,
        wallClock: () => wall,
      );
      prepared = <String>[];
    });

    Future<void> deliver(List<Map<String, Object?>> offers) async {
      final refreshing = store.refresh();
      source.complete(<String, Object?>{
        'server_time': '2026-10-23T00:42:05+00:00',
        'offers': offers,
      });
      await refreshing;
    }

    Future<void> showCard(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DriverPendingOfferCard(
                tripReference: _ref,
                store: store,
                controllerFactory: _recordingFactory(prepared),
                pickDeclineReason: (_) async => null,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('prepares nothing for an offer the server no longer lists', (
      tester,
    ) async {
      await tester.runAsync(() => deliver([_offer(staff: true)]));
      wall = wall.add(const Duration(minutes: 35));

      await showCard(tester);
      expect(source.calls, 2, reason: 'the card asks for a fresh list');
      expect(prepared, isEmpty);

      source.complete(<String, Object?>{
        'server_time': '2026-10-23T01:17:05+00:00',
        'offers': <Object?>[],
      });
      await tester.pump();
      await tester.pump();

      expect(prepared, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('prepares once the fresh list still has the offer', (
      tester,
    ) async {
      await tester.runAsync(() => deliver([_offer(staff: true)]));
      wall = wall.add(const Duration(minutes: 35));

      await showCard(tester);
      expect(prepared, isEmpty);

      source.complete(<String, Object?>{
        'server_time': '2026-10-23T01:17:05+00:00',
        'offers': [_offer(staff: true)],
      });
      await tester.pump();
      await tester.pump();

      expect(prepared, [_ref]);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a fresh list prepares at once, as before', (tester) async {
      await tester.runAsync(() => deliver([_offer()]));

      await showCard(tester);

      expect(prepared, [_ref]);
      expect(source.calls, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}

const _ref = 'TRIP-4F5837A6421D';

Map<String, Object?> _offer({bool staff = false}) => <String, Object?>{
  'trip_reference': _ref,
  'pickup_location': 'Pinned location',
  'passenger_count': 1,
  'fare_amount': null,
  'fare_currency': 'GHS',
  'assigned_at': '2026-10-23T00:42:00+00:00',
  'offer_expires_at': staff ? null : '2026-10-23T00:42:45+00:00',
  'requested_pickup_time': null,
};

/// Records each prepare and never finishes it: preparing is what writes the
/// Accept record, so the count is what matters here.
DriverOfferResponseControllerFactory _recordingFactory(List<String> log) {
  return (reference, {assignedAt, unknownOffer = false}) {
    log.add(reference);
    return Completer<DriverOfferResponseResilienceController>().future;
  };
}

final class _ManualClock implements DriverMonotonicClock {
  Duration value = const Duration(seconds: 100);

  @override
  Duration get now => value;
}

final class _ControlledSource implements DriverPendingOffersSource {
  Completer<DriverPendingOffersFetch>? _pending;
  var calls = 0;

  @override
  Future<DriverPendingOffersFetch> fetch() {
    calls += 1;
    return (_pending = Completer<DriverPendingOffersFetch>()).future;
  }

  void complete(Object? json) =>
      _pending!.complete(DriverPendingOffersFetched(json));

  void fail() => _pending!.complete(const DriverPendingOffersUnavailable());
}

final class _TripGateway implements DriverDutyGateway {
  _TripGateway(this.status);

  String status;
  bool fail = false;
  var calls = 0;

  @override
  Future<DriverAssignedTrip> fetchTripDetail(String tripReference) async {
    calls += 1;
    if (fail) {
      throw const DriverDutyApiException(
        DriverDutyApiFailureType.unavailable,
        'Cannot reach the server.',
      );
    }
    return DriverAssignedTrip(
      reference: tripReference,
      status: status,
      pickupLocation: 'Pinned location',
      destination: 'Back to Work 23b',
      passengerCount: 1,
      vehicleReference: 'ALANTEH-DEMO-VEH-01',
    );
  }

  @override
  Future<DriverDutySummary> fetchDuty() => throw UnimplementedError();

  @override
  Future<List<DriverAssignedTrip>> fetchTrips() async => const [];
}
