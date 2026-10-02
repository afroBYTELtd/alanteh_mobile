import 'dart:async';

import 'package:asm_app_config/asm_app_config.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:asm_maps/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:passenger_app/passenger_home.dart';

// Measured on the Android test phone indoors: a high-accuracy (GPS) fix
// never arrived, while a balanced (Wi-Fi/cell) fix took 33-49 ms. Recenter
// and the blue dot both waited on the GPS fix with no time limit, so the
// blue dot never appeared and recenter never moved. These tests pin the
// replacement: answer from what is known, then refine, within limits, and
// never go silent.
const _osu = LatLng(5.5560, -0.1820);
const _osuPrecise = LatLng(5.5571, -0.1829); // ~160 m from _osu
const _airport = LatLng(5.6050, -0.1668);

PassengerDevicePosition _fix(
  LatLng at, {
  double accuracy = 60,
  Duration age = Duration.zero,
}) {
  return PassengerDevicePosition(
    coordinates: at,
    accuracyMetres: accuracy,
    timestamp: DateTime.now().subtract(age),
  );
}

void main() {
  test('limits and freshness are the approved numbers', () {
    expect(passengerHomeRecentPositionMaxAge, const Duration(seconds: 60));
    expect(passengerHomeRecentPositionMaxAccuracyMetres, 150);
    expect(passengerHomeQuickFixLimit, const Duration(seconds: 5));
    expect(passengerHomePreciseFixLimit, const Duration(seconds: 15));
  });

  group('blue dot', () {
    testWidgets('appears from the stream without waiting for any fix', (
      tester,
    ) async {
      final location = _ScriptedLocation();
      await _pumpHome(tester, location: location);

      expect(location.activeStreams, 1);
      expect(location.requests, isEmpty);
      location.emit(_fix(_osu));
      await _deliver(tester);

      expect(_blueDot(tester), _osu);
    });

    testWidgets('shows a recent last-known position at once', (tester) async {
      final location = _ScriptedLocation(lastKnown: _fix(_osu));
      await _pumpHome(tester, location: location);

      expect(_blueDot(tester), _osu);
    });

    testWidgets('ignores a last-known position that is old or vague', (
      tester,
    ) async {
      for (final stale in <PassengerDevicePosition>[
        _fix(_osu, age: const Duration(seconds: 61)),
        _fix(_osu, accuracy: 151),
      ]) {
        await _pumpHome(tester, location: _ScriptedLocation(lastKnown: stale));
        expect(_blueDot(tester), isNull);
      }
    });

    testWidgets('another stream error restarts it after a growing pause', (
      tester,
    ) async {
      final location = _ScriptedLocation();
      await _pumpHome(tester, location: location);

      location.streamError(PassengerLocationFailure.unavailable);
      await _deliver(tester);
      expect(location.activeStreams, 0);
      await tester.pump(const Duration(milliseconds: 1999));
      expect(location.streamsStarted, 1);
      await tester.pump(const Duration(milliseconds: 1));
      expect(location.streamsStarted, 2);
      expect(location.activeStreams, 1);

      location.streamError(PassengerLocationFailure.unavailable);
      await tester.pump(const Duration(milliseconds: 3999));
      expect(location.streamsStarted, 2);
      await tester.pump(const Duration(milliseconds: 1));
      expect(location.streamsStarted, 3);
    });

    testWidgets('background stops the stream; returning starts exactly one', (
      tester,
    ) async {
      final location = _ScriptedLocation();
      await _pumpHome(tester, location: location);

      for (var cycle = 0; cycle < 3; cycle += 1) {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();
        expect(location.activeStreams, 0);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        await tester.pump();
        expect(location.activeStreams, 1);
      }
      expect(location.streamsStarted, 4);
      expect(location.requests, isEmpty);
    });
  });

  group('recenter', () {
    testWidgets('with a recent position moves at once, then refines', (
      tester,
    ) async {
      final location = _ScriptedLocation();
      await _pumpHome(tester, location: location);
      location.emit(_fix(_osu));
      await _deliver(tester);

      await _tapRecenter(tester);
      await tester.pump(asmFakeMapAnimationDuration);

      expect(_map(tester).camera.center, _osu);
      expect(location.requests, [
        (precise: true, limit: passengerHomePreciseFixLimit),
      ]);
      expect(find.byKey(const Key('passenger-home-locating')), findsNothing);

      location.answer(0, _fix(_osuPrecise, accuracy: 8));
      await tester.pump();
      await tester.pump(asmFakeMapAnimationDuration);
      expect(_map(tester).camera.center, _osuPrecise);
    });

    testWidgets('without one, says it is locating and asks within limits', (
      tester,
    ) async {
      final location = _ScriptedLocation();
      await _pumpHome(tester, location: location);

      await _tapRecenter(tester);

      expect(find.text('Finding your location…'), findsOneWidget);
      expect(location.requests, [
        (precise: false, limit: passengerHomeQuickFixLimit),
        (precise: true, limit: passengerHomePreciseFixLimit),
      ]);

      location.answer(0, _fix(_osu, accuracy: 100));
      await tester.pump();
      await tester.pump(asmFakeMapAnimationDuration);

      expect(_map(tester).camera.center, _osu);
      expect(_blueDot(tester), _osu);
      expect(find.text('Finding your location…'), findsNothing);
    });

    testWidgets('a precise fix still moves the map if the quick one fails', (
      tester,
    ) async {
      final location = _ScriptedLocation();
      await _pumpHome(tester, location: location);
      await _tapRecenter(tester);

      location.fail(0, PassengerLocationFailure.timedOut);
      await tester.pump();
      expect(find.text('Finding your location…'), findsOneWidget);

      location.answer(1, _fix(_osuPrecise, accuracy: 8));
      await tester.pump();
      await tester.pump(asmFakeMapAnimationDuration);
      expect(_map(tester).camera.center, _osuPrecise);
      expect(find.text('Finding your location…'), findsNothing);
    });

    testWidgets('when nothing arrives, says so and leaves the map alone', (
      tester,
    ) async {
      final location = _ScriptedLocation();
      await _pumpHome(tester, location: location);
      await _tapRecenter(tester);

      location.fail(0, PassengerLocationFailure.timedOut);
      location.fail(1, PassengerLocationFailure.timedOut);
      await tester.pump();
      await tester.pump(asmFakeMapAnimationDuration);

      expect(_map(tester).camera.center, passengerHomePickupDefaultCenter);
      expect(find.text('Finding your location…'), findsNothing);
      expect(
        find.text("Couldn't find your location. Move the pin to your pickup."),
        findsOneWidget,
      );
    });

    testWidgets('a drag after recenter cancels the refinement', (tester) async {
      final location = _ScriptedLocation();
      await _pumpHome(tester, location: location);
      location.emit(_fix(_osu));
      await _deliver(tester);
      await _tapRecenter(tester);
      await tester.pump(asmFakeMapAnimationDuration);

      _map(tester)
        ..dragTo(_airport)
        ..release();
      await tester.pump();
      location.answer(0, _fix(_osuPrecise, accuracy: 8));
      await tester.pump();
      await tester.pump(asmFakeMapAnimationDuration);

      expect(_map(tester).camera.center, _airport);
    });

    testWidgets('confirming the pickup cancels the refinement', (tester) async {
      final location = _ScriptedLocation();
      final selections = <PassengerPickupSelection>[];
      await _pumpHome(
        tester,
        location: location,
        onConfirmPickup: selections.add,
      );
      location.emit(_fix(_osu));
      await _deliver(tester);
      await _tapRecenter(tester);
      await tester.pump(asmFakeMapAnimationDuration);

      await tester.tap(find.byKey(const Key('confirm-pickup')));
      await tester.pump();
      location.answer(0, _fix(_osuPrecise, accuracy: 8));
      await tester.pump();
      await tester.pump(asmFakeMapAnimationDuration);

      expect(_map(tester).camera.center, _osu);
      expect(selections.single.coordinates, _osu);
    });

    testWidgets('a search after recenter cancels the refinement', (
      tester,
    ) async {
      final location = _ScriptedLocation();
      await _pumpHome(
        tester,
        location: location,
        onOpenPickupSearch: (_) async => 'Searched pickup',
      );
      location.emit(_fix(_osu));
      await _deliver(tester);
      await _tapRecenter(tester);
      await tester.pump(asmFakeMapAnimationDuration);

      await tester.tap(
        find.byKey(const Key('passenger-home-pickup-address-row')),
      );
      await tester.pump();
      location.answer(0, _fix(_osuPrecise, accuracy: 8));
      await tester.pump();
      await tester.pump(asmFakeMapAnimationDuration);

      expect(_map(tester).camera.center, _osu);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('confirm-pickup')))
            .onPressed,
        isNull,
      );
    });

    testWidgets('the pickup after a recenter is where the camera went', (
      tester,
    ) async {
      final location = _ScriptedLocation();
      final selections = <PassengerPickupSelection>[];
      await _pumpHome(
        tester,
        location: location,
        onConfirmPickup: selections.add,
      );
      await _tapRecenter(tester);
      location.answer(0, _fix(_osu, accuracy: 100));
      location.fail(1, PassengerLocationFailure.timedOut);
      await tester.pump();
      await tester.pump(asmFakeMapAnimationDuration);

      await tester.tap(find.byKey(const Key('confirm-pickup')));
      await tester.pump();
      expect(selections.single.coordinates, _osu);
    });

    testWidgets('with location services off, offers to turn them on', (
      tester,
    ) async {
      final location = _ScriptedLocation();
      final permission = _Permission(
        PassengerHomeLocationPermissionState.granted,
      );
      await _pumpHome(tester, location: location, permission: permission);
      permission.state = PassengerHomeLocationPermissionState.servicesDisabled;

      await _tapRecenter(tester);

      expect(location.requests, isEmpty);
      expect(find.text('Finding your location…'), findsNothing);
      expect(
        find.text('Location is turned off. Turn it on to find where you are.'),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const Key('passenger-home-location-settings-action')),
      );
      await tester.pump();
      expect(permission.openLocationSettingsCalls, 1);
    });
  });

  testWidgets('the location message sits fully above the bottom sheet', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final location = _ScriptedLocation();
    await _pumpHome(tester, location: location);
    await _tapRecenter(tester);
    location.fail(0, PassengerLocationFailure.timedOut);
    location.fail(1, PassengerLocationFailure.timedOut);
    await tester.pump();

    final message = tester.getRect(
      find.byKey(const Key('passenger-home-location-message')),
    );
    final sheet = tester.getRect(
      find.byKey(const Key('passenger-home-bottom-sheet')),
    );
    expect(message.bottom, lessThanOrEqualTo(sheet.top));
  });

  testWidgets('recenter restarts a stream stopped while location was off', (
    tester,
  ) async {
    final location = _ScriptedLocation();
    await _pumpHome(tester, location: location);
    location.streamError(PassengerLocationFailure.servicesOff);
    await _deliver(tester);
    expect(location.activeStreams, 0);

    // Location is back on, but the app never left the screen.
    await _tapRecenter(tester);

    expect(location.activeStreams, 1);
    expect(location.streamsStarted, 2);
  });

  group('permission revoked while the app is running', () {
    testWidgets('the stream reporting it shows the banner and stops', (
      tester,
    ) async {
      final location = _ScriptedLocation();
      await _pumpHome(tester, location: location);

      location.streamError(PassengerLocationFailure.permissionDenied);
      await _deliver(tester);
      await tester.pump(const Duration(seconds: 70));

      expect(
        find.byKey(const Key('passenger-home-location-recovery')),
        findsOneWidget,
      );
      expect(location.streamsStarted, 1);
      expect(location.activeStreams, 0);
    });

    testWidgets('recenter after revocation shows the banner, no spinner', (
      tester,
    ) async {
      final location = _ScriptedLocation();
      final permission = _Permission(
        PassengerHomeLocationPermissionState.granted,
      );
      await _pumpHome(tester, location: location, permission: permission);
      permission.state = PassengerHomeLocationPermissionState.denied;

      await _tapRecenter(tester);

      expect(
        find.byKey(const Key('passenger-home-location-recovery')),
        findsOneWidget,
      );
      expect(find.text('Finding your location…'), findsNothing);
      expect(location.requests, isEmpty);
    });

    testWidgets('a fix refused for permission shows the banner, no spinner', (
      tester,
    ) async {
      final location = _ScriptedLocation();
      await _pumpHome(tester, location: location);
      await _tapRecenter(tester);

      location.fail(0, PassengerLocationFailure.permissionDenied);
      location.fail(1, PassengerLocationFailure.permissionDenied);
      await tester.pump();

      expect(
        find.byKey(const Key('passenger-home-location-recovery')),
        findsOneWidget,
      );
      expect(find.text('Finding your location…'), findsNothing);
      expect(
        find.text("Couldn't find your location. Move the pin to your pickup."),
        findsNothing,
      );
    });

    testWidgets('granting it again clears the banner and restarts the dot', (
      tester,
    ) async {
      final location = _ScriptedLocation();
      final permission = _Permission(
        PassengerHomeLocationPermissionState.granted,
      );
      await _pumpHome(tester, location: location, permission: permission);
      location.streamError(PassengerLocationFailure.permissionDenied);
      await _deliver(tester);
      expect(
        find.byKey(const Key('passenger-home-location-recovery')),
        findsOneWidget,
      );

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const Key('passenger-home-location-recovery')),
        findsNothing,
      );
      expect(location.activeStreams, 1);
    });
  });
}

