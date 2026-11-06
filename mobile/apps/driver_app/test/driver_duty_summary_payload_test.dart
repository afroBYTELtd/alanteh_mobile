// F3 (phone session 6): Work's "Driver duty summary" showed Driver, Phone,
// Status and Vehicle as "Not assigned yet". The server (GET /api/driver/me/,
// DriverDutySummaryAPIView at backend df18738, api_driver.py 725-768) sends
// them inside "driver", the phone already masked as "phone_masked".

import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:driver_app/driver_duty_trips.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every key the server view sends, in its own formats. Values are the test
/// driver's as Control Center showed them (31 Oct and 6 Nov); phone_masked
/// is what the server's _mask_phone makes of its phone number.
Map<String, Object?> _serverAnswer({
  String? vehicleReference = 'ALANTEH-DEMO-VEH-01',
}) => <String, Object?>{
  'driver': <String, Object?>{
    'driver_reference': 'QA-DRV-001',
    'display_name': 'Production QA Driver',
    'phone_masked': '+233******567',
    'status': 'active',
    'vehicle_reference': vehicleReference,
  },
  'duty': <String, Object?>{
    'duty_status': 'online',
    'duty_since': '2026-10-30T05:51:47+00:00',
    'shift_check_today': false,
    'shift_check_today_reference': null,
    'can_receive_assignments': false,
    'active_trip_count': 0,
    'assigned_trip_count': 18,
  },
};

void main() {
  group('the server answer is read', () {
    test('all five driver values come from the nested "driver" object', () {
      final summary = DriverDutySummary.fromJson(_serverAnswer());

      expect(summary.driverReference, 'QA-DRV-001');
      expect(summary.displayName, 'Production QA Driver');
      expect(summary.phoneMasked, '+233******567');
      expect(summary.status, 'active');
      expect(summary.assignedVehicleReference, 'ALANTEH-DEMO-VEH-01');
    });

    test('the duty values are unchanged', () {
      final summary = DriverDutySummary.fromJson(_serverAnswer());

      expect(summary.dutyStatus, 'online');
      expect(summary.dutySince, DateTime.utc(2026, 10, 30, 5, 51, 47));
      expect(summary.shiftCheckToday, isFalse);
      expect(summary.shiftCheckTodayReference, isNull);
      expect(summary.canReceiveAssignments, isFalse);
      expect(summary.activeTripCount, 0);
      expect(summary.assignedTripCount, 18);
    });

    test('no vehicle: null', () {
      final summary = DriverDutySummary.fromJson(
        _serverAnswer(vehicleReference: null),
      );

      expect(summary.assignedVehicleReference, isNull);
    });

    test('top-level keys, which the server never sends, are not read', () {
      final summary = DriverDutySummary.fromJson(const <String, Object?>{
        'display_name': 'ROOT',
        'name': 'ROOT',
        'phone': '+233000000000',
        'phone_masked': '+233******000',
        'status': 'active',
        'vehicle_reference': 'ROOT-VEH',
        'vehicle': 'ROOT-VEH',
      });

      expect(summary.displayName, isNull);
      expect(summary.phoneMasked, isNull);
      expect(summary.status, isNull);
      expect(summary.assignedVehicleReference, isNull);
    });

    test('a duty change keeps the four values', () {
      final summary = DriverDutySummary.fromJson(_serverAnswer())
          .withDutyTransition(
            DriverDutyTransition(
              dutyStatus: 'offline',
              since: DateTime.utc(2026, 11, 6),
            ),
          );

      expect(summary.dutyStatus, 'offline');
      expect(summary.displayName, 'Production QA Driver');
      expect(summary.phoneMasked, '+233******567');
      expect(summary.status, 'active');
      expect(summary.assignedVehicleReference, 'ALANTEH-DEMO-VEH-01');
    });

    test('the duty gateway decodes the server answer the same way', () async {
      final gateway = AsmDriverDutyGateway.withApiClient(
        apiClient: _ServerAnswerClient(_serverAnswer()),
      );

      final summary = await gateway.fetchDuty();

      expect(summary.displayName, 'Production QA Driver');
      expect(summary.phoneMasked, '+233******567');
      expect(summary.status, 'active');
      expect(summary.assignedVehicleReference, 'ALANTEH-DEMO-VEH-01');
    });
  });

  group("Work's Driver duty summary panel", () {
    testWidgets('shows the four values from the server answer, the phone as '
        'the server masked it', (tester) async {
      await _pumpPanel(tester, DriverDutySummary.fromJson(_serverAnswer()));

      expect(_detail(tester, 'Driver'), 'Production QA Driver');
      expect(_detail(tester, 'Driver reference'), 'QA-DRV-001');
      expect(_detail(tester, 'Phone'), '+233******567');
      expect(_detail(tester, 'Status'), 'Active');
      expect(_detail(tester, 'Vehicle'), 'ALANTEH-DEMO-VEH-01');
    });

    testWidgets('no vehicle: "Not assigned yet"', (tester) async {
      await _pumpPanel(
        tester,
        DriverDutySummary.fromJson(_serverAnswer(vehicleReference: null)),
      );

      expect(_detail(tester, 'Vehicle'), driverEmptyValue);
      expect(_detail(tester, 'Phone'), '+233******567');
    });
  });
}

Future<void> _pumpPanel(WidgetTester tester, DriverDutySummary summary) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AsmThemes.driver,
      home: Scaffold(
        body: SingleChildScrollView(
          child: DriverDutySummaryPanel(summary: summary),
        ),
      ),
    ),
  );
}

/// The value next to [label] in the duty panel.
String? _detail(WidgetTester tester, String label) {
  final row = find.ancestor(of: find.text(label), matching: find.byType(Row));
  final texts = find
      .descendant(of: row.first, matching: find.byType(Text))
      .evaluate()
      .map((element) => (element.widget as Text).data)
      .where((text) => text != label)
      .toList();
  return texts.isEmpty ? null : texts.single;
}

final class _ServerAnswerClient implements DriverDutyApiClient {
  _ServerAnswerClient(this.answer);

  final Map<String, Object?> answer;

  @override
  Future<ApiResponse<T>> get<T>(String path, {JsonDecoder<T>? decoder}) async {
    expect(path, driverDutyPath);
    return ApiResponse<T>.success(decoder!(answer), statusCode: 200);
  }
}
