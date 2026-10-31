import 'dart:async';

import 'package:asm_offline_queue/asm_offline_queue.dart';
import 'package:driver_app/driver_duty_trips.dart';
import 'package:driver_app/network/driver_offer_response_gateway.dart';
import 'package:driver_app/network/driver_offer_response_resilience.dart';
import 'package:driver_app/network/driver_trip_action_resilience.dart';
import 'package:driver_app/offers/driver_offer_coordinator.dart';
import 'package:driver_app/offers/driver_pending_offer_store.dart';
import 'package:driver_app/offers/driver_pending_offers_panel.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// B9: an offer withdrawn while its card is open. Seen 31 Oct: staff cancelled
// a staff offer, the cancel push arrived, and the card kept offering the trip
// for 13 minutes; nothing asked the server while the card was open.
void main() {
  late _Harness h;

  setUp(() => h = _Harness());

  group('the open card learns the offer has gone', () {
    testWidgets('a poll that no longer lists it turns the card to the ended '
        'state, Accept and Decline off, and does not remove it', (
      tester,
    ) async {
      await h.pumpHome(tester);
      expect(h.countdown(tester), 'Waiting for your response');

      h.server.offers = [];
      h.timers.tick();
      await h.advance(tester, const Duration(seconds: 1));

      expect(find.byKey(const Key('offer-card')), findsOneWidget);
      expect(h.countdown(tester), 'Offer ended');
      expect(find.text(driverOfferNoLongerAvailableMessage), findsOneWidget);
      expect(h.enabled(tester, 'offer-card-accept'), isFalse);
      expect(h.enabled(tester, 'offer-card-decline'), isFalse);
    });

    testWidgets('it clears 5 s later, and Work says "Waiting for offers"', (
      tester,
    ) async {
      await h.pumpHome(tester);
      h.server.offers = [];
      h.timers.tick();
      await h.advance(tester, const Duration(seconds: 4));
      expect(find.byKey(const Key('offer-card')), findsOneWidget);

      await h.advance(tester, const Duration(seconds: 2));

      expect(find.byKey(const Key('offer-card')), findsNothing);
      expect(find.byKey(const Key('waiting')), findsOneWidget);
    });

    testWidgets('a poll that still lists it changes nothing while the '
        'decline sheet is open', (tester) async {
      await h.pumpHome(tester);
      await tester.tap(find.byKey(const Key('offer-card-decline')));
      await tester.pump();
      expect(h.popups.value, 1, reason: 'the sheet is open');

      h.timers.tick();
      await h.advance(tester, const Duration(seconds: 1));

      expect(h.sheetSawEnded, isFalse);
      expect(h.countdown(tester), 'Waiting for your response');
      h.closeSheet(
        const DriverDeclineChoice(reason: DriverDeclineReason.endOfShift),
      );
      await h.advance(tester, const Duration(seconds: 1));
      expect(h.gateway.declines, 1, reason: 'the decline still goes out');
    });

    testWidgets('a poll that still lists it changes nothing while an Accept '
        'is in flight', (tester) async {
      await h.pumpHome(tester);
      h.gateway.holdAccept = Completer<void>();
      await tester.tap(find.byKey(const Key('offer-card-accept')));
      await tester.pump();
      expect(find.text('Sending…'), findsOneWidget);

      h.timers.tick();
      await h.advance(tester, const Duration(seconds: 1));
      expect(find.text('Sending…'), findsOneWidget);

      h.gateway.holdAccept!.complete();
      await h.advance(tester, const Duration(seconds: 1));
      expect(h.accepted, [_ref], reason: 'the Accept still lands, once');
    });

    testWidgets('an ended card does not clear while a sheet is open; it '
        'clears 5 s after the sheet closes', (tester) async {
      await h.pumpHome(tester);
      await tester.tap(find.byKey(const Key('offer-card-decline')));
      await tester.pump();
      h.server.offers = [];
      h.timers.tick();
      await h.advance(tester, const Duration(seconds: 1));
      expect(h.sheetSawEnded, isTrue, reason: 'the sheet says it ended');

      await h.advance(tester, const Duration(seconds: 10));
      expect(find.byKey(const Key('offer-card')), findsOneWidget);

      h.closeSheet(null);
      await h.advance(tester, const Duration(seconds: 4));
      expect(find.byKey(const Key('offer-card')), findsOneWidget);
      await h.advance(tester, const Duration(seconds: 2));
      expect(find.byKey(const Key('offer-card')), findsNothing);
    });
  });

  group('the full "Trip offer" screen', () {
    testWidgets('closes 5 s after its offer ended', (tester) async {
      await h.pumpHome(tester);
      h.openScreen();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('offer-screen')), findsOneWidget);
      // Only a fetch that left after the card opened can end it.
      await h.advance(tester, const Duration(seconds: 1));

      h.server.offers = [];
      await h.coordinator.offerPushed();
      await h.advance(tester, const Duration(seconds: 1));
      expect(h.countdown(tester), 'Offer ended');
      await h.advance(tester, const Duration(seconds: 3));
      expect(find.byKey(const Key('offer-screen')), findsOneWidget);

      await h.advance(tester, const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('offer-screen')), findsNothing);
    });

    testWidgets('moves to a newer live offer instead of closing', (
      tester,
    ) async {
      await h.pumpHome(tester);
      h.openScreen();
      await tester.pumpAndSettle();

      h.server.offers = [h.offer(reference: 'TRIP-2', pickup: 'Osu Castle')];
      await h.coordinator.offerPushed();
      await h.advance(tester, const Duration(seconds: 10));

      expect(find.byKey(const Key('offer-screen')), findsOneWidget);
      expect(find.text('Osu Castle'), findsWidgets);
      expect(h.countdown(tester), 'Waiting for your response');
    });

    testWidgets('does not close while the decline sheet is open on it', (
      tester,
    ) async {
      await h.pumpHome(tester);
      h.openScreen();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('offer-card-decline')).last);
      await tester.pumpAndSettle();

      h.server.offers = [];
      await h.coordinator.offerPushed();
      await h.advance(tester, const Duration(seconds: 10));
      expect(find.byKey(const Key('offer-screen')), findsOneWidget);

      Navigator.of(tester.element(find.text('Offer ended').last)).pop();
      await tester.pumpAndSettle();
      await h.advance(tester, const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('offer-screen')), findsNothing);
    });
  });

  testWidgets('Accept refused with 404 while time is left: "This offer is no '
      'longer available", whatever the error said', (tester) async {
    h.server.offers = [h.offer(expiresAt: 45)];
    await h.pumpHome(tester);
    h.gateway.acceptError = const DriverOfferResponseException(
      type: DriverOfferResponseFailureType.offerUnavailable,
      message: driverOfferExpiredMessage,
    );
    await tester.tap(find.byKey(const Key('offer-card-accept')));
    await h.advance(tester, const Duration(seconds: 1));

    expect(find.text(driverOfferNoLongerAvailableMessage), findsOneWidget);
    expect(find.text(driverOfferExpiredMessage), findsNothing);
  });

  group('the coordinator', () {
    test('a cancel push fetches the offers at once; an offer push is left to '
        'the card it opens', () async {
      h.coordinator.tripPushed('trip_cancelled_by_operations');
      await pumpEventQueue();
      expect(h.server.calls, 1);

      h.coordinator.tripPushed('trip_cancelled_by_passenger');
      await pumpEventQueue();
      expect(h.server.calls, 2);

      h.coordinator.tripPushed('driver_assigned');
      await pumpEventQueue();
      expect(h.server.calls, 2);
    });

    test('one OFFER_FETCH line per fetch, for each reason, with no trip '
        'reference, name or phone number', () async {
      h.coordinator.setOnDuty(true);
      await pumpEventQueue();
      h.timers.tick();
      await pumpEventQueue();
      h.coordinator
        ..setForeground(false)
        ..setForeground(true);
      await pumpEventQueue();
      await h.coordinator.offerPushed();
      h.coordinator.tripPushed('trip_cancelled_by_operations');
      await pumpEventQueue();
      await h.coordinator.fetchThenCanOpen(_ref);

      expect(h.log.map(_reasonOf), [
        'poll',
        'poll',
        'resume',
        'push_assigned',
        'push_cancelled',
        'card_open',
      ]);
      final shape = RegExp(
        r'^OFFER_FETCH reason=[a-z_]+ offers=\d+ changed=(true|false)$',
      );
      for (final line in h.log) {
        expect(line, matches(shape));
        expect(line, isNot(contains('TRIP')));
        expect(line, isNot(contains('Pinned')));
      }
      expect(h.log.first, endsWith('offers=1 changed=true'));
      expect(h.log[1], endsWith('offers=1 changed=false'));
    });
  });
}

