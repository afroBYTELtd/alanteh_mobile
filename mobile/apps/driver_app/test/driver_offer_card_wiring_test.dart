import 'dart:async';

import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_auth/asm_auth.dart';
import 'package:asm_offline_queue/asm_offline_queue.dart';
import 'package:driver_app/driver_duty_trips.dart';
import 'package:driver_app/driver_home.dart';
import 'package:driver_app/main.dart';
import 'package:driver_app/network/driver_offer_response_gateway.dart';
import 'package:driver_app/network/driver_offer_response_resilience.dart';
import 'package:driver_app/network/driver_trip_action_resilience.dart';
import 'package:driver_app/notifications/push_notification_runtime.dart';
import 'package:driver_app/offers/driver_offer_coordinator.dart';
import 'package:driver_app/offers/driver_offer_layer.dart';
import 'package:driver_app/offers/driver_pending_offer_store.dart';
import 'package:driver_app/trip_progress/driver_trip_visual_sequence.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

  testWidgets('Decline while the offer never arrives: the shell asks for '
      'an answer of its own (unknown offer)', (tester) async {
    final app = _App();
    await app.pumpSignedIn(tester);

    app.push.emitOpened(_offerMessage('TRIP-1'));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('offer-card-decline')));
    await _settle(tester);
    await tester.tap(
      find.byKey(const Key('driver-decline-reason-option-end_of_shift')),
    );
    await _settle(tester);
    await tester.tap(find.byKey(const Key('driver-decline-reason-confirm')));
    await tester.pump(const Duration(seconds: 9));
    await _settle(tester);

    expect(app.unknownOffers, contains(true));
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

  // An automatic offer lives 45 s: a pushed or tapped offer is never dropped
  // because the list held was old. A fetch decides; if it fails, or takes
  // more than 5 s, the list held before decides, as it always did.
  group('a tap that opened the app, with an old list held', () {
    Future<_App> withOldList(WidgetTester tester) async {
      final app = _App(initial: _offerMessage('TRIP-1'))
        ..source.offers = [_offer('TRIP-1')];
      await app.coordinator.store.refresh();
      app.clock.value += const Duration(seconds: 30);
      expect(app.coordinator.store.isFresh, isFalse);
      return app;
    }

    testWidgets('the fetch still lists the offer: the card opens', (
      tester,
    ) async {
      final app = await withOldList(tester);
      await app.pumpRestoring(tester);
      await _settle(tester);

      expect(find.byKey(const Key('offer-screen')), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('the fetch fails: the card opens from the old list', (
      tester,
    ) async {
      final app = await withOldList(tester);
      app.source.failAll = true;
      await app.pumpRestoring(tester);
      await _settle(tester);

      expect(find.byKey(const Key('offer-screen')), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('the fetch is slow: the card opens from the old list after '
        '5 s', (tester) async {
      final app = await withOldList(tester);
      app.source.hold = true;
      await app.pumpRestoring(tester);
      await _settle(tester);
      expect(find.byKey(const Key('offer-screen')), findsNothing);

      await tester.pump(const Duration(seconds: 4));
      await _settle(tester);
      expect(find.byKey(const Key('offer-screen')), findsOneWidget);
      app.source.release([_offer('TRIP-1')]);
      await _settle(tester);
      await app.dispose(tester);
    });

    testWidgets('a current list without the offer: no card', (tester) async {
      final app = await withOldList(tester);
      app.source.offers = [];
      await app.pumpRestoring(tester);
      await _settle(tester);

      expect(find.byKey(const Key('offer-screen')), findsNothing);
      await app.dispose(tester);
    });
  });

  group('a push while the app is open, with an old list held', () {
    Future<_App> withOldList(WidgetTester tester) async {
      final app = _App();
      await app.pumpSignedIn(tester);
      app.source.offers = [_offer('TRIP-1')];
      await app.coordinator.store.refresh();
      await _settle(tester);
      app.clock.value += const Duration(seconds: 30);
      expect(app.coordinator.store.isFresh, isFalse);
      return app;
    }

    testWidgets('the fetch still lists the offer: the card opens', (
      tester,
    ) async {
      final app = await withOldList(tester);

      app.push.emitForeground(_offerMessage('TRIP-1'));
      await _settle(tester);
      expect(find.byKey(const Key('offer-screen')), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('the fetch fails: the card opens from the old list', (
      tester,
    ) async {
      final app = await withOldList(tester);
      app.source.failAll = true;

      app.push.emitForeground(_offerMessage('TRIP-1'));
      await _settle(tester);
      expect(find.byKey(const Key('offer-screen')), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('the fetch is slow: the card opens from the old list after '
        '5 s', (tester) async {
      final app = await withOldList(tester);
      app.source.hold = true;

      app.push.emitForeground(_offerMessage('TRIP-1'));
      await _settle(tester);
      expect(find.byKey(const Key('offer-screen')), findsNothing);
      await tester.pump(const Duration(seconds: 4));
      await _settle(tester);
      expect(find.byKey(const Key('offer-screen')), findsOneWidget);
      app.source.release([_offer('TRIP-1')]);
      await _settle(tester);
      await app.dispose(tester);
    });

    testWidgets('a current list without the offer: the snackbar, no card', (
      tester,
    ) async {
      final app = await withOldList(tester);
      app.source.offers = [];

      app.push.emitForeground(_offerMessage('TRIP-1'));
      await _settle(tester);
      expect(find.byKey(const Key('offer-screen')), findsNothing);
      expect(find.byKey(const Key('push-snackbar-open')), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('nothing held to open from: it waits for the slow fetch', (
      tester,
    ) async {
      final app = _App();
      await app.pumpSignedIn(tester);
      app.source.hold = true;

      app.push.emitForeground(_offerMessage('TRIP-1'));
      await tester.pump(const Duration(seconds: 7));
      app.source.release([_offer('TRIP-1')]);
      await _settle(tester);
      expect(find.byKey(const Key('offer-screen')), findsOneWidget);
      await app.dispose(tester);
    });
  });

  // B5: one card for the whole app, on every tab and over any screen the
  // driver has open. Seen 24 Oct: an offer for TRIP-76C8ADB446D4 ran out
  // while the driver was on the "Trip completed" screens, where no card
  // showed.
  group('one offer card everywhere', () {
    Future<void> offerArrives(WidgetTester tester, _App app) async {
      app.source.offers = [
        _offer('TRIP-1', expiresAt: '2026-10-09T10:01:00+00:00'),
      ];
      await app.coordinator.store.refresh();
      await _settle(tester);
    }

    Future<void> selectTab(WidgetTester tester, String label) async {
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(label),
        ),
      );
      await _settle(tester);
    }

    testWidgets('on Work: exactly one card, and no "Waiting for offers"', (
      tester,
    ) async {
      final app = _App();
      await app.pumpSignedIn(tester);
      await offerArrives(tester, app);

      expect(find.byKey(const Key('offer-card')), findsOneWidget);
      expect(find.text('Waiting for offers'), findsNothing);
      await app.dispose(tester);
    });

    testWidgets('on Trips: the card shows and Accept opens the trip', (
      tester,
    ) async {
      final app = _App();
      await app.pumpSignedIn(tester);
      await selectTab(tester, 'Trips');
      await offerArrives(tester, app);

      expect(find.byKey(const Key('offer-card')), findsOneWidget);
      await tester.tap(find.byKey(const Key('offer-card-accept')));
      await _settle(tester);

      expect(app.offerGateway.acceptedTrips, ['TRIP-1']);
      expect(find.byType(DriverTripDetailScreen), findsOneWidget);
      await app.dispose(tester);
    });

    testWidgets('on Account: Decline asks for a reason and sends it', (
      tester,
    ) async {
      final app = _App();
      await app.pumpSignedIn(tester);
      await selectTab(tester, 'Account');
      await offerArrives(tester, app);

      await tester.tap(find.byKey(const Key('offer-card-decline')));
      await _settle(tester);
      expect(find.text('Why are you declining?'), findsOneWidget);
      await tester.tap(
        find.byKey(const Key('driver-decline-reason-option-end_of_shift')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('driver-decline-reason-confirm')));
      await _settle(tester);

      expect(app.offerGateway.declines, 1);
      expect(find.byKey(const Key('offer-card')), findsNothing);
      await app.dispose(tester);
    });

    testWidgets('switching tabs keeps the countdown and "Sending…"', (
      tester,
    ) async {
      final app = _App();
      await app.pumpSignedIn(tester);
      await offerArrives(tester, app);
      app.offerGateway.holdAccept = Completer<void>();

      await tester.tap(find.byKey(const Key('offer-card-accept')));
      await tester.pump();
      expect(find.text('Sending…'), findsOneWidget);
      final countdown = tester
          .widget<Text>(find.byKey(const Key('offer-card-countdown')))
          .data;

      await selectTab(tester, 'Trips');
      expect(find.byKey(const Key('offer-card')), findsOneWidget);
      expect(find.text('Sending…'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('offer-card-countdown'))).data,
        countdown,
      );
      expect(app.offerGateway.accepts, 1, reason: 'not sent twice');

      app.offerGateway.holdAccept!.complete();
      await _settle(tester);
      await app.dispose(tester);
    });

    testWidgets('over the "Trip completed" screen: the card shows and Accept '
        'works', (tester) async {
      final app = _App();
      await app.pumpSignedIn(tester);
      unawaited(
        Navigator.of(tester.element(find.byType(DriverShell))).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => const DriverTripVisualSequencePage(
              initialStatus: 'completed_pending_review',
              tripReference: 'TRIP-0',
            ),
          ),
        ),
      );
      await _settle(tester);
      expect(
        find.text('Trip completed — awaiting operations review'),
        findsWidgets,
      );

      await offerArrives(tester, app);
      expect(find.byKey(const Key('offer-card')), findsOneWidget);
      await tester.tap(find.byKey(const Key('offer-card-accept')));
      await _settle(tester);

      expect(app.offerGateway.acceptedTrips, ['TRIP-1']);
      await app.dispose(tester);
    });

    testWidgets('on the tabs it sits above the tab bar, clear of the header '
        '(Sign out, Go offline)', (tester) async {
      final app = _App();
      await app.pumpSignedIn(tester);
      await offerArrives(tester, app);

      final card = tester.getRect(find.byKey(const Key('offer-card')));
      final tabs = tester.getRect(find.byType(NavigationBar));
      final signOut = tester.getRect(find.byKey(const Key('driver-sign-out')));
      expect(card.bottom, lessThanOrEqualTo(tabs.top));
      expect(card.top, greaterThan(signOut.bottom));
      await app.dispose(tester);
    });

    testWidgets('over a pushed screen it sits at the top, clear of the '
        'bottom of the screen', (tester) async {
      final app = _App();
      await app.pumpSignedIn(tester);
      unawaited(
        Navigator.of(tester.element(find.byType(DriverShell))).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: Text('Emergency 191'),
              ),
            ),
          ),
        ),
      );
      await _settle(tester);
      await offerArrives(tester, app);

      final card = tester.getRect(find.byKey(const Key('offer-card')));
      final bottomButton = tester.getRect(find.text('Emergency 191'));
      expect(card.top, lessThan(100));
      expect(card.bottom, lessThan(bottomButton.top));
      await app.dispose(tester);
    });

    testWidgets('while the reason sheet is open the card is hidden, and it '
        'comes back after "Never mind"', (tester) async {
      final app = _App();
      await app.pumpSignedIn(tester);
      await offerArrives(tester, app);

      await tester.tap(find.byKey(const Key('offer-card-decline')));
      await _settle(tester);
      expect(find.text('Why are you declining?'), findsOneWidget);
      expect(find.byKey(const Key('offer-card')), findsNothing);

      await tester.tap(find.byKey(const Key('driver-decline-reason-cancel')));
      await _settle(tester);
      expect(find.byKey(const Key('offer-card')), findsOneWidget);
      expect(app.offerGateway.declines, 0);
      await app.dispose(tester);
    });

    testWidgets('a 409: "My Assigned Trips" on the card opens the Trips tab', (
      tester,
    ) async {
      final app = _App();
      await app.pumpSignedIn(tester);
      await offerArrives(tester, app);
      app.offerGateway.acceptError = const DriverOfferResponseException(
        type: DriverOfferResponseFailureType.conflict,
        message: driverOfferConflictMessage,
      );

      await tester.tap(find.byKey(const Key('offer-card-accept')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('offer-card-open-assigned-trips')));
      await _settle(tester);

      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        1,
      );
      await app.dispose(tester);
    });

    for (final (navigation, bottomInset) in const [
      ('gesture navigation', 0.0),
      ('three-button navigation', 126.0),
    ]) {
      testWidgets('at a large text size (2.0), $navigation: the card still '
          'sits above the tab bar', (tester) async {
        // The test phone's screen (1080 x 2340 px), with the text size
        // turned up after signing in, as a driver would in settings.
        tester.view.physicalSize = const Size(1080, 2340);
        tester.view.devicePixelRatio = 2.625;
        tester.view.padding = FakeViewPadding(bottom: bottomInset);
        tester.view.viewPadding = FakeViewPadding(bottom: bottomInset);
        addTearDown(tester.view.reset);
        final app = _App();
        await app.pumpSignedIn(tester);
        tester.platformDispatcher.textScaleFactorTestValue = 2.0;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await _settle(tester);
        await offerArrives(tester, app);

        final card = tester.getRect(find.byKey(const Key('offer-card')));
        final tabs = tester.getRect(find.byType(NavigationBar));
        expect(card.bottom, lessThanOrEqualTo(tabs.top));
        expect(tabs.height, driverOfferLayerTabBarHeight + bottomInset / 2.625);
        await app.dispose(tester);
      });
    }

    testWidgets('sign out and in again in the same shell: the card shows only '
        "the new session's offers", (tester) async {
      final app = _App()
        ..source.offers = [_offer('TRIP-A', pickup: 'Pickup A')];
      await app.pumpSignedIn(tester);
      expect(find.text('Pickup A'), findsOneWidget);

      await tester.tap(find.byKey(const Key('driver-sign-out')));
      await _settle(tester);
      expect(find.byKey(const Key('offer-card')), findsNothing);

      app.source.offers = [_offer('TRIP-B', pickup: 'Pickup B')];
      await app.signIn(tester);
      await app.coordinator.store.refresh();
      await _settle(tester);

      expect(find.text('Pickup B'), findsOneWidget);
      expect(find.text('Pickup A'), findsNothing);
      await tester.tap(find.byKey(const Key('offer-card-accept')));
      await _settle(tester);
      expect(app.offerGateway.acceptedTrips, ['TRIP-B']);
      await app.dispose(tester);
    });

    testWidgets('signed out: no card', (tester) async {
      final app = _App();
      await app.pumpSignedOut(tester);
      app.source.offers = [_offer('TRIP-1')];
      await app.coordinator.store.refresh();
      await _settle(tester);

      expect(find.byKey(const Key('offer-card')), findsNothing);
      await app.dispose(tester);
    });
  });

  // B7.1: a driver the server holds online without today's shift check
  // gets no automatic trips, but staff offers need no shift check, so the
  // app still asks for offers.
  testWidgets('online on the server without today\'s shift check: the poll '
      'runs', (tester) async {
    final app = _App()..duty.shiftCheckToday = false;
    await app.pumpSignedIn(tester);

    expect(app.coordinator.polling, isTrue);
    await app.dispose(tester);
  });

  testWidgets('online without today\'s shift check: a staff offer waiting '
      'shows the card (the poll asks as soon as the driver is on duty)', (
    tester,
  ) async {
    final app = _App()
      ..duty.shiftCheckToday = false
      ..source.offers = [
        {..._offer('TRIP-S'), 'offer_expires_at': null},
      ];
    await app.pumpSignedIn(tester);

    expect(find.byKey(const Key('offer-card')), findsOneWidget);
    await app.dispose(tester);
  });

  // B7.2: seen 25 Oct, GO OFFLINE on Work never reached the server.
  testWidgets('GO OFFLINE on Work reaches the server', (tester) async {
    final app = _App();
    await app.pumpSignedIn(tester);

    await tester.tap(find.byKey(const Key('driver-go-offline')));
    await _settle(tester);

    expect(app.duty.updates, [DriverOperationalDutyStatus.offline]);
    expect(find.byKey(const Key('driver-offline-status')), findsOneWidget);
    expect(find.byKey(const Key('driver-offline-screen')), findsNothing);
    await app.dispose(tester);
  });

  testWidgets('GO ONLINE on Work reaches the server', (tester) async {
    final app = _App()..duty.dutyStatus = 'offline';
    await app.pumpSignedIn(tester);

    await tester.tap(find.byKey(const Key('driver-go-online')));
    await _settle(tester);

    expect(app.duty.updates, [DriverOperationalDutyStatus.online]);
    expect(find.byKey(const Key('driver-online-status')), findsOneWidget);
    await app.dispose(tester);
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

  // B5.1: at large text the Account page overflowed even with no card (by
  // 168 px at 2.0), so "Sign out" could not always be reached.
  group('Account page at large text', () {
    for (final textScale in _largeTextScales) {
      for (final (navigation, bottomInset) in _bottomInsets) {
        testWidgets('at text $textScale, $navigation: no overflow, and '
            '"Safety & emergency" and "Sign out" scroll into full view', (
          tester,
        ) async {
          _phoneScreen(tester, bottomInset: bottomInset);
          final app = _App();
          await app.pumpSignedIn(tester);
          _textScale(tester, textScale);
          await _selectTab(tester, 'Account');

          expect(tester.takeException(), isNull);
          final page = tester.getRect(
            find.byKey(const Key('driver-account-screen')),
          );
          for (final row in const [
            Key('driver-account-safety-emergency'),
            Key('driver-account-sign-out'),
          ]) {
            await tester.ensureVisible(find.byKey(row));
            await _settle(tester);
            final rect = tester.getRect(find.byKey(row));
            expect(rect.top, greaterThanOrEqualTo(page.top), reason: '$row');
            expect(rect.bottom, lessThanOrEqualTo(page.bottom), reason: '$row');
          }
          expect(tester.takeException(), isNull);
          await app.dispose(tester);
        });
      }
    }
  });

  // B5.1: at 2.0 the card was 1,528 dp tall on an 891 dp screen: "New trip
  // request" had 81 dp beside the countdown and "GHS 35.00" 12 dp beside
  // "1 passenger", so both broke almost a letter per line.
  group('offer card at large text', () {
    for (final textScale in _largeTextScales) {
      for (final (navigation, bottomInset) in _bottomInsets) {
        for (final fare in const ['35.00', null]) {
          testWidgets('at text $textScale, $navigation, fare $fare: no word '
              'is broken, and the whole card fits above the tab bar', (
            tester,
          ) async {
            _phoneScreen(tester, bottomInset: bottomInset);
            final app = _App();
            await app.pumpSignedIn(tester);
            _textScale(tester, textScale);
            await _offerArrives(tester, app, fare: fare);

            final card = find.byKey(const Key('offer-card'));
            _expectNoBrokenWords(tester, card);
            final rect = tester.getRect(card);
            final tabs = tester.getRect(find.byType(NavigationBar));
            expect(rect.top, greaterThanOrEqualTo(0));
            expect(rect.bottom, lessThanOrEqualTo(tabs.top));
            final screenHeight =
                tester.view.physicalSize.height / tester.view.devicePixelRatio;
            expect(rect.height, lessThanOrEqualTo(screenHeight * 0.6 + 0.5));
            if (textScale < 2.0) {
              expect(
                _scrollExtentInside(tester, card),
                0,
                reason: 'an ordinary offer fits without scrolling',
              );
            }
            for (final button in const [
              Key('offer-card-decline'),
              Key('offer-card-accept'),
            ]) {
              final buttonRect = tester.getRect(find.byKey(button));
              expect(buttonRect.top, greaterThanOrEqualTo(rect.top));
              expect(buttonRect.bottom, lessThanOrEqualTo(rect.bottom));
            }
            await app.dispose(tester);
          });
        }
      }
    }

    // The test font draws every letter 1 em wide, about twice as wide as
    // the phone's, so here "Sending…" misses half of a 411 dp card by 1 dp.
    // On a wider screen the labels fit, as they do on the phone.
    testWidgets('when the labels fit, Accept and Decline stay side by side', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 2340);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      final app = _App();
      await app.pumpSignedIn(tester);
      await _offerArrives(tester, app, fare: null);

      final decline = tester.getRect(
        find.byKey(const Key('offer-card-decline')),
      );
      final accept = tester.getRect(find.byKey(const Key('offer-card-accept')));
      expect(accept.top, decline.top);
      expect(accept.left, greaterThan(decline.right));
      _expectNoBrokenWords(tester, find.byKey(const Key('offer-card')));
      await app.dispose(tester);
    });

    // A mis-tap on Decline only opens the reason sheet; one on Accept
    // commits the driver. So when they stack, Accept is on top.
    testWidgets('when they do not fit side by side, Accept is above Decline', (
      tester,
    ) async {
      _phoneScreen(tester, bottomInset: 126);
      final app = _App();
      await app.pumpSignedIn(tester);
      _textScale(tester, 2.0);
      await _offerArrives(tester, app, fare: null);

      final decline = tester.getRect(
        find.byKey(const Key('offer-card-decline')),
      );
      final accept = tester.getRect(find.byKey(const Key('offer-card-accept')));
      expect(accept.width, decline.width);
      expect(accept.bottom, lessThanOrEqualTo(decline.top));
      await app.dispose(tester);
    });

    for (final (navigation, bottomInset) in _bottomInsets) {
      testWidgets('a very long pickup at text 2.0, $navigation: the card '
          'stops at 60% of the screen, its details scroll, and Accept and '
          'Decline stay in view', (tester) async {
        _phoneScreen(tester, bottomInset: bottomInset);
        final app = _App();
        await app.pumpSignedIn(tester);
        _textScale(tester, 2.0);
        await _offerArrives(
          tester,
          app,
          pickup: List.filled(30, 'Kotoka International Airport').join(' '),
        );

        final card = tester.getRect(find.byKey(const Key('offer-card')));
        final screenHeight =
            tester.view.physicalSize.height / tester.view.devicePixelRatio;
        expect(card.height, lessThanOrEqualTo(screenHeight * 0.6 + 0.5));
        expect(card.top, greaterThanOrEqualTo(0));
        expect(
          _scrollExtentInside(tester, find.byKey(const Key('offer-card'))),
          greaterThan(0),
        );
        for (final button in const [
          Key('offer-card-decline'),
          Key('offer-card-accept'),
        ]) {
          final rect = tester.getRect(find.byKey(button));
          expect(rect.top, greaterThanOrEqualTo(card.top), reason: '$button');
          expect(
            rect.bottom,
            lessThanOrEqualTo(card.bottom),
            reason: '$button',
          );
        }
        await tester.tap(find.byKey(const Key('offer-card-accept')));
        await _settle(tester);
        expect(app.offerGateway.acceptedTrips, ['TRIP-1']);
        await app.dispose(tester);
      });
    }

    testWidgets('the full "Trip offer" screen at text 2.0: no word is '
        'broken, and Accept is on screen', (tester) async {
      _phoneScreen(tester, bottomInset: 126);
      final app = _App()..source.offers = [_offer('TRIP-1', fare: null)];
      await app.pumpSignedIn(tester);
      _textScale(tester, 2.0);
      app.push.emitOpened(_offerMessage('TRIP-1'));
      await _settle(tester);

      expect(find.byKey(const Key('offer-screen')), findsOneWidget);
      final card = find.byKey(const Key('offer-card'));
      _expectNoBrokenWords(tester, card);
      final screenHeight =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      final accept = tester.getRect(find.byKey(const Key('offer-card-accept')));
      expect(accept.top, greaterThanOrEqualTo(0));
      expect(accept.bottom, lessThanOrEqualTo(screenHeight));
      await app.dispose(tester);
    });
  });

  // B5.1: seen 24 Oct on Account, the card covered "Sign out" and most of
  // the "Safety & emergency" row. On the tabs the page now ends above the
  // card; the header and the tab bar stay where they are.
  group('on the tabs the page ends above the card', () {
    for (final textScale in [1.0, ..._largeTextScales]) {
      for (final (navigation, bottomInset) in _bottomInsets) {
        testWidgets('on Account at text $textScale, $navigation: '
            '"Safety & emergency" and "Sign out" can be seen in full, clear '
            'of the card', (tester) async {
          _phoneScreen(tester, bottomInset: bottomInset);
          final app = _App();
          await app.pumpSignedIn(tester);
          _textScale(tester, textScale);
          await _selectTab(tester, 'Account');
          final tabs = tester.getRect(find.byType(NavigationBar));
          await _offerArrives(tester, app, fare: null);

          final card = tester.getRect(find.byKey(const Key('offer-card')));
          final page = tester.getRect(
            find.byKey(const Key('driver-account-screen')),
          );
          expect(_pageArea(tester).bottom, lessThanOrEqualTo(card.top));
          expect(page.bottom, lessThanOrEqualTo(card.top));
          expect(tester.getRect(find.byType(NavigationBar)), tabs);
          for (final row in const [
            Key('driver-account-safety-emergency'),
            Key('driver-account-sign-out'),
          ]) {
            await _expectScrollsIntoView(tester, find.byKey(row), page);
          }
          expect(tester.takeException(), isNull);
          await app.dispose(tester);
        });

        testWidgets('on Work and Trips at text $textScale, $navigation: the '
            'page ends above the card; the header and the tab bar stay put', (
          tester,
        ) async {
          _phoneScreen(tester, bottomInset: bottomInset);
          final app = _App();
          await app.pumpSignedIn(tester);
          _textScale(tester, textScale);
          await _settle(tester);
          final header = tester.getRect(
            find.byKey(const Key('driver-sign-out')),
          );
          final tabs = tester.getRect(find.byType(NavigationBar));
          await _offerArrives(tester, app, fare: null);

          expect(
            tester.getRect(find.byKey(const Key('driver-sign-out'))),
            header,
          );
          for (final (tab, page) in [
            ('Work', find.byType(DriverHome)),
            ('Trips', find.byType(DriverAssignedTripsScreen)),
          ]) {
            await _selectTab(tester, tab);
            expect(page, findsOneWidget, reason: tab);
            final card = tester.getRect(find.byKey(const Key('offer-card')));
            expect(
              _pageArea(tester).bottom,
              lessThanOrEqualTo(card.top),
              reason: tab,
            );
            expect(
              tester.getRect(find.byType(NavigationBar)),
              tabs,
              reason: tab,
            );
          }
          expect(tester.takeException(), isNull);
          await app.dispose(tester);
        });
      }
    }

    testWidgets('when the card goes, each tab is full height again', (
      tester,
    ) async {
      final app = _App();
      await app.pumpSignedIn(tester);
      await _selectTab(tester, 'Account');
      final tabs = tester.getRect(find.byType(NavigationBar));
      expect(_pageArea(tester).bottom, tabs.top);
      await _offerArrives(tester, app);
      expect(_pageArea(tester).bottom, lessThan(tabs.top));

      await tester.tap(find.byKey(const Key('offer-card-decline')));
      await _settle(tester);
      await tester.tap(
        find.byKey(const Key('driver-decline-reason-option-end_of_shift')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('driver-decline-reason-confirm')));
      await _settle(tester);

      expect(find.byKey(const Key('offer-card')), findsNothing);
      expect(_pageArea(tester).bottom, tabs.top);
      for (final tab in const ['Work', 'Trips']) {
        await _selectTab(tester, tab);
        expect(_pageArea(tester).bottom, tabs.top, reason: tab);
      }
      await app.dispose(tester);
    });

    testWidgets('over a pushed screen the card stays on top and the screen '
        'keeps its full height', (tester) async {
      final app = _App();
      await app.pumpSignedIn(tester);
      unawaited(
        Navigator.of(tester.element(find.byType(DriverShell))).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(
              key: Key('pushed-screen'),
              body: SizedBox.expand(),
            ),
          ),
        ),
      );
      await _settle(tester);
      final screen = tester.getRect(find.byKey(const Key('pushed-screen')));
      final tabsTop = _pageArea(tester).bottom;
      await _offerArrives(tester, app);

      final card = tester.getRect(find.byKey(const Key('offer-card')));
      expect(card.top, lessThan(100));
      expect(tester.getRect(find.byKey(const Key('pushed-screen'))), screen);
      expect(
        _pageArea(tester).bottom,
        tabsTop,
        reason: 'the tabs under the pushed screen are not shortened',
      );
      await app.dispose(tester);
    });

    testWidgets('an offer that arrives on a pushed screen: back on the tabs, '
        'the page ends above the card', (tester) async {
      final app = _App();
      await app.pumpSignedIn(tester);
      unawaited(
        Navigator.of(tester.element(find.byType(DriverShell))).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(
              key: Key('pushed-screen'),
              body: SizedBox.expand(),
            ),
          ),
        ),
      );
      await _settle(tester);
      await _offerArrives(tester, app);

      Navigator.of(
        tester.element(find.byKey(const Key('pushed-screen'))),
      ).pop();
      await _settle(tester);
      final card = tester.getRect(find.byKey(const Key('offer-card')));
      expect(
        card.bottom,
        lessThanOrEqualTo(tester.getRect(find.byType(NavigationBar)).top),
      );
      expect(_pageArea(tester).bottom, lessThanOrEqualTo(card.top));
      await app.dispose(tester);
    });
  });

  // B9. Seen 31 Oct: staff cancelled a staff offer while its card was open
  // on Work; the cancel push arrived, and the card kept offering the trip
  // for 13 minutes.
  group('a trip push in front (B9)', () {
    testWidgets('the 31 Oct case: staff offer, card open, cancel push: the '
        'card says the offer is no longer available, then goes', (
      tester,
    ) async {
      final app = _App();
      app.source.offers = [_staffOffer('TRIP-97C00E85A3BF')];
      await app.pumpSignedIn(tester);
      expect(find.byKey(const Key('offer-card')), findsOneWidget);
      expect(find.text('Waiting for your response'), findsOneWidget);

      // Staff cancel it; the fetch the push makes leaves after the card
      // opened.
      app.clock.value += const Duration(seconds: 1);
      app.source.offers = [];
      final fetches = app.source.calls;
      app.push.emitForeground(_cancelMessage('TRIP-97C00E85A3BF'));
      await _settle(tester);

      expect(app.source.calls, fetches + 1);
      expect(find.text('Offer ended'), findsOneWidget);
      expect(find.text(driverOfferNoLongerAvailableMessage), findsOneWidget);

      for (var i = 0; i < 6; i += 1) {
        app.clock.value += const Duration(seconds: 1);
        await tester.pump(const Duration(seconds: 1));
      }
      await _settle(tester);
      expect(find.byKey(const Key('offer-card')), findsNothing);
      await app.dispose(tester);
    });

    testWidgets('one cancel push in front writes exactly one OFFER_FETCH '
        'reason=push_cancelled line', (tester) async {
      final app = _App();
      await app.pumpSignedIn(tester);
      app.fetchLog.clear();

      app.push.emitForeground(_cancelMessage('TRIP-1'));
      await _settle(tester);

      expect(
        app.fetchLog.where((line) => line.contains('reason=push_cancelled')),
        hasLength(1),
      );
      await app.dispose(tester);
    });

    testWidgets('sign-out (the offers cleared) asks the server for no duty '
        'and no trips through the reload signal', (tester) async {
      final app = _App()..source.offers = [_staffOffer('TRIP-1')];
      await app.pumpSignedIn(tester);
      expect(find.byKey(const Key('offer-card')), findsOneWidget);
      final dutyCalls = app.duty.dutyCalls;
      final tripCalls = app.duty.tripCalls;

      await tester.tap(find.byKey(const Key('driver-sign-out')));
      await _settle(tester);

      expect(find.byKey(const Key('driver-sign-in')), findsOneWidget);
      expect(app.duty.dutyCalls, dutyCalls);
      expect(app.duty.tripCalls, tripCalls);
      await app.dispose(tester);
    });

    testWidgets('a trip push reloads the Trips list', (tester) async {
      final app = _App();
      await app.pumpSignedIn(tester);
      await _selectTab(tester, 'Trips');
      final calls = app.duty.tripCalls;

      app.push.emitForeground(_cancelMessage('TRIP-1'));
      await _settle(tester);

      expect(app.duty.tripCalls, calls + 1);
      await app.dispose(tester);
    });
  });
}

