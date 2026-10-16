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
    testWidgets('before any fetch: "Respond quickly", Decline on, Accept off', (
      tester,
    ) async {
      await h.pump(tester);

      expect(find.byKey(const Key('offer-card')), findsOneWidget);
      expect(find.text('New trip request'), findsOneWidget);
      expect(h.countdownText(tester), 'Respond quickly');
      expect(h.enabled(tester, 'offer-card-decline'), isTrue);
      expect(h.enabled(tester, 'offer-card-accept'), isFalse);
      await h.dispose(tester);
    });

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
    testWidgets(
      'no fare (the usual case): Accept on, and "Fare to be confirmed by '
      'dispatch" in the fare position',
      (tester) async {
        await h.pump(tester);
        await h.deliver(tester, [h.offer(fare: null)]);

        expect(h.enabled(tester, 'offer-card-accept'), isTrue);
        expect(
          tester.widget<Text>(find.byKey(const Key('offer-card-fare'))).data,
          'Fare to be confirmed by dispatch',
        );

        // No fare is not missing detail: no "Couldn't load" after 8 s.
        await h.advance(tester, const Duration(seconds: 8));
        expect(find.text("Couldn't load trip details"), findsNothing);

        await tester.tap(find.byKey(const Key('offer-card-accept')));
        await tester.pump();
        h.gateway.finishAccept();
        await tester.pumpAndSettle(const Duration(milliseconds: 10));
        expect(h.accepted, [_ref]);
        await h.dispose(tester);
      },
    );

    testWidgets('no pickup label: Accept stays off', (tester) async {
      await h.pump(tester);
      await h.deliver(tester, [h.offer(pickup: null)]);
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
      // It waits for the offer for up to the details timeout first.
      await tester.pump(const Duration(seconds: 9));
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

  group('an ended card says so plainly', () {
    // Seen on the test phone (9 Oct): a card opened from a push after the
    // offer had gone showed "Loading trip details…" above "This offer is no
    // longer available", with "Respond quickly" in the corner.
    testWidgets('gone before its details arrived: "Offer ended", and no '
        '"Loading trip details…"', (tester) async {
      await h.pump(tester);
      // The fetch leaves after the card opened (the tap comes first).
      h.clock.value += const Duration(seconds: 1);
      await h.deliver(tester, const []);

      expect(h.countdownText(tester), 'Offer ended');
      expect(find.text('Loading trip details…'), findsNothing);
      expect(find.text('This offer is no longer available'), findsOneWidget);
      await h.dispose(tester);
    });

    testWidgets('gone after its details arrived: "Offer ended", and the '
        'pickup stays', (tester) async {
      await h.pump(tester);
      await h.deliver(tester, [h.offer()]);
      await h.deliver(tester, const []);

      expect(h.countdownText(tester), 'Offer ended');
      expect(find.text('Accra Mall, Spintex Road'), findsOneWidget);
      await h.dispose(tester);
    });

    testWidgets('Accept refused as ended: "Offer ended" in the corner, not '
        'the countdown', (tester) async {
      await h.pump(tester);
      await h.deliver(tester, [h.offer()]);
      h.gateway.acceptError = const DriverOfferResponseException(
        type: DriverOfferResponseFailureType.offerUnavailable,
        message: driverOfferNoLongerAvailableMessage,
      );
      await tester.tap(find.byKey(const Key('offer-card-accept')));
      await tester.pumpAndSettle(const Duration(milliseconds: 10));

      expect(h.countdownText(tester), 'Offer ended');
      await h.dispose(tester);
    });

    testWidgets('a poll that started before the card opened does not end '
        'it', (tester) async {
      // The poll leaves before the offer exists; a push tap opens the card;
      // the old poll then comes back without the offer.
      final oldPoll = h.store.refresh();
      h.clock.value += const Duration(seconds: 1);
      await h.pump(tester);
      h.clock.value += const Duration(seconds: 1);
      h.source.complete(<String, Object?>{
        'server_time': '2026-10-09T10:00:05+00:00',
        'offers': const <Object?>[],
      });
      await oldPoll;
      await tester.pump();

      expect(h.countdownText(tester), 'Respond quickly');
      expect(find.text('This offer is no longer available'), findsNothing);
      expect(h.enabled(tester, 'offer-card-decline'), isTrue);

      // A poll that leaves after the card opened does count.
      await h.deliver(tester, const []);
      expect(h.countdownText(tester), 'Offer ended');
      await h.dispose(tester);
    });

    testWidgets('time ran out: still "Offer expired"', (tester) async {
      await h.pump(tester);
      await h.deliver(tester, [h.offer()]);
      await h.advance(tester, const Duration(seconds: 39));

      expect(h.countdownText(tester), 'Offer expired');
      await h.dispose(tester);
    });
  });

  testWidgets('several offers: says how many more are waiting', (tester) async {
    await h.pump(tester);
    await h.deliver(tester, [
      h.offer(),
      h.offer(reference: 'TRIP-2', expiresAt: '2026-10-09T10:01:30+00:00'),
    ]);
    expect(find.text('1 more offer waiting'), findsOneWidget);
    await h.dispose(tester);
  });

  // A trip can be offered to the same driver again; each offer is answered
  // under its own `assigned_at`, so the server cannot replay an answer to
  // an earlier offer.
  group('answers under its own offer', () {
    final offerTag = '${DateTime.utc(2026, 10, 9, 10).microsecondsSinceEpoch}';

    testWidgets('opened by a push tap before the offer was listed: Accept '
        "goes out under the listed offer's assigned_at", (tester) async {
      await h.pump(tester);
      expect(h.preparedFor, [null]);
      await h.deliver(tester, [h.offer()]);

      await tester.tap(find.byKey(const Key('offer-card-accept')));
      await tester.pump();
      h.gateway.finishAccept();
      await tester.pumpAndSettle(const Duration(milliseconds: 10));

      expect(h.gateway.keys, hasLength(1));
      expect(h.gateway.keys.single, contains(offerTag));
      expect(h.accepted, [_ref]);
      await h.dispose(tester);
    });

    testWidgets('Decline likewise', (tester) async {
      await h.pump(tester);
      await h.deliver(tester, [h.offer()]);

      await tester.tap(find.byKey(const Key('offer-card-decline')));
      await tester.pumpAndSettle(const Duration(milliseconds: 10));

      expect(h.gateway.keys, hasLength(1));
      expect(h.gateway.keys.single, contains(offerTag));
      expect(h.finished, [_ref]);
      await h.dispose(tester);
    });

    testWidgets('Decline before the offer is listed waits for it; if it '
        'never comes, it goes out once under a fresh key, and Decline again '
        'after the offer is listed reuses that key', (tester) async {
      await h.pump(tester);
      h.gateway.declineError = const DriverOfferResponseException(
        type: DriverOfferResponseFailureType.temporarilyUnavailable,
        message: 'Network is slow.',
      );
      await tester.tap(find.byKey(const Key('offer-card-decline')));
      await tester.pump(const Duration(seconds: 9));
      await tester.pumpAndSettle(const Duration(milliseconds: 10));
      expect(h.gateway.keys, hasLength(1));

      await h.deliver(tester, [h.offer()]);
      h.gateway.declineError = null;
      await tester.tap(find.byKey(const Key('offer-card-decline')));
      await tester.pumpAndSettle(const Duration(milliseconds: 10));

      expect(h.gateway.keys, hasLength(2));
      expect(h.gateway.keys.last, h.gateway.keys.first);
      expect(h.finished, [_ref]);
      await h.dispose(tester);
    });

    testWidgets('Decline during "Loading…" and the offer turns out to be '
        'gone: nothing is sent and the card says so', (tester) async {
      await h.pump(tester);
      await h.advance(tester, const Duration(seconds: 1));
      await tester.tap(find.byKey(const Key('offer-card-decline')));
      await tester.pump(const Duration(seconds: 1));
      await h.deliver(tester, const []);
      await tester.pump(const Duration(seconds: 9));
      await tester.pumpAndSettle(const Duration(milliseconds: 10));

      expect(h.gateway.keys, isEmpty);
      expect(find.text('This offer is no longer available'), findsOneWidget);
      await h.dispose(tester);
    });

    // What the installed build leaves behind: its decline record for the
    // trip, keyed by trip only and already synced. The server keeps the
    // receipt for that key.
    void leaveOldDecline() {
      h.queue = _KeepingQueue()..events[_oldDecline.id] = _oldDecline;
      h.gateway.seenKeys.add(_oldDecline.idempotencyKey);
    }

    testWidgets('the trip offered again, Decline during "Loading…", the offer '
        "listed a moment later: Decline goes out under this offer's key, not "
        'the old record', (tester) async {
      leaveOldDecline();
      await h.pump(tester);
      await tester.tap(find.byKey(const Key('offer-card-decline')));
      await tester.pump(const Duration(seconds: 1));
      await h.deliver(tester, [h.offer()]);
      await tester.pumpAndSettle(const Duration(milliseconds: 10));

      expect(h.gateway.keys, hasLength(1));
      expect(h.gateway.keys.single, isNot(_oldDecline.idempotencyKey));
      expect(h.gateway.keys.single, contains(offerTag));
      expect(h.gateway.duplicates, 0);
      expect(h.finished, [_ref]);
      await h.dispose(tester);
    });

    testWidgets('the same, but the offer is never listed: after the details '
        'timeout Decline goes out under a fresh key, not the old record', (
      tester,
    ) async {
      leaveOldDecline();
      await h.pump(tester);
      await tester.tap(find.byKey(const Key('offer-card-decline')));
      await tester.pump(const Duration(seconds: 9));
      await tester.pumpAndSettle(const Duration(milliseconds: 10));

      expect(h.gateway.keys, hasLength(1));
      expect(h.gateway.keys.single, isNot(_oldDecline.idempotencyKey));
      expect(h.gateway.duplicates, 0);
      expect(h.finished, [_ref]);
      await h.dispose(tester);
    });

    testWidgets('opened with its offer listed: prepares for that offer once', (
      tester,
    ) async {
      final refreshing = h.store.refresh();
      h.source.complete(<String, Object?>{
        'server_time': '2026-10-09T10:00:05+00:00',
        'offers': [h.offer()],
      });
      await refreshing;
      await h.pump(tester);
      await tester.pump();

      expect(h.preparedFor, [DateTime.utc(2026, 10, 9, 10)]);
      await tester.tap(find.byKey(const Key('offer-card-accept')));
      await tester.pump();
      h.gateway.finishAccept();
      await tester.pumpAndSettle(const Duration(milliseconds: 10));
      expect(h.preparedFor, hasLength(1));
      expect(h.gateway.keys.single, contains(offerTag));
      await h.dispose(tester);
    });
  });
}

final class _Harness {
  final clock = _ManualClock();
  final source = _ControlledSource();
  final gateway = _FakeGateway();
  final accepted = <String>[];
  final finished = <String>[];
  final preparedFor = <DateTime?>[];

  /// Shared by every controller when set; otherwise each gets its own.
  DriverTripActionPersistentQueue? queue;
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
              controllerFactory:
                  (reference, {assignedAt, unknownOffer = false}) async {
                    preparedFor.add(assignedAt);
                    return DriverOfferResponseResilienceController(
                      queue: queue ?? _MemoryQueue(),
                      gateway: gateway,
                      tripReference: reference,
                      driverId: 'DRV-1',
                      assignedAt: assignedAt,
                      unknownOffer: unknownOffer,
                      verifyServerState: (receipt) async =>
                          DriverOfferVerifiedTrip(
                            tripReference: reference,
                            status: receipt.tripStatus,
                          ),
                    );
                  },
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
    final button = tester.widget<ButtonStyleButton>(find.byKey(Key(key)));
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
  final keys = <String>[];
  DriverOfferResponseException? declineError;

  /// Keys the server applied an answer for. As at 07e86be, a key seen
  /// before is answered as a duplicate with the trip as it is now.
  final seenKeys = <String>{};
  var duplicates = 0;
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
    keys.add(idempotencyKey);
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
    keys.add(idempotencyKey);
    final error = declineError;
    if (error != null) {
      throw error;
    }
    if (!seenKeys.add(idempotencyKey)) {
      duplicates += 1;
      return DriverOfferResponseReceipt(
        tripReference: tripReference,
        tripStatus: 'driver_offer_sent',
        duplicate: true,
      );
    }
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

/// Keeps synced records, as the phone's SQLite queue does.
final class _KeepingQueue implements DriverTripActionPersistentQueue {
  final events = <String, QueuedEvent>{};

  bool _pending(QueuedEvent event) =>
      event.syncStatus == QueueSyncStatus.pending ||
      event.syncStatus == QueueSyncStatus.failed;

  @override
  Future<QueuedEvent> enqueue(QueuedEvent event) async =>
      events[event.id] = event;

  @override
  Future<QueuedEvent?> eventById(String id) async => events[id];

  @override
  Future<List<QueuedEvent>> pendingEvents() async =>
      events.values.where(_pending).toList();

  @override
  Future<void> markSynced(String id) async =>
      events[id] = events[id]!.copyWith(syncStatus: QueueSyncStatus.synced);

  @override
  Future<void> markFailed(String id) async {}

  @override
  Future<void> markPermanentlyFailed(String id) async => events[id] =
      events[id]!.copyWith(syncStatus: QueueSyncStatus.permanentlyFailed);
}

final _oldDecline = QueuedEvent(
  id: 'driver-offer-decline:${_ref.toLowerCase()}',
  eventType: '${driverOfferResponsePath(_ref)}$driverOfferDeclineEventIdentity',
  tripReference: _ref,
  driverId: 'DRV-1',
  payloadJson: <String, Object?>{
    'response': driverOfferDeclineResponse,
    'reason': DriverDeclineReason.endOfShift.code,
    'device_timestamp': '2026-10-09T09:00:00.000Z',
  },
  idempotencyKey: 'DRIVER-OFFER-DECLINE-$_ref-old-installed-build-key',
  syncStatus: QueueSyncStatus.synced,
);
