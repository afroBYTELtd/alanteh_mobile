import 'package:asm_design_system/asm_design_system.dart';
import 'package:asm_maps/asm_maps.dart';
import 'package:asm_maps/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:passenger_app/ride_requests/ride_request_history.dart';
import 'package:passenger_app/tracking/ride_tracking_screen.dart';

// Ride data has no pickup or destination coordinates yet, and no road route.
// The tracking map used to stand in fixed Accra points and straight lines
// between them, which looked real and was not. Until real data arrives the
// map shows only what is known: the vehicle's last reported position.
const _vehicle = LatLng(5.5980, -0.1795);

void main() {
  for (final staffState in <String>[
    'driver assigned',
    'vehicle en route',
    'driver arrived',
    'trip in progress',
    'trip completed',
  ]) {
    for (final withVehicle in <bool>[true, false]) {
      testWidgets(
        '$staffState, ${withVehicle ? 'with' : 'without'} a vehicle: '
        'no lines and no stand-in points',
        (tester) async {
          await _pumpTracking(
            tester,
            _record(staffState, vehicle: withVehicle ? _vehicle : null),
          );

          final map = tester.state<AsmFakeMapState>(find.byType(AsmFakeMap));
          expect(map.view.polylines, isEmpty);
          expect(
            map.markers.map((marker) => (marker.style, marker.position)),
            withVehicle
                ? [(AsmMapMarkerStyle.vehicle, _vehicle)]
                : isEmpty,
          );
        },
      );
    }
  }
}

PassengerRideRequestRecord _record(String staffState, {LatLng? vehicle}) {
  return PassengerRideRequestRecord(
    requestReference: 'RR-APP-HONEST',
    status: 'requested',
    pickupLocation: 'Solar Hotel',
    destination: 'Accra Airport',
    passengerCount: 1,
    createdAt: DateTime.utc(2026, 10, 2, 7),
    updatedAt: DateTime.utc(2026, 10, 2, 7, 5),
    hasMobileReceipt: true,
    tripCreated: false,
    latestStaffState: staffState,
    plateNumber: 'GT 1234-26',
    vehicleLatitude: vehicle?.latitude,
    vehicleLongitude: vehicle?.longitude,
  );
}

Future<void> _pumpTracking(
  WidgetTester tester,
  PassengerRideRequestRecord record,
) async {
  tester.view.physicalSize = const Size(430, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

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
