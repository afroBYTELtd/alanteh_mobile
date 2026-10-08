import 'dart:async';
import 'dart:io';

import 'package:asm_design_system/asm_design_system.dart';
import 'package:asm_maps/asm_maps.dart';
import 'package:asm_maps/testing.dart';
import 'package:driver_app/safety/driver_trip_safety.dart';
import 'package:driver_app/trip_progress/driver_trip_map.dart';
import 'package:driver_app/trip_progress/driver_trip_visual_sequence.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

// The driver map shows only real data: the pickup pin from the trip's
// coordinates, the destination pin once the driver has accepted (the
// payload carries it from then), and the driver's own position from the
// phone. No invented route, pins, car, distance or time. Google's EEA
// terms allow a Google map with our own text and coordinates on it.
const _pickup = LatLng(5.6227, -0.1737);
const _destination = LatLng(5.6052, -0.1668);
const _driver = LatLng(5.6100, -0.1800);

void main() {
  testWidgets('before pickup: the real pickup pin, no route, no car', (
    tester,
  ) async {
    await _pumpTrip(tester, status: 'driver_accepted');

    expect(find.byType(AsmMapView), findsOneWidget);
    final map = _map(tester);
    expect(map.view.polylines, isEmpty);
    expect(_marker(map, AsmMapMarkerStyle.pickup)?.position, _pickup);
    expect(_marker(map, AsmMapMarkerStyle.vehicle), isNull);
  });

  testWidgets('the destination pin shows once the payload carries it', (
    tester,
  ) async {
    await _pumpTrip(tester, status: 'driver_accepted', destination: null);
    expect(_marker(_map(tester), AsmMapMarkerStyle.destination), isNull);

    await _pumpTrip(tester, status: 'driver_accepted');
    expect(
      _marker(_map(tester), AsmMapMarkerStyle.destination)?.position,
      _destination,
    );
  });

  testWidgets("the driver's own position comes from the phone", (tester) async {
    final positions = _Positions();
    await _pumpTrip(tester, status: 'driver_accepted', positions: positions);
    expect(_marker(_map(tester), AsmMapMarkerStyle.deviceLocation), isNull);

    positions.emit(_driver);
    await tester.pump();
    await tester.pump();
    expect(
      _marker(_map(tester), AsmMapMarkerStyle.deviceLocation)?.position,
      _driver,
    );

    const moved = LatLng(5.6150, -0.1760);
    positions.emit(moved);
    await tester.pump();
    await tester.pump();
    expect(
      _marker(_map(tester), AsmMapMarkerStyle.deviceLocation)?.position,
      moved,
    );
    await tester.pump(asmFakeMapAnimationDuration);
  });

  testWidgets('the camera is fitted to the leg and the driver', (tester) async {
    final positions = _Positions();
    await _pumpTrip(tester, status: 'driver_accepted', positions: positions);
    await tester.pump(asmFakeMapAnimationDuration);
    expect(_map(tester).fittedPoints, const [_pickup]);

    positions.emit(_driver);
    await tester.pump();
    await tester.pump();
    await tester.pump(asmFakeMapAnimationDuration);
    expect(_map(tester).fittedPoints, const [_pickup, _driver]);
  });

  testWidgets('a driver far from the pickup still sees the pickup', (
    tester,
  ) async {
    // 8 Oct phone check: the phone was in China, the pickup in Accra.
    const farAway = LatLng(31.30, 120.75);
    final positions = _Positions();
    await _pumpTrip(tester, status: 'driver_accepted', positions: positions);
    await tester.pump(asmFakeMapAnimationDuration);

    positions.emit(farAway);
    await tester.pump();
    await tester.pump();
    await tester.pump(asmFakeMapAnimationDuration);

    final map = _map(tester);
    expect(map.fittedPoints, const [_pickup, farAway]);
    expect(map.camera.center, _pickup);
    expect(_marker(map, AsmMapMarkerStyle.deviceLocation)?.position, farAway);
  });

  testWidgets('on the trip the leg is the destination', (tester) async {
    await _pumpTrip(tester, status: 'in_progress');
    await tester.pump(asmFakeMapAnimationDuration);

    final map = _map(tester);
    expect(_marker(map, AsmMapMarkerStyle.destination)?.position, _destination);
    expect(map.fittedPoints, const [_destination]);
  });

  testWidgets('without coordinates for the leg: a note and no Navigate', (
    tester,
  ) async {
    await _pumpTrip(tester, status: 'driver_accepted', pickup: null);

    expect(_marker(_map(tester), AsmMapMarkerStyle.pickup), isNull);
    expect(find.byKey(const Key('driver-trip-no-pin-note')), findsOneWidget);
    expect(
      find.text(
        'No map pin for this stop. Use the place name and the '
        "passenger's message.",
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('driver-trip-navigate')), findsNothing);
  });

  testWidgets('with coordinates there is no note', (tester) async {
    await _pumpTrip(tester, status: 'driver_accepted');
    expect(find.byKey(const Key('driver-trip-no-pin-note')), findsNothing);
  });

  testWidgets('no invented distance or time anywhere', (tester) async {
    for (final status in const [
      'driver_accepted',
      'in_progress',
      'completed_pending_review',
    ]) {
      await _pumpTrip(tester, status: status);
      expect(
        find.textContaining(RegExp(r'\d km')),
        findsNothing,
        reason: status,
      );
      expect(
        find.textContaining(RegExp(r'\d+ min')),
        findsNothing,
        reason: status,
      );
      expect(find.text('Distance'), findsNothing, reason: status);
      expect(find.text('Duration'), findsNothing, reason: status);
    }
  });

  testWidgets('our label, the message and Navigate stay', (tester) async {
    await _pumpTrip(tester, status: 'driver_accepted');

    expect(find.text('Near Accra Mall'), findsWidgets);
    expect(find.text('Main gate, blue kiosk'), findsOneWidget);
    expect(find.byKey(const Key('driver-trip-navigate')), findsOneWidget);
  });

  test('the OpenStreetMap map and the invented route are gone', () {
    expect(
      File('pubspec.yaml').readAsStringSync(),
      isNot(contains('flutter_map')),
    );
    expect(
      File('lib/trip_progress/driver_trip_route.dart').existsSync(),
      isFalse,
    );
    for (final file
        in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'))) {
      final source = file.readAsStringSync();
      expect(
        source,
        isNot(contains('tile.openstreetmap.org')),
        reason: file.path,
      );
      expect(
        source,
        isNot(contains('package:flutter_map/')),
        reason: file.path,
      );
    }
  });
}