String _reasonOf(String line) =>
    RegExp(r'reason=([a-z_]+)').firstMatch(line)!.group(1)!;

const _ref = 'TRIP-1';
final _assigned = DateTime.utc(2026, 10, 31, 1, 56);

final class _Harness {
  final clock = _ManualClock();
  final timers = _FakeTimers();
  final log = <String>[];
  final popups = ValueNotifier<int>(0);
  late final server = _Server(clock)..offers = [offer(expiresAt: null)];
  late final store = DriverPendingOfferStore(source: server, clock: clock);
  late final coordinator = DriverOfferCoordinator(
    store: store,
    periodicTimer: timers.create,
    log: log.add,
  );
  final _navigator = GlobalKey<NavigatorState>();
  final gateway = _Gateway();
  final accepted = <String>[];

  Completer<DriverDeclineChoice?>? _sheet;
  bool sheetSawEnded = false;

  /// A staff offer has no expiry ([expiresAt] null).
  Map<String, Object?> offer({
    Object? expiresAt,
    String reference = _ref,
    String pickup = 'Pinned location',
  }) => <String, Object?>{
    'trip_reference': reference,
    'pickup_location': pickup,
    'passenger_count': 1,
    'fare_amount': null,
    'fare_currency': 'GHS',
    'assigned_at': _assigned.toIso8601String(),
    'offer_expires_at': expiresAt == null
        ? null
        : _assigned.add(Duration(seconds: expiresAt as int)).toIso8601String(),
    'requested_pickup_time': null,
  };

