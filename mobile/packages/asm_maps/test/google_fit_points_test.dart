import 'dart:async';

import 'package:asm_maps/asm_maps.dart';
import 'package:asm_maps/src/google_asm_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart'
    as gmp;
import 'package:latlong2/latlong.dart';

// The pickup on the 8 Oct phone check, and where the phone really was.
const accra = LatLng(5.6037, -0.1870);
const phoneInChina = LatLng(31.30, 120.75);

void main() {
  late _RecordingMapsPlatform platform;

  setUp(() {
    platform = _RecordingMapsPlatform();
    gmp.GoogleMapsFlutterPlatform.instance = platform;
  });

  // The camera update the real adapter sends to Google for [points].
  Future<Object> fitOnGoogle(WidgetTester tester, List<LatLng> points) async {
    AsmMapController? controller;
    await tester.pumpWidget(
      MaterialApp(
        home: GoogleAsmMap(
          view: AsmMapView(
            initialCamera: const AsmMapCamera(center: accra, zoom: 15),
            onMapCreated: (created) => controller = created,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(controller, isNotNull, reason: 'the map was never created');
    await controller!.fitPoints(points);
    final update = platform.lastCameraUpdate;
    expect(update, isNotNull, reason: 'fitPoints sent no camera update');
    return update!.toJson();
  }

  // Zoom 16 shows a few hundred metres around the point.
  Object closeUp(LatLng point) => [
    'newLatLngZoom',
    [point.latitude, point.longitude],
    16.0,
  ];

  group('fitPoints on the Google map', () {
    testWidgets('one point is shown close up', (tester) async {
      expect(await fitOnGoogle(tester, [accra]), closeUp(accra));
    });

    testWidgets('two identical points are shown close up, like one', (
      tester,
    ) async {
      expect(await fitOnGoogle(tester, [accra, accra]), closeUp(accra));
    });

    testWidgets('points a few metres apart are shown close up on the first', (
      tester,
    ) async {
      // About 4 m north.
      const nearby = LatLng(5.60374, -0.1870);

      expect(await fitOnGoogle(tester, [accra, nearby]), closeUp(accra));
    });

    testWidgets('points about 5 km apart are framed together', (tester) async {
      // About 5 km north: the normal Accra case.
      const fiveKmNorth = LatLng(5.6487, -0.1870);

      expect(await fitOnGoogle(tester, [accra, fiveKmNorth]), [
        'newLatLngBounds',
        [
          [accra.latitude, accra.longitude],
          [fiveKmNorth.latitude, fiveKmNorth.longitude],
        ],
        fitPaddingPixels,
      ]);
    });

    testWidgets('points about 11,000 km apart frame the first point only', (
      tester,
    ) async {
      // Framing both needs a zoom far below the map's minimum (5), so the
      // map would sit over the sea between them with neither in view.
      expect(await fitOnGoogle(tester, [accra, phoneInChina]), closeUp(accra));
    });
  });

  group('the framing rule', () {
    // Metres per degree of latitude, near enough for these margins.
    const metresPerDegree = 111195.0;
    LatLng north(double metres) =>
        LatLng(accra.latitude + metres / metresPerDegree, accra.longitude);

    test('a point just inside the span is framed with the first', () {
      final inside = north(fitMaxSpanMetres - 500);

      expect(asmCameraFit([accra, inside]), AsmCameraBounds(accra, inside));
    });

    test('a point just outside the span is left out', () {
      expect(
        asmCameraFit([accra, north(fitMaxSpanMetres + 500)]),
        const AsmCameraCloseUp(accra),
      );
    });

    test('a point just outside the close-up distance is framed', () {
      final apart = north(fitCloseUpMetres + 10);

      expect(asmCameraFit([accra, apart]), AsmCameraBounds(accra, apart));
    });

    test('a point just inside the close-up distance is shown close up', () {
      expect(
        asmCameraFit([accra, north(fitCloseUpMetres - 10)]),
        const AsmCameraCloseUp(accra),
      );
    });

    test('far points are dropped and near ones still framed', () {
      final near = north(3000);

      expect(
        asmCameraFit([accra, phoneInChina, near]),
        AsmCameraBounds(accra, near),
      );
    });

    test('nothing to frame for no points', () {
      expect(asmCameraFit(const []), isNull);
    });

    test('a driver 45 km from the pickup is framed with it', () {
      final near = north(45000);

      expect(asmCameraFit([accra, near]), AsmCameraBounds(accra, near));
    });

    test('a driver 55 km from the pickup is left out of the frame', () {
      // Past 50 km. Framing both at Accra still works to about 1,700 km
      // (zoom 5, the map's minimum), but a frame that wide shows neither.
      expect(
        asmCameraFit([accra, north(55000)]),
        const AsmCameraCloseUp(accra),
      );
    });

    test('points 100 m apart are shown close up on the first', () {
      expect(asmCameraFit([accra, north(100)]), const AsmCameraCloseUp(accra));
    });

    test('points 200 m apart are framed together', () {
      final apart = north(200);

      expect(asmCameraFit([accra, apart]), AsmCameraBounds(accra, apart));
    });
  });
}

/// Stands in for the native Google map and records the camera updates the
/// adapter sends it.
class _RecordingMapsPlatform extends gmp.GoogleMapsFlutterPlatform {
  gmp.CameraUpdate? lastCameraUpdate;

  @override
  Future<void> init(int mapId) async {}

  @override
  Widget buildViewWithConfiguration(
    int creationId,
    PlatformViewCreatedCallback onPlatformViewCreated, {
    required gmp.MapWidgetConfiguration widgetConfiguration,
    gmp.MapObjects mapObjects = const gmp.MapObjects(),
    gmp.MapConfiguration mapConfiguration = const gmp.MapConfiguration(),
  }) {
    onPlatformViewCreated(creationId);
    return const SizedBox.expand();
  }

  @override
  Future<void> animateCamera(
    gmp.CameraUpdate cameraUpdate, {
    required int mapId,
  }) async {
    lastCameraUpdate = cameraUpdate;
  }

  @override
  Future<void> animateCameraWithConfiguration(
    gmp.CameraUpdate cameraUpdate,
    gmp.CameraUpdateAnimationConfiguration configuration, {
    required int mapId,
  }) async {
    lastCameraUpdate = cameraUpdate;
  }

  @override
  Future<void> moveCamera(
    gmp.CameraUpdate cameraUpdate, {
    required int mapId,
  }) async {}

  @override
  Future<void> updateMapConfiguration(
    gmp.MapConfiguration configuration, {
    required int mapId,
  }) async {}

  @override
  Future<void> updateMarkers(
    gmp.MarkerUpdates markerUpdates, {
    required int mapId,
  }) async {}

  @override
  Future<void> updatePolylines(
    gmp.PolylineUpdates polylineUpdates, {
    required int mapId,
  }) async {}

  @override
  Future<void> updatePolygons(
    gmp.PolygonUpdates polygonUpdates, {
    required int mapId,
  }) async {}

  @override
  Future<void> updateCircles(
    gmp.CircleUpdates circleUpdates, {
    required int mapId,
  }) async {}

  @override
  Future<void> updateHeatmaps(
    gmp.HeatmapUpdates heatmapUpdates, {
    required int mapId,
  }) async {}

  @override
  Future<void> updateTileOverlays({
    required Set<gmp.TileOverlay> newTileOverlays,
    required int mapId,
  }) async {}

  @override
  Future<void> updateClusterManagers(
    gmp.ClusterManagerUpdates clusterManagerUpdates, {
    required int mapId,
  }) async {}

  @override
  Future<void> updateGroundOverlays(
    gmp.GroundOverlayUpdates groundOverlayUpdates, {
    required int mapId,
  }) async {}

  @override
  void dispose({required int mapId}) {}

  Stream<T> _none<T>() => const Stream.empty();

  @override
  Stream<gmp.CameraMoveStartedEvent> onCameraMoveStarted({
    required int mapId,
  }) => _none();

  @override
  Stream<gmp.CameraMoveEvent> onCameraMove({required int mapId}) => _none();

  @override
  Stream<gmp.CameraIdleEvent> onCameraIdle({required int mapId}) => _none();

  @override
  Stream<gmp.MarkerTapEvent> onMarkerTap({required int mapId}) => _none();

  @override
  Stream<gmp.InfoWindowTapEvent> onInfoWindowTap({required int mapId}) =>
      _none();

  @override
  Stream<gmp.MarkerDragStartEvent> onMarkerDragStart({required int mapId}) =>
      _none();

  @override
  Stream<gmp.MarkerDragEvent> onMarkerDrag({required int mapId}) => _none();

  @override
  Stream<gmp.MarkerDragEndEvent> onMarkerDragEnd({required int mapId}) =>
      _none();

  @override
  Stream<gmp.PolylineTapEvent> onPolylineTap({required int mapId}) => _none();

  @override
  Stream<gmp.PolygonTapEvent> onPolygonTap({required int mapId}) => _none();

  @override
  Stream<gmp.CircleTapEvent> onCircleTap({required int mapId}) => _none();

  @override
  Stream<gmp.MapTapEvent> onTap({required int mapId}) => _none();

  @override
  Stream<gmp.MapLongPressEvent> onLongPress({required int mapId}) => _none();

  @override
  Stream<gmp.ClusterTapEvent> onClusterTap({required int mapId}) => _none();

  @override
  Stream<gmp.GroundOverlayTapEvent> onGroundOverlayTap({required int mapId}) =>
      _none();
}
