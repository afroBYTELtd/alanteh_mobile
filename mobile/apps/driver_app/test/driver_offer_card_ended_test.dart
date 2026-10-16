import 'dart:async';

import 'package:asm_offline_queue/asm_offline_queue.dart';
import 'package:driver_app/network/driver_offer_response_gateway.dart';
import 'package:driver_app/network/driver_offer_response_resilience.dart';
import 'package:driver_app/network/driver_trip_action_resilience.dart';
import 'package:driver_app/offers/driver_offer_coordinator.dart';
import 'package:driver_app/offers/driver_pending_offer_store.dart';
import 'package:driver_app/offers/driver_pending_offers_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// An automatic offer whose time ran out must not stay on the home screen.
// Seen on the test phone (9 Oct): the one check at zero still found the
// offer pending (the server expires it a moment later), the ended card kept
// the 12 s poll paused, and nothing ever fetched again.
void main() {
  late _Harness h;

  setUp(() => h = _Harness());

  testWidgets('the check at zero still says pending: a few seconds later the '
      'card is gone and the poll is running', (tester) async {
    await h.pumpHome(tester);
    await h.advance(tester, const Duration(seconds: 45));
    expect(h.countdown(tester), 'Offer expired');

    await h.advance(tester, const Duration(seconds: 6));

    expect(find.byKey(const Key('offer-card')), findsNothing);
    expect(find.byKey(const Key('waiting')), findsOneWidget);
    expect(h.coordinator.polling, isTrue);
  });

  group('each rule', () {
    testWidgets('an ended card does not pause the poll', (tester) async {
      await h.pumpHome(tester);
      expect(h.coordinator.polling, isFalse, reason: 'a live card pauses it');

      await h.advance(tester, const Duration(seconds: 46));

      expect(find.byKey(const Key('offer-card')), findsOneWidget);
      expect(h.coordinator.polling, isTrue);
    });

    testWidgets('the poll resumes at zero even while the check at zero is '
        'still out (a slow network)', (tester) async {
      await h.pumpHome(tester);
      await h.advance(tester, const Duration(seconds: 44));
      h.server.hold = Completer<void>();

      await h.advance(tester, const Duration(seconds: 1));

      expect(h.countdown(tester), 'Offer expired');
      expect(h.coordinator.polling, isTrue);
      h.server.hold!.complete();
      await tester.pump();
    });

    testWidgets('the server is checked again about 3 s after zero', (
      tester,
    ) async {
      await h.pumpHome(tester);
      await h.advance(tester, const Duration(seconds: 46));
      final callsAfterZero = h.server.calls;

      await h.advance(tester, const Duration(seconds: 3));

      expect(h.server.calls, callsAfterZero + 1);
    });

    testWidgets('the server says pending for ever: the home card is removed '
        'locally 5 s after zero, not before', (tester) async {
      await h.pumpHome(tester);
      await h.advance(tester, const Duration(seconds: 49));
      expect(find.byKey(const Key('offer-card')), findsOneWidget);

      await h.advance(tester, const Duration(seconds: 2));
      expect(find.byKey(const Key('offer-card')), findsNothing);
      expect(find.byKey(const Key('waiting')), findsOneWidget);

      // A later poll that still lists it does not bring it back.
      h.timers.tick();
      await h.advance(tester, const Duration(seconds: 1));
      expect(find.byKey(const Key('offer-card')), findsNothing);
    });

    testWidgets('a new offer for the same trip after the old one was removed '
        'shows on the home screen', (tester) async {
      await h.pumpHome(tester);
      await h.advance(tester, const Duration(seconds: 51));
      expect(find.byKey(const Key('offer-card')), findsNothing);

      // Re-offered to the same driver (our only driver can be): a new
      // assignment, with no fetch in between that left the trip out.
      h.server.offers = [h.offer(assignedAfter: 55, expiresAt: 100)];
      h.timers.tick();
      await h.advance(tester, const Duration(seconds: 1));

      expect(find.byKey(const Key('offer-card')), findsOneWidget);
      // A live countdown (about 48 s left, minus the fetch time).
      expect(h.countdown(tester), matches(RegExp(r'^0:4\d left$')));
    });

    testWidgets('a re-offer of the same trip while the ended home card is '
        'still shown replaces it with a live card', (tester) async {
      await h.pumpHome(tester);
      await h.advance(tester, const Duration(seconds: 46));
      expect(h.countdown(tester), 'Offer expired');

      h.server.offers = [h.offer(assignedAfter: 46, expiresAt: 91)];
      h.timers.tick();
      await h.advance(tester, const Duration(seconds: 1));

      expect(h.countdown(tester), matches(RegExp(r'^0:4\d left$')));
      expect(h.coordinator.polling, isFalse, reason: 'a live card again');

      // The old card's clean-up (closing, its 5 s removal) must not drop
      // the re-offer: it is still there 10 s later.
      await h.advance(tester, const Duration(seconds: 10));
      expect(find.byKey(const Key('offer-card')), findsOneWidget);
      expect(h.countdown(tester), matches(RegExp(r'^0:3\d left$')));
    });

    testWidgets('a staff offer has no expiry: it stays and keeps the poll '
        'paused', (tester) async {
      h.server.offers = [h.offer(expiresAt: null)];
      await h.pumpHome(tester);
      final calls = h.server.calls;

      await h.advance(tester, const Duration(seconds: 120));

      expect(h.countdown(tester), 'Waiting for your response');
      expect(h.coordinator.polling, isFalse);
      expect(h.server.calls, calls);
    });
  });

  group('an ended full-screen card yields to a newer live offer', () {
    // Seen on the test phone (10 Oct, repeat 2): an ended card left open
    // kept the screen, so a tap for the next offer only showed "1 more
    // offer waiting" under "Offer expired".
    Map<String, Object?> other() => h.offer(
      reference: 'TRIP-2',
      pickup: 'Osu Castle',
      assignedAfter: 50,
      expiresAt: 95,
    );

    testWidgets('a push or tap for a new offer (the offers are fetched): the '
        'new offer shows', (tester) async {
      await h.pumpScreen(tester);
      await h.advance(tester, const Duration(seconds: 46));
      expect(h.countdown(tester), 'Offer expired');

      h.server.offers = [h.offer(), other()];
      await h.coordinator.offerPushed();
      await h.advance(tester, const Duration(seconds: 1));

      expect(find.text('Osu Castle'), findsOneWidget);
      expect(h.countdown(tester), matches(RegExp(r'^0:\d\d left$')));
      expect(find.byKey(const Key('offer-screen')), findsOneWidget);
      expect(h.coordinator.polling, isFalse, reason: 'a live card again');
    });

    testWidgets('a poll that lists a newer offer, with no tap: the new offer '
        'shows', (tester) async {
      await h.pumpScreen(tester);
      await h.advance(tester, const Duration(seconds: 46));
      expect(h.coordinator.polling, isTrue);

      h.server.offers = [other()];
      h.timers.tick();
      await h.advance(tester, const Duration(seconds: 1));

      expect(find.text('Osu Castle'), findsOneWidget);
      expect(h.countdown(tester), matches(RegExp(r'^0:\d\d left$')));
    });

    testWidgets('a re-offer of the same trip: it shows', (tester) async {
      await h.pumpScreen(tester);
      await h.advance(tester, const Duration(seconds: 46));

      h.server.offers = [h.offer(assignedAfter: 46, expiresAt: 91)];
      h.timers.tick();
      await h.advance(tester, const Duration(seconds: 1));

      expect(h.countdown(tester), matches(RegExp(r'^0:4\d left$')));
    });

    testWidgets('a live card is never replaced: "1 more offer waiting"', (
      tester,
    ) async {
      await h.pumpScreen(tester);
      h.server.offers = [h.offer(), other()];
      await h.coordinator.offerPushed();
      await h.advance(tester, const Duration(seconds: 1));

      expect(find.text('Pinned location'), findsOneWidget);
      expect(find.text('Osu Castle'), findsNothing);
      expect(find.text('1 more offer waiting'), findsOneWidget);
    });

    testWidgets('the ended offer itself, still listed, is not "newer"', (
      tester,
    ) async {
      await h.pumpScreen(tester);
      await h.advance(tester, const Duration(seconds: 50));

      expect(h.countdown(tester), 'Offer expired');
      expect(find.byKey(const Key('offer-screen')), findsOneWidget);
    });

    testWidgets('an offer refused as ended but still listed and not yet '
        'expired is not "newer": the card stays ended', (tester) async {
      await h.pumpScreen(tester);
      await h.advance(tester, const Duration(seconds: 2));
      h.gateway.acceptError = const DriverOfferResponseException(
        type: DriverOfferResponseFailureType.offerUnavailable,
        message: driverOfferNoLongerAvailableMessage,
      );
      await tester.tap(find.byKey(const Key('offer-card-accept')));
      await tester.pump();
      await h.advance(tester, const Duration(seconds: 2));

      expect(h.countdown(tester), 'Offer ended');
      expect(find.text(driverOfferNoLongerAvailableMessage), findsOneWidget);
    });

    testWidgets('another offer that has also run out is not live: the card '
        'stays ended', (tester) async {
      await h.pumpScreen(tester);
      await h.advance(tester, const Duration(seconds: 46));

      h.server.offers = [
        h.offer(),
        h.offer(reference: 'TRIP-2', pickup: 'Osu Castle', expiresAt: 40),
      ];
      h.timers.tick();
      await h.advance(tester, const Duration(seconds: 1));

      expect(find.text('Osu Castle'), findsNothing);
      expect(h.countdown(tester), 'Offer expired');
    });

    testWidgets('the open offer disappears in the same fetch that lists a new '
        'one: the new offer shows at once, before any poll', (tester) async {
      await h.pumpScreen(tester);
      await h.advance(tester, const Duration(seconds: 2));
      final calls = h.server.calls;

      h.server.offers = [other()];
      await h.coordinator.offerPushed();
      await tester.pump();
      await tester.pump();

      expect(find.text('Osu Castle'), findsOneWidget);
      expect(h.server.calls, calls + 1, reason: 'no second fetch needed');
    });

    testWidgets('closing an ended card by hand still works', (tester) async {
      await h.pumpHome(tester);
      h.openScreen(tester);
      await tester.pumpAndSettle();
      await h.advance(tester, const Duration(seconds: 46));

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('offer-screen')), findsNothing);
    });
  });

  group('the full-screen card', () {
    testWidgets('its 5 s removal drops only its own offer, not a re-offer '
        'of the trip listed meanwhile', (tester) async {
      await h.pumpScreen(tester);
      await h.advance(tester, const Duration(seconds: 46));

      h.server.offers = [h.offer(assignedAfter: 46, expiresAt: 91)];
      h.timers.tick();
      await h.advance(tester, const Duration(seconds: 6));

      expect(h.store.offerFor(_ref), isNotNull);
    });

    testWidgets('stays until the driver closes it, and does not pause the '
        'poll once ended', (tester) async {
      await h.pumpScreen(tester);
      expect(h.coordinator.polling, isFalse);

      await h.advance(tester, const Duration(seconds: 55));

      expect(find.byKey(const Key('offer-screen')), findsOneWidget);
      expect(h.countdown(tester), 'Offer expired');
      expect(h.coordinator.polling, isTrue);
    });

    testWidgets('closing it clears the ended offer from the home screen at '
        'once', (tester) async {
      await h.pumpHome(tester);
      h.openScreen(tester);
      await tester.pumpAndSettle();
      await h.advance(tester, const Duration(seconds: 46));

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('offer-screen')), findsNothing);
      expect(find.byKey(const Key('offer-card')), findsNothing);
      expect(find.byKey(const Key('waiting')), findsOneWidget);
    });
  });
}

