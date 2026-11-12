import 'package:asm_design_system/asm_design_system.dart';
import 'package:driver_app/driver_duty_trips.dart';
import 'package:driver_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// F-A (lead, 8 Nov), the shell's side: Work is reset only when the sign-out
// says the session ended. In the app the sign-in screen replaces the shell
// at once, so only a shell kept on screen shows the difference (mutant A3).
void main() {
  for (final (ended, tabAfter) in const [(true, 0), (false, 2)]) {
    testWidgets('onSignOut answers $ended: the tab after is $tabAfter', (
      tester,
    ) async {
      var signOuts = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AsmThemes.driver,
          home: DriverShell(
            driverDutyGateway: _Online(),
            deviceNow: () => DateTime(2026, 11, 9, 9),
            onSignOut: () async {
              signOuts += 1;
              return ended;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Account'));
      await tester.pumpAndSettle();
      final button = find.byKey(const Key('driver-account-sign-out'));
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(signOuts, 1);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        tabAfter,
      );
    });
  }
}

/// Online with today's shift check: Work opens on its own.
final class _Online implements DriverDutyGateway {
  @override
  Future<DriverDutySummary> fetchDuty() async => DriverDutySummary(
    driverReference: 'DRV-1',
    dutyStatus: 'online',
    dutySince: DateTime(2026, 11, 9, 8),
    shiftCheckToday: true,
  );

  @override
  Future<List<DriverAssignedTrip>> fetchTrips() async => const [];

  @override
  Future<DriverAssignedTrip> fetchTripDetail(String tripReference) =>
      throw UnimplementedError();
}
