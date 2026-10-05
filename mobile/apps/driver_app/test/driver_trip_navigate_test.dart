import 'package:asm_design_system/asm_design_system.dart';
import 'package:asm_maps/testing.dart';
import 'package:driver_app/driver_duty_trips.dart';
import 'package:driver_app/safety/driver_trip_safety.dart';
import 'package:driver_app/trip_progress/driver_trip_visual_sequence.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Google's EEA terms keep Places text off any map, so beside the trip map
// the driver reads our own label and the passenger's message, and
// Navigate hands the coordinates to the Google Maps app - coordinates are
// free to use on any screen.
void main() {
  group('trip coordinates', () {
    test('are read from the trip payload', () {
      final trip = DriverAssignedTrip.fromJson(const {
        'trip_reference': 'TRIP-NAV-1',
        'pickup_location': 'Near Accra Mall',
        'pickup_latitude': 5.6227,
        'pickup_longitude': -0.1737,
        'destination': 'Airport, Terminal 3',
        'destination_latitude': 5.6052,
        'destination_longitude': -0.1668,
      });

      expect(trip.pickupLatitude, 5.6227);
      expect(trip.pickupLongitude, -0.1737);
      expect(trip.destinationLatitude, 5.6052);
      expect(trip.destinationLongitude, -0.1668);
    });

    test('are absent when not sent, null, or not a coordinate pair', () {
      for (final extra in <Map<String, Object?>>[
        const {},
        const {'pickup_latitude': null, 'pickup_longitude': null},
        const {'pickup_latitude': 5.6227},
        const {'pickup_latitude': 'north', 'pickup_longitude': -0.17},
        const {'pickup_latitude': 95.0, 'pickup_longitude': -0.17},
      ]) {
        final trip = DriverAssignedTrip.fromJson({
          'trip_reference': 'TRIP-NAV-2',
          ...extra,
        });
        expect(trip.pickupLatitude, isNull, reason: '$extra');
        expect(trip.pickupLongitude, isNull, reason: '$extra');
      }
    });
  });

  group('Navigate', () {
    testWidgets('before pickup it opens Google Maps at the pickup', (
      tester,
    ) async {
      final launcher = _RecordingLauncher();
      await _pumpTrip(tester, status: 'driver_accepted', launcher: launcher);

      expect(find.text('Near Accra Mall'), findsWidgets);
      expect(find.text('Main gate, blue kiosk'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('driver-trip-navigate')));
      await tester.tap(find.byKey(const Key('driver-trip-navigate')));
      await tester.pump();

      expect(launcher.launched, [
        Uri.parse(
          'https://www.google.com/maps/dir/?api=1'
          '&destination=5.6227,-0.1737&travelmode=driving',
        ),
      ]);
    });

    testWidgets('on the trip it opens Google Maps at the destination', (
      tester,
    ) async {
      final launcher = _RecordingLauncher();
      await _pumpTrip(tester, status: 'in_progress', launcher: launcher);

      await tester.ensureVisible(find.byKey(const Key('driver-trip-navigate')));
      await tester.tap(find.byKey(const Key('driver-trip-navigate')));
      await tester.pump();

      expect(
        launcher.launched.single.queryParameters['destination'],
        '5.6052,-0.1668',
      );
    });

    testWidgets('without coordinates for the leg there is no Navigate', (
      tester,
    ) async {
      await _pumpTrip(
        tester,
        status: 'in_progress',
        launcher: _RecordingLauncher(),
        destination: null,
      );

      expect(find.byKey(const Key('driver-trip-navigate')), findsNothing);
    });

    testWidgets('a finished trip has no Navigate', (tester) async {
      await _pumpTrip(
        tester,
        status: 'completed_pending_review',
        launcher: _RecordingLauncher(),
      );

      expect(find.byKey(const Key('driver-trip-navigate')), findsNothing);
    });
  });
}

Future<void> _pumpTrip(
  WidgetTester tester, {
  required String status,
  required _RecordingLauncher launcher,
  (double, double)? destination = (5.6052, -0.1668),
}) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AsmThemes.driver,
      home: DriverTripVisualSequencePage(
        initialStatus: status,
        tripReference: 'TRIP-NAV-1',
        pickupLocation: 'Near Accra Mall',
        destination: 'Airport, Terminal 3',
        passengerCount: 1,
        passengerNote: 'Main gate, blue kiosk',
        pickupLatitude: 5.6227,
        pickupLongitude: -0.1737,
        destinationLatitude: destination?.$1,
        destinationLongitude: destination?.$2,
        safetyUriLauncher: launcher,
      ),
    ),
  );
  await tester.pump();
  // The map's camera fit animates; let it finish.
  await tester.pump(asmFakeMapAnimationDuration);
}

final class _RecordingLauncher implements DriverSafetyUriLauncher {
  final launched = <Uri>[];

  @override
  Future<bool> canLaunch(Uri uri) async => true;

  @override
  Future<bool> launch(Uri uri) async {
    launched.add(uri);
    return true;
  }
}
