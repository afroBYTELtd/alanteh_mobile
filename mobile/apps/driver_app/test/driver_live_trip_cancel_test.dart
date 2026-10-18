import 'dart:async';

import 'package:asm_design_system/asm_design_system.dart';
import 'package:asm_maps/testing.dart';
import 'package:asm_offline_queue/asm_offline_queue.dart';
import 'package:driver_app/driver_duty_trips.dart';
import 'package:driver_app/network/driver_trip_action_gateway.dart';
import 'package:driver_app/network/driver_trip_action_resilience.dart';
import 'package:driver_app/notifications/push_notification_runtime.dart';
import 'package:driver_app/safety/driver_trip_safety.dart';
import 'package:driver_app/trip_progress/driver_live_trip_check.dart';
import 'package:driver_app/trip_progress/driver_trip_visual_sequence.dart';
import 'package:driver_app/trip_progress/driver_trip_visual_state.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Seen on the test phone (17 Oct, 4D): the passenger cancelled, the driver
// got the push, and the live screen still said "Heading to pickup"; "I've
// arrived" then failed with "This assigned trip could not be found." The
// live screen now reloads its trip while it is in front, on resume, on a
// cancel push for that trip and when an action is refused, and shows what
// happened.
void main() {
  const reference = 'TRIP-Q3-1';
  const interval = driverLiveTripCheckInterval;

  group('reload while the screen is in front', () {
    testWidgets('a cancel is found with no push: the cancelled card, no '
        'Navigate or stage button, safety controls stay, same screen', (
      tester,
    ) async {
      final check = _Check([
        DriverLiveTripFinding.live,
        DriverLiveTripFinding.cancelledByPassenger,
      ]);
      await _pumpLive(tester, check: check);
      expect(find.text("I've arrived"), findsOneWidget);

      await tester.pump(interval);
      await tester.pump();
      expect(check.calls, 1);
      expect(find.text("I've arrived"), findsOneWidget);

      await tester.pump(interval);
      await tester.pump();
      expect(check.calls, 2);

      expect(find.byKey(const Key('driver-live-trip-cancelled')), findsOne);
      expect(find.text('Trip cancelled'), findsWidgets);
      expect(
        find.text('The passenger cancelled. No need to go to the pickup.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('driver-trip-navigate')), findsNothing);
      expect(find.byKey(const Key('driver-mark-arrived-pickup')), findsNothing);
      expect(
        find.byKey(const Key('driver-trip-safety-emergency')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('driver-trip-safety-alert-dispatch')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextButton>(
              find.byKey(const Key('driver-trip-safety-alert-dispatch')),
            )
            .onPressed,
        isNotNull,
      );
      expect(find.text('Work'), findsNothing);
    });

    testWidgets('once the card shows, the screen stops reloading', (
      tester,
    ) async {
      final check = _Check([DriverLiveTripFinding.cancelledByPassenger]);
      await _pumpLive(tester, check: check);
      await tester.pump(interval);
      await tester.pump();
      expect(check.calls, 1);

      await tester.pump(interval * 8);
      expect(check.calls, 1);
    });

    testWidgets('one reload at a time: a push during a reload waits for it, '
        'then reloads once more', (tester) async {
      final check = _Check([
        DriverLiveTripFinding.live,
        DriverLiveTripFinding.cancelledByOperations,
      ]);
      final first = Completer<void>();
      check.holds[0] = first;
      await _pumpLive(tester, check: check);

      await tester.pump(interval);
      expect(check.calls, 1);
      expect(DriverLiveTripScreens.instance.checkNow(reference), isTrue);
      await tester.pump(interval * 3);
      expect(check.calls, 1);
      expect(check.maxInFlight, 1);

      first.complete();
      await tester.pump();
      await tester.pump();
      expect(check.calls, 2);
      expect(check.maxInFlight, 1);
      expect(find.byKey(const Key('driver-live-trip-cancelled')), findsOne);
    });

    testWidgets('a failed reload waits longer before the next', (tester) async {
      final check = _Check([
        _fails,
        _fails,
        _fails,
        DriverLiveTripFinding.live,
        DriverLiveTripFinding.live,
      ]);
      await _pumpLive(tester, check: check);

      await tester.pump(interval);
      await tester.pump();
      expect(check.calls, 1);
      await tester.pump(interval);
      expect(check.calls, 1);
      await tester.pump(interval);
      await tester.pump();
      expect(check.calls, 2);
      await tester.pump(interval * 3);
      expect(check.calls, 2);
      await tester.pump(interval);
      await tester.pump();
      expect(check.calls, 3);
      await tester.pump(interval * 4);
      await tester.pump();
      expect(check.calls, 4);
      await tester.pump(interval);
      await tester.pump();
      expect(check.calls, 5);
      expect(find.text("I've arrived"), findsOneWidget);
    });

    testWidgets('it stops when the screen closes', (tester) async {
      final check = _Check(const []);
      await _pumpLive(tester, check: check);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Work'), findsOneWidget);

      await tester.pump(interval * 8);
      expect(check.calls, 0);
      expect(DriverLiveTripScreens.instance.checkNow(reference), isFalse);
    });

    testWidgets('it stops in the background and reloads at once on resume', (
      tester,
    ) async {
      final check = _Check([DriverLiveTripFinding.cancelledByPassenger]);
      await _pumpLive(tester, check: check);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(interval * 8);
      expect(check.calls, 0);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();
      expect(check.calls, 1);
      expect(find.byKey(const Key('driver-live-trip-cancelled')), findsOne);
    });

    testWidgets('resume with the trip still live: one reload, nothing '
        'changes', (tester) async {
      final check = _Check([DriverLiveTripFinding.live]);
      await _pumpLive(tester, check: check);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();

      expect(check.calls, 1);
      expect(find.text("I've arrived"), findsOneWidget);
      expect(find.byKey(const Key('driver-live-trip-cancelled')), findsNothing);
    });

    testWidgets('a reload that finds the trip gone says "No longer assigned '
        'to you"', (tester) async {
      final check = _Check([DriverLiveTripFinding.notAssigned]);
      await _pumpLive(tester, check: check);
      await tester.pump(interval);
      await tester.pump();

      expect(find.byKey(const Key('driver-live-trip-not-assigned')), findsOne);
      expect(find.text('No longer assigned to you'), findsWidgets);
      expect(find.text('Trip cancelled'), findsNothing);
    });

    testWidgets('a finished trip stops the reloads quietly: no card, the '
        'screen stays', (tester) async {
      final check = _Check([DriverLiveTripFinding.ended]);
      await _pumpLive(tester, check: check, status: 'in_progress');
      await tester.pump(interval);
      await tester.pump();
      expect(check.calls, 1);

      await tester.pump(interval * 8);
      expect(check.calls, 1);
      expect(find.byKey(const Key('driver-live-trip-cancelled')), findsNothing);
      expect(
        find.byKey(const Key('driver-live-trip-not-assigned')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('driver-mark-arrived-destination')),
        findsOneWidget,
      );
    });

    testWidgets('an unknown status changes nothing and the reloads go on', (
      tester,
    ) async {
      final check = _Check([DriverLiveTripFinding.unknown]);
      await _pumpLive(tester, check: check);
      await tester.pump(interval);
      await tester.pump();
      await tester.pump(interval);
      await tester.pump();

      expect(check.calls, 2);
      expect(find.text("I've arrived"), findsOneWidget);
      expect(
        find.byKey(const Key('driver-live-trip-not-assigned')),
        findsNothing,
      );
    });

    testWidgets('a reload that fails changes nothing', (tester) async {
      final check = _Check([_fails]);
      await _pumpLive(tester, check: check);
      await tester.pump(interval);
      await tester.pump();

      expect(check.calls, 1);
      expect(find.text("I've arrived"), findsOneWidget);
    });
  });

  group('what the card says, by stage', () {
    Future<void> cancelAt(
      WidgetTester tester,
      String status,
      DriverLiveTripFinding finding, {
      _Launcher? launcher,
    }) async {
      await _pumpLive(
        tester,
        status: status,
        check: _Check([finding]),
        launcher: launcher,
      );
      await tester.pump(interval);
      await tester.pump();
      await tester.pump(asmFakeMapAnimationDuration);
    }

    testWidgets('a no-show: "Trip ended", no Navigate or stage button, the '
        'safety controls stay, and the reloads stop', (tester) async {
      final check = _Check([DriverLiveTripFinding.noShow]);
      await _pumpLive(tester, check: check, status: 'arrived_at_pickup');
      await tester.pump(interval);
      await tester.pump();
      await tester.pump(asmFakeMapAnimationDuration);

      expect(find.byKey(const Key('driver-live-trip-no-show')), findsOne);
      expect(find.text('Trip ended'), findsWidgets);
      expect(
        find.text(
          'Dispatch recorded this trip as a no-show. You can leave the pickup.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('driver-trip-navigate')), findsNothing);
      expect(
        find.byKey(const Key('driver-open-onboard-confirmation')),
        findsNothing,
      );
      for (final key in [
        'driver-trip-safety-emergency',
        'driver-trip-safety-message-contact',
        'driver-trip-safety-alert-dispatch',
      ]) {
        expect(find.byKey(Key(key)), findsOneWidget, reason: key);
      }
      expect(find.byKey(const Key('driver-live-trip-ended-back')), findsOne);

      await tester.pump(interval * 8);
      expect(check.calls, 1);
    });

    testWidgets('heading to pickup, dispatch cancelled', (tester) async {
      await cancelAt(
        tester,
        'driver_en_route',
        DriverLiveTripFinding.cancelledByOperations,
      );
      expect(find.text('Trip cancelled'), findsWidgets);
      expect(
        find.text('Dispatch cancelled this trip. No need to go to the pickup.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('driver-trip-navigate')), findsNothing);
    });

    testWidgets('at the pickup, passenger cancelled', (tester) async {
      await cancelAt(
        tester,
        'arrived_at_pickup',
        DriverLiveTripFinding.cancelledByPassenger,
      );
      expect(
        find.text('The passenger cancelled. You can leave the pickup.'),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('driver-open-onboard-confirmation')),
        findsNothing,
      );
      expect(find.byKey(const Key('driver-trip-navigate')), findsNothing);
    });

    testWidgets('at the pickup, dispatch cancelled', (tester) async {
      await cancelAt(
        tester,
        'arrived_at_pickup',
        DriverLiveTripFinding.cancelledByOperations,
      );
      expect(
        find.text('Dispatch cancelled this trip. You can leave the pickup.'),
        findsOneWidget,
      );
    });

    testWidgets('trip in progress, dispatch cancelled: Navigate to the '
        'drop-off stays, the stage button goes', (tester) async {
      final launcher = _Launcher();
      await cancelAt(
        tester,
        'in_progress',
        DriverLiveTripFinding.cancelledByOperations,
        launcher: launcher,
      );
      expect(find.text('Trip cancelled by dispatch'), findsWidgets);
      expect(
        find.text(
          'Stop where it is safe and contact dispatch about the passenger.',
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('driver-mark-arrived-destination')),
        findsNothing,
      );

      final navigate = find.byKey(const Key('driver-trip-navigate'));
      await tester.ensureVisible(navigate);
      await tester.tap(navigate);
      await tester.pump();
      expect(
        launcher.launched.single.queryParameters['destination'],
        '5.6052,-0.1668',
      );
    });
  });

  group('leaving the card', () {
    testWidgets('Back to Work reaches Work; the card never closes the screen '
        'by itself', (tester) async {
      await _pumpLive(
        tester,
        check: _Check([DriverLiveTripFinding.cancelledByPassenger]),
      );
      await tester.pump(interval);
      await tester.pump();
      await tester.pump(interval * 4);
      expect(find.byKey(const Key('driver-live-trip-cancelled')), findsOne);

      await tester.tap(find.byKey(const Key('driver-live-trip-ended-back')));
      await tester.pumpAndSettle();
      expect(find.text('Work'), findsOneWidget);
    });

    testWidgets('as in the app (Work, trip detail, live screen), Back to Work '
        'passes the trip detail too', (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final gateway = _DutyGateway('driver_accepted');
      await tester.pumpWidget(
        MaterialApp(
          theme: AsmThemes.driver,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                key: const Key('open-detail'),
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => DriverTripDetailScreen(
                      gateway: gateway,
                      tripReference: 'TRIP-Q3-1',
                      actionControllerFactory: (tripReference) async =>
                          DriverTripActionResilienceController(
                            queue: _Queue(),
                            gateway: _ActionGateway(
                              DriverTripActionFailureType.notFound,
                            ),
                            tripReference: tripReference,
                            driverId: 'DRV-Q3',
                          ),
                    ),
                  ),
                ),
                child: const Text('Work'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('open-detail')));
      await tester.pumpAndSettle();
      final open = find.byKey(const Key('driver-open-live-trip-actions'));
      await tester.ensureVisible(open);
      await tester.pumpAndSettle();
      await tester.tap(open);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(asmFakeMapAnimationDuration);
      gateway.status = 'cancelled_by_passenger';
      await tester.pump(interval);
      await tester.pump();
      await tester.pump(asmFakeMapAnimationDuration);

      await tester.tap(find.byKey(const Key('driver-live-trip-ended-back')));
      await tester.pumpAndSettle();

      expect(find.text('Work'), findsOneWidget);
      expect(find.byType(DriverTripDetailScreen), findsNothing);
    });

    testWidgets('the back arrow still goes back one screen', (tester) async {
      await _pumpLive(
        tester,
        check: _Check([DriverLiveTripFinding.cancelledByPassenger]),
      );
      await tester.pump(interval);
      await tester.pump();

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Work'), findsOneWidget);
    });
  });

  group('a refused action reloads the trip first', () {
    Future<_ActionGateway> refuse(
      WidgetTester tester,
      DriverTripActionFailureType type,
      List<Object> findings,
    ) async {
      final gateway = _ActionGateway(type);
      await _pumpLive(
        tester,
        check: _Check(findings),
        actionRecorder: DriverTripActionResilienceController(
          queue: _Queue(),
          gateway: gateway,
          tripReference: reference,
          driverId: 'DRV-Q3',
        ),
      );
      final arrived = find.byKey(const Key('driver-mark-arrived-pickup'));
      await tester.ensureVisible(arrived);
      await tester.tap(arrived);
      await tester.pump();
      await tester.pump();
      await tester.pump();
      return gateway;
    }

    testWidgets('404, and the trip is now cancelled: the cancelled card, not '
        '"could not be found"', (tester) async {
      await refuse(tester, DriverTripActionFailureType.notFound, [
        DriverLiveTripFinding.cancelledByPassenger,
      ]);
      expect(find.byKey(const Key('driver-live-trip-cancelled')), findsOne);
      expect(find.text('This assigned trip could not be found.'), findsNothing);
    });

    testWidgets('404, and the trip is gone too: "No longer assigned to you"', (
      tester,
    ) async {
      await refuse(tester, DriverTripActionFailureType.notFound, [
        DriverLiveTripFinding.notAssigned,
      ]);
      expect(find.byKey(const Key('driver-live-trip-not-assigned')), findsOne);
      expect(find.text('This assigned trip could not be found.'), findsNothing);
    });

    testWidgets('404 while the trip still reads live: "No longer assigned to '
        'you"', (tester) async {
      await refuse(tester, DriverTripActionFailureType.notFound, [
        DriverLiveTripFinding.live,
      ]);
      expect(find.byKey(const Key('driver-live-trip-not-assigned')), findsOne);
      expect(find.text('This assigned trip could not be found.'), findsNothing);
    });

    testWidgets('404 and the reload fails: the screen and the message stay', (
      tester,
    ) async {
      await refuse(tester, DriverTripActionFailureType.notFound, [_fails]);
      expect(
        find.byKey(const Key('driver-live-trip-not-assigned')),
        findsNothing,
      );
      expect(find.text("I've arrived"), findsOneWidget);
      expect(
        find.text('This assigned trip could not be found.'),
        findsOneWidget,
      );
    });

    testWidgets('a refused move while the trip is live keeps the screen and '
        'its message', (tester) async {
      await refuse(tester, DriverTripActionFailureType.invalidTransition, [
        DriverLiveTripFinding.live,
      ]);
      expect(find.text("I've arrived"), findsOneWidget);
      expect(
        find.byKey(const Key('driver-live-trip-not-assigned')),
        findsNothing,
      );
      expect(find.text('Refused.'), findsOneWidget);
    });
  });

  group('a reload answer that comes too late is dropped', () {
    testWidgets('a reload is running, the driver completes, the answer '
        'arrives: no card', (tester) async {
      final check = _Check([DriverLiveTripFinding.cancelledByOperations]);
      final answer = Completer<void>();
      check.holds[0] = answer;
      await _pumpLive(
        tester,
        check: check,
        status: 'in_progress',
        actionRecorder: _okRecorder(_OkGateway()),
      );

      await tester.pump(interval);
      expect(check.calls, 1);
      final arrived = find.byKey(const Key('driver-mark-arrived-destination'));
      await tester.ensureVisible(arrived);
      await tester.tap(arrived);
      await tester.pump();
      await tester.tap(find.byKey(const Key('driver-complete-trip')));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('driver-trip-completed')), findsOneWidget);

      answer.complete();
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('driver-live-trip-cancelled')), findsNothing);
      expect(find.byKey(const Key('driver-trip-completed')), findsOneWidget);
      await tester.pump(interval * 8);
      expect(check.calls, 1);
    });

    testWidgets("an answer that arrives while the driver's own action is on "
        'its way is dropped; the next reload decides', (tester) async {
      final check = _Check([
        DriverLiveTripFinding.cancelledByPassenger,
        DriverLiveTripFinding.live,
      ]);
      final answer = Completer<void>();
      check.holds[0] = answer;
      final gateway = _OkGateway()..hold = Completer<void>();
      await _pumpLive(
        tester,
        check: check,
        actionRecorder: _okRecorder(gateway),
      );

      await tester.pump(interval);
      expect(check.calls, 1);
      final arrived = find.byKey(const Key('driver-mark-arrived-pickup'));
      await tester.ensureVisible(arrived);
      await tester.tap(arrived);
      await tester.pump();
      expect(find.text('Confirming...'), findsOneWidget);

      answer.complete();
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('driver-live-trip-cancelled')), findsNothing);

      gateway.hold!.complete();
      await tester.pump();
      await tester.pump();
      expect(
        find.byKey(const Key('driver-open-onboard-confirmation')),
        findsOneWidget,
      );

      await tester.pump(interval);
      await tester.pump();
      expect(check.calls, 2);
      expect(find.byKey(const Key('driver-live-trip-cancelled')), findsNothing);
    });

    testWidgets('an answer for a reload that began before an action that has '
        'since finished is dropped too', (tester) async {
      final check = _Check([
        DriverLiveTripFinding.cancelledByPassenger,
        DriverLiveTripFinding.live,
      ]);
      final answer = Completer<void>();
      check.holds[0] = answer;
      await _pumpLive(
        tester,
        check: check,
        actionRecorder: _okRecorder(_OkGateway()),
      );

      await tester.pump(interval);
      final arrived = find.byKey(const Key('driver-mark-arrived-pickup'));
      await tester.ensureVisible(arrived);
      await tester.tap(arrived);
      await tester.pump();
      await tester.pump();
      expect(
        find.byKey(const Key('driver-open-onboard-confirmation')),
        findsOneWidget,
      );

      answer.complete();
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('driver-live-trip-cancelled')), findsNothing);
    });
  });

  group('a reload answer that comes too late is dropped (more)', () {
    testWidgets('a reload that starts while the driver\'s action is on its '
        'way: its answer is dropped', (tester) async {
      final check = _Check([
        DriverLiveTripFinding.cancelledByPassenger,
        DriverLiveTripFinding.live,
      ]);
      final gateway = _OkGateway()..hold = Completer<void>();
      await _pumpLive(
        tester,
        check: check,
        actionRecorder: _okRecorder(gateway),
      );

      final arrived = find.byKey(const Key('driver-mark-arrived-pickup'));
      await tester.ensureVisible(arrived);
      await tester.tap(arrived);
      await tester.pump();
      expect(find.text('Confirming...'), findsOneWidget);

      expect(DriverLiveTripScreens.instance.checkNow(reference), isTrue);
      await tester.pump();
      await tester.pump();
      expect(check.calls, 1);
      expect(find.byKey(const Key('driver-live-trip-cancelled')), findsNothing);

      gateway.hold!.complete();
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('driver-live-trip-cancelled')), findsNothing);
    });

    testWidgets('the pickup-code start counts as the driver\'s own action', (
      tester,
    ) async {
      final check = _Check([
        DriverLiveTripFinding.cancelledByPassenger,
        DriverLiveTripFinding.live,
      ]);
      final answer = Completer<void>();
      check.holds[0] = answer;
      await _pumpLive(
        tester,
        check: check,
        status: 'passenger_onboard',
        actionRecorder: _okRecorder(_OkGateway()),
        pickupVerificationRequired: true,
      );

      await tester.pump(interval);
      expect(check.calls, 1);
      await tester.enterText(
        find.byKey(const Key('driver-pickup-verification-code-field')),
        '1234',
      );
      await tester.tap(find.byKey(const Key('driver-confirm-onboard')));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('driver-active-trip')), findsOneWidget);

      answer.complete();
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('driver-live-trip-cancelled')), findsNothing);
      await tester.pump(asmFakeMapAnimationDuration);
    });
  });

  group('cancel pushes', () {
    RemoteMessage message(String type, String trip) => RemoteMessage(
      data: <String, dynamic>{'event_type': type, 'trip_reference': trip},
      notification: const RemoteNotification(
        title: 'Trip cancelled',
        body: 'The passenger cancelled this trip.',
      ),
    );

    test(
      'both cancel types are read; they never open a screen or an offer',
      () {
        for (final type in [
          'trip_cancelled_by_passenger',
          'trip_cancelled_by_operations',
        ]) {
          expect(
            driverTripCancelledPushReference(message(type, ' $reference ')),
            reference,
          );
          expect(
            driverPushNavigationIntentFromMessage(message(type, reference)),
            isNull,
          );
        }
        for (final type in ['driver_assigned', 'cancelled_by_operations', '']) {
          expect(
            driverTripCancelledPushReference(message(type, reference)),
            isNull,
          );
        }
        expect(
          driverTripCancelledPushReference(
            message('trip_cancelled_by_passenger', ' '),
          ),
          isNull,
        );
      },
    );

    testWidgets('a cancel push for the open trip shows the card at once, '
        'with no snackbar and no navigation', (tester) async {
      final push = _Push();
      final check = _Check([DriverLiveTripFinding.cancelledByPassenger]);
      await _pumpLive(tester, check: check, push: push);

      push.foreground(message('trip_cancelled_by_passenger', 'trip-q3-1'));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(check.calls, 1);
      expect(find.byKey(const Key('driver-live-trip-cancelled')), findsOne);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('Work'), findsNothing);
    });

    testWidgets('a cancel push for another trip changes nothing here; its '
        'text shows as before', (tester) async {
      final push = _Push();
      final check = _Check([DriverLiveTripFinding.cancelledByPassenger]);
      await _pumpLive(tester, check: check, push: push);

      push.foreground(message('trip_cancelled_by_operations', 'TRIP-OTHER'));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(check.calls, 0);
      expect(find.text("I've arrived"), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
    });
  });

  group('arrived_at_destination', () {
    test('is a live status, and the live screen opens at the destination '
        'stage', () {
      expect(driverCanOpenLiveTripActions('arrived_at_destination'), isTrue);
      expect(
        DriverTripVisualState.fromBackendStatus('arrived_at_destination').stage,
        DriverTripVisualStage.arrivedAtDestination,
      );
    });
  });

  group('the trip detail screen reloads through the gateway', () {
    // Every Trip.TripStatus on the server (backend 07e86be, models.py).
    const serverStatuses = <String, DriverLiveTripFinding>{
      'requested': DriverLiveTripFinding.notAssigned,
      'under_review': DriverLiveTripFinding.notAssigned,
      'fare_confirmed': DriverLiveTripFinding.notAssigned,
      'awaiting_payment': DriverLiveTripFinding.notAssigned,
      'payment_confirmed': DriverLiveTripFinding.notAssigned,
      'driver_offer_sent': DriverLiveTripFinding.notAssigned,
      'driver_accepted': DriverLiveTripFinding.live,
      'driver_declined': DriverLiveTripFinding.notAssigned,
      'assigned': DriverLiveTripFinding.live,
      'dispatched': DriverLiveTripFinding.live,
      'driver_en_route': DriverLiveTripFinding.live,
      'arrived_at_pickup': DriverLiveTripFinding.live,
      'passenger_onboard': DriverLiveTripFinding.live,
      'in_progress': DriverLiveTripFinding.live,
      'arrived_at_destination': DriverLiveTripFinding.live,
      'completed_pending_review': DriverLiveTripFinding.ended,
      'completed_confirmed': DriverLiveTripFinding.ended,
      'review_overdue': DriverLiveTripFinding.ended,
      'cancelled_by_passenger': DriverLiveTripFinding.cancelledByPassenger,
      'cancelled_by_operations': DriverLiveTripFinding.cancelledByOperations,
      'no_show': DriverLiveTripFinding.noShow,
      'disputed': DriverLiveTripFinding.ended,
    };

    test('every server status is mapped explicitly', () {
      expect(serverStatuses, hasLength(22));
      for (final entry in serverStatuses.entries) {
        expect(
          driverLiveTripFindingFor(entry.key),
          entry.value,
          reason: entry.key,
        );
        expect(
          driverLiveTripFindingFor(' ${entry.key} '),
          entry.value,
          reason: 'padded ${entry.key}',
        );
      }
    });

    test('every status the driver can be in on the live screen reads live, '
        'and matches the statuses that open live actions', () {
      for (final entry in serverStatuses.entries) {
        expect(
          driverLiveTripFindingFor(entry.key) == DriverLiveTripFinding.live,
          driverCanOpenLiveTripActions(entry.key),
          reason: entry.key,
        );
      }
    });

    test('a status the app does not know changes nothing', () {
      for (final status in [null, '', 'cancelled', 'accepted_for_trip']) {
        expect(
          driverLiveTripFindingFor(status),
          DriverLiveTripFinding.unknown,
          reason: '$status',
        );
      }
    });

    testWidgets('a dispatch cancel reaches the open live screen with no push', (
      tester,
    ) async {
      final gateway = _DutyGateway('driver_accepted');
      await _pumpDetail(tester, gateway);
      gateway.status = 'cancelled_by_operations';

      await tester.pump(interval);
      await tester.pump();

      expect(find.byKey(const Key('driver-live-trip-cancelled')), findsOne);
      expect(
        find.text('Dispatch cancelled this trip. No need to go to the pickup.'),
        findsOneWidget,
      );
    });

    testWidgets('a 404 on the reload reads "No longer assigned to you"', (
      tester,
    ) async {
      final gateway = _DutyGateway('driver_accepted');
      await _pumpDetail(tester, gateway);
      gateway.notFound = true;

      await tester.pump(interval);
      await tester.pump();

      expect(find.byKey(const Key('driver-live-trip-not-assigned')), findsOne);
    });

    test('a trip detail with assigned_to_you still reads by its status', () {
      final trip = DriverAssignedTrip.fromJson(const {
        'trip_reference': reference,
        'status': 'driver_accepted',
        'assigned_to_you': false,
      });
      expect(trip.status, 'driver_accepted');
      expect(driverLiveTripFindingFor(trip.status), DriverLiveTripFinding.live);
    });
  });
}