/// A staff offer: no expiry.
Map<String, Object?> _staffOffer(String reference) => <String, Object?>{
  ..._offer(reference, pickup: 'Pinned location', fare: null),
  'offer_expires_at': null,
};

RemoteMessage _cancelMessage(String reference) => RemoteMessage(
  data: <String, dynamic>{
    'event_type': 'trip_cancelled_by_operations',
    'trip_reference': reference,
  },
  notification: const RemoteNotification(title: 'Trip cancelled'),
);

Future<void> _offerArrives(
  WidgetTester tester,
  _App app, {
  String pickup = 'Accra Mall',
  String? fare = '35.00',
}) async {
  app.source.offers = [
    _offer(
      'TRIP-1',
      pickup: pickup,
      fare: fare,
      expiresAt: '2026-10-09T10:01:00+00:00',
    ),
  ];
  await app.coordinator.store.refresh();
  await _settle(tester);
}

/// The space the shell offers the selected tab's page: above the tab bar,
/// and above an offer card on the tabs. (A page may use less: the empty
/// Trips list is shorter, with nothing below it.)
Rect _pageArea(WidgetTester tester) {
  final body = find.byKey(const Key('driver-shell-body'), skipOffstage: false);
  final padding = tester
      .widget<Padding>(body)
      .padding
      .resolve(TextDirection.ltr);
  final offered = tester.renderObject<RenderBox>(body).constraints.maxHeight;
  final rect = tester.getRect(body);
  return Rect.fromLTRB(
    rect.left,
    rect.top + padding.top,
    rect.right,
    rect.top + offered - padding.bottom,
  );
}