AsmFakeMapState _map(WidgetTester tester) {
  return tester.state<AsmFakeMapState>(find.byType(AsmFakeMap));
}

LatLng? _blueDot(WidgetTester tester) {
  for (final marker in _map(tester).markers) {
    if (marker.id == 'passenger-home-device-blue-dot') {
      return marker.position;
    }
  }
  return null;
}

// A stream event reaches the screen in the frame after it is sent.
Future<void> _deliver(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

Future<void> _tapRecenter(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('passenger-home-recenter')));
  await tester.pump();
  await tester.pump();
}

Future<void> _pumpHome(
  WidgetTester tester, {
  required _ScriptedLocation location,
  _Permission? permission,
  ValueChanged<PassengerPickupSelection>? onConfirmPickup,
  PassengerHomePickupSearch? onOpenPickupSearch,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AsmThemes.passenger,
      home: Scaffold(
        body: PassengerHome(
          market: AsmAppConfig.localGhana.market,
          localQaEnabled: true,
          pickupDescription: null,
          destinationDescription: null,
          canContinue: false,
          locationsMatch: false,
          canSwap: false,
          hasRoute: false,
          onChoosePickup: () {},
          onChooseDestination: () {},
          onContinue: () {},
          onOpenRequests: () {},
          onSwap: () {},
          onClear: () {},
          onOpenPickupSearch: onOpenPickupSearch ?? (_) async => null,
          onConfirmPickup: onConfirmPickup ?? (_) {},
          reverseGeocoder: const _NoGeocoder(),
          deviceLocationService: location,
          locationPermissionService:
              permission ??
              _Permission(PassengerHomeLocationPermissionState.granted),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

class _ScriptedLocation implements PassengerHomeDeviceLocationService {
  _ScriptedLocation({this.lastKnown});

  final PassengerDevicePosition? lastKnown;
  final requests = <({bool precise, Duration limit})>[];
  final _answers = <Completer<PassengerDevicePosition>>[];
  StreamController<PassengerDevicePosition>? _stream;
  int streamsStarted = 0;
  int activeStreams = 0;

  @override
  Future<PassengerDevicePosition?> lastKnownPosition() async => lastKnown;

  @override
  Future<PassengerDevicePosition> currentPosition({
    required bool precise,
    required Duration timeLimit,
  }) {
    requests.add((precise: precise, limit: timeLimit));
    final answer = Completer<PassengerDevicePosition>();
    _answers.add(answer);
    return answer.future;
  }

  @override
  Stream<PassengerDevicePosition> get positionStream {
    streamsStarted += 1;
    final controller = StreamController<PassengerDevicePosition>(
      onListen: () => activeStreams += 1,
      onCancel: () => activeStreams -= 1,
    );
    _stream = controller;
    return controller.stream;
  }

  void answer(int request, PassengerDevicePosition position) =>
      _answers[request].complete(position);

  void fail(int request, PassengerLocationFailure failure) =>
      _answers[request].completeError(PassengerLocationException(failure));

  void emit(PassengerDevicePosition position) => _stream!.add(position);

  void streamError(PassengerLocationFailure failure) =>
      _stream!.addError(PassengerLocationException(failure));
}

class _Permission implements PassengerHomeLocationPermissionService {
  _Permission(this.state);

  PassengerHomeLocationPermissionState state;
  int openLocationSettingsCalls = 0;

  @override
  Future<PassengerHomeLocationPermissionState> ensurePermission() async =>
      state;

  @override
  Future<bool> openAppSettings() async => true;

  @override
  Future<bool> openLocationSettings() async {
    openLocationSettingsCalls += 1;
    return true;
  }
}

class _NoGeocoder implements PassengerHomeReverseGeocoder {
  const _NoGeocoder();

  @override
  Future<String> reverseGeocode(LatLng coordinates) async => 'Somewhere';
}
