import 'package:asm_design_system/asm_design_system.dart';
import 'package:driver_app/driver_duty_trips.dart';
import 'package:driver_app/driver_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// F-B (lead, 8 Nov): the Account card "Assigned vehicle", the Shift summary
// and the Shift history show the vehicle from the driver summary
// (GET /api/driver/me/, "driver"."vehicle_reference"), or "Not assigned
// yet" when there is none.
void main() {
  Future<void> pumpShell(WidgetTester tester, Object? vehicle) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.driver,
        home: DriverShell(
          driverDutyGateway: _Duty(
            DriverDutySummary.fromJson(<String, Object?>{
              'driver': <String, Object?>{
                'driver_reference': 'DRV-TEST-01',
                'vehicle_reference': ?vehicle,
              },
              'duty': <String, Object?>{
                'duty_status': 'online',
                'duty_since': '2026-11-12T08:00:00Z',
                'shift_check_today': true,
              },
            }),
          ),
          deviceNow: () => DateTime(2026, 11, 12, 9),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The value next to "Vehicle" on [screen].
  String vehicleRow(WidgetTester tester, Finder screen) {
    final row = find
        .ancestor(
          of: find.descendant(of: screen, matching: find.text('Vehicle')),
          matching: find.byType(Row),
        )
        .first;
    return tester
        .widgetList<Text>(find.descendant(of: row, matching: find.byType(Text)))
        .last
        .data!;
  }

  Future<String> accountCard(WidgetTester tester) async {
    await tester.tap(find.text('Account'));
    await tester.pumpAndSettle();
    final card = find.byKey(const Key('driver-account-vehicle-card'));
    await tester.ensureVisible(card);
    final texts = tester
        .widgetList<Text>(
          find.descendant(of: card, matching: find.byType(Text)),
        )
        .map((text) => text.data)
        .toList();
    return texts[1]!;
  }

  Future<String> shiftSummary(WidgetTester tester) async {
    final open = find.byKey(const Key('driver-home-open-shift-summary'));
    await tester.ensureVisible(open);
    await tester.pumpAndSettle();
    await tester.tap(open);
    await tester.pumpAndSettle();
    return vehicleRow(
      tester,
      find.byKey(const Key('driver-shift-summary-screen')),
    );
  }

  Future<String> shiftHistory(WidgetTester tester) async {
    await tester.tap(find.text('Account'));
    await tester.pumpAndSettle();
    final open = find.byKey(const Key('driver-account-open-shift-history'));
    await tester.ensureVisible(open);
    await tester.pumpAndSettle();
    await tester.tap(open);
    await tester.pumpAndSettle();
    // The current shift's card is the first one on the history screen.
    final current = find.descendant(
      of: find.byKey(const Key('driver-shift-history-screen')),
      matching: find.byType(InkWell),
    );
    await tester.tap(current.first);
    await tester.pumpAndSettle();
    return vehicleRow(
      tester,
      find.byKey(const Key('driver-shift-detail-screen')),
    );
  }

  for (final (name, vehicle, shown) in const <(String, Object?, String)>[
    ('a vehicle', ' VEH-TEST-01 ', 'VEH-TEST-01'),
    ('no vehicle', null, 'Not assigned yet'),
    ('a blank vehicle', '   ', 'Not assigned yet'),
  ]) {
    testWidgets('$name: the Account card shows "$shown"', (tester) async {
      await pumpShell(tester, vehicle);
      expect(await accountCard(tester), shown);
    });

    testWidgets('$name: the Shift summary shows "$shown"', (tester) async {
      await pumpShell(tester, vehicle);
      expect(await shiftSummary(tester), shown);
    });

    testWidgets('$name: the Shift history shows "$shown"', (tester) async {
      await pumpShell(tester, vehicle);
      expect(await shiftHistory(tester), shown);
    });
  }
}

final class _Duty implements DriverDutyGateway {
  _Duty(this.summary);

  final DriverDutySummary summary;

  @override
  Future<DriverDutySummary> fetchDuty() async => summary;

  @override
  Future<List<DriverAssignedTrip>> fetchTrips() async => const [];

  @override
  Future<DriverAssignedTrip> fetchTripDetail(String tripReference) =>
      throw UnimplementedError();
}
