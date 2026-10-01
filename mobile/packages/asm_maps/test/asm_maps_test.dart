import 'package:asm_maps/asm_maps.dart';
import 'package:asm_maps/src/google_asm_map.dart';
import 'package:asm_maps/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gm;
import 'package:latlong2/latlong.dart';

const _accra = LatLng(5.6050, -0.1668);
const _camera = AsmMapCamera(center: _accra, zoom: 16);

void main() {
  group('stand-in map', () {
    setUp(() => AsmMapView.debugBuilderOverride = asmFakeMapBuilder);
    tearDown(() => AsmMapView.debugBuilderOverride = null);

    testWidgets('reports creation, then one idle at the starting camera', (
      tester,
    ) async {
      final events = _Events();
      await tester.pumpWidget(_map(events));
      await tester.pump();

      expect(events.log, <String>['created', 'idle 5.6050,-0.1668']);
      expect(events.controller!.camera, _camera);
    });

    testWidgets('a drag fires move started once, moves, then idle on release', (
      tester,
    ) async {
      final events = _Events();
      await tester.pumpWidget(_map(events));
      await tester.pump();
      events.log.clear();

      final map = tester.state<AsmFakeMapState>(find.byType(AsmFakeMap));
      map.dragTo(const LatLng(5.6100, -0.1700));
      map.dragTo(const LatLng(5.6110, -0.1710));
      expect(events.log, <String>[
        'move started',
        'move 5.6100,-0.1700',
        'move 5.6110,-0.1710',
      ]);

      map.release();
      expect(events.log.last, 'idle 5.6110,-0.1710');
      expect(events.log.where((e) => e.startsWith('idle')), hasLength(1));
      expect(map.camera.center, const LatLng(5.6110, -0.1710));
    });

    testWidgets('animateTo moves like a gesture and ends idle at the target', (
      tester,
    ) async {
      final events = _Events();
      await tester.pumpWidget(_map(events));
      await tester.pump();
      events.log.clear();

      const target = LatLng(5.5600, -0.2000);
      final done = events.controller!.animateTo(target);
      await tester.pump(asmFakeMapAnimationDuration);
      await done;

      expect(events.log.first, 'move started');
      expect(events.log.where((e) => e == 'move started'), hasLength(1));
      // Moves in steps, not a jump: more than one move besides the start.
      expect(
        events.log.where((e) => e.startsWith('move 5.')).length,
        greaterThan(1),
      );
      expect(events.log.last, 'idle 5.5600,-0.2000');
      expect(events.controller!.camera.center, target);
      expect(events.controller!.camera.zoom, 16);
    });

    testWidgets('shows each marker under its id and keeps the view', (
      tester,
    ) async {
      await tester.pumpWidget(
        _map(
          _Events(),
          markers: const <AsmMapMarker>[
            AsmMapMarker(
              id: 'pickup-marker',
              position: _accra,
              style: AsmMapMarkerStyle.pickup,
            ),
          ],
        ),
      );

      expect(find.byKey(const Key('pickup-marker')), findsOneWidget);
      final map = tester.state<AsmFakeMapState>(find.byType(AsmFakeMap));
      expect(map.markers.single.style, AsmMapMarkerStyle.pickup);
    });
  });

  testWidgets('without an override the view is the Google map', (tester) async {
    expect(AsmMapView.debugBuilderOverride, isNull);
    Widget? built;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          built = const AsmMapView(initialCamera: _camera).build(context);
          return const SizedBox();
        },
      ),
    );

    expect(built, isA<GoogleAsmMap>());
  });

  group('Google adapter', () {
    test('passes camera, padding, zoom limits and quiet chrome', () {
      final map = googleMapFor(
        const AsmMapView(
          initialCamera: _camera,
          minZoom: 5,
          maxZoom: 18,
          padding: EdgeInsets.only(bottom: 240),
        ),
        relay: GoogleCameraRelay(_camera),
        icons: null,
        onMapCreated: (_) {},
      );

      expect(
        map.initialCameraPosition.target,
        const gm.LatLng(5.6050, -0.1668),
      );
      expect(map.initialCameraPosition.zoom, 16);
      expect(map.padding, const EdgeInsets.only(bottom: 240));
      expect(map.minMaxZoomPreference, const gm.MinMaxZoomPreference(5, 18));
      expect(map.scrollGesturesEnabled, isTrue);
      expect(map.zoomGesturesEnabled, isTrue);
      expect(map.rotateGesturesEnabled, isFalse);
      expect(map.tiltGesturesEnabled, isFalse);
      // The app draws its own device dot and recenter button.
      expect(map.myLocationEnabled, isFalse);
      expect(map.myLocationButtonEnabled, isFalse);
      expect(map.zoomControlsEnabled, isFalse);
      expect(map.mapToolbarEnabled, isFalse);
    });

    test('a non-interactive view takes no gestures', () {
      final map = googleMapFor(
        const AsmMapView(initialCamera: _camera, interactive: false),
        relay: GoogleCameraRelay(_camera),
        icons: null,
        onMapCreated: (_) {},
      );

      expect(map.scrollGesturesEnabled, isFalse);
      expect(map.zoomGesturesEnabled, isFalse);
    });

    test('markers wait for their icons, then keep id, position and anchor', () {
      const view = AsmMapView(
        initialCamera: _camera,
        markers: <AsmMapMarker>[
          AsmMapMarker(
            id: 'dot',
            position: LatLng(31.2304, 121.4737),
            style: AsmMapMarkerStyle.deviceLocation,
          ),
          AsmMapMarker(
            id: 'drop',
            position: LatLng(5.5495, -0.2069),
            style: AsmMapMarkerStyle.destination,
          ),
        ],
      );
      final relay = GoogleCameraRelay(_camera);

      expect(
        googleMapFor(
          view,
          relay: relay,
          icons: null,
          onMapCreated: (_) {},
        ).markers,
        isEmpty,
      );

      final icons = <AsmMapMarkerStyle, gm.BitmapDescriptor>{
        for (final style in AsmMapMarkerStyle.values)
          style: gm.BitmapDescriptor.defaultMarker,
      };
      final markers = {
        for (final marker in googleMapFor(
          view,
          relay: relay,
          icons: icons,
          onMapCreated: (_) {},
        ).markers)
          marker.markerId.value: marker,
      };

      expect(markers.keys, unorderedEquals(<String>['dot', 'drop']));
      expect(markers['dot']!.position, const gm.LatLng(31.2304, 121.4737));
      // A dot is centred on its point; a pin stands on it.
      expect(markers['dot']!.anchor, const Offset(0.5, 0.5));
      expect(markers['drop']!.anchor.dx, 0.5);
      expect(markers['drop']!.anchor.dy, greaterThan(0.85));
    });

    test('route lines keep their points, colour and width', () {
      final map = googleMapFor(
        const AsmMapView(
          initialCamera: _camera,
          polylines: <AsmMapPolyline>[
            AsmMapPolyline(
              id: 'route',
              points: <LatLng>[_accra, LatLng(5.5495, -0.2069)],
              color: Color(0xFF123456),
              width: 5,
            ),
          ],
        ),
        relay: GoogleCameraRelay(_camera),
        icons: null,
        onMapCreated: (_) {},
      );

      final line = map.polylines.single;
      expect(line.polylineId.value, 'route');
      expect(line.points, const <gm.LatLng>[
        gm.LatLng(5.6050, -0.1668),
        gm.LatLng(5.5495, -0.2069),
      ]);
      expect(line.color, const Color(0xFF123456));
      expect(line.width, 5);
    });

    test('idle reports where the last move left the camera', () {
      // Google's idle callback carries no position.
      final events = _Events();
      final view = _view(events);
      final map = googleMapFor(
        view,
        relay: GoogleCameraRelay(_camera),
        icons: null,
        onMapCreated: (_) {},
      );

      map.onCameraIdle!();
      map.onCameraMoveStarted!();
      map.onCameraMove!(
        const gm.CameraPosition(target: gm.LatLng(5.6100, -0.1700), zoom: 15),
      );
      map.onCameraIdle!();

      expect(events.log, <String>[
        'idle 5.6050,-0.1668',
        'move started',
        'move 5.6100,-0.1700',
        'idle 5.6100,-0.1700',
      ]);
    });
  });
}

class _Events {
  final log = <String>[];
  AsmMapController? controller;

  static String _at(AsmMapCamera camera) =>
      '${camera.center.latitude.toStringAsFixed(4)},'
      '${camera.center.longitude.toStringAsFixed(4)}';
}

AsmMapView _view(
  _Events events, {
  List<AsmMapMarker> markers = const <AsmMapMarker>[],
}) {
  return AsmMapView(
    initialCamera: _camera,
    markers: markers,
    onMapCreated: (controller) {
      events.controller = controller;
      events.log.add('created');
    },
    onCameraMoveStarted: () => events.log.add('move started'),
    onCameraMove: (camera) => events.log.add('move ${_Events._at(camera)}'),
    onCameraIdle: (camera) => events.log.add('idle ${_Events._at(camera)}'),
  );
}

Widget _map(
  _Events events, {
  List<AsmMapMarker> markers = const <AsmMapMarker>[],
}) {
  return MaterialApp(
    home: Scaffold(body: _view(events, markers: markers)),
  );
}