/// Every part of [row] can be scrolled into view inside [page]: in full at
/// once when it fits, else its top and then its bottom (the test font makes
/// some rows taller than the page left above the card at 2.0).
Future<void> _expectScrollsIntoView(
  WidgetTester tester,
  Finder row,
  Rect page,
) async {
  for (final alignment in const [0.0, 1.0]) {
    await Scrollable.ensureVisible(tester.element(row), alignment: alignment);
    await _settle(tester);
    final rect = tester.getRect(row);
    if (rect.height <= page.height) {
      expect(rect.top, greaterThanOrEqualTo(page.top), reason: '$row');
      expect(rect.bottom, lessThanOrEqualTo(page.bottom), reason: '$row');
    } else if (alignment == 0) {
      expect(rect.top, greaterThanOrEqualTo(page.top), reason: '$row top');
    } else {
      expect(rect.bottom, lessThanOrEqualTo(page.bottom), reason: '$row end');
    }
  }
}

/// No text inside [within] is narrower than its widest word, so no word is
/// broken across lines.
void _expectNoBrokenWords(WidgetTester tester, Finder within) {
  final paragraphs = find.descendant(
    of: within,
    matching: find.byType(RichText),
  );
  expect(paragraphs, findsWidgets);
  for (final element in paragraphs.evaluate()) {
    final paragraph = element.renderObject! as RenderParagraph;
    final text = paragraph.text.toPlainText();
    for (final word in text.split(RegExp(r'\s+'))) {
      final painter = TextPainter(
        text: TextSpan(text: word, style: paragraph.text.style),
        textScaler: paragraph.textScaler,
        textDirection: TextDirection.ltr,
      )..layout();
      expect(
        paragraph.size.width,
        greaterThanOrEqualTo(painter.width - 0.5),
        reason: '"$word" in "$text"',
      );
      painter.dispose();
    }
  }
}