/// A reload that fails (no connection).
const _fails = 'fails';

Future<void> _pumpLive(
  WidgetTester tester, {
  required _Check check,
  String status = 'driver_accepted',
  _Launcher? launcher,
  DriverTripActionResilienceController? actionRecorder,
  _Push? push,
  bool pickupVerificationRequired = false,
}) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final page = DriverTripVisualSequencePage(
    initialStatus: status,
    tripReference: 'TRIP-Q3-1',
    pickupLocation: 'Near Accra Mall',
    destination: 'Airport, Terminal 3',
    passengerCount: 1,
    pickupLatitude: 5.6227,
    pickupLongitude: -0.1737,
    destinationLatitude: 5.6052,
    destinationLongitude: -0.1668,
    safetyUriLauncher: launcher ?? _Launcher(),
    driverSafetyAlertRepository: _Alerts(),
    actionRecorder: actionRecorder,
    checkTrip: check.call,
    pickupVerificationRequired: pickupVerificationRequired,
  );
  Widget work = Builder(
    builder: (context) => Scaffold(
      body: Column(
        children: [
          const Text('Work'),
          TextButton(
            key: const Key('open-live'),
            onPressed: () => Navigator.of(
              context,
            ).push<bool>(MaterialPageRoute<bool>(builder: (_) => page)),
            child: const Text('Open'),
          ),
        ],
      ),
    ),
  );
  if (push != null) {
    work = FirebaseForegroundPushListener(messageSource: push, child: work);
  }
  await tester.pumpWidget(MaterialApp(theme: AsmThemes.driver, home: work));
  await tester.tap(find.byKey(const Key('open-live')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(asmFakeMapAnimationDuration);
}

Future<void> _pumpDetail(WidgetTester tester, _DutyGateway gateway) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AsmThemes.driver,
      home: DriverTripDetailScreen(
        gateway: gateway,
        tripReference: 'TRIP-Q3-1',
        actionControllerFactory: (tripReference) async =>
            DriverTripActionResilienceController(
              queue: _Queue(),
              gateway: _ActionGateway(DriverTripActionFailureType.notFound),
              tripReference: tripReference,
              driverId: 'DRV-Q3',
            ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final open = find.byKey(const Key('driver-open-live-trip-actions'));
  await tester.ensureVisible(open);
  await tester.pumpAndSettle();
  await tester.tap(open);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(asmFakeMapAnimationDuration);
  expect(find.byKey(const Key('driver-trip-sequence-page')), findsOneWidget);
}

/// Answers reloads in order: a finding, or [_fails]. Runs out as live.
final class _Check {
  _Check(this.answers);

  final List<Object> answers;
  final holds = <int, Completer<void>>{};
  var calls = 0;
  var _inFlight = 0;
  var maxInFlight = 0;

  Future<DriverLiveTripFinding> call() async {
    final index = calls;
    calls += 1;
    _inFlight += 1;
    if (_inFlight > maxInFlight) {
      maxInFlight = _inFlight;
    }
    try {
      final hold = holds[index];
      if (hold != null) {
        await hold.future;
      }
      final answer = index < answers.length
          ? answers[index]
          : DriverLiveTripFinding.live;
      if (answer is DriverLiveTripFinding) {
        return answer;
      }
      throw StateError('no connection');
    } finally {
      _inFlight -= 1;
    }
  }
}

final class _DutyGateway implements DriverDutyGateway {
  _DutyGateway(this.status);

  String status;
  bool notFound = false;

  @override
  Future<DriverDutySummary> fetchDuty() async => DriverDutySummary.empty();

  @override
  Future<List<DriverAssignedTrip>> fetchTrips() async => const [];

  @override
  Future<DriverAssignedTrip> fetchTripDetail(String tripReference) async {
    if (notFound) {
      throw const DriverDutyApiException(
        DriverDutyApiFailureType.notFound,
        'The requested trip was not found.',
      );
    }
    return DriverAssignedTrip(
      reference: tripReference,
      status: status,
      pickupLocation: 'Near Accra Mall',
      destination: 'Airport, Terminal 3',
    );
  }
}

final class _ActionGateway implements DriverTripActionGateway {
  _ActionGateway(this.type);

  final DriverTripActionFailureType type;

  @override
  Future<DriverTripActionReceipt> submit({
    required DriverTripAction action,
    required String tripReference,
    required String idempotencyKey,
    Map<String, Object?> body = const <String, Object?>{},
    String? pickupVerificationCode,
  }) async {
    throw DriverTripActionException(
      type: type,
      message: type == DriverTripActionFailureType.notFound
          ? 'This assigned trip could not be found.'
          : 'Refused.',
    );
  }
}

DriverTripActionResilienceController _okRecorder(_OkGateway gateway) =>
    DriverTripActionResilienceController(
      queue: _Queue(),
      gateway: gateway,
      tripReference: 'TRIP-Q3-1',
      driverId: 'DRV-Q3',
    );

/// Accepts every action, after [hold] when set.
final class _OkGateway implements DriverTripActionGateway {
  Completer<void>? hold;

  @override
  Future<DriverTripActionReceipt> submit({
    required DriverTripAction action,
    required String tripReference,
    required String idempotencyKey,
    Map<String, Object?> body = const <String, Object?>{},
    String? pickupVerificationCode,
  }) async {
    final wait = hold;
    if (wait != null) {
      await wait.future;
    }
    return DriverTripActionReceipt(
      tripReference: tripReference,
      status: 'ok',
      message: 'Recorded.',
      duplicate: false,
    );
  }
}

final class _Queue implements DriverTripActionPersistentQueue {
  final events = <QueuedEvent>[];

  @override
  Future<QueuedEvent> enqueue(QueuedEvent event) async {
    events
      ..removeWhere((candidate) => candidate.id == event.id)
      ..add(event);
    return event;
  }

  @override
  Future<QueuedEvent?> eventById(String id) async {
    for (final event in events) {
      if (event.id == id) {
        return event;
      }
    }
    return null;
  }

  @override
  Future<List<QueuedEvent>> pendingEvents() async => events
      .where(
        (event) =>
            event.syncStatus == QueueSyncStatus.pending ||
            event.syncStatus == QueueSyncStatus.failed,
      )
      .toList(growable: false);

  @override
  Future<void> markFailed(String id) async {}

  @override
  Future<void> markPermanentlyFailed(String id) async {}

  @override
  Future<void> markSynced(String id) async {
    final event = await eventById(id);
    if (event != null) {
      await enqueue(event.copyWith(syncStatus: QueueSyncStatus.synced));
    }
  }
}

final class _Launcher implements DriverSafetyUriLauncher {
  final launched = <Uri>[];

  @override
  Future<bool> canLaunch(Uri uri) async => true;

  @override
  Future<bool> launch(Uri uri) async {
    launched.add(uri);
    return true;
  }
}

final class _Alerts implements DriverSafetyAlertRepository {
  @override
  Future<void> send({
    String? tripReference,
    double? latitude,
    double? longitude,
  }) async {}
}

final class _Push implements DriverPushMessageSource {
  final _foreground = StreamController<RemoteMessage>.broadcast();
  final _opened = StreamController<RemoteMessage>.broadcast();

  void foreground(RemoteMessage message) => _foreground.add(message);

  @override
  Stream<RemoteMessage> get foregroundMessages => _foreground.stream;

  @override
  Stream<RemoteMessage> get openedMessages => _opened.stream;

  @override
  Future<RemoteMessage?> getInitialMessage() async => null;
}