const _ref = 'TRIP-1';
final _assigned = DateTime.utc(2026, 10, 9, 10);

final class _Harness {
  final clock = _ManualClock();
  final timers = _FakeTimers();
  late final server = _Server(clock)..offers = [offer()];
  late final store = DriverPendingOfferStore(source: server, clock: clock);
  late final coordinator = DriverOfferCoordinator(
    store: store,
    periodicTimer: timers.create,
  );
  final _navigator = GlobalKey<NavigatorState>();
  final gateway = _Gateway();

  Map<String, Object?> offer({
    Object? expiresAt = 45,
    int assignedAfter = 0,
    String reference = _ref,
    String pickup = 'Pinned location',
  }) => <String, Object?>{
    'trip_reference': reference,
    'pickup_location': pickup,
    'passenger_count': 1,
    'fare_amount': null,
    'fare_currency': 'GHS',
    'assigned_at': _assigned
        .add(Duration(seconds: assignedAfter))
        .toIso8601String(),
    'offer_expires_at': expiresAt == null
        ? null
        : _assigned.add(Duration(seconds: expiresAt as int)).toIso8601String(),
    'requested_pickup_time': null,
  };

  Future<DriverOfferResponseResilienceController> _controller(
    String reference, {
    DateTime? assignedAt,
  }) async => DriverOfferResponseResilienceController(
    queue: _MemoryQueue(),
    gateway: gateway,
    tripReference: reference,
    driverId: 'DRV-1',
    verifyServerState: (receipt) async => DriverOfferVerifiedTrip(
      tripReference: reference,
      status: receipt.tripStatus,
    ),
  );

