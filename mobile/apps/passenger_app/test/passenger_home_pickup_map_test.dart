import 'dart:convert';
import 'dart:io';

import 'package:asm_app_config/asm_app_config.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:passenger_app/booking/booking_page.dart';
import 'package:passenger_app/location/location_search_page.dart';
import 'package:passenger_app/passenger_home.dart';
import 'package:passenger_app/passenger_shell.dart';

void main() {
  testWidgets('test_pin_widget_is_flutter_widget_not_map_marker', (
    tester,
  ) async {
    final geocoder = _FakeReverseGeocoder(address: 'Accra pickup');
    await _pumpHome(tester, geocoder: geocoder);

    final centrePin = find.byKey(const Key('passenger-home-centre-pin'));
    expect(centrePin, findsOneWidget);
    expect(
      find.descendant(of: find.byType(FlutterMap), matching: centrePin),
      findsNothing,
    );

    final map = tester.widget<FlutterMap>(
      find.byKey(const Key('passenger-home-flutter-map')),
    );
    expect(map.children.whereType<MarkerLayer>(), hasLength(1));
    final markerLayer = map.children.whereType<MarkerLayer>().single;
    expect(
      markerLayer.markers.any(
        (marker) => marker.child.key == const Key('passenger-home-centre-pin'),
      ),
      isFalse,
    );
  });

  testWidgets('test_geocoding_fires_on_map_event_move_end_not_during_move', (
    tester,
  ) async {
    final geocoder = _FakeReverseGeocoder(address: 'Idle address');
    await _pumpHome(tester, geocoder: geocoder);
    await tester.pump(const Duration(milliseconds: 401));
    geocoder.reset();

    final map = tester.widget<FlutterMap>(
      find.byKey(const Key('passenger-home-flutter-map')),
    );
    final controller = map.mapController!;
    final oldCamera = controller.camera;
    final movedCamera = oldCamera.withPosition(
      center: const LatLng(5.6100, -0.1700),
    );

    map.options.onMapEvent!.call(
      MapEventMove(
        source: MapEventSource.onDrag,
        oldCamera: oldCamera,
        camera: movedCamera,
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(geocoder.calls, isEmpty);

    map.options.onMapEvent!.call(
      MapEventMoveEnd(source: MapEventSource.dragEnd, camera: movedCamera),
    );
    await tester.pump(const Duration(milliseconds: 399));
    expect(geocoder.calls, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));

    expect(geocoder.calls, [const LatLng(5.6100, -0.1700)]);
  });

  testWidgets('test_geocoding_debounced_300_to_500ms', (tester) async {
    final geocoder = _FakeReverseGeocoder(address: 'Debounced address');
    await _pumpHome(tester, geocoder: geocoder);
    await tester.pump(const Duration(milliseconds: 401));
    geocoder.reset();

    final map = tester.widget<FlutterMap>(
      find.byKey(const Key('passenger-home-flutter-map')),
    );
    final controller = map.mapController!;
    final firstCamera = controller.camera.withPosition(
      center: const LatLng(5.6110, -0.1710),
    );
    final secondCamera = controller.camera.withPosition(
      center: const LatLng(5.6120, -0.1720),
    );

    map.options.onMapEvent!.call(
      MapEventMoveEnd(source: MapEventSource.dragEnd, camera: firstCamera),
    );
    await tester.pump(const Duration(milliseconds: 250));

    map.options.onMapEvent!.call(
      MapEventMoveEnd(source: MapEventSource.dragEnd, camera: secondCamera),
    );
    await tester.pump(const Duration(milliseconds: 399));
    expect(geocoder.calls, isEmpty);

    await tester.pump(const Duration(milliseconds: 1));
    expect(geocoder.calls, [const LatLng(5.6120, -0.1720)]);
    expect(
      passengerHomePickupGeocodeDebounce.inMilliseconds,
      inInclusiveRange(300, 500),
    );
  });

  testWidgets('test_address_field_tap_opens_location_search', (tester) async {
    await _pumpShell(tester);

    await tester.tap(
      find.byKey(const Key('passenger-home-pickup-address-row')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(LocationSearchPage), findsOneWidget);
    expect(find.byKey(const Key('location-description')), findsOneWidget);
  });

  testWidgets('test_edit_icon_opens_location_search', (tester) async {
    await _pumpShell(tester);

    await tester.tap(find.byKey(const Key('passenger-home-edit-pickup')));
    await tester.pumpAndSettle();

    expect(find.byType(LocationSearchPage), findsOneWidget);
    expect(find.byKey(const Key('location-description')), findsOneWidget);
  });

  testWidgets('test_geocoding_failure_shows_coordinate_fallback', (
    tester,
  ) async {
    final geocoder = _FakeReverseGeocoder(shouldThrow: true);
    await _pumpHome(tester, geocoder: geocoder);
    await tester.pump(const Duration(milliseconds: 401));

    expect(find.text('5.60500, -0.16680'), findsOneWidget);
  });

  testWidgets('test_full_address_visible_on_long_press', (tester) async {
    const fullAddress =
        '123 Very Long Solar Mobility Avenue, Airport Residential Area, '
        'Accra, Greater Accra Region, Ghana';
    final geocoder = _FakeReverseGeocoder(address: fullAddress);

    await _pumpHome(tester, geocoder: geocoder);
    await tester.pump(const Duration(milliseconds: 401));

    final displayed = tester.widget<Text>(
      find.byKey(const Key('passenger-home-pickup-address-text')),
    );
    expect(displayed.data, isNot(fullAddress));
    expect(displayed.data!.runes.length, lessThanOrEqualTo(60));

    await tester.longPress(
      find.byKey(const Key('passenger-home-pickup-address-row')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('passenger-home-pickup-full-address')),
      findsOneWidget,
    );
    expect(find.text(fullAddress), findsOneWidget);
  });

  testWidgets('test_underline_styling_absent', (tester) async {
    final geocoder = _FakeReverseGeocoder(address: 'Accra pickup');
    await _pumpHome(tester, geocoder: geocoder);

    final row = find.byKey(const Key('passenger-home-pickup-address-row'));
    expect(
      find.descendant(of: row, matching: find.byType(TextField)),
      findsNothing,
    );
    expect(
      find.descendant(of: row, matching: find.byType(TextFormField)),
      findsNothing,
    );

    final source = File('lib/passenger_home.dart').readAsStringSync();
    expect(source, isNot(contains('UnderlineInputBorder')));
  });

  testWidgets('test_confirm_pickup_passes_coordinates_downstream', (
    tester,
  ) async {
    await _pumpShell(tester);

    await tester.tap(find.byKey(const Key('confirm-pickup')));
    await tester.pumpAndSettle();

    final booking = tester.widget<BookingPage>(find.byType(BookingPage));
    expect(booking.initialPickupDescription, isNotEmpty);
    expect(booking.initialPickupLatitude, closeTo(5.6050, 0.000001));
    expect(booking.initialPickupLongitude, closeTo(-0.1668, 0.000001));
    expect(find.byKey(const Key('booking-destination')), findsOneWidget);
  });

  testWidgets(
    'test_home_map_opens_centred_on_accra_regardless_of_device_location',
    (tester) async {
      const farOutsideGhana = LatLng(31.2304, 121.4737);
      const deviceLocationService = _FixedDeviceLocationService(
        farOutsideGhana,
      );

      await _pumpHome(
        tester,
        geocoder: _FakeReverseGeocoder(address: 'Accra pickup'),
        deviceLocationService: deviceLocationService,
      );
      await tester.pump();

      final map = tester.widget<FlutterMap>(
        find.byKey(const Key('passenger-home-flutter-map')),
      );

      expect(
        map.mapController!.camera.center.latitude,
        closeTo(passengerHomePickupDefaultCenter.latitude, 0.000001),
      );
      expect(
        map.mapController!.camera.center.longitude,
        closeTo(passengerHomePickupDefaultCenter.longitude, 0.000001),
      );
    },
  );

  testWidgets('test_blue_dot_shows_device_position_not_map_centre', (
    tester,
  ) async {
    const farOutsideGhana = LatLng(31.2304, 121.4737);
    const deviceLocationService = _FixedDeviceLocationService(farOutsideGhana);

    await _pumpHome(
      tester,
      geocoder: _FakeReverseGeocoder(address: 'Accra pickup'),
      deviceLocationService: deviceLocationService,
    );
    await tester.pump();

    final map = tester.widget<FlutterMap>(
      find.byKey(const Key('passenger-home-flutter-map')),
    );
    final markerLayer = map.children.whereType<MarkerLayer>().single;
    final blueDotMarker = markerLayer.markers.singleWhere(
      (marker) =>
          marker.child.key == const Key('passenger-home-device-blue-dot'),
    );

    expect(
      map.mapController!.camera.center.latitude,
      closeTo(passengerHomePickupDefaultCenter.latitude, 0.000001),
    );
    expect(
      map.mapController!.camera.center.longitude,
      closeTo(passengerHomePickupDefaultCenter.longitude, 0.000001),
    );
    expect(
      blueDotMarker.point.latitude,
      closeTo(farOutsideGhana.latitude, 0.000001),
    );
    expect(
      blueDotMarker.point.longitude,
      closeTo(farOutsideGhana.longitude, 0.000001),
    );
  });

  testWidgets('test_recenter_fab_moves_to_device_position', (tester) async {
    const farOutsideGhana = LatLng(31.2304, 121.4737);
    const deviceLocationService = _FixedDeviceLocationService(farOutsideGhana);

    await _pumpHome(
      tester,
      geocoder: _FakeReverseGeocoder(address: 'Accra pickup'),
      deviceLocationService: deviceLocationService,
    );
    await tester.pump();

    final mapFinder = find.byKey(const Key('passenger-home-flutter-map'));
    var map = tester.widget<FlutterMap>(mapFinder);

    expect(
      map.mapController!.camera.center.latitude,
      closeTo(passengerHomePickupDefaultCenter.latitude, 0.000001),
    );
    expect(
      map.mapController!.camera.center.longitude,
      closeTo(passengerHomePickupDefaultCenter.longitude, 0.000001),
    );

    await tester.tap(find.byKey(const Key('passenger-home-recenter')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    map = tester.widget<FlutterMap>(mapFinder);
    expect(
      map.mapController!.camera.center.latitude,
      closeTo(farOutsideGhana.latitude, 0.000001),
    );
    expect(
      map.mapController!.camera.center.longitude,
      closeTo(farOutsideGhana.longitude, 0.000001),
    );
  });

  test('test_initial_centre_is_kotoka_airport_coordinates', () {
    expect(
      passengerHomePickupDefaultCenter.latitude,
      closeTo(5.6050, 0.000001),
    );
    expect(
      passengerHomePickupDefaultCenter.longitude,
      closeTo(-0.1668, 0.000001),
    );
  });

  testWidgets('test_recenter_fab_present', (tester) async {
    final geocoder = _FakeReverseGeocoder(address: 'Accra pickup');
    await _pumpHome(tester, geocoder: geocoder);

    expect(find.byKey(const Key('passenger-home-recenter')), findsOneWidget);
    expect(find.byIcon(Icons.my_location), findsOneWidget);
  });

  testWidgets('test_permission_denied_forever_shows_recovery_banner', (
    tester,
  ) async {
    final permissionService = _FakeLocationPermissionService(
      PassengerHomeLocationPermissionState.deniedForever,
    );
    await _pumpHome(
      tester,
      geocoder: _FakeReverseGeocoder(),
      locationPermissionService: permissionService,
    );
    await tester.pump();

    expect(
      find.byKey(const Key('passenger-home-location-recovery')),
      findsOneWidget,
    );
    expect(find.text(passengerHomeLocationRecoveryCopy), findsOneWidget);
    expect(find.byKey(const Key('confirm-pickup')), findsOneWidget);
    expect(find.byKey(const Key('passenger-home-flutter-map')), findsOneWidget);
  });

  testWidgets('test_recovery_banner_opens_app_settings', (tester) async {
    final permissionService = _FakeLocationPermissionService(
      PassengerHomeLocationPermissionState.deniedForever,
    );
    await _pumpHome(
      tester,
      geocoder: _FakeReverseGeocoder(),
      locationPermissionService: permissionService,
    );
    await tester.pump();

    await tester.tap(
      find.byKey(const Key('passenger-home-location-recovery-action')),
    );
    await tester.pump();

    expect(permissionService.openAppSettingsCalls, 1);
  });

  testWidgets('test_recovery_banner_absent_when_permission_granted', (
    tester,
  ) async {
    final permissionService = _FakeLocationPermissionService(
      PassengerHomeLocationPermissionState.deniedForever,
    );
    await _pumpHome(
      tester,
      geocoder: _FakeReverseGeocoder(),
      locationPermissionService: permissionService,
    );
    await tester.pump();

    expect(
      find.byKey(const Key('passenger-home-location-recovery')),
      findsOneWidget,
    );

    permissionService.state = PassengerHomeLocationPermissionState.granted;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const Key('passenger-home-location-recovery')),
      findsNothing,
    );
  });

  testWidgets('test_banner_does_not_overlap_header_on_small_screen', (
    tester,
  ) async {
    await _pumpHome(
      tester,
      geocoder: _FakeReverseGeocoder(),
      mediaSize: const Size(375, 812),
      mediaPadding: const EdgeInsets.only(top: 50),
    );

    final headerRect = tester.getRect(
      find.byKey(const Key('passenger-home-floating-header')),
    );
    final bannerRect = tester.getRect(
      find.byKey(const Key('passenger-home-solar-banner')),
    );

    expect(headerRect.overlaps(bannerRect), isFalse);
    expect(bannerRect.top, greaterThanOrEqualTo(headerRect.bottom));
  });

  testWidgets('test_banner_positioned_below_header_safe_area', (tester) async {
    const topSafeArea = 50.0;
    await _pumpHome(
      tester,
      geocoder: _FakeReverseGeocoder(),
      mediaSize: const Size(375, 812),
      mediaPadding: const EdgeInsets.only(top: topSafeArea),
    );

    final topContentRect = tester.getRect(
      find.byKey(const Key('passenger-home-safe-top-content')),
    );
    final headerRect = tester.getRect(
      find.byKey(const Key('passenger-home-floating-header')),
    );
    final bannerRect = tester.getRect(
      find.byKey(const Key('passenger-home-solar-banner')),
    );

    expect(topContentRect.top, greaterThanOrEqualTo(topSafeArea));
    expect(headerRect.top, greaterThanOrEqualTo(topSafeArea));
    expect(bannerRect.top, greaterThan(headerRect.bottom));
  });

  test('test_launch_screen_background_is_brand_green', () {
    final storyboard = File(
      'ios/Runner/Base.lproj/LaunchScreen.storyboard',
    ).readAsStringSync();
    final colorset =
        jsonDecode(
              File(
                'ios/Runner/Assets.xcassets/'
                'ALANTEHBrandGreen.colorset/Contents.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;

    expect(
      storyboard,
      contains('<color key="backgroundColor" name="ALANTEHBrandGreen"/>'),
    );
    expect(storyboard, contains('<namedColor name="ALANTEHBrandGreen">'));

    final colors = colorset['colors'] as List<dynamic>;
    expect(colors, hasLength(1));
    final color =
        (colors.single as Map<String, dynamic>)['color']
            as Map<String, dynamic>;
    expect(color['color-space'], 'srgb');

    final components = color['components'] as Map<String, dynamic>;
    expect(components['red'], '0.07058823529411765');
    expect(components['green'], '0.23529411764705882');
    expect(components['blue'], '0.1607843137254902');
    expect(components['alpha'], '1.000');
  });

  test('test_launch_image_asset_unchanged', () {
    const expectedSha256 = <String, String>{
      'ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage.png':
          '388bcfa75150f7212912b03b9602fb7115718f1b73ba6a46194af8e9d060191e',
      'ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@2x.png':
          '98bd946ec42f1b838638c2a07175a8cdb395fee483d06e481e06f90b9f6d0675',
      'ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@3x.png':
          '4423ec3d5b4af0d42f34ddf0acaccd4c37eea03075152c60b6aee02988a06c87',
      'ios/Runner/Assets.xcassets/LaunchImage.imageset/Contents.json':
          'ccc7950fd5f5b82067c85f667940a9d59189151460761ece8098ca78daa19469',
    };

    for (final entry in expectedSha256.entries) {
      final result = Process.runSync('shasum', ['-a', '256', entry.key]);
      expect(
        result.exitCode,
        0,
        reason: 'Unable to hash ${entry.key}: ${result.stderr}',
      );
      final digest = (result.stdout as String)
          .trim()
          .split(RegExp(r'\s+'))
          .first;
      expect(digest, entry.value, reason: '${entry.key} changed unexpectedly');
    }
  });

  test('test_launch_screen_width_constraint_preserved', () {
    final storyboard = File(
      'ios/Runner/Base.lproj/LaunchScreen.storyboard',
    ).readAsStringSync();

    expect(
      storyboard,
      contains('firstAttribute="width" constant="220" id="launch-width-220"'),
    );
  });

  test('test_launch_screen_image_has_explicit_constraints', () {
    final storyboard = File(
      'ios/Runner/Base.lproj/LaunchScreen.storyboard',
    ).readAsStringSync();

    expect(
      storyboard,
      contains('contentMode="scaleAspectFit" image="LaunchImage"'),
    );
    expect(
      storyboard,
      contains('firstAttribute="width" constant="220" id="launch-width-220"'),
    );
    expect(
      storyboard,
      contains(
        'secondAttribute="height" multiplier="3:1" '
        'id="launch-aspect-3-1"',
      ),
    );
    expect(
      storyboard,
      contains(
        'firstAttribute="centerX" secondItem="Ze5-6b-2t3" '
        'secondAttribute="centerX"',
      ),
    );
    expect(
      storyboard,
      contains(
        'firstAttribute="centerY" secondItem="Ze5-6b-2t3" '
        'secondAttribute="centerY"',
      ),
    );
  });

  test('test_geolocator_used_only_for_device_position_not_driver_tracking', () {
    final geolocatorFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where((file) => file.readAsStringSync().contains('Geolocator'))
        .map((file) => file.path.replaceAll('\\', '/'))
        .toList();

    expect(geolocatorFiles, ['lib/passenger_home.dart']);

    final source = File('lib/passenger_home.dart').readAsStringSync();
    expect(source, contains('Geolocator.getCurrentPosition()'));
    expect(source, contains('Geolocator.getPositionStream()'));
    expect(source, isNot(contains('driverPosition')));
    expect(source, isNot(contains('driver tracking')));
    expect(source, isNot(contains('fakeGps')));
    expect(source, isNot(contains('ETA')));
  });

  testWidgets('test_home_map_is_only_pickup_map_surface', (tester) async {
    await _pumpShell(tester);

    expect(find.byType(FlutterMap), findsOneWidget);
    expect(
      find.byKey(const Key('passenger-home-full-screen-map-layout')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('passenger-home-flutter-map')), findsOneWidget);

    final libSources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .map((file) => file.readAsStringSync())
        .join('\n');

    expect(libSources, isNot(contains('PickupMapConfirmationPage')));
    expect(
      File('lib/location/pickup_map_confirmation_page.dart').existsSync(),
      isFalse,
    );
  });

  testWidgets('test_no_navigation_to_second_pickup_map', (tester) async {
    await _pumpShell(tester);

    expect(find.byType(FlutterMap), findsOneWidget);
    expect(
      find.byKey(const Key('passenger-home-pickup-address-row')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('confirm-pickup')), findsOneWidget);

    await tester.tap(find.byKey(const Key('confirm-pickup')));
    await tester.pumpAndSettle();

    expect(find.byType(BookingPage), findsOneWidget);
    expect(find.byKey(const Key('passenger-home-flutter-map')), findsNothing);

    final shellSource = File('lib/passenger_shell.dart').readAsStringSync();
    expect(shellSource, isNot(contains('PickupMapConfirmationPage')));
    expect(shellSource, isNot(contains('_selectingPickupOnMap')));
  });
}

Future<void> _pumpHome(
  WidgetTester tester, {
  required PassengerHomeReverseGeocoder geocoder,
  PassengerHomeDeviceLocationService deviceLocationService =
      const _NoDeviceLocationService(),
  PassengerHomeLocationPermissionService locationPermissionService =
      const _GrantedLocationPermissionService(),
  Size? mediaSize,
  EdgeInsets mediaPadding = EdgeInsets.zero,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AsmThemes.passenger,
      builder: (context, child) {
        final current = MediaQuery.of(context);
        return MediaQuery(
          data: current.copyWith(
            size: mediaSize ?? current.size,
            padding: mediaPadding,
            viewPadding: mediaPadding,
          ),
          child: child!,
        );
      },
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
          onOpenPickupSearch: (_) async => null,
          onConfirmPickup: (_) {},
          reverseGeocoder: geocoder,
          deviceLocationService: deviceLocationService,
          locationPermissionService: locationPermissionService,
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _pumpShell(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AsmThemes.passenger,
      home: const PassengerShell(
        configuration: AsmAppConfig.localGhana,
        localQaEnabled: true,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _FakeReverseGeocoder implements PassengerHomeReverseGeocoder {
  _FakeReverseGeocoder({
    this.address = 'Accra pickup',
    this.shouldThrow = false,
  });

  final String address;
  final bool shouldThrow;
  final List<LatLng> calls = [];

  void reset() => calls.clear();

  @override
  Future<String> reverseGeocode(LatLng coordinates) async {
    calls.add(coordinates);
    if (shouldThrow) {
      throw StateError('Reverse geocoding unavailable.');
    }
    return address;
  }
}

class _GrantedLocationPermissionService
    implements PassengerHomeLocationPermissionService {
  const _GrantedLocationPermissionService();

  @override
  Future<PassengerHomeLocationPermissionState> ensurePermission() async =>
      PassengerHomeLocationPermissionState.granted;

  @override
  Future<bool> openAppSettings() async => true;
}

class _FakeLocationPermissionService
    implements PassengerHomeLocationPermissionService {
  _FakeLocationPermissionService(this.state);

  PassengerHomeLocationPermissionState state;
  int openAppSettingsCalls = 0;

  @override
  Future<PassengerHomeLocationPermissionState> ensurePermission() async =>
      state;

  @override
  Future<bool> openAppSettings() async {
    openAppSettingsCalls += 1;
    return true;
  }
}

class _FixedDeviceLocationService
    implements PassengerHomeDeviceLocationService {
  const _FixedDeviceLocationService(this.position);

  final LatLng position;

  @override
  Stream<LatLng> get devicePositionStream => const Stream<LatLng>.empty();

  @override
  Future<LatLng?> getCurrentDevicePosition() async => position;
}

class _NoDeviceLocationService implements PassengerHomeDeviceLocationService {
  const _NoDeviceLocationService();

  @override
  Stream<LatLng> get devicePositionStream => const Stream<LatLng>.empty();

  @override
  Future<LatLng?> getCurrentDevicePosition() async => null;
}
