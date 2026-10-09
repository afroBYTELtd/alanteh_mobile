import 'dart:async';

import 'package:asm_offline_queue/asm_offline_queue.dart';
import 'package:driver_app/driver_duty_trips.dart';
import 'package:driver_app/network/driver_offer_response_gateway.dart';
import 'package:driver_app/network/driver_offer_response_resilience.dart';
import 'package:driver_app/network/driver_trip_action_resilience.dart';
import 'package:driver_app/offers/driver_pending_offer_card.dart';
import 'package:driver_app/offers/driver_pending_offer_store.dart';
import 'package:driver_app/offers/driver_pending_offers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _ref = 'TRIP-1';

void main() {
  late _Harness h;

  setUp(() => h = _Harness());

  group('appears at once', () {
    testWidgets(
      'before any fetch: "Respond quickly", Decline on, Accept off',
      (tester) async {
        await h.pump(tester);

        expect(find.byKey(const Key('offer-card')), findsOneWidget);
        expect(find.text('New trip request'), findsOneWidget);
        expect(h.countdownText(tester), 'Respond quickly');
        expect(h.enabled(tester, 'offer-card-decline'), isTrue);
        expect(h.enabled(tester, 'offer-card-accept'), isFalse);
        await h.dispose(tester);
      },
    );

    testWidgets('fills in the pickup, passengers, fare and countdown', (
      tester,
    ) async {
      await h.pump(tester);
      await h.deliver(tester, [h.offer()]);

      expect(find.text('Accra Mall, Spintex Road'), findsOneWidget);
      expect(find.text('2 passengers'), findsOneWidget);
      expect(find.text('GHS 35.00'), findsOneWidget);
      // 40 s on the server, minus the 1 s request.
      expect(h.countdownText(tester), '0:39 left');
      expect(h.enabled(tester, 'offer-card-accept'), isTrue);
      await h.dispose(tester);
    });

    testWidgets('a staff offer has no countdown', (tester) async {
      await h.pump(tester);
      await h.deliver(tester, [h.offer(expiresAt: null)]);
      expect(h.countdownText(tester), 'Waiting for your response');
      await h.dispose(tester);
    });

    testWidgets('an older server without expiry says "Respond quickly"', (
      tester,
    ) async {
      await h.pump(tester);
      await h.deliver(tester, [h.offer(includeExpiry: false)]);
      expect(h.countdownText(tester), 'Respond quickly');
      await h.dispose(tester);
    });
  });

  group('countdown', () {
    testWidgets('counts down on the monotonic clock', (tester) async {
      await h.pump(tester);
      await h.deliver(tester, [h.offer()]);
      await h.advance(tester, const Duration(seconds: 10));
      expect(h.countdownText(tester), '0:29 left');
      await h.dispose(tester);
    });

    testWidgets('at zero: "Offer expired", buttons locked, offers refetched', (
      tester,
    ) async {
      await h.pump(tester);
      await h.deliver(tester, [h.offer()]);
      final fetchesBefore = h.source.calls;
      await h.advance(tester, const Duration(seconds: 39));

      expect(h.countdownText(tester), 'Offer expired');
      expect(h.enabled(tester, 'offer-card-accept'), isFalse);
      expect(h.enabled(tester, 'offer-card-decline'), isFalse);
      expect(h.source.calls, fetchesBefore + 1);
      await h.dispose(tester);
    });
  });

  group('Accept waits for what the driver must see', () {
    testWidgets('no fare: Accept stays off', (tester) async {
      await h.pump(tester);
      await h.deliver(tester, [h.offer(fare: null)]);
      expect(h.enabled(tester, 'offer-card-accept'), isFalse);
      await h.dispose(tester);
    });

    testWidgets(
      'no details after 8 s: "Couldn\'t load trip details" and Try again; '
      'the countdown keeps running',
      (tester) async {
        await h.pump(tester);
        await h.deliver(tester, [h.offer(pickup: null)]);
        await h.advance(tester, const Duration(seconds: 8));

        expect(find.text("Couldn't load trip details"), findsOneWidget);
        expect(h.countdownText(tester), '0:31 left');
        final before = h.source.calls;
        await tester.tap(find.byKey(const Key('offer-card-try-again')));
        await tester.pump();
        expect(h.source.calls, before + 1);
        await h.dispose(tester);
      },
    );

    testWidgets(
      'pickup time missing from the offer: asked for, Accept off until known',
      (tester) async {
        final lookup = Completer<DriverOfferPickupTime>();
        await h.pump(tester, pickupTimeLookup: (_) => lookup.future);
        await h.deliver(tester, [h.offer(includePickupTime: false)]);
        expect(h.enabled(tester, 'offer-card-accept'), isFalse);

        lookup.complete(DriverOfferPickupAt(DateTime.utc(2030, 1, 2, 14, 30)));
        await tester.pump();
        expect(h.enabled(tester, 'offer-card-accept'), isTrue);
        expect(find.byKey(const Key('offer-card-scheduled')), findsOneWidget);
        await h.dispose(tester);
      },
    );

    testWidgets('a scheduled ride shows the pickup time badge', (tester) async {
      await h.pump(tester);
      await h.deliver(tester, [
        h.offer(requestedPickupTime: '2030-01-02T14:30:00+00:00'),
      ]);
      expect(find.byKey(const Key('offer-card-scheduled')), findsOneWidget);
      expect(find.textContaining('Scheduled pickup'), findsOneWidget);
      await h.dispose(tester);
    });
  });

  group('responding', () {
    testWidgets('Accept: one request even if tapped twice, then onAccepted', (
      tester,
    ) async {
      await h.pump(tester);
      await h.deliver(tester, [h.offer()]);

      await tester.tap(find.byKey(const Key('offer-card-accept')));
      await tester.tap(find.byKey(const Key('offer-card-accept')));
      await tester.pump();
      expect(h.gateway.accepts, 1);
      expect(h.enabled(tester, 'offer-card-decline'), isFalse);

      h.gateway.finishAccept();
      await tester.pumpAndSettle(const Duration(milliseconds: 10));
      expect(h.accepted, [_ref]);
      expect(h.store.offerFor(_ref), isNull);
      await h.dispose(tester);
    });

    testWidgets('Accept after an expiry race: "This offer expired"', (
      tester,
    ) async {
      await h.pump(tester);
      await h.deliver(tester, [h.offer()]);
      h.gateway.acceptError = const DriverOfferResponseException(
        type: DriverOfferResponseFailureType.offerUnavailable,
        message: driverOfferExpiredMessage,
      );
      await tester.tap(find.byKey(const Key('offer-card-accept')));
      await tester.pumpAndSettle(const Duration(milliseconds: 10));

      expect(find.text('This offer expired'), findsOneWidget);
      expect(h.enabled(tester, 'offer-card-accept'), isFalse);
      expect(h.enabled(tester, 'offer-card-decline'), isFalse);
      await h.dispose(tester);
    });

    testWidgets('Accept when the offer ended: "This offer is no longer '
        'available"', (tester) async {
      await h.pump(tester);
      await h.deliver(tester, [h.offer()]);
      h.gateway.acceptError = const DriverOfferResponseException(
        type: DriverOfferResponseFailureType.offerUnavailable,
        message: driverOfferNoLongerAvailableMessage,
      );
      await tester.tap(find.byKey(const Key('offer-card-accept')));
      await tester.pumpAndSettle(const Duration(milliseconds: 10));
      expect(find.text('This offer is no longer available'), findsOneWidget);
      await h.dispose(tester);
    });

    testWidgets('Decline works before the details arrive', (tester) async {
      await h.pump(tester);
      await tester.tap(find.byKey(const Key('offer-card-decline')));
      await tester.pumpAndSettle(const Duration(milliseconds: 10));

      expect(h.gateway.declines, 1);
      expect(h.finished, [_ref]);
      await h.dispose(tester);
    });

    testWidgets('an offer gone from a newer fetch has ended', (tester) async {
      await h.pump(tester);
      await h.deliver(tester, [h.offer()]);
      await h.deliver(tester, const []);
      expect(find.text('This offer is no longer available'), findsOneWidget);
      expect(h.enabled(tester, 'offer-card-accept'), isFalse);
      await h.dispose(tester);
    });
  });

  testWidgets('several offers: says how many more are waiting', (
    tester,
  ) async {
    await h.pump(tester);
    await h.deliver(tester, [
      h.offer(),
      h.offer(reference: 'TRIP-2', expiresAt: '2026-10-09T10:01:30+00:00'),
    ]);
    expect(find.text('1 more offer waiting'), findsOneWidget);
    await h.dispose(tester);
  });
}