AsmFakeMapState _map(WidgetTester tester) {
  return tester.state<AsmFakeMapState>(find.byType(AsmFakeMap));
}

AsmMapMarker? _marker(AsmFakeMapState map, AsmMapMarkerStyle style) {
  for (final marker in map.markers) {
    if (marker.style == style) {
      return marker;
    }
  }
  return null;
}

Future<void> _pumpTrip(
  WidgetTester tester, {
  required String status,
  LatLng? pickup = _pickup,
  LatLng? destination = _destination,
  _Positions? positions,
}) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(
    MaterialApp(
      theme: AsmThemes.driver,
      home: DriverTripVisualSequencePage(
        initialStatus: status,
        tripReference: 'TRIP-MAP-1',
        pickupLocation: 'Near Accra Mall',
        destination: 'Airport, Terminal 3',
        passengerCount: 1,
        passengerNote: 'Main gate, blue kiosk',
        pickupLatitude: pickup?.latitude,
        pickupLongitude: pickup?.longitude,
        destinationLatitude: destination?.latitude,
        destinationLongitude: destination?.longitude,
        devicePositionSource: positions ?? _Positions(),
        safetyUriLauncher: const _NoLauncher(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  // The map's camera fit animates; let it finish.
  await tester.pump(asmFakeMapAnimationDuration);
}

final class _Positions implements DriverDevicePositionSource {
  final _controller = StreamController<LatLng>.broadcast();

  @override
  Stream<LatLng> positions() => _controller.stream;

  void emit(LatLng position) => _controller.add(position);
}

final class _NoLauncher implements DriverSafetyUriLauncher {
  const _NoLauncher();

  @override
  Future<bool> canLaunch(Uri uri) async => true;

  @override
  Future<bool> launch(Uri uri) async => true;
}