  Future<DriverOfferResponseResilienceController> _controller(
    String reference, {
    DateTime? assignedAt,
    bool unknownOffer = false,
  }) async => DriverOfferResponseResilienceController(
    queue: _MemoryQueue(),
    gateway: gateway,
    tripReference: reference,
    driverId: 'DRV-1',
    assignedAt: assignedAt,
    verifyServerState: (receipt) async => DriverOfferVerifiedTrip(
      tripReference: reference,
      status: receipt.tripStatus,
    ),
  );

  /// The decline sheet over the home card: counted as an open popup, like
  /// the navigator's own sheet.
  Future<DriverDeclineChoice?> _pickReason(
    BuildContext _,
    ValueListenable<bool> offerEnded,
  ) async {
    final sheet = _sheet = Completer<DriverDeclineChoice?>();
    void watch() => sheetSawEnded = sheetSawEnded || offerEnded.value;
    offerEnded.addListener(watch);
    popups.value += 1;
    try {
      return await sheet.future;
    } finally {
      popups.value -= 1;
      offerEnded.removeListener(watch);
    }
  }

  void closeSheet(DriverDeclineChoice? choice) => _sheet!.complete(choice);

  Future<void> pumpHome(WidgetTester tester) async {
    coordinator.setOnDuty(true);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: _navigator,
        home: Scaffold(
          body: SingleChildScrollView(
            child: DriverPendingOffersPanel(
              coordinator: coordinator,
              controllerFactory: _controller,
              pickDeclineReason: _pickReason,
              openPopups: popups,
              onAccepted: accepted.add,
              waitingPanel: const Text(
                'Waiting for offers',
                key: Key('waiting'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  void openScreen() {
    unawaited(
      _navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => DriverPendingOfferScreen(
            tripReference: _ref,
            coordinator: coordinator,
            controllerFactory: _controller,
          ),
        ),
      ),
    );
  }

  /// Moves the phone's clock and the test's clock together, a second at a
  /// time, so the card's 1 s ticker sees every second.
  Future<void> advance(WidgetTester tester, Duration by) async {
    for (var i = 0; i < by.inSeconds; i += 1) {
      clock.value += const Duration(seconds: 1);
      await tester.pump(const Duration(seconds: 1));
    }
  }

  String? countdown(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const Key('offer-card-countdown')).last)
      .data;

  bool enabled(WidgetTester tester, String key) =>
      tester.widget<ButtonStyleButton>(find.byKey(Key(key)).last).onPressed !=
      null;
}

final class _ManualClock implements DriverMonotonicClock {
  static const start = Duration(seconds: 100);
  Duration value = start;

  @override
  Duration get now => value;
}

/// Answers at once, with a server clock that runs with the phone's.
final class _Server implements DriverPendingOffersSource {
  _Server(this.clock);

  final _ManualClock clock;
  var offers = <Map<String, Object?>>[];
  var calls = 0;

  @override
  Future<DriverPendingOffersFetch> fetch() async {
    calls += 1;
    final serverNow = _assigned.add(clock.value - _ManualClock.start);
    return DriverPendingOffersFetched(<String, Object?>{
      'server_time': serverNow.toIso8601String(),
      'offers': List<Map<String, Object?>>.of(offers),
    });
  }
}

final class _FakeTimers {
  final _timers = <_FakeTimer>[];

  Timer create(Duration interval, void Function(Timer) onTick) {
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

final class _Gateway implements DriverOfferResponseGateway {
  DriverOfferResponseException? acceptError;
  Completer<void>? holdAccept;
  var declines = 0;

  @override
  Future<DriverOfferResponseReceipt> accept({
    required String tripReference,
    required String idempotencyKey,
    required String deviceTimestamp,
    DriverOfferSubmissionTelemetrySink? telemetrySink,
  }) async {
    await holdAccept?.future;
    final error = acceptError;
    if (error != null) {
      throw error;
    }
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