final class _Harness {
  final clock = _ManualClock();
  final source = _ControlledSource();
  final gateway = _FakeGateway();
  final accepted = <String>[];
  final finished = <String>[];
  late final store = DriverPendingOfferStore(source: source, clock: clock);

  Future<void> pump(
    WidgetTester tester, {
    DriverOfferPickupTimeLookup? pickupTimeLookup,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DriverPendingOfferCard(
              tripReference: _ref,
              store: store,
              controllerFactory: (reference) async =>
                  DriverOfferResponseResilienceController(
                    queue: _MemoryQueue(),
                    gateway: gateway,
                    tripReference: reference,
                    driverId: 'DRV-1',
                    verifyServerState: (receipt) async =>
                        DriverOfferVerifiedTrip(
                          tripReference: reference,
                          status: receipt.tripStatus,
                        ),
                  ),
              pickupTimeLookup: pickupTimeLookup,
              pickDeclineReason: (_) async => const DriverDeclineChoice(
                reason: DriverDeclineReason.endOfShift,
              ),
              onAccepted: accepted.add,
              onFinished: finished.add,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Map<String, Object?> offer({
    String reference = _ref,
    Object? expiresAt = '2026-10-09T10:00:45+00:00',
    bool includeExpiry = true,
    Object? fare = '35.00',
    Object? pickup = 'Accra Mall, Spintex Road',
    Object? requestedPickupTime,
    bool includePickupTime = true,
  }) => <String, Object?>{
    'trip_reference': reference,
    'pickup_location': pickup,
    'passenger_count': 2,
    'fare_amount': fare,
    'fare_currency': 'GHS',
    'assigned_at': '2026-10-09T10:00:00+00:00',
    if (includeExpiry) 'offer_expires_at': expiresAt,
    if (includePickupTime) 'requested_pickup_time': requestedPickupTime,
  };

  /// One fetch that took 1 s and returned [offers] with server time 10:00:05.
  Future<void> deliver(
    WidgetTester tester,
    List<Map<String, Object?>> offers,
  ) async {
    final refreshing = store.refresh();
    clock.value += const Duration(seconds: 1);
    source.complete(<String, Object?>{
      'server_time': '2026-10-09T10:00:05+00:00',
      'offers': offers,
    });
    await refreshing;
    await tester.pump();
  }

  Future<void> advance(WidgetTester tester, Duration by) async {
    for (var i = 0; i < by.inSeconds; i += 1) {
      clock.value += const Duration(seconds: 1);
      await tester.pump(const Duration(seconds: 1));
    }
  }

  String? countdownText(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('offer-card-countdown'))).data;

  bool enabled(WidgetTester tester, String key) {
    final button = tester.widget<ButtonStyleButton>(
      find.byKey(Key(key)),
    );
    return button.onPressed != null;
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
  }
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
}

final class _FakeGateway implements DriverOfferResponseGateway {
  var accepts = 0;
  var declines = 0;
  DriverOfferResponseException? acceptError;
  Completer<void>? _accept;

  void finishAccept() => _accept?.complete();

  @override
  Future<DriverOfferResponseReceipt> accept({
    required String tripReference,
    required String idempotencyKey,
    required String deviceTimestamp,
    DriverOfferSubmissionTelemetrySink? telemetrySink,
  }) async {
    accepts += 1;
    final error = acceptError;
    if (error != null) {
      throw error;
    }
    await (_accept = Completer<void>()).future;
    return DriverOfferResponseReceipt(
      tripReference: tripReference,
      tripStatus: 'driver_accepted',
      duplicate: false,
    );
  }

  @override
  Future<DriverOfferResponseReceipt> decline({
    required String tripReference,
    required String idempotencyKey,
    required String deviceTimestamp,
    required DriverDeclineReason reason,
    String? reasonNote,
    DriverOfferSubmissionTelemetrySink? telemetrySink,
  }) async {
    declines += 1;
    return DriverOfferResponseReceipt(
      tripReference: tripReference,
      tripStatus: 'driver_declined',
      duplicate: false,
    );
  }
}

final class _MemoryQueue implements DriverTripActionPersistentQueue {
  final _events = <String, QueuedEvent>{};

  @override
  Future<QueuedEvent> enqueue(QueuedEvent event) async =>
      _events.putIfAbsent(event.id, () => event);

  @override
  Future<QueuedEvent?> eventById(String id) async => _events[id];

  @override
  Future<List<QueuedEvent>> pendingEvents() async => _events.values.toList();

  @override
  Future<void> markSynced(String id) async => _events.remove(id);

  @override
  Future<void> markFailed(String id) async {}

  @override
  Future<void> markPermanentlyFailed(String id) async => _events.remove(id);
}
