import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:latlong2/latlong.dart';
import 'package:passenger_app/passenger_home.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

// The adapter between the home screen and the geolocator plugin: which
// accuracy and time limit it asks for, and how plugin errors are named.
void main() {
  late _RecordingGeolocator platform;
  const service = GeolocatorPassengerHomeDeviceLocationService();

  setUp(() {
    platform = _RecordingGeolocator();
    GeolocatorPlatform.instance = platform;
  });

  test('a quick fix asks for balanced accuracy within its limit', () async {
    final fix = await service.currentPosition(
      precise: false,
      timeLimit: const Duration(seconds: 5),
    );

    final settings = platform.currentSettings.single!;
    expect(settings.accuracy, LocationAccuracy.medium);
    expect(settings.timeLimit, const Duration(seconds: 5));
    expect(fix.coordinates, const LatLng(5.5560, -0.1820));
    expect(fix.accuracyMetres, 60);
    expect(fix.timestamp, DateTime.utc(2026, 10, 3, 9));
  });

  test('a precise fix asks for high accuracy within its limit', () async {
    await service.currentPosition(
      precise: true,
      timeLimit: const Duration(seconds: 15),
    );

    final settings = platform.currentSettings.single!;
    expect(settings.accuracy, LocationAccuracy.high);
    expect(settings.timeLimit, const Duration(seconds: 15));
  });

  test('plugin errors become named failures', () async {
    final cases = <Object, PassengerLocationFailure>{
      const PermissionDeniedException('revoked'):
          PassengerLocationFailure.permissionDenied,
      const LocationServiceDisabledException():
          PassengerLocationFailure.servicesOff,
      TimeoutException('no fix'): PassengerLocationFailure.timedOut,
      StateError('anything else'): PassengerLocationFailure.unavailable,
    };
    for (final entry in cases.entries) {
      platform.currentError = entry.key;
      await expectLater(
        service.currentPosition(
          precise: true,
          timeLimit: const Duration(seconds: 15),
        ),
        throwsA(
          isA<PassengerLocationException>().having(
            (e) => e.failure,
            'failure',
            entry.value,
          ),
        ),
        reason: '${entry.key}',
      );
    }
  });

  test('the stream asks for balanced accuracy and names its errors', () async {
    final events = <Object>[];
    final done = Completer<void>();
    service.positionStream.listen(
      (fix) => events.add(fix.coordinates),
      onError: (Object error) => events.add(error),
      onDone: done.complete,
    );
    platform.streamController.add(_position);
    platform.streamController.addError(
      const PermissionDeniedException('revoked'),
    );
    await platform.streamController.close();
    await done.future;

    final settings = platform.streamSettings!;
    expect(settings.accuracy, LocationAccuracy.medium);
    expect(settings.distanceFilter, 10);
    expect(events.first, const LatLng(5.5560, -0.1820));
    expect(
      (events.last as PassengerLocationException).failure,
      PassengerLocationFailure.permissionDenied,
    );
  });

  test('last known position: mapped, and null rather than an error', () async {
    expect(
      (await service.lastKnownPosition())!.coordinates,
      const LatLng(5.5560, -0.1820),
    );
    platform.lastKnownError = StateError('plugin missing');
    expect(await service.lastKnownPosition(), isNull);
  });
}

final _position = Position(
  latitude: 5.5560,
  longitude: -0.1820,
  timestamp: DateTime.utc(2026, 10, 3, 9),
  accuracy: 60,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

class _RecordingGeolocator extends GeolocatorPlatform
    with MockPlatformInterfaceMixin {
  final currentSettings = <LocationSettings?>[];
  LocationSettings? streamSettings;
  Object? currentError;
  Object? lastKnownError;
  final streamController = StreamController<Position>();

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async {
    currentSettings.add(locationSettings);
    if (currentError != null) {
      throw currentError!;
    }
    return _position;
  }

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) {
    streamSettings = locationSettings;
    return streamController.stream;
  }

  @override
  Future<Position?> getLastKnownPosition({
    bool forceLocationManager = false,
  }) async {
    if (lastKnownError != null) {
      throw lastKnownError!;
    }
    return _position;
  }
}
