import 'dart:async';

import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_app_config/asm_app_config.dart';
import 'package:asm_auth/asm_auth.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:asm_offline_queue/asm_offline_queue.dart';
import 'package:driver_app/driver_back_to_work.dart';
import 'package:driver_app/driver_duty_trips.dart';
import 'package:driver_app/driver_home.dart';
import 'package:driver_app/driver_shell.dart';
import 'package:driver_app/network/driver_trip_action_gateway.dart';
import 'package:driver_app/network/driver_trip_action_resilience.dart';
import 'package:driver_app/readiness/driver_readiness_check.dart';
import 'package:driver_app/readiness/driver_shift_check_submission.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _shiftCheckSavedGoOnline =
    "Today's shift check is already saved. Tap Go online to start getting "
    'trips.';

void main() {
  final now = DateTime(2026, 8, 7, 8);

  test('test_nested_offline_no_check_decodes_correctly', () {
    final summary = DriverDutySummary.fromJson(const <String, Object?>{
      'duty': <String, Object?>{
        'duty_status': 'offline',
        'shift_check_today': false,
      },
    });

    expect(summary.dutyStatus, 'offline');
    expect(summary.shiftCheckToday, isFalse);
  });

  test('test_nested_online_with_check_decodes_correctly', () {
    final summary = DriverDutySummary.fromJson(const <String, Object?>{
      'duty': <String, Object?>{
        'duty_status': 'online',
        'shift_check_today': true,
        'shift_check_today_reference': 'SC-QA-DRV-001-20260807',
      },
    });

    expect(summary.dutyStatus, 'online');
    expect(summary.shiftCheckToday, isTrue);
    expect(summary.shiftCheckTodayReference, 'SC-QA-DRV-001-20260807');
  });

  test('test_nested_duty_since_decodes_correctly', () {
    final summary = DriverDutySummary.fromJson(const <String, Object?>{
      'duty': <String, Object?>{'duty_since': '2026-08-07T23:35:37Z'},
    });

    expect(summary.dutySince, DateTime.parse('2026-08-07T23:35:37Z'));
  });

  test('test_top_level_duty_status_not_used', () {
    final summary = DriverDutySummary.fromJson(const <String, Object?>{
      'duty_status': 'online',
      'duty': <String, Object?>{'duty_status': 'offline'},
    });

    expect(summary.dutyStatus, 'offline');
  });

  test('test_null_duty_object_produces_safe_defaults', () {
    final summary = DriverDutySummary.fromJson(const <String, Object?>{
      'duty': null,
    });

    expect(summary.dutyStatus, isNull);
    expect(summary.shiftCheckToday, isFalse);
  });

  testWidgets(
    'test_offline_no_check_does_not_render_home_before_shift_check_route',
    (tester) async {
      final firstDuty = Completer<DriverDutySummary>();
      final summary = DriverDutySummary(
        dutyStatus: 'offline',
        dutySince: now.subtract(const Duration(days: 1)),
        shiftCheckToday: false,
      );
      final gateway = _MutableDutyGateway(
        summary,
        firstDutyCompleter: firstDuty,
      );

      await tester.pumpWidget(
        _testApp(DriverShell(driverDutyGateway: gateway, deviceNow: () => now)),
      );

      expect(
        find.byKey(const Key('driver-duty-startup-loading')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('driver-home-assigned-trips-card')),
        findsNothing,
      );

      firstDuty.complete(summary);
      await tester.pump();

      expect(
        find.byKey(const Key('driver-duty-startup-loading')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('driver-home-assigned-trips-card')),
        findsNothing,
        reason:
            'DriverHome must not render in the frame before required '
            'startup shift-check navigation.',
      );
      expect(find.text('START SHIFT CHECK'), findsNothing);
      expect(gateway.dutyCalls, 1);
    },
  );

  testWidgets(
    'test_offline_no_check_shift_check_is_first_duty_flow_destination',
    (tester) async {
      final firstDuty = Completer<DriverDutySummary>();
      final summary = DriverDutySummary(
        dutyStatus: 'offline',
        dutySince: now.subtract(const Duration(days: 1)),
        shiftCheckToday: false,
      );
      final gateway = _MutableDutyGateway(
        summary,
        firstDutyCompleter: firstDuty,
      );

      await tester.pumpWidget(
        _testApp(DriverShell(driverDutyGateway: gateway, deviceNow: () => now)),
      );

      firstDuty.complete(summary);
      await tester.pump();

      expect(
        find.byKey(const Key('driver-home-assigned-trips-card')),
        findsNothing,
      );

      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const Key('driver-shift-readiness-screen')),
        findsOneWidget,
      );
      expect(
        find.text(
          'Complete these checks once before your first trip of the day.',
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('driver-home-assigned-trips-card')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'test_offline_check_done_preserves_existing_offline_home_startup',
    (tester) async {
      final gateway = _MutableDutyGateway(
        DriverDutySummary(
          dutyStatus: 'offline',
          dutySince: now.subtract(const Duration(hours: 1)),
          shiftCheckToday: true,
        ),
      );

      await tester.pumpWidget(
        _testApp(DriverShell(driverDutyGateway: gateway, deviceNow: () => now)),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('driver-shift-readiness-screen')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('driver-home-assigned-trips-card')),
        findsOneWidget,
      );
      expect(find.text("Today's shift · offline"), findsOneWidget);
      expect(find.text('GO ONLINE'), findsOneWidget);
    },
  );

  testWidgets(
    'test_online_startup_preserves_existing_online_home_without_shift_check',
    (tester) async {
      final gateway = _MutableDutyGateway(
        DriverDutySummary(
          dutyStatus: 'online',
          dutySince: now.subtract(const Duration(minutes: 5)),
          shiftCheckToday: true,
        ),
      );

      await tester.pumpWidget(
        _testApp(DriverShell(driverDutyGateway: gateway, deviceNow: () => now)),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('driver-shift-readiness-screen')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('driver-home-assigned-trips-card')),
        findsOneWidget,
      );
      expect(find.text("You're online"), findsOneWidget);
      expect(find.text('GO OFFLINE'), findsOneWidget);
    },
  );

  testWidgets('test_first_shift_check_today_transitions_to_online_directly', (
    tester,
  ) async {
    final dutyGateway = _MutableDutyGateway(
      DriverDutySummary(
        driverReference: 'DRV-001',
        dutyStatus: 'offline',
        dutySince: DateTime(2026, 8, 6, 8),
        shiftCheckToday: false,
      ),
    );
    final queue = _MemoryQueue();
    final shiftGateway = _SuccessfulShiftCheckGateway(
      onSubmit: () {
        dutyGateway.current = DriverDutySummary(
          driverReference: 'DRV-001',
          dutyStatus: 'online',
          dutySince: now,
          shiftCheckToday: true,
          shiftCheckTodayReference: 'SC-QA-DRV-001-20260807',
        );
      },
    );
    final controller = DriverShiftCheckSubmissionController(
      queue: queue,
      gateway: shiftGateway,
      isOnline: () async => true,
    );
    var permissionRequests = 0;

    await tester.pumpWidget(
      _testApp(
        DriverShell(
          driverDutyGateway: dutyGateway,
          driverShiftCheckController: controller,
          requestNotificationPermission: () async {
            permissionRequests += 1;
            return false;
          },
          deviceNow: () => now,
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    expect(permissionRequests, 0);

    expect(
      find.byKey(const Key('driver-shift-readiness-screen')),
      findsOneWidget,
    );
    expect(
      find.text(
        'Complete these checks once before your first trip of the day.',
      ),
      findsOneWidget,
    );

    await _completeReadiness(tester);
    await tester.tap(find.byKey(const Key('readiness-ready')));
    await tester.pump();
    await tester.pump();

    expect(shiftGateway.calls, 1);

    await tester.pump(const Duration(milliseconds: 350));
    expect(dutyGateway.dutyCalls, greaterThanOrEqualTo(2));
    expect(permissionRequests, 0);

    expect(find.byKey(const Key('driver-online-transition')), findsOneWidget);
    expect(find.text('Shift check submitted.'), findsOneWidget);
    expect(find.text('You are now online.'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(permissionRequests, 1);
    expect(find.text("Today's shift · online now"), findsOneWidget);
    expect(find.text("You're online"), findsOneWidget);
    expect(find.text("Today's shift · offline"), findsNothing);
    expect(dutyGateway.dutyCalls, greaterThanOrEqualTo(2));

    await controller.stopAutomaticSync();
  });

  // Seen on the test phone (16 and 17 Oct): after "I am ready" the Work
  // screen showed the old "You're offline · START SHIFT CHECK" for about a
  // second while the app confirmed the driver was online.
  testWidgets('after a submitted shift check the old offline screen never '
      'shows while online is being confirmed', (tester) async {
    final dutyGateway = _MutableDutyGateway(
      DriverDutySummary(
        driverReference: 'DRV-001',
        // As on the phone on 17 Oct: online from yesterday, no shift check
        // for today, so Work shows START SHIFT CHECK and the driver taps it.
        dutyStatus: 'online',
        dutySince: DateTime(2026, 8, 6, 8),
        shiftCheckToday: false,
      ),
    );
    final shiftGateway = _SuccessfulShiftCheckGateway(
      onSubmit: () {
        dutyGateway.current = DriverDutySummary(
          driverReference: 'DRV-001',
          dutyStatus: 'online',
          dutySince: now,
          shiftCheckToday: true,
          shiftCheckTodayReference: 'SC-QA-DRV-001-20260807',
        );
      },
    );
    final controller = DriverShiftCheckSubmissionController(
      queue: _MemoryQueue(),
      gateway: shiftGateway,
      isOnline: () async => true,
    );

    await tester.pumpWidget(
      _testApp(
        DriverShell(
          driverDutyGateway: dutyGateway,
          driverShiftCheckController: controller,
          deviceNow: () => now,
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('driver-shift-check-needed-start')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('driver-shift-check-needed-start')));
    await tester.pumpAndSettle();

    await _completeReadiness(tester);
    final slowConfirm = Completer<void>();
    dutyGateway.holdNext = slowConfirm;
    await tester.tap(find.byKey(const Key('readiness-ready')));
    for (var i = 0; i < 20; i += 1) {
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('START SHIFT CHECK'), findsNothing);
      expect(find.text("You're offline"), findsNothing);
      expect(find.text("Today's shift · not yet started"), findsNothing);
    }
    expect(
      find.byKey(const Key('driver-shift-check-confirming')),
      findsOneWidget,
    );
    expect(find.text('Shift check submitted.'), findsOneWidget);

    slowConfirm.complete();
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('driver-online-transition')), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text("Today's shift · online now"), findsOneWidget);

    await controller.stopAutomaticSync();
  });

  testWidgets('if the server says offline after a submitted shift check, '
      'Work says so with Go online, not an error and not the old offline '
      'screen', (tester) async {
    final dutyGateway = _MutableDutyGateway(
      DriverDutySummary(
        driverReference: 'DRV-001',
        // As on the phone on 17 Oct: online from yesterday, no shift check
        // for today, so Work shows START SHIFT CHECK and the driver taps it.
        dutyStatus: 'online',
        dutySince: DateTime(2026, 8, 6, 8),
        shiftCheckToday: false,
      ),
    );
    final controller = DriverShiftCheckSubmissionController(
      queue: _MemoryQueue(),
      gateway: _SuccessfulShiftCheckGateway(
        onSubmit: () {
          dutyGateway.current = DriverDutySummary(
            driverReference: 'DRV-001',
            dutyStatus: 'offline',
            dutySince: now,
            shiftCheckToday: true,
          );
        },
      ),
      isOnline: () async => true,
    );

    await tester.pumpWidget(
      _testApp(
        DriverShell(
          driverDutyGateway: dutyGateway,
          driverShiftCheckController: controller,
          deviceNow: () => now,
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('driver-shift-check-needed-start')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('driver-shift-check-needed-start')));
    await tester.pumpAndSettle();

    await _completeReadiness(tester);
    final slowConfirm = Completer<void>();
    dutyGateway.holdNext = slowConfirm;
    await tester.tap(find.byKey(const Key('readiness-ready')));
    for (var i = 0; i < 20; i += 1) {
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('START SHIFT CHECK'), findsNothing);
    }
    slowConfirm.complete();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('driver-shift-check-confirming')),
      findsNothing,
    );
    expect(find.byKey(const Key('driver-online-transition')), findsNothing);
    expect(find.text('START SHIFT CHECK'), findsNothing);
    expect(find.byKey(const Key('driver-offline-screen')), findsNothing);
    expect(find.text("You're offline"), findsOneWidget);
    expect(find.text(_shiftCheckSavedGoOnline), findsOneWidget);
    expect(find.text('GO ONLINE'), findsOneWidget);

    await controller.stopAutomaticSync();
  });

  testWidgets('if the online check fails after a submitted shift check, the '
      'error shows, not "Going online…" forever', (tester) async {
    final dutyGateway = _MutableDutyGateway(
      DriverDutySummary(
        driverReference: 'DRV-001',
        dutyStatus: 'online',
        dutySince: DateTime(2026, 8, 6, 8),
        shiftCheckToday: false,
      ),
    );
    final controller = DriverShiftCheckSubmissionController(
      queue: _MemoryQueue(),
      gateway: _SuccessfulShiftCheckGateway(onSubmit: () {}),
      isOnline: () async => true,
    );

    await tester.pumpWidget(
      _testApp(
        DriverShell(
          driverDutyGateway: dutyGateway,
          driverShiftCheckController: controller,
          deviceNow: () => now,
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('driver-shift-check-needed-start')));
    await tester.pumpAndSettle();

    await _completeReadiness(tester);
    dutyGateway.failNext = true;
    await tester.tap(find.byKey(const Key('readiness-ready')));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('driver-shift-check-confirming')),
      findsNothing,
    );
    expect(find.byKey(const Key('driver-offline-screen')), findsOneWidget);
    expect(find.text("Couldn't confirm you're online"), findsOneWidget);
    expect(
      find.text(
        'Your shift check is saved. Check your connection and tap Retry.',
      ),
      findsOneWidget,
    );
    expect(find.text('You’re offline'), findsNothing);

    // Retry asks again; the server has the driver online by now.
    dutyGateway.current = DriverDutySummary(
      driverReference: 'DRV-001',
      dutyStatus: 'online',
      dutySince: now,
      shiftCheckToday: true,
    );
    await tester.tap(find.byKey(const Key('driver-offline-retry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('driver-offline-screen')), findsNothing);
    expect(find.text("You're online"), findsOneWidget);

    await controller.stopAutomaticSync();
  });

  testWidgets('"Going online…" says "Still trying…" once the duty check has '
      'taken 15 s', (tester) async {
    final dutyGateway = _MutableDutyGateway(
      DriverDutySummary(
        driverReference: 'DRV-001',
        dutyStatus: 'online',
        dutySince: DateTime(2026, 8, 6, 8),
        shiftCheckToday: false,
      ),
    );
    final controller = DriverShiftCheckSubmissionController(
      queue: _MemoryQueue(),
      gateway: _SuccessfulShiftCheckGateway(
        onSubmit: () {
          dutyGateway.current = DriverDutySummary(
            driverReference: 'DRV-001',
            dutyStatus: 'online',
            dutySince: now,
            shiftCheckToday: true,
          );
        },
      ),
      isOnline: () async => true,
    );

    await tester.pumpWidget(
      _testApp(
        DriverShell(
          driverDutyGateway: dutyGateway,
          driverShiftCheckController: controller,
          deviceNow: () => now,
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('driver-shift-check-needed-start')));
    await tester.pumpAndSettle();

    await _completeReadiness(tester);
    final slowConfirm = Completer<void>();
    dutyGateway.holdNext = slowConfirm;
    await tester.tap(find.byKey(const Key('readiness-ready')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Going online…'), findsOneWidget);
    expect(find.text('Still trying…'), findsNothing);

    // Counted from when "Going online…" appeared (at most 0.5 s ago).
    await tester.pump(const Duration(seconds: 14));
    expect(find.text('Still trying…'), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Going online…'), findsOneWidget);
    expect(find.text('Still trying…'), findsOneWidget);

    slowConfirm.complete();
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('driver-online-transition')), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    await controller.stopAutomaticSync();
  });

  // The offer card's "My Assigned Trips" after a 409 uses this.
  testWidgets('from a screen over the shell, "My Assigned Trips" closes it '
      'and opens the Trips tab', (tester) async {
    final dutyGateway = _MutableDutyGateway(
      DriverDutySummary(
        dutyStatus: 'online',
        dutySince: now,
        shiftCheckToday: true,
      ),
    );
    await tester.pumpWidget(
      _testApp(
        DriverShell(driverDutyGateway: dutyGateway, deviceNow: () => now),
      ),
    );
    await tester.pumpAndSettle();
    final shellContext = tester.element(find.byType(DriverShell));
    unawaited(
      Navigator.of(shellContext).push<void>(
        MaterialPageRoute<void>(
          builder: (context) => Scaffold(
            body: TextButton(
              key: const Key('over-the-shell'),
              onPressed: () => DriverBackToWork.goToAssignedTrips(context),
              child: const Text('My Assigned Trips'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('over-the-shell')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('over-the-shell')), findsNothing);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );
  });

  testWidgets('a duty check that fails at start-up still shows the plain '
      'offline screen', (tester) async {
    final dutyGateway = _MutableDutyGateway(
      DriverDutySummary(
        dutyStatus: 'online',
        dutySince: now,
        shiftCheckToday: true,
      ),
    )..failNext = true;

    await tester.pumpWidget(
      _testApp(
        DriverShell(driverDutyGateway: dutyGateway, deviceNow: () => now),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('driver-offline-screen')), findsOneWidget);
    expect(find.text('You’re offline'), findsOneWidget);
    expect(find.text("Couldn't confirm you're online"), findsNothing);
  });

  // In the app a sign-out replaces the shell with the sign-in form, so a
  // new shell starts clean; this keeps one shell across the sign-out so the
  // flag itself is checked.
  testWidgets('a sign-out while online is being confirmed after a shift '
      'check leaves no "Going online…" behind', (tester) async {
    final dutyGateway = _MutableDutyGateway(
      DriverDutySummary(
        driverReference: 'DRV-001',
        dutyStatus: 'online',
        dutySince: DateTime(2026, 8, 6, 8),
        shiftCheckToday: false,
      ),
    );
    final controller = DriverShiftCheckSubmissionController(
      queue: _MemoryQueue(),
      gateway: _SuccessfulShiftCheckGateway(onSubmit: () {}),
      isOnline: () async => true,
    );
    var signOuts = 0;

    await tester.pumpWidget(
      _testApp(
        DriverShell(
          driverDutyGateway: dutyGateway,
          driverShiftCheckController: controller,
          deviceNow: () => now,
          onSignOut: () async => signOuts += 1,
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('driver-shift-check-needed-start')));
    await tester.pumpAndSettle();

    await _completeReadiness(tester);
    final slowConfirm = Completer<void>();
    dutyGateway.holdNext = slowConfirm;
    await tester.tap(find.byKey(const Key('readiness-ready')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Going online…'), findsOneWidget);

    await tester.tap(find.text('Account'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('driver-account-sign-out')));
    await tester.pump();
    expect(signOuts, 1);
    await tester.tap(find.text('Work'));
    await tester.pump();

    expect(find.text('Going online…'), findsNothing);
    expect(
      find.byKey(const Key('driver-shift-check-confirming')),
      findsNothing,
    );

    slowConfirm.complete();
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    await controller.stopAutomaticSync();
  });

  testWidgets('queued readiness does not request notification permission', (
    tester,
  ) async {
    final dutyGateway = _MutableDutyGateway(
      DriverDutySummary(
        driverReference: 'DRV-001',
        dutyStatus: 'offline',
        dutySince: DateTime(2026, 8, 6, 8),
        shiftCheckToday: false,
      ),
    );
    var permissionRequests = 0;

    await tester.pumpWidget(
      _testApp(
        DriverShell(
          driverDutyGateway: dutyGateway,
          requestNotificationPermission: () async {
            permissionRequests += 1;
            return true;
          },
          deviceNow: () => now,
        ),
      ),
    );

    await tester.pumpAndSettle();
    await _completeReadiness(tester);

    expect(permissionRequests, 0);

    await tester.tap(find.byKey(const Key('readiness-ready')));
    await tester.pumpAndSettle();

    expect(permissionRequests, 0);
    expect(
      find.byKey(const Key('driver-shift-readiness-screen')),
      findsNothing,
    );
  });

  testWidgets('test_409_triggers_duty_refresh_not_error_display', (
    tester,
  ) async {
    final dutyGateway = _MutableDutyGateway(
      DriverDutySummary(
        driverReference: 'DRV-001',
        dutyStatus: 'offline',
        dutySince: DateTime(2026, 8, 6, 8),
        shiftCheckToday: false,
      ),
    );

    final controller = DriverShiftCheckSubmissionController(
      queue: _MemoryQueue(),
      gateway: _ConflictShiftCheckGateway(),
      isOnline: () async => true,
    );

    await tester.pumpWidget(
      _testApp(
        DriverShell(
          driverDutyGateway: dutyGateway,
          driverShiftCheckController: controller,
          deviceNow: () => now,
        ),
      ),
    );

    await tester.pumpAndSettle();

    await _completeReadiness(tester);
    await tester.tap(find.byKey(const Key('readiness-ready')));

    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(dutyGateway.dutyCalls, greaterThanOrEqualTo(1));
    expect(find.textContaining('error'), findsNothing);
  });

  testWidgets('test_duty_online_after_409_navigates_to_online_home', (
    tester,
  ) async {
    final dutyGateway = _MutableDutyGateway(
      DriverDutySummary(
        driverReference: 'DRV-001',
        dutyStatus: 'online',
        dutySince: now,
        shiftCheckToday: true,
      ),
    );

    final controller = DriverShiftCheckSubmissionController(
      queue: _MemoryQueue(),
      gateway: _ConflictShiftCheckGateway(),
      isOnline: () async => true,
    );

    await tester.pumpWidget(
      _testApp(
        DriverShell(
          driverDutyGateway: dutyGateway,
          driverShiftCheckController: controller,
          deviceNow: () => now,
        ),
      ),
    );

    await tester.pumpAndSettle();

    await tester.pump();
    await tester.pump();

    expect(find.text("You're online"), findsOneWidget);
  });

  testWidgets('test_shift_check_today_true_skips_shift_check_screen', (
    tester,
  ) async {
    final gateway = _MutableDutyGateway(
      DriverDutySummary(
        dutyStatus: 'offline',
        dutySince: now.subtract(const Duration(hours: 1)),
        shiftCheckToday: true,
      ),
    );

    await tester.pumpWidget(
      _testApp(DriverShell(driverDutyGateway: gateway, deviceNow: () => now)),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('driver-shift-readiness-screen')),
      findsNothing,
    );
    expect(find.text('GO ONLINE'), findsOneWidget);
    expect(find.text('START SHIFT CHECK'), findsNothing);
  });

  testWidgets('test_shift_check_today_false_shows_shift_check_screen', (
    tester,
  ) async {
    final gateway = _MutableDutyGateway(
      DriverDutySummary(
        dutyStatus: 'offline',
        dutySince: now.subtract(const Duration(days: 1)),
        shiftCheckToday: false,
      ),
    );

    await tester.pumpWidget(
      _testApp(DriverShell(driverDutyGateway: gateway, deviceNow: () => now)),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('driver-shift-readiness-screen')),
      findsOneWidget,
    );
  });

  testWidgets('test_duty_since_not_used_for_shift_check_inference', (
    tester,
  ) async {
    final gateway = _MutableDutyGateway(
      DriverDutySummary(
        dutyStatus: 'offline',
        dutySince: now,
        shiftCheckToday: false,
      ),
    );

    await tester.pumpWidget(
      _testApp(DriverShell(driverDutyGateway: gateway, deviceNow: () => now)),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('driver-shift-readiness-screen')),
      findsOneWidget,
      reason:
          "Today's duty_since must not imply that today's shift check exists.",
    );
  });

  testWidgets('test_go_offline_calls_duty_endpoint_with_offline', (
    tester,
  ) async {
    final gateway = _MutableDutyGateway(
      DriverDutySummary(
        dutyStatus: 'online',
        dutySince: now.subtract(const Duration(minutes: 30)),
        shiftCheckToday: true,
      ),
      transitionNow: now,
    );

    await tester.pumpWidget(
      _testApp(DriverShell(driverDutyGateway: gateway, deviceNow: () => now)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('driver-go-offline')));
    await tester.pumpAndSettle();

    expect(gateway.transitionStatuses, <DriverOperationalDutyStatus>[
      DriverOperationalDutyStatus.offline,
    ]);
    expect(find.text("Today's shift · offline"), findsOneWidget);
    expect(find.text('GO ONLINE'), findsOneWidget);
  });

  testWidgets('test_go_online_calls_duty_endpoint_with_online', (tester) async {
    final gateway = _MutableDutyGateway(
      DriverDutySummary(
        dutyStatus: 'offline',
        dutySince: now.subtract(const Duration(minutes: 30)),
        shiftCheckToday: true,
      ),
      transitionNow: now,
    );

    await tester.pumpWidget(
      _testApp(DriverShell(driverDutyGateway: gateway, deviceNow: () => now)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('driver-go-online')));
    await tester.pumpAndSettle();

    expect(gateway.transitionStatuses, <DriverOperationalDutyStatus>[
      DriverOperationalDutyStatus.online,
    ]);
    expect(find.text("Today's shift · online now"), findsOneWidget);
    expect(find.text('GO OFFLINE'), findsOneWidget);
  });

  testWidgets(
    'test_complete_readiness_check_not_visible_after_shift_check_done',
    (tester) async {
      final gateway = _MutableDutyGateway(
        DriverDutySummary(
          dutyStatus: 'offline',
          dutySince: now.subtract(const Duration(hours: 2)),
          shiftCheckToday: true,
        ),
      );

      await tester.pumpWidget(
        _testApp(DriverShell(driverDutyGateway: gateway, deviceNow: () => now)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Complete readiness check'), findsNothing);
      expect(find.text('START SHIFT CHECK'), findsNothing);
      expect(find.text('GO ONLINE'), findsOneWidget);
    },
  );

  testWidgets('test_shift_check_screen_not_shown_if_already_done_today', (
    tester,
  ) async {
    final gateway = _MutableDutyGateway(
      DriverDutySummary(
        dutyStatus: 'offline',
        dutySince: now.subtract(const Duration(minutes: 10)),
        shiftCheckToday: true,
      ),
    );

    await tester.pumpWidget(
      _testApp(DriverShell(driverDutyGateway: gateway, deviceNow: () => now)),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('driver-shift-readiness-screen')),
      findsNothing,
    );
    expect(find.text('Shift check'), findsNothing);
  });

  testWidgets('test_online_state_shows_correct_wording', (tester) async {
    final gateway = _MutableDutyGateway(
      DriverDutySummary(
        dutyStatus: 'online',
        dutySince: now.subtract(const Duration(minutes: 5)),
        shiftCheckToday: true,
      ),
    );

    await tester.pumpWidget(
      _testApp(DriverShell(driverDutyGateway: gateway, deviceNow: () => now)),
    );
    await tester.pumpAndSettle();

    for (final text in <String>[
      "Today's shift · online now",
      "You're online",
      'Ready to receive nearby ride offers.',
      'Waiting for offers',
      'WAITING FOR A RIDE OFFER NEARBY',
      'Stay in your zone for faster matches.',
      'GO OFFLINE',
    ]) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
  });

  testWidgets('test_offline_state_post_check_shows_correct_wording', (
    tester,
  ) async {
    final gateway = _MutableDutyGateway(
      DriverDutySummary(
        dutyStatus: 'offline',
        dutySince: now.subtract(const Duration(hours: 3)),
        shiftCheckToday: true,
      ),
    );

    await tester.pumpWidget(
      _testApp(DriverShell(driverDutyGateway: gateway, deviceNow: () => now)),
    );
    await tester.pumpAndSettle();

    expect(find.text("Today's shift · offline"), findsOneWidget);
    expect(find.text("You're offline"), findsOneWidget);
    expect(find.text(_shiftCheckSavedGoOnline), findsOneWidget);
    expect(find.text('GO ONLINE'), findsOneWidget);
    expect(find.text('START SHIFT CHECK'), findsNothing);
    expect(find.text('Complete readiness check'), findsNothing);
  });

  testWidgets('test_offline_state_no_check_shows_correct_wording', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        DriverHome(
          market: MarketConfig.ghanaAccra,
          isOnShift: false,
          shiftCheckCompletedToday: false,
          dutyActionInFlight: false,
          onOpenReadiness: () {},
          onGoOnline: null,
          onGoOffline: null,
          onRecordConcern: () {},
          onPreviewIncomingRequest: () {},
          localQaEnabled: false,
          onOpenAssignedTrips: () {},
          onOpenShiftSummary: () {},
        ),
      ),
    );

    expect(find.text("Today's shift · not yet started"), findsOneWidget);
    expect(find.text("You're offline"), findsOneWidget);
    expect(
      find.text('Complete your pre-shift check to go online.'),
      findsOneWidget,
    );
    expect(find.text('START SHIFT CHECK'), findsOneWidget);
    expect(
      find.text('Complete readiness before starting your shift.'),
      findsNothing,
    );
  });

  test('test_token_refreshed_before_duty_post', () async {
    const expiredToken = 'e30.eyJleHAiOjF9.';
    const refreshedToken = 'e30.eyJleHAiOjQxMDI0NDQ4MDB9.';

    final tokenStore = _MutableTokenStore(expiredToken);
    final apiClient = _RecordingDutyApiClient();
    var refreshCalls = 0;

    final gateway = AsmDriverDutyGateway.withApiClient(
      apiClient: apiClient,
      tokenStore: tokenStore,
      refreshAccessToken: () async {
        refreshCalls += 1;
        tokenStore.accessToken = refreshedToken;
        return DriverTokenRefreshOutcome.refreshed;
      },
      dutyRetryDelay: (_) async {},
    );

    final transition = await gateway.updateDutyStatus(
      DriverOperationalDutyStatus.online,
    );

    expect(transition.dutyStatus, 'online');
    expect(refreshCalls, 1);
    expect(apiClient.postCalls, 1);
    expect(apiClient.paths.single, driverDutyStatusPath);
    expect(apiClient.headers.single['Authorization'], 'Bearer $refreshedToken');
    expect(apiClient.bodies.single, <String, Object?>{'status': 'online'});
  });

  test('test_duty_call_not_queued_on_failure', () async {
    const validToken = 'e30.eyJleHAiOjQxMDI0NDQ4MDB9.';

    final tokenStore = _MutableTokenStore(validToken);
    final apiClient = _FailingDutyApiClient();

    final gateway = AsmDriverDutyGateway.withApiClient(
      apiClient: apiClient,
      tokenStore: tokenStore,
      refreshAccessToken: () async => DriverTokenRefreshOutcome.sessionExpired,
      dutyRetryDelay: (_) async {},
    );

    await expectLater(
      gateway.updateDutyStatus(DriverOperationalDutyStatus.online),
      throwsA(isA<DriverDutyApiException>()),
    );

    expect(apiClient.postCalls, 4);

    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(
      apiClient.postCalls,
      4,
      reason: 'No deferred queue or later duty delivery may remain.',
    );
  });
  testWidgets('test_greeting_before_noon_is_good_morning', (tester) async {
    await tester.pumpWidget(
      _testApp(
        DriverHome(
          market: MarketConfig.ghanaAccra,
          isOnShift: false,
          shiftCheckCompletedToday: false,
          dutyActionInFlight: false,
          onOpenReadiness: () {},
          onGoOnline: null,
          onGoOffline: null,
          onRecordConcern: () {},
          onPreviewIncomingRequest: () {},
          localQaEnabled: false,
          onOpenAssignedTrips: () {},
          onOpenShiftSummary: () {},
          greetingNow: () => DateTime(2026, 8, 7, 8),
        ),
      ),
    );

    expect(find.text('Good morning, Driver'), findsOneWidget);
  });

  testWidgets('test_greeting_noon_to_1759_is_good_afternoon', (tester) async {
    await tester.pumpWidget(
      _testApp(
        DriverHome(
          market: MarketConfig.ghanaAccra,
          isOnShift: false,
          shiftCheckCompletedToday: false,
          dutyActionInFlight: false,
          onOpenReadiness: () {},
          onGoOnline: null,
          onGoOffline: null,
          onRecordConcern: () {},
          onPreviewIncomingRequest: () {},
          localQaEnabled: false,
          onOpenAssignedTrips: () {},
          onOpenShiftSummary: () {},
          greetingNow: () => DateTime(2026, 8, 7, 12),
        ),
      ),
    );

    expect(find.text('Good afternoon, Driver'), findsOneWidget);
  });

  testWidgets('test_greeting_1759_is_good_afternoon', (tester) async {
    await tester.pumpWidget(
      _testApp(
        DriverHome(
          market: MarketConfig.ghanaAccra,
          isOnShift: false,
          shiftCheckCompletedToday: false,
          dutyActionInFlight: false,
          onOpenReadiness: () {},
          onGoOnline: null,
          onGoOffline: null,
          onRecordConcern: () {},
          onPreviewIncomingRequest: () {},
          localQaEnabled: false,
          onOpenAssignedTrips: () {},
          onOpenShiftSummary: () {},
          greetingNow: () => DateTime(2026, 8, 7, 17, 59),
        ),
      ),
    );

    expect(find.text('Good afternoon, Driver'), findsOneWidget);
  });

  testWidgets('test_greeting_2359_is_good_evening', (tester) async {
    await tester.pumpWidget(
      _testApp(
        DriverHome(
          market: MarketConfig.ghanaAccra,
          isOnShift: false,
          shiftCheckCompletedToday: false,
          dutyActionInFlight: false,
          onOpenReadiness: () {},
          onGoOnline: null,
          onGoOffline: null,
          onRecordConcern: () {},
          onPreviewIncomingRequest: () {},
          localQaEnabled: false,
          onOpenAssignedTrips: () {},
          onOpenShiftSummary: () {},
          greetingNow: () => DateTime(2026, 8, 7, 23, 59),
        ),
      ),
    );

    expect(find.text('Good evening, Driver'), findsOneWidget);
  });

  testWidgets('test_greeting_1800_and_after_is_good_evening', (tester) async {
    await tester.pumpWidget(
      _testApp(
        DriverHome(
          market: MarketConfig.ghanaAccra,
          isOnShift: false,
          shiftCheckCompletedToday: false,
          dutyActionInFlight: false,
          onOpenReadiness: () {},
          onGoOnline: null,
          onGoOffline: null,
          onRecordConcern: () {},
          onPreviewIncomingRequest: () {},
          localQaEnabled: false,
          onOpenAssignedTrips: () {},
          onOpenShiftSummary: () {},
          greetingNow: () => DateTime(2026, 8, 7, 18),
        ),
      ),
    );

    expect(find.text('Good evening, Driver'), findsOneWidget);
  });
  // Sign-in build A3: a 401 on Work goes to the sign-in screen at once, not
  // to an offline or "Session expired" panel.
  group('Work 401 goes to sign-in (A3)', () {
    const expired = DriverDutyApiException(
      DriverDutyApiFailureType.sessionExpired,
      driverSessionExpiredMessage,
    );
    var signIns = 0;

    setUp(() {
      signIns = 0;
      DriverSessionEnd.signIn = () async => signIns += 1;
    });
    tearDown(() => DriverSessionEnd.signIn = null);

    DriverDutySummary online() => DriverDutySummary(
      driverReference: 'DRV-001',
      dutyStatus: 'online',
      dutySince: now.subtract(const Duration(hours: 1)),
      shiftCheckToday: true,
    );

    Future<void> pumpShell(
      WidgetTester tester,
      _MutableDutyGateway gateway, {
      DriverShiftCheckSubmissionController? controller,
    }) async {
      await tester.pumpWidget(
        _testApp(
          DriverShell(
            driverDutyGateway: gateway,
            driverShiftCheckController: controller,
            deviceNow: () => now,
          ),
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();
    }

    testWidgets('the first duty load', (tester) async {
      final gateway = _MutableDutyGateway(online())..errorNext = expired;

      await pumpShell(tester, gateway);

      expect(signIns, 1);
    });

    testWidgets('GO OFFLINE', (tester) async {
      final gateway = _MutableDutyGateway(online());
      await pumpShell(tester, gateway);
      gateway.transitionError = expired;

      await tester.tap(find.text('GO OFFLINE'));
      await tester.pumpAndSettle();

      expect(signIns, 1);
    });

    testWidgets('a quiet reload (Refresh)', (tester) async {
      final gateway = _MutableDutyGateway(online());
      await pumpShell(tester, gateway);
      gateway.errorNext = expired;
      final refresh = find.byKey(const Key('driver-duty-refresh'));
      await tester.ensureVisible(refresh);
      await tester.pumpAndSettle();

      await tester.tap(refresh);
      await tester.pumpAndSettle();

      expect(signIns, 1);
    });

    testWidgets('confirming online after the shift check', (tester) async {
      final gateway = _MutableDutyGateway(
        DriverDutySummary(
          driverReference: 'DRV-001',
          dutyStatus: 'offline',
          dutySince: DateTime(2026, 8, 6, 8),
          shiftCheckToday: false,
        ),
      );
      final controller = DriverShiftCheckSubmissionController(
        queue: _MemoryQueue(),
        gateway: _SuccessfulShiftCheckGateway(
          onSubmit: () => gateway.errorNext = expired,
        ),
        isOnline: () async => true,
      );
      await pumpShell(tester, gateway, controller: controller);

      await _completeReadiness(tester);
      await tester.tap(find.byKey(const Key('readiness-ready')));
      await tester.pumpAndSettle();

      expect(signIns, 1);
      await controller.stopAutomaticSync();
    });

    testWidgets('another failure keeps Work (no sign-in)', (tester) async {
      final gateway = _MutableDutyGateway(online())..failNext = true;

      await pumpShell(tester, gateway);

      expect(signIns, 0);
    });
  });
  // Sign-in build A3: the server refused the shift check as one from an
  // earlier day (the phone clock is a day behind): the driver reads the
  // server's words, nothing says "submitted", and Work still asks for the
  // shift check.
  testWidgets('a stale shift check is not submitted (A3)', (tester) async {
    const staleText =
        "This shift check was done on an earlier day. Do today's shift check.";
    final gateway = _MutableDutyGateway(
      DriverDutySummary(
        driverReference: 'DRV-001',
        dutyStatus: 'offline',
        dutySince: DateTime(2026, 8, 6, 8),
        shiftCheckToday: false,
      ),
    );
    final controller = DriverShiftCheckSubmissionController(
      queue: _MemoryQueue(),
      gateway: _StaleShiftCheckGateway(staleText),
      isOnline: () async => true,
    );
    await tester.pumpWidget(
      _testApp(
        DriverShell(
          driverDutyGateway: gateway,
          driverShiftCheckController: controller,
          deviceNow: () => now,
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    await _completeReadiness(tester);
    await tester.tap(find.byKey(const Key('readiness-ready')));
    await tester.pumpAndSettle();

    expect(find.text(staleText), findsOneWidget);
    expect(find.text('Shift check submitted'), findsNothing);
    await tester.tap(find.byKey(const Key('driver-shift-check-stale-ok')));
    await tester.pumpAndSettle();

    expect(find.text('START SHIFT CHECK'), findsOneWidget);
    expect(gateway.transitionStatuses, isEmpty);
    await controller.stopAutomaticSync();
  });
}

Widget _testApp(Widget home) {
  return MaterialApp(theme: AsmThemes.driver, home: home);
}

Future<void> _completeReadiness(WidgetTester tester) async {
  for (final item in DriverReadinessItem.values) {
    final finder = find.byKey(ValueKey<String>('readiness-${item.name}'));
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pump();
    await tester.tap(finder);
    await tester.pump();
  }

  final ready = find.byKey(const Key('readiness-ready'));
  await tester.scrollUntilVisible(
    ready,
    200,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.pump();

  expect(tester.widget<FilledButton>(ready).onPressed, isNotNull);
}

final class _MutableDutyGateway
    implements DriverDutyGateway, DriverDutyStatusGateway {
  _MutableDutyGateway(
    this.current, {
    DateTime? transitionNow,
    this._firstDutyCompleter,
  }) : transitionNow = transitionNow ?? DateTime(2026, 8, 7, 8);

  DriverDutySummary current;
  final DateTime transitionNow;
  final Completer<DriverDutySummary>? _firstDutyCompleter;

  int dutyCalls = 0;

  /// When set, the next fetchDuty waits for it (a slow network).
  Completer<void>? holdNext;

  /// When true, the next fetchDuty fails (the network drops).
  bool failNext = false;

  /// When set, the next fetchDuty throws it (A3: a 401).
  DriverDutyApiException? errorNext;

  /// When set, every duty change throws it.
  DriverDutyApiException? transitionError;
  final List<DriverOperationalDutyStatus> transitionStatuses =
      <DriverOperationalDutyStatus>[];

  @override
  Future<DriverDutySummary> fetchDuty() async {
    dutyCalls += 1;
    if (dutyCalls == 1 && _firstDutyCompleter != null) {
      return _firstDutyCompleter.future;
    }
    final hold = holdNext;
    if (hold != null) {
      holdNext = null;
      await hold.future;
    }
    final error = errorNext;
    if (error != null) {
      errorNext = null;
      throw error;
    }
    if (failNext) {
      failNext = false;
      throw const DriverDutyApiException(
        DriverDutyApiFailureType.unavailable,
        'Cannot reach the server.',
      );
    }
    return current;
  }

  @override
  Future<List<DriverAssignedTrip>> fetchTrips() async {
    return const <DriverAssignedTrip>[];
  }

  @override
  Future<DriverAssignedTrip> fetchTripDetail(String tripReference) async {
    throw StateError('Trip detail not used in duty-status tests.');
  }

  @override
  Future<DriverDutyTransition> updateDutyStatus(
    DriverOperationalDutyStatus status,
  ) async {
    transitionStatuses.add(status);
    final error = transitionError;
    if (error != null) {
      throw error;
    }

    final transition = DriverDutyTransition(
      dutyStatus: status.wireValue,
      since: transitionNow,
    );

    current = current.withDutyTransition(transition);
    return transition;
  }
}

final class _ConflictShiftCheckGateway implements DriverShiftCheckGateway {
  int calls = 0;

  @override
  Future<ApiResponse<Object?>> submit({
    required Map<String, Object?> body,
    required String idempotencyKey,
  }) async {
    calls += 1;
    return ApiResponse.apiFailure(
      const AsmApiException(
        type: AsmApiExceptionType.server,
        message: 'Already submitted today.',
        statusCode: 409,
      ),
    );
  }
}

final class _SuccessfulShiftCheckGateway implements DriverShiftCheckGateway {
  _SuccessfulShiftCheckGateway({this.onSubmit});

  final VoidCallback? onSubmit;
  int calls = 0;

  @override
  Future<ApiResponse<Object?>> submit({
    required Map<String, Object?> body,
    required String idempotencyKey,
  }) async {
    calls += 1;
    onSubmit?.call();

    return ApiResponse<Object?>.success(const <String, Object?>{
      'ok': true,
    }, statusCode: 201);
  }
}

final class _MemoryQueue implements DriverTripActionPersistentQueue {
  final Map<String, QueuedEvent> _events = <String, QueuedEvent>{};

  @override
  Future<QueuedEvent> enqueue(QueuedEvent event) async {
    _events[event.id] = event;
    return event;
  }

  @override
  Future<QueuedEvent?> eventById(String id) async {
    return _events[id];
  }

  @override
  Future<List<QueuedEvent>> pendingEvents() async {
    return _events.values
        .where(
          (event) =>
              event.syncStatus == QueueSyncStatus.pending ||
              event.syncStatus == QueueSyncStatus.failed,
        )
        .toList(growable: false);
  }

  @override
  Future<void> markSynced(String id) async {
    final event = _events[id];
    if (event != null) {
      _events[id] = event.copyWith(syncStatus: QueueSyncStatus.synced);
    }
  }

  @override
  Future<void> markFailed(String id) async {
    final event = _events[id];
    if (event != null) {
      _events[id] = event.copyWith(
        syncStatus: QueueSyncStatus.failed,
        retryCount: event.retryCount + 1,
      );
    }
  }

  @override
  Future<void> markPermanentlyFailed(String id) async {
    final event = _events[id];
    if (event != null) {
      _events[id] = event.copyWith(
        syncStatus: QueueSyncStatus.permanentlyFailed,
      );
    }
  }
}

final class _MutableTokenStore implements AuthTokenStore {
  _MutableTokenStore(this.accessToken);

  String? accessToken;

  @override
  Future<void> saveTokens(AuthTokens tokens) async {
    accessToken = tokens.accessToken;
  }

  @override
  Future<String?> readAccessToken() async => accessToken;

  @override
  Future<String?> readRefreshToken() async => null;

  @override
  Future<void> clearTokens() async {
    accessToken = null;
  }
}

final class _RecordingDutyApiClient
    implements DriverDutyApiClient, DriverDutyPostApiClient {
  int postCalls = 0;
  final List<String> paths = <String>[];
  final List<Object?> bodies = <Object?>[];
  final List<Map<String, String>> headers = <Map<String, String>>[];

  @override
  Future<ApiResponse<T>> get<T>(String path, {JsonDecoder<T>? decoder}) async {
    throw StateError('GET not used by this gateway test.');
  }

  @override
  Future<ApiResponse<T>> post<T>(
    String path, {
    Object? data,
    Map<String, String>? headers,
    JsonDecoder<T>? decoder,
  }) async {
    postCalls += 1;
    paths.add(path);
    bodies.add(data);
    this.headers.add(<String, String>{...?headers});

    final decoded = decoder!(<String, Object?>{
      'duty_status': 'online',
      'since': '2026-08-07T08:00:00Z',
    });

    return ApiResponse<T>.success(decoded, statusCode: 200);
  }
}

final class _FailingDutyApiClient
    implements DriverDutyApiClient, DriverDutyPostApiClient {
  int postCalls = 0;

  @override
  Future<ApiResponse<T>> get<T>(String path, {JsonDecoder<T>? decoder}) async {
    throw StateError('GET not used by this gateway test.');
  }

  @override
  Future<ApiResponse<T>> post<T>(
    String path, {
    Object? data,
    Map<String, String>? headers,
    JsonDecoder<T>? decoder,
  }) async {
    postCalls += 1;

    return ApiResponse<T>.apiFailure(
      const AsmApiException(
        type: AsmApiExceptionType.network,
        message: 'Network unavailable.',
      ),
    );
  }
}

final class _StaleShiftCheckGateway implements DriverShiftCheckGateway {
  _StaleShiftCheckGateway(this.text);

  final String text;

  @override
  Future<ApiResponse<Object?>> submit({
    required Map<String, Object?> body,
    required String idempotencyKey,
  }) async => ApiResponse.apiFailure(
    AsmApiException(
      type: AsmApiExceptionType.badResponse,
      message: 'conflict',
      statusCode: 409,
      cause: <String, Object?>{'detail': text, 'code': 'shift_check_stale'},
    ),
  );
}