  Widget _screen() => DriverPendingOfferScreen(
    tripReference: _ref,
    coordinator: coordinator,
    controllerFactory: _controller,
  );

  Future<void> _start(WidgetTester tester, Widget home) async {
    coordinator.setOnDuty(true);
    await tester.pumpWidget(MaterialApp(navigatorKey: _navigator, home: home));
    await tester.pump();
    await tester.pump();
  }

  Future<void> pumpHome(WidgetTester tester) => _start(
    tester,
    Scaffold(
      body: SingleChildScrollView(
        child: DriverPendingOffersPanel(
          coordinator: coordinator,
          controllerFactory: _controller,
          waitingPanel: const Text('Waiting for offers', key: Key('waiting')),
        ),
      ),
    ),
  );

  Future<void> pumpScreen(WidgetTester tester) => _start(tester, _screen());

  void openScreen(WidgetTester tester) {
    unawaited(
      _navigator.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => _screen()),
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
}

final class _ManualClock implements DriverMonotonicClock {
  static const start = Duration(seconds: 100);
  Duration value = start;

  @override
  Duration get now => value;
}

/// Answers at once, with a server clock that runs with the phone's, and the
/// offers it was given: it never expires them itself.
final class _Server implements DriverPendingOffersSource {
  _Server(this.clock);

  final _ManualClock clock;
  var offers = <Map<String, Object?>>[];
  var calls = 0;

  /// While set, answers wait for it.
  Completer<void>? hold;

  @override
  Future<DriverPendingOffersFetch> fetch() async {
    calls += 1;
    await hold?.future;
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

  @override
  Future<DriverOfferResponseReceipt> accept({
    required String tripReference,
    required String idempotencyKey,
    required String deviceTimestamp,
    DriverOfferSubmissionTelemetrySink? telemetrySink,
  }) async {
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
  }) async => DriverOfferResponseReceipt(
    tripReference: tripReference,
    tripStatus: 'driver_declined',
    duplicate: false,
  );
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
