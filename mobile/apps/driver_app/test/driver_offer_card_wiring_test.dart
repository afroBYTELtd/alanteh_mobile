import 'dart:async';

import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_auth/asm_auth.dart';
import 'package:asm_offline_queue/asm_offline_queue.dart';
import 'package:driver_app/driver_duty_trips.dart';
import 'package:driver_app/main.dart';
import 'package:driver_app/network/driver_offer_response_gateway.dart';
import 'package:driver_app/network/driver_offer_response_resilience.dart';
import 'package:driver_app/network/driver_trip_action_resilience.dart';
import 'package:driver_app/notifications/push_notification_runtime.dart';
import 'package:driver_app/offers/driver_offer_coordinator.dart';
import 'package:driver_app/offers/driver_pending_offer_store.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a push tap while signed in opens the card at once, '
      'before the offers fetch returns', (tester) async {
    final app = _App();
    await app.pumpSignedIn(tester);
    app.source.hold = true;

    app.push.emitOpened(_offerMessage('TRIP-1'));
    await tester.pump(); // the stream delivers the tap
    await tester.pump(); // the route's first (offstage) frame
    // On screen 50 ms later, with the offers fetch still out.
    await tester.pump(const Duration(milliseconds: 50));

    expect(app.source.held, 1, reason: 'the offers fetch is still out');
    expect(find.byKey(const Key('offer-screen')), findsOneWidget);
    expect(find.byKey(const Key('offer-card')), findsOneWidget);
    expect(find.text('Respond quickly'), findsOneWidget);
    // The fetch from before the tap does not count as the offer being gone.
    expect(find.text('This offer is no longer available'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    app.source.release([_offer('TRIP-1', pickup: 'Accra Mall')]);
    await _settle(tester);
    expect(find.text('Accra Mall'), findsOneWidget);
    await app.dispose(tester);
  });

  testWidgets('repeat 2 on the phone: an ended card is open and a tap for '
      'a new offer arrives; the new offer shows', (tester) async {
    final app = _App()..source.offers = [_offer('TRIP-1')];
    // The server's clock runs with the phone's, so a refetch does not
    // restart the countdown.
    app.source.serverNow = () => DateTime.utc(
      2026,
      10,
      9,
      10,
      0,
      5,
    ).add(app.clock.value - const Duration(seconds: 100));
    await app.pumpSignedIn(tester);
    app.push.emitOpened(_offerMessage('TRIP-1'));
    await _settle(tester);
    for (var i = 0; i < 41; i += 1) {
      app.clock.value += const Duration(seconds: 1);
      await tester.pump(const Duration(seconds: 1));
    }
    expect(find.text('Offer expired'), findsOneWidget);

    app.source.offers = [
      _offer('TRIP-1'),
      _offer(
        'TRIP-2',
        pickup: 'Osu Castle',
        expiresAt: '2026-10-09T10:01:30+00:00',
      ),
    ];
    app.push.emitOpened(_offerMessage('TRIP-2'));
    await _settle(tester);

    expect(find.byKey(const Key('offer-screen')), findsOneWidget);
    expect(find.text('Osu Castle'), findsOneWidget);
    expect(find.text('Offer expired'), findsNothing);
    expect(find.textContaining(' left'), findsOneWidget);
    await app.dispose(tester);
  });

  testWidgets('a poll already out when the tap opens the card comes back '
      'without the offer: the card asks again and shows it well before 8 s', (
    tester,
  ) async {
    final app = _App();
    await app.pumpSignedIn(tester);
    // A normal poll leaves before the offer exists, and is slow.
    app.source.hold = true;
    final stalePoll = app.coordinator.store.refresh();
    final callsBefore = app.source.calls;

    app.push.emitOpened(_offerMessage('TRIP-1'));
    await tester.pump();
    await tester.pump();
    expect(app.source.calls, callsBefore, reason: 'the tap joined the poll');

    // The old poll returns without the offer; the server now has it.
    app.source.hold = false;
    app.source.offers = [_offer('TRIP-1', pickup: 'Accra Mall')];
    app.source.releaseOldest(const []);
    await stalePoll;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(app.source.calls, callsBefore + 1, reason: 'one fresh request');
    expect(find.text('Accra Mall'), findsOneWidget);
    expect(find.text("Couldn't load trip details"), findsNothing);
    await app.dispose(tester);
  });

  testWidgets('the fresh request fails too: the card does not keep asking', (
    tester,
  ) async {
    final app = _App();
    await app.pumpSignedIn(tester);
    app.source.hold = true;
    final stalePoll = app.coordinator.store.refresh();
    final callsBefore = app.source.calls;
    app.push.emitOpened(_offerMessage('TRIP-1'));
    await tester.pump();
    await tester.pump();

    app.source.failNext = true;
    app.source.releaseOldest(const []);
    await stalePoll;
    for (var i = 0; i < 5; i += 1) {
      await tester.pump(const Duration(milliseconds: 500));
    }

    expect(app.source.calls, callsBefore + 1, reason: 'asked once, not more');
    await app.dispose(tester);
  });

  testWidgets('the fresh request also lacks the offer: it has ended', (
    tester,
  ) async {
    final app = _App();
    await app.pumpSignedIn(tester);
    app.source.hold = true;
    final stalePoll = app.coordinator.store.refresh();
    app.push.emitOpened(_offerMessage('TRIP-1'));
    await tester.pump();
    await tester.pump();

    app.clock.value += const Duration(seconds: 1);
    app.source.hold = false;
    app.source.offers = const [];
    app.source.releaseOldest(const []);
    await stalePoll;
    await _settle(tester);

    expect(find.text('Offer ended'), findsOneWidget);
    await app.dispose(tester);
  });

  for (final withPickupTime in [false, true]) {
    final label = withPickupTime
        ? 'with requested_pickup_time'
        : 'without requested_pickup_time (looked up, slowly)';
    testWidgets('after the switch from an ended card, Accept turns on and '
        'works ($label)', (tester) async {
      final app = _App()
        ..source.offers = [_offer('TRIP-1', includePickupTime: withPickupTime)];
      app.source.serverNow = () => DateTime.utc(
        2026,
        10,
        9,
        10,
        0,
        5,
      ).add(app.clock.value - const Duration(seconds: 100));
      await app.pumpSignedIn(tester);
      app.push.emitOpened(_offerMessage('TRIP-1'));
      await _settle(tester);
      for (var i = 0; i < 41; i += 1) {
        app.clock.value += const Duration(seconds: 1);
        await tester.pump(const Duration(seconds: 1));
      }
      expect(find.text('Offer expired'), findsOneWidget);

      app.duty.detailDelay = const Duration(seconds: 4);
      app.source.offers = [
        _offer('TRIP-1', includePickupTime: withPickupTime),
        _offer(
          'TRIP-2',
          pickup: 'Osu Castle',
          expiresAt: '2026-10-09T10:01:30+00:00',
          includePickupTime: withPickupTime,
        ),
      ];
      app.push.emitOpened(_offerMessage('TRIP-2'));
      await _settle(tester);
      expect(find.text('Osu Castle'), findsOneWidget);
      if (!withPickupTime) {
        // Not before the lookup answers (it takes 4 s here).
        expect(app.duty.detailCalls, contains('TRIP-2'));
        expect(
          tester
              .widget<ButtonStyleButton>(
                find.byKey(const Key('offer-card-accept')),
              )
              .onPressed,
          isNull,
        );
      }

      // Within the lookup's time, Accept turns on.
      for (var i = 0; i < 5; i += 1) {
        app.clock.value += const Duration(seconds: 1);
        await tester.pump(const Duration(seconds: 1));
      }
      final accept = tester.widget<ButtonStyleButton>(
        find.byKey(const Key('offer-card-accept')),
      );
      expect(accept.onPressed, isNotNull, reason: 'Accept is on');

      app.duty.detailDelay = Duration.zero;
      await tester.tap(find.byKey(const Key('offer-card-accept')));
      await _settle(tester);
      expect(app.offerGateway.accepts, 1);
      expect(app.offerGateway.acceptedTrips, ['TRIP-2']);
      expect(find.byType(DriverTripDetailScreen), findsOneWidget);
      await app.dispose(tester);
    });
  }

  testWidgets('Accept on the card opens the trip', (tester) async {
    final app = _App()..source.offers = [_offer('TRIP-1')];
    await app.pumpSignedIn(tester);

    app.push.emitOpened(_offerMessage('TRIP-1'));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('offer-card-accept')));
    await _settle(tester);

    expect(app.offerGateway.accepts, 1);
    expect(find.byType(DriverTripDetailScreen), findsOneWidget);
    expect(find.byKey(const Key('offer-screen')), findsNothing);
    await app.dispose(tester);
  });

  testWidgets("the card's answer is for the listed offer's assigned_at", (
    tester,
  ) async {
    final app = _App()..source.offers = [_offer('TRIP-1')];
    await app.pumpSignedIn(tester);

    app.push.emitOpened(_offerMessage('TRIP-1'));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('offer-card-accept')));
    await _settle(tester);

    expect(app.offerGateway.accepts, 1);
    expect(app.preparedFor.last, DateTime.utc(2026, 10, 9, 10));
    await app.dispose(tester);
  });

  group('a tap that opened the app (cold start)', () {
    testWidgets('restore succeeds and the offer is pending: the card opens', (
      tester,
    ) async {
      final app = _App(initial: _offerMessage('TRIP-1'))
        ..source.offers = [_offer('TRIP-1')];
      await app.pumpRestoring(tester);
      await _settle(tester);

      expect(find.byKey(const Key('offer-screen')), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('restore succeeds but the offer is gone: no card', (
      tester,
    ) async {
      final app = _App(initial: _offerMessage('TRIP-1'))..source.offers = [];
      await app.pumpRestoring(tester);
      await _settle(tester);

      expect(find.byKey(const Key('offer-screen')), findsNothing);
      await app.dispose(tester);
    });

    testWidgets('restore fails: the tap is dropped, even after a later '
        'sign-in', (tester) async {
      final app = _App(initial: _offerMessage('TRIP-1'))
        ..auth.refreshRejected = true
        ..source.offers = [_offer('TRIP-1')];
      await app.pumpRestoring(tester);
      await _settle(tester);
      expect(find.byKey(const Key('driver-sign-in')), findsOneWidget);

      await app.signIn(tester);
      expect(find.byKey(const Key('offer-screen')), findsNothing);
      await app.dispose(tester);
    });

    testWidgets('a launch tap handed over after the restore failed is '
        'dropped too', (tester) async {
      final app = _App(initial: _offerMessage('TRIP-1'), holdInitial: true)
        ..auth.refreshRejected = true
        ..source.offers = [_offer('TRIP-1')];
      await app.pumpRestoring(tester);
      await _settle(tester);
      expect(find.byKey(const Key('driver-sign-in')), findsOneWidget);

      app.push.releaseInitial();
      await _settle(tester);
      await app.signIn(tester);
      expect(find.byKey(const Key('offer-screen')), findsNothing);
      await app.dispose(tester);
    });

    testWidgets('more than 2 minutes before sign-in: the tap is dropped', (
      tester,
    ) async {
      final app = _App(initial: _offerMessage('TRIP-1'))
        ..source.offers = [_offer('TRIP-1')]
        ..auth.holdRefresh = true;
      await app.pumpRestoring(tester);
      await tester.pump();
      app.clock.value += const Duration(minutes: 2, seconds: 1);
      app.auth.releaseRefresh();
      await _settle(tester);

      expect(find.byKey(const Key('offer-screen')), findsNothing);
      await app.dispose(tester);
    });
  });

  testWidgets('a second driver on the same phone never sees the first '
      "driver's offer", (tester) async {
    final app = _App()..source.offers = [_offer('TRIP-A', pickup: 'Pickup A')];
    await app.pumpSignedIn(tester);
    expect(find.text('Pickup A'), findsOneWidget, reason: 'A sees it');

    // A fetch for driver A is still out when A signs out.
    app.source.hold = true;
    unawaited(app.coordinator.store.refresh());
    await tester.tap(find.byKey(const Key('driver-sign-out')));
    await _settle(tester);
    expect(app.coordinator.store.snapshot, isNull);

    await app.signIn(tester);
    expect(find.text('Pickup A'), findsNothing);

    // A's late answer arrives after B signed in: ignored. B's own fetch
    // finds no offers for B.
    app.source.releaseOldest([_offer('TRIP-A', pickup: 'Pickup A')]);
    app.source.release(const []);
    await _settle(tester);
    expect(find.text('Pickup A'), findsNothing);
    expect(app.coordinator.store.offerFor('TRIP-A'), isNull);
    await app.dispose(tester);
  });

  group('a push while the app is open', () {
    testWidgets('with the offer in the fetch: the card opens', (tester) async {
      final app = _App();
      await app.pumpSignedIn(tester);
      app.source.offers = [_offer('TRIP-1')];

      app.push.emitForeground(_offerMessage('TRIP-1'));
      await _settle(tester);
      expect(find.byKey(const Key('offer-screen')), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('without it: the snackbar, with Open', (tester) async {
      final app = _App();
      await app.pumpSignedIn(tester);
      app.source.offers = [];

      app.push.emitForeground(_offerMessage('TRIP-1'));
      await _settle(tester);
      expect(find.byKey(const Key('offer-screen')), findsNothing);
      expect(find.byKey(const Key('push-snackbar-open')), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('signed out: nothing is shown and nothing is fetched', (
      tester,
    ) async {
      final app = _App();
      await app.pumpSignedOut(tester);
      final fetches = app.source.calls;

      app.push.emitForeground(_offerMessage('TRIP-1'));
      app.push.emitForeground(
        const RemoteMessage(
          data: <String, dynamic>{'event_type': 'trip_cancelled'},
          notification: RemoteNotification(title: 'Trip cancelled'),
        ),
      );
      await _settle(tester);
      expect(find.byType(SnackBar), findsNothing);
      expect(app.source.calls, fetches);
      await app.dispose(tester);
    });
  });

  testWidgets('polls only while on duty; sign-out stops it', (tester) async {
    final app = _App();
    await app.pumpSignedIn(tester);
    expect(app.coordinator.polling, isTrue);

    await tester.tap(find.byKey(const Key('driver-sign-out')));
    await _settle(tester);
    expect(app.coordinator.polling, isFalse);
    await app.dispose(tester);
  });
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i += 1) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

RemoteMessage _offerMessage(String reference) => RemoteMessage(
  data: <String, dynamic>{
    'event_type': 'driver_assigned',
    'trip_reference': reference,
  },
  notification: const RemoteNotification(
    title: 'New trip request',
    body: 'Open the app to respond.',
  ),
);

Map<String, Object?> _offer(
  String reference, {
  String pickup = 'Accra Mall',
  String expiresAt = '2026-10-09T10:00:45+00:00',
  bool includePickupTime = true,
}) => <String, Object?>{
  'trip_reference': reference,
  'pickup_location': pickup,
  'passenger_count': 1,
  'fare_amount': '35.00',
  'fare_currency': 'GHS',
  'assigned_at': '2026-10-09T10:00:00+00:00',
  'offer_expires_at': expiresAt,
  if (includePickupTime) 'requested_pickup_time': null,
};

final class _App {
  _App({RemoteMessage? initial, bool holdInitial = false})
    : push = _PushSource(initial, holdInitial: holdInitial);

  final _PushSource push;
  final clock = _ManualClock();
  final source = _Source();
  final timers = _Timers();
  final auth = _AuthApi();
  final offerGateway = _OfferGateway();

  /// One queue for every card, as the real card factory shares one.
  final queue = _Queue();
  final preparedFor = <DateTime?>[];
  final tokenStore = MemoryAuthTokenStore();
  final duty = _Duty();
  late final coordinator = DriverOfferCoordinator(
    store: DriverPendingOfferStore(source: source, clock: clock),
    periodicTimer: timers.create,
  );

  Widget _app() => DriverApp(
    showLoginShell: true,
    authService: AuthService(
      apiGateway: auth,
      tokenStore: tokenStore,
      appContext: AuthAppContext.driver,
    ),
    authTokenStore: tokenStore,
    driverDutyGateway: duty,
    pushMessageSource: push,
    offerCoordinator: coordinator,
    offerCardControllerFactory: (reference, {assignedAt}) async {
      preparedFor.add(assignedAt);
      return DriverOfferResponseResilienceController(
        queue: queue,
        gateway: offerGateway,
        tripReference: reference,
        driverId: 'DRV-1',
        assignedAt: assignedAt,
        verifyServerState: (receipt) async => DriverOfferVerifiedTrip(
          tripReference: reference,
          status: receipt.tripStatus,
        ),
      );
    },
  );

  Future<void> pumpSignedOut(WidgetTester tester) async {
    await tester.pumpWidget(_app());
    await _settle(tester);
  }

  Future<void> pumpSignedIn(WidgetTester tester) async {
    await pumpSignedOut(tester);
    await signIn(tester);
  }

  /// Starts with a stored session, so the app restores it.
  Future<void> pumpRestoring(WidgetTester tester) async {
    await tokenStore.saveTokens(
      AuthTokens(accessToken: 'stored-access', refreshToken: 'stored-refresh'),
    );
    await tester.pumpWidget(_app());
    await tester.pump();
  }

  Future<void> signIn(WidgetTester tester) async {
    await tester.enterText(
      find.byKey(const Key('driver-phone-field')),
      '+233000000001',
    );
    await tester.enterText(find.byKey(const Key('driver-pin-field')), '9876');
    await tester.tap(find.byKey(const Key('driver-sign-in')));
    await _settle(tester);
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await push.dispose();
  }
}

final class _ManualClock implements DriverMonotonicClock {
  Duration value = const Duration(seconds: 100);

  @override
  Duration get now => value;
}

final class _Source implements DriverPendingOffersSource {
  List<Map<String, Object?>> offers = const [];
  bool hold = false;
  final _held = <Completer<DriverPendingOffersFetch>>[];

  int get held => _held.length;

  var calls = 0;

  /// The server's clock; a fixed 10:00:05 when unset.
  DateTime Function()? serverNow;

  /// The next request fails as if there were no network.
  bool failNext = false;

  @override
  Future<DriverPendingOffersFetch> fetch() {
    calls += 1;
    if (failNext) {
      failNext = false;
      return Future.value(const DriverPendingOffersUnavailable());
    }
    if (hold) {
      final pending = Completer<DriverPendingOffersFetch>();
      _held.add(pending);
      return pending.future;
    }
    return Future.value(_reply(offers, serverNow));
  }

  void release(List<Map<String, Object?>> withOffers) {
    hold = false;
    offers = withOffers;
    for (final pending in _held) {
      pending.complete(_reply(withOffers, serverNow));
    }
    _held.clear();
  }

  /// Answers only the oldest held fetch; later ones stay held.
  void releaseOldest(List<Map<String, Object?>> withOffers) =>
      _held.removeAt(0).complete(_reply(withOffers, serverNow));

  static DriverPendingOffersFetch _reply(
    List<Map<String, Object?>> offers,
    DateTime Function()? serverNow,
  ) => DriverPendingOffersFetched(<String, Object?>{
    'server_time':
        serverNow?.call().toIso8601String() ?? '2026-10-09T10:00:05+00:00',
    'offers': offers,
  });
}

final class _Timers {
  Timer create(Duration interval, void Function(Timer) onTick) => _Timer();
}

final class _Timer implements Timer {
  var _active = true;

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;

  @override
  void cancel() => _active = false;
}

final class _AuthApi implements AuthApiGateway {
  bool refreshRejected = false;
  bool holdRefresh = false;
  final _gate = Completer<void>();

  void releaseRefresh() => _gate.complete();

  @override
  Future<ApiResponse<Map<String, Object?>>> post(
    String path, {
    required Map<String, Object?> body,
  }) async {
    if (path == AuthService.refreshPath) {
      if (holdRefresh) {
        await _gate.future;
      }
      if (refreshRejected) {
        return ApiResponse<Map<String, Object?>>.apiFailure(
          const AsmApiException(
            type: AsmApiExceptionType.authentication,
            message: 'rejected',
            statusCode: 401,
          ),
        );
      }
      return ApiResponse<Map<String, Object?>>.success(<String, Object?>{
        'access': 'refreshed-access',
      }, statusCode: 200);
    }
    return ApiResponse<Map<String, Object?>>.success(<String, Object?>{
      'access': 'driver-access',
      'refresh': 'driver-refresh',
      'account_type': 'driver',
      'account': <String, Object?>{},
    }, statusCode: 200);
  }
}

final class _Duty implements DriverDutyGateway {
  @override
  Future<DriverDutySummary> fetchDuty() async => DriverDutySummary(
    driverReference: 'DRV-1',
    dutyStatus: 'online',
    dutySince: DateTime(2026, 10, 9, 8),
    shiftCheckToday: true,
    canReceiveAssignments: true,
  );

  @override
  Future<List<DriverAssignedTrip>> fetchTrips() async => const [];

  /// Trip-detail lookups wait this long (a slow network).
  Duration detailDelay = Duration.zero;
  final detailCalls = <String>[];

  @override
  Future<DriverAssignedTrip> fetchTripDetail(String tripReference) async {
    detailCalls.add(tripReference);
    if (detailDelay > Duration.zero) {
      await Future<void>.delayed(detailDelay);
    }
    return DriverAssignedTrip(
      reference: tripReference,
      status: 'driver_accepted',
      pickupLocation: 'Accra Mall',
      destination: 'Independence Square',
    );
  }
}

final class _OfferGateway implements DriverOfferResponseGateway {
  var accepts = 0;
  final acceptedTrips = <String>[];

  @override
  Future<DriverOfferResponseReceipt> accept({
    required String tripReference,
    required String idempotencyKey,
    required String deviceTimestamp,
    DriverOfferSubmissionTelemetrySink? telemetrySink,
  }) async {
    accepts += 1;
    acceptedTrips.add(tripReference);
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

final class _Queue implements DriverTripActionPersistentQueue {
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

final class _PushSource implements DriverPushMessageSource {
  _PushSource(this.initialMessage, {bool holdInitial = false})
    : _initialGate = holdInitial ? Completer<void>() : null;

  final RemoteMessage? initialMessage;
  final Completer<void>? _initialGate;

  /// Hands over the launch tap now (Firebase can be slower than a restore).
  void releaseInitial() => _initialGate?.complete();
  final _foreground = StreamController<RemoteMessage>.broadcast();
  final _opened = StreamController<RemoteMessage>.broadcast();

  @override
  Stream<RemoteMessage> get foregroundMessages => _foreground.stream;

  @override
  Stream<RemoteMessage> get openedMessages => _opened.stream;

  @override
  Future<RemoteMessage?> getInitialMessage() async {
    await _initialGate?.future;
    return initialMessage;
  }

  void emitOpened(RemoteMessage message) => _opened.add(message);

  void emitForeground(RemoteMessage message) => _foreground.add(message);

  Future<void> dispose() async {
    await _foreground.close();
    await _opened.close();
  }
}
