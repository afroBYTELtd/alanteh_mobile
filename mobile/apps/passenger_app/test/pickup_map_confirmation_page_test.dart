import 'dart:async';
import 'dart:io';

import 'package:asm_app_config/asm_app_config.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:passenger_app/booking/booking_page.dart';
import 'package:passenger_app/location/location_search_page.dart';
import 'package:passenger_app/location/pickup_map_confirmation_page.dart';
import 'package:passenger_app/passenger_shell.dart';

void main() {
  testWidgets('test_pin_widget_is_flutter_widget_not_map_marker', (
    tester,
  ) async {
    final geocoder = _FakeReverseGeocoder(address: 'Accra pickup');
    await _pumpPickupPage(tester, geocoder: geocoder);

    final centrePin = find.byKey(const Key('pickup-map-centre-pin'));
    expect(centrePin, findsOneWidget);
    expect(
      find.descendant(of: centrePin, matching: find.byType(Marker)),
      findsNothing,
    );

    final map = tester.widget<FlutterMap>(
      find.byKey(const Key('pickup-confirmation-flutter-map')),
    );
    expect(map.children.whereType<MarkerLayer>(), hasLength(1));
    final markerLayer = map.children.whereType<MarkerLayer>().single;
    expect(
      markerLayer.markers.any(
        (marker) => marker.child.key == const Key('pickup-map-centre-pin'),
      ),
      isFalse,
    );
  });

  testWidgets('test_geocoding_fires_on_map_event_move_end_not_during_move', (
    tester,
  ) async {
    final geocoder = _FakeReverseGeocoder(address: 'Idle address');
    await _pumpPickupPage(tester, geocoder: geocoder);
    await tester.pump(const Duration(milliseconds: 401));
    geocoder.reset();

    final map = tester.widget<FlutterMap>(
      find.byKey(const Key('pickup-confirmation-flutter-map')),
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
    await _pumpPickupPage(tester, geocoder: geocoder);
    await tester.pump(const Duration(milliseconds: 401));
    geocoder.reset();

    final map = tester.widget<FlutterMap>(
      find.byKey(const Key('pickup-confirmation-flutter-map')),
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
    expect(pickupMapGeocodeDebounce.inMilliseconds, inInclusiveRange(300, 500));
  });

  testWidgets('test_address_field_tap_opens_location_search', (tester) async {
    await _pumpShellToPickupMap(tester);

    await tester.tap(find.byKey(const Key('pickup-map-address-row')));
    await tester.pumpAndSettle();

    expect(find.byType(LocationSearchPage), findsOneWidget);
    expect(find.text('Where are you?'), findsWidgets);
    expect(find.byKey(const Key('location-description')), findsOneWidget);
  });

  testWidgets('test_edit_icon_opens_location_search', (tester) async {
    await _pumpShellToPickupMap(tester);

    await tester.tap(find.byKey(const Key('pickup-map-edit-address')));
    await tester.pumpAndSettle();

    expect(find.byType(LocationSearchPage), findsOneWidget);
    expect(find.text('Where are you?'), findsWidgets);
    expect(find.byKey(const Key('location-description')), findsOneWidget);
  });

  testWidgets('test_geocoding_failure_shows_coordinate_fallback', (
    tester,
  ) async {
    final geocoder = _FakeReverseGeocoder(shouldThrow: true);
    await _pumpPickupPage(tester, geocoder: geocoder);
    await tester.pump(const Duration(milliseconds: 401));

    expect(find.text('5.60500, -0.16680'), findsOneWidget);
  });

  testWidgets('test_full_address_visible_on_long_press', (tester) async {
    const fullAddress =
        '123 Very Long Solar Mobility Avenue, Airport Residential Area, '
        'Accra, Greater Accra Region, Ghana';
    final geocoder = _FakeReverseGeocoder(address: fullAddress);

    await _pumpPickupPage(tester, geocoder: geocoder);
    await tester.pump(const Duration(milliseconds: 401));

    final displayed = tester.widget<Text>(
      find.byKey(const Key('pickup-map-address-text')),
    );
    expect(displayed.data, isNot(fullAddress));
    expect(displayed.data!.runes.length, lessThanOrEqualTo(60));

    await tester.longPress(find.byKey(const Key('pickup-map-address-row')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('pickup-map-full-address')), findsOneWidget);
    expect(find.text(fullAddress), findsOneWidget);
  });

  testWidgets('test_underline_styling_absent', (tester) async {
    final geocoder = _FakeReverseGeocoder(address: 'Accra pickup');
    await _pumpPickupPage(tester, geocoder: geocoder);

    expect(
      find.descendant(
        of: find.byKey(const Key('pickup-map-address-row')),
        matching: find.byType(TextField),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('pickup-map-address-row')),
        matching: find.byType(TextFormField),
      ),
      findsNothing,
    );

    final source = File(
      'lib/location/pickup_map_confirmation_page.dart',
    ).readAsStringSync();
    expect(source, isNot(contains('UnderlineInputBorder')));
  });

  testWidgets('test_confirm_pickup_passes_coordinates_downstream', (
    tester,
  ) async {
    await _pumpShellToPickupMap(tester);

    await tester.tap(find.byKey(const Key('confirm-pickup')));
    await tester.pumpAndSettle();

    final booking = tester.widget<BookingPage>(find.byType(BookingPage));
    expect(booking.initialPickupDescription, isNotEmpty);
    expect(booking.initialPickupLatitude, closeTo(5.6050, 0.000001));
    expect(booking.initialPickupLongitude, closeTo(-0.1668, 0.000001));
    expect(find.byKey(const Key('booking-destination')), findsOneWidget);
  });

  testWidgets('test_recenter_fab_present', (tester) async {
    final geocoder = _FakeReverseGeocoder(address: 'Accra pickup');
    await _pumpPickupPage(tester, geocoder: geocoder);

    expect(find.byKey(const Key('pickup-map-recenter')), findsOneWidget);
    expect(find.byIcon(Icons.my_location), findsOneWidget);
  });

  test('test_geolocator_used_only_for_device_position_not_driver_tracking', () {
    final passengerLib = Directory('lib');
    final geolocatorFiles = passengerLib
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where((file) => file.readAsStringSync().contains('Geolocator'))
        .map((file) => file.path.replaceAll('\\', '/'))
        .toList();

    expect(geolocatorFiles, ['lib/location/pickup_map_confirmation_page.dart']);

    final source = File(
      'lib/location/pickup_map_confirmation_page.dart',
    ).readAsStringSync();

    expect(source, contains('Geolocator.getCurrentPosition()'));
    expect(source, contains('Geolocator.getPositionStream()'));
    expect(source, isNot(contains('driverPosition')));
    expect(source, isNot(contains('driver tracking')));
    expect(source, isNot(contains('fakeGps')));
    expect(source, isNot(contains('ETA')));
  });
}

Future<void> _pumpPickupPage(
  WidgetTester tester, {
  required PickupReverseGeocoder geocoder,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AsmThemes.passenger,
      home: Scaffold(
        body: PickupMapConfirmationPage(
          reverseGeocoder: geocoder,
          deviceLocationService: const _NoDeviceLocationService(),
          onOpenLocationSearch: (_) async => null,
          onConfirm: (_) {},
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _pumpShellToPickupMap(WidgetTester tester) async {
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

  await tester.tap(find.byKey(const Key('open-live-request')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));

  expect(
    find.byKey(const Key('pickup-map-confirmation-screen')),
    findsOneWidget,
  );
}

class _FakeReverseGeocoder implements PickupReverseGeocoder {
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

class _NoDeviceLocationService implements PickupDeviceLocationService {
  const _NoDeviceLocationService();

  @override
  Stream<LatLng> get devicePositionStream => const Stream<LatLng>.empty();

  @override
  Future<LatLng?> getCurrentDevicePosition() async => null;
}
