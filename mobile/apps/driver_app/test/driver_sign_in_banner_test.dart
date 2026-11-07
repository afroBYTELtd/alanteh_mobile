import 'package:asm_design_system/asm_design_system.dart';
import 'package:driver_app/driver_duty_trips.dart';
import 'package:driver_app/driver_home.dart';
import 'package:driver_app/driver_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Sign-in build A3, the Work banner that the sign-in ends soon (it reads
// the refresh token's exp, now sign-in + 30 days):
// - under 12 h when the app opens or comes back to the front;
// - under 2 h during a shift, checked on Work's 3-minute timer;
// - never during an active trip; it shows when the trip ends.
// The pre-shift-check dialog (B7) stays as it is.

const _banner = Key('driver-sign-in-ends-banner');

void main() {
  final now = DateTime(2026, 11, 7, 9);
  late Duration? left;
  late _Duty duty;
  late int signOuts;

  setUp(() {
    left = null;
    signOuts = 0;
    duty = _Duty(online: true, activeTrips: 0, now: now);
  });

  Future<void> pumpShell(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.driver,
        home: DriverShell(
          driverDutyGateway: duty,
          deviceNow: () => now,
          signInTimeLeft: () async => left,
          onSignOut: () async => signOuts += 1,
        ),
      ),
    );
    for (var i = 0; i < 6; i += 1) {
      await tester.pump();
    }
  }

  Future<void> timerTick(WidgetTester tester) async {
    await tester.pump(driverDutyReloadInterval);
    for (var i = 0; i < 6; i += 1) {
      await tester.pump();
    }
  }

  Future<void> resume(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    for (var i = 0; i < 6; i += 1) {
      await tester.pump();
    }
  }

  group('on open', () {
    testWidgets('11 h 59 min left: the banner', (tester) async {
      left = const Duration(hours: 11, minutes: 59);

      await pumpShell(tester);

      expect(find.byKey(_banner), findsOneWidget);
    });

    testWidgets('12 h 1 min left: no banner', (tester) async {
      left = const Duration(hours: 12, minutes: 1);

      await pumpShell(tester);

      expect(find.byKey(_banner), findsNothing);
    });

    testWidgets('unknown: no banner', (tester) async {
      await pumpShell(tester);

      expect(find.byKey(_banner), findsNothing);
    });

    testWidgets('the threshold is 12 h', (tester) async {
      expect(driverSignInBannerOnOpen, const Duration(hours: 12));
      expect(driverSignInBannerDuringShift, const Duration(hours: 2));
    });
  });

  group('on resume', () {
    testWidgets('under 12 h now: the banner', (tester) async {
      left = const Duration(hours: 20);
      await pumpShell(tester);
      expect(find.byKey(_banner), findsNothing);

      left = const Duration(hours: 11);
      await resume(tester);

      expect(find.byKey(_banner), findsOneWidget);
    });
  });

  group("during a shift, on Work's timer", () {
    testWidgets('under 2 h: the banner', (tester) async {
      left = const Duration(hours: 13);
      await pumpShell(tester);
      expect(find.byKey(_banner), findsNothing);

      left = const Duration(hours: 1, minutes: 59);
      await timerTick(tester);

      expect(find.byKey(_banner), findsOneWidget);
    });

    testWidgets('between 2 h and 12 h: no banner from the timer', (
      tester,
    ) async {
      left = const Duration(hours: 13);
      await pumpShell(tester);

      left = const Duration(hours: 5);
      await timerTick(tester);

      expect(find.byKey(_banner), findsNothing);
    });

    testWidgets('offline (no shift): the timer does not show it', (
      tester,
    ) async {
      duty.online = false;
      left = const Duration(hours: 13);
      await pumpShell(tester);

      left = const Duration(hours: 1);
      await timerTick(tester);

      expect(find.byKey(_banner), findsNothing);
    });
  });

  group('an active trip', () {
    testWidgets('hides it; it shows when the trip ends', (tester) async {
      duty.activeTrips = 1;
      left = const Duration(hours: 3);
      await pumpShell(tester);
      expect(find.byKey(_banner), findsNothing);

      duty.activeTrips = 0;
      await timerTick(tester);

      expect(find.byKey(_banner), findsOneWidget);
    });
  });

  testWidgets('the banner says so and offers Sign in again', (tester) async {
    left = const Duration(hours: 4);
    await pumpShell(tester);

    expect(
      find.descendant(
        of: find.byKey(_banner),
        matching: find.textContaining('Your sign-in ends soon'),
      ),
      findsOneWidget,
    );
    // Lead, 7 Nov: say plainly that signing in again takes the driver
    // offline (sign-out goes through the server).
    expect(
      find.descendant(
        of: find.byKey(_banner),
        matching: find.text(driverSignInAgainGoesOfflineNote),
      ),
      findsOneWidget,
    );
    expect(
      driverSignInAgainGoesOfflineNote,
      'Signing in again takes you offline. Go online again after you sign '
      'in.',
    );
    final renew = find.byKey(const Key('driver-sign-in-ends-banner-renew'));
    await tester.ensureVisible(renew);
    await tester.pumpAndSettle();
    await tester.tap(renew);
    await tester.pumpAndSettle();

    expect(signOuts, 1);
  });
}

final class _Duty implements DriverDutyGateway {
  _Duty({required this.online, required this.activeTrips, required this.now});

  bool online;
  int activeTrips;
  final DateTime now;

  @override
  Future<DriverDutySummary> fetchDuty() async => DriverDutySummary(
    driverReference: 'DRV-001',
    dutyStatus: online ? 'online' : 'offline',
    dutySince: now.subtract(const Duration(hours: 1)),
    shiftCheckToday: true,
    activeTripCount: activeTrips,
  );

  @override
  Future<List<DriverAssignedTrip>> fetchTrips() async =>
      const <DriverAssignedTrip>[];

  @override
  Future<DriverAssignedTrip> fetchTripDetail(String tripReference) =>
      throw StateError('not used');
}
