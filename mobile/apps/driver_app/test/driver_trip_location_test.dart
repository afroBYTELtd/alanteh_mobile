import 'dart:async';

import 'package:asm_design_system/asm_design_system.dart';
import 'package:asm_maps/asm_maps.dart';
import 'package:asm_maps/testing.dart';
import 'package:driver_app/trip_progress/driver_trip_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:latlong2/latlong.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

// The driver's "you" dot: a balanced (Wi-Fi/cell) stream only - never a
// one-off fix that could wait without limit, never a high-power request -
// nothing at all without permission, and no requests while the app is in
// the background.
void main() {
  group('the phone source', () {
    late _RecordingGeolocator platform;
    const source = GeolocatorDriverDevicePositionSource();

    setUp(() {
      platform = _RecordingGeolocator();
      GeolocatorPlatform.instance = platform;
    });

    test('streams balanced positions, with no one-off fix', () async {
      platform.permission = LocationPermission.whileInUse;
      platform.positions = [_position(5.61, -0.18), _position(5.62, -0.17)];

      final positions = await source.positions().toList();

      expect(positions, const [LatLng(5.61, -0.18), LatLng(5.62, -0.17)]);
      expect(platform.streamSettings.single!.accuracy, LocationAccuracy.medium);
      expect(platform.currentPositionRequests, 0);
      expect(platform.permissionRequests, 0);
    });

    for (final permission in [
      LocationPermission.denied,
      LocationPermission.deniedForever,
      LocationPermission.unableToDetermine,
    ]) {
      test('$permission: no dot, no request, no prompt', () async {
        platform.permission = permission;

        expect(await source.positions().toList(), isEmpty);
        expect(platform.streamSettings, isEmpty);
        expect(platform.currentPositionRequests, 0);
        expect(platform.permissionRequests, 0);
      });
    }

    test('an error just stops the dot', () async {
      platform.permission = LocationPermission.always;
      platform.streamError = const LocationServiceDisabledException();

      expect(await source.positions().toList(), isEmpty);
    });
  });

  testWidgets('no position requests while the app is in the background', (
    tester,
  ) async {
    final source = _CountingSource();
    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.driver,
        home: Scaffold(
          body: DriverTripMap(
            pickup: const LatLng(5.6227, -0.1737),
            destination: null,
            legTarget: const LatLng(5.6227, -0.1737),
            devicePositionSource: source,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(asmFakeMapAnimationDuration);
    expect(source.active, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(source.active, 0);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(source.active, 1);
    expect(source.started, 2);

    await tester.pumpWidget(const SizedBox());
    expect(source.active, 0);
    expect(find.byType(AsmMapView), findsNothing);
  });
}

Position _position(double latitude, double longitude) {
  return Position(
    latitude: latitude,
    longitude: longitude,
    timestamp: DateTime.utc(2026, 10, 5, 9),
    accuracy: 40,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
}

final class _CountingSource implements DriverDevicePositionSource {
  int started = 0;
  int active = 0;

  @override
  Stream<LatLng> positions() {
    started += 1;
    late final StreamController<LatLng> controller;
    controller = StreamController<LatLng>(
      onListen: () => active += 1,
      onCancel: () => active -= 1,
    );
    return controller.stream;
  }
}

class _RecordingGeolocator extends GeolocatorPlatform
    with MockPlatformInterfaceMixin {
  LocationPermission permission = LocationPermission.denied;
  List<Position> positions = const [];
  Object? streamError;
  final streamSettings = <LocationSettings?>[];
  int currentPositionRequests = 0;
  int permissionRequests = 0;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() async {
    permissionRequests += 1;
    return permission;
  }

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) {
    streamSettings.add(locationSettings);
    final error = streamError;
    if (error != null) {
      return Stream<Position>.error(error);
    }
    return Stream<Position>.fromIterable(positions);
  }

  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) {
    currentPositionRequests += 1;
    return Future<Position>.value(_position(0, 0));
  }
}
