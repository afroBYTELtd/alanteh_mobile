import 'package:asm_design_system/asm_design_system.dart';
import 'package:asm_maps/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:passenger_app/ride_requests/ride_request_history.dart';
import 'package:passenger_app/tracking/ride_tracking_screen.dart';

// The tracking sheet covers the bottom of the full-screen map. Padding the
// map by the sheet's height keeps the Google logo in view and centres the
// camera (the vehicle, once known) in the part of the map that shows.
void main() {
  testWidgets('the tracking map is padded by the bottom sheet', (tester) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final record = PassengerRideRequestRecord(
      requestReference: 'RR-APP-PADDING',
      status: 'requested',
      pickupLocation: 'Solar Hotel',
      destination: 'Accra Airport',
      passengerCount: 1,
      createdAt: DateTime.utc(2026, 10, 2, 7),
      updatedAt: DateTime.utc(2026, 10, 2, 7, 5),
      hasMobileReceipt: true,
      tripCreated: false,
      latestStaffState: 'driver assigned',
      plateNumber: 'GT 1234-26',
      vehicleLatitude: 5.5980,
      vehicleLongitude: -0.1795,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: RideTrackingScreen(
          repository: _Static(record),
          requestReference: record.requestReference,
          initialRecord: record,
          pollInterval: const Duration(hours: 1),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    final map = tester.state<AsmFakeMapState>(find.byType(AsmFakeMap));
    final mapRect = tester.getRect(find.byType(AsmFakeMap));
    final sheetRect = tester.getRect(
      find.byKey(const Key('tracking-bottom-sheet')),
    );

    expect(sheetRect.bottom, mapRect.bottom);
    expect(map.view.padding, EdgeInsets.only(bottom: sheetRect.height));
    expect(map.view.initialCamera.center, const LatLng(5.5980, -0.1795));
  });
}

class _Static implements PassengerRideRequestHistoryRepository {
  _Static(this.record);

  final PassengerRideRequestRecord record;

  @override
  Future<List<PassengerRideRequestRecord>> fetchRequests() async => [record];

  @override
  Future<PassengerRideRequestRecord> fetchRequest(String reference) async =>
      record;
}