/// How far the scrolling part of [within] can scroll; 0 when it has none.
double _scrollExtentInside(WidgetTester tester, Finder within) {
  final scrollables = find.descendant(
    of: within,
    matching: find.byType(Scrollable),
  );
  if (scrollables.evaluate().isEmpty) {
    return 0;
  }
  return tester
      .state<ScrollableState>(scrollables.first)
      .position
      .maxScrollExtent;
}

/// Text sizes a driver can pick in the phone's settings, above the default.
const _largeTextScales = [1.3, 1.5, 2.0];

/// Gesture navigation, and three-button navigation (48 dp at the bottom).
const _bottomInsets = [
  ('gesture navigation', 0.0),
  ('three-button navigation', 126.0),
];

/// The test phone's screen: 1080 x 2340 px at 2.625.
void _phoneScreen(WidgetTester tester, {required double bottomInset}) {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 2.625;
  tester.view.padding = FakeViewPadding(bottom: bottomInset);
  tester.view.viewPadding = FakeViewPadding(bottom: bottomInset);
  addTearDown(tester.view.reset);
}

/// The text size turned up after signing in, as a driver would in settings.
void _textScale(WidgetTester tester, double scale) {
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

Future<void> _selectTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await _settle(tester);
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
  String? fare = '35.00',
}) => <String, Object?>{
  'trip_reference': reference,
  'pickup_location': pickup,
  'passenger_count': 1,
  'fare_amount': fare,
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
  final unknownOffers = <bool>[];
  final tokenStore = MemoryAuthTokenStore();
  final duty = _Duty();
  final fetchLog = <String>[];
  late final coordinator = DriverOfferCoordinator(
    store: DriverPendingOfferStore(source: source, clock: clock),
    periodicTimer: timers.create,
    log: fetchLog.add,
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
    offerCardControllerFactory:
        (reference, {assignedAt, unknownOffer = false}) async {
          preparedFor.add(assignedAt);
          unknownOffers.add(unknownOffer);
          return DriverOfferResponseResilienceController(
            queue: queue,
            gateway: offerGateway,
            tripReference: reference,
            driverId: 'DRV-1',
            assignedAt: assignedAt,
            unknownOffer: unknownOffer,
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

  /// Every request fails as if there were no network.
  bool failAll = false;

  @override
  Future<DriverPendingOffersFetch> fetch() {
    calls += 1;
    if (failAll) {
      return Future.value(const DriverPendingOffersUnavailable());
    }
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

final class _Duty implements DriverDutyGateway, DriverDutyStatusGateway {
  /// The server's duty state.
  String dutyStatus = 'online';
  bool shiftCheckToday = true;
  final updates = <DriverOperationalDutyStatus>[];

  @override
  Future<DriverDutyTransition> updateDutyStatus(
    DriverOperationalDutyStatus status,
  ) async {
    updates.add(status);
    dutyStatus = status.wireValue;
    return DriverDutyTransition(
      dutyStatus: status.wireValue,
      since: DateTime(2026, 10, 9, 9),
    );
  }

  int dutyCalls = 0;

  @override
  Future<DriverDutySummary> fetchDuty() async {
    dutyCalls += 1;
    return DriverDutySummary(
      driverReference: 'DRV-1',
      dutyStatus: dutyStatus,
      dutySince: DateTime(2026, 10, 9, 8),
      shiftCheckToday: shiftCheckToday,
      canReceiveAssignments: true,
    );
  }

  int tripCalls = 0;

  @override
  Future<List<DriverAssignedTrip>> fetchTrips() async {
    tripCalls += 1;
    return const [];
  }

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
  var declines = 0;
  final acceptedTrips = <String>[];

  /// When set, Accept waits for it (a slow answer).
  Completer<void>? holdAccept;

  /// When set, Accept fails with it.
  DriverOfferResponseException? acceptError;

  @override
  Future<DriverOfferResponseReceipt> accept({
    required String tripReference,
    required String idempotencyKey,
    required String deviceTimestamp,
    DriverOfferSubmissionTelemetrySink? telemetrySink,
  }) async {
    accepts += 1;
    acceptedTrips.add(tripReference);
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
