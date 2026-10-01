import 'dart:ui' as ui;

import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gm;
import 'package:latlong2/latlong.dart';

import 'asm_map_view.dart';

Widget buildGoogleAsmMap(BuildContext context, AsmMapView view) {
  return GoogleAsmMap(view: view);
}

class GoogleAsmMap extends StatefulWidget {
  const GoogleAsmMap({required this.view, super.key});

  final AsmMapView view;

  @override
  State<GoogleAsmMap> createState() => _GoogleAsmMapState();
}

class _GoogleAsmMapState extends State<GoogleAsmMap> {
  late final GoogleCameraRelay _relay = GoogleCameraRelay(
    widget.view.initialCamera,
  );
  Map<AsmMapMarkerStyle, gm.BitmapDescriptor>? _icons;
  double? _iconPixelRatio;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    if (pixelRatio != _iconPixelRatio) {
      _iconPixelRatio = pixelRatio;
      _loadIcons(pixelRatio);
    }
  }

  Future<void> _loadIcons(double pixelRatio) async {
    final icons = await renderAsmMarkerIcons(pixelRatio);
    if (mounted && pixelRatio == _iconPixelRatio) {
      setState(() => _icons = icons);
    }
  }

  @override
  Widget build(BuildContext context) {
    return googleMapFor(
      widget.view,
      relay: _relay,
      icons: _icons,
      onMapCreated: (controller) => widget.view.onMapCreated?.call(
        _GoogleAsmMapController(controller, _relay),
      ),
    );
  }
}

/// Google's idle callback carries no position, so the camera is tracked
/// from the moves and handed to idle.
class GoogleCameraRelay {
  GoogleCameraRelay(this._camera);

  AsmMapCamera _camera;

  AsmMapCamera get camera => _camera;

  void move(AsmMapView view, gm.CameraPosition position) {
    _camera = AsmMapCamera(
      center: LatLng(position.target.latitude, position.target.longitude),
      zoom: position.zoom,
    );
    view.onCameraMove?.call(_camera);
  }

  void idle(AsmMapView view) => view.onCameraIdle?.call(_camera);
}

class _GoogleAsmMapController implements AsmMapController {
  _GoogleAsmMapController(this._controller, this._relay);

  final gm.GoogleMapController _controller;
  final GoogleCameraRelay _relay;

  @override
  AsmMapCamera get camera => _relay.camera;

  @override
  Future<void> animateTo(LatLng target) {
    return _controller.animateCamera(
      gm.CameraUpdate.newLatLng(_google(target)),
    );
  }
}

/// The Google map for [view]. Markers are left off until [icons] exist.
gm.GoogleMap googleMapFor(
  AsmMapView view, {
  required GoogleCameraRelay relay,
  required Map<AsmMapMarkerStyle, gm.BitmapDescriptor>? icons,
  required ValueChanged<gm.GoogleMapController> onMapCreated,
}) {
  return gm.GoogleMap(
    initialCameraPosition: gm.CameraPosition(
      target: _google(view.initialCamera.center),
      zoom: view.initialCamera.zoom,
    ),
    padding: view.padding,
    minMaxZoomPreference: gm.MinMaxZoomPreference(view.minZoom, view.maxZoom),
    scrollGesturesEnabled: view.interactive,
    zoomGesturesEnabled: view.interactive,
    rotateGesturesEnabled: false,
    tiltGesturesEnabled: false,
    myLocationEnabled: false,
    myLocationButtonEnabled: false,
    zoomControlsEnabled: false,
    mapToolbarEnabled: false,
    compassEnabled: false,
    markers: icons == null
        ? const <gm.Marker>{}
        : <gm.Marker>{
            for (final marker in view.markers)
              gm.Marker(
                markerId: gm.MarkerId(marker.id),
                position: _google(marker.position),
                icon: icons[marker.style]!,
                anchor: _anchors[marker.style]!,
                consumeTapEvents: true,
              ),
          },
    polylines: <gm.Polyline>{
      for (final line in view.polylines)
        gm.Polyline(
          polylineId: gm.PolylineId(line.id),
          points: <gm.LatLng>[for (final point in line.points) _google(point)],
          color: line.color,
          width: line.width,
        ),
    },
    onMapCreated: onMapCreated,
    onCameraMoveStarted: view.onCameraMoveStarted,
    onCameraMove: (position) => relay.move(view, position),
    onCameraIdle: () => relay.idle(view),
  );
}

gm.LatLng _google(LatLng point) => gm.LatLng(point.latitude, point.longitude);

class _MarkerArt {
  const _MarkerArt({
    required this.size,
    required this.icon,
    required this.color,
    this.iconSize,
    this.disc,
  });

  final double size;
  final IconData? icon;
  final Color color;
  final double? iconSize;
  final Color? disc;
}

// Matches the markers the passenger map drew before Google Maps.
const _art = <AsmMapMarkerStyle, _MarkerArt>{
  AsmMapMarkerStyle.deviceLocation: _MarkerArt(
    size: 30,
    icon: null,
    color: Color(0xFF1A73E8),
  ),
  AsmMapMarkerStyle.pickup: _MarkerArt(
    size: 44,
    icon: Icons.trip_origin,
    iconSize: 34,
    color: AsmColors.brandDeepGreen,
  ),
  AsmMapMarkerStyle.destination: _MarkerArt(
    size: 44,
    icon: Icons.location_on,
    iconSize: 40,
    color: Color(0xFF151A15),
  ),
  AsmMapMarkerStyle.vehicle: _MarkerArt(
    size: 48,
    icon: Icons.electric_car,
    iconSize: 27,
    color: Colors.white,
    disc: AsmColors.brandDeepGreen,
  ),
};

// The destination pin's tip is near the bottom of its glyph box; dots and
// rings are centred on their point.
const _anchors = <AsmMapMarkerStyle, Offset>{
  AsmMapMarkerStyle.deviceLocation: Offset(0.5, 0.5),
  AsmMapMarkerStyle.pickup: Offset(0.5, 0.5),
  AsmMapMarkerStyle.destination: Offset(0.5, 0.9),
  AsmMapMarkerStyle.vehicle: Offset(0.5, 0.5),
};

/// Draws each marker style as a bitmap at [pixelRatio].
Future<Map<AsmMapMarkerStyle, gm.BitmapDescriptor>> renderAsmMarkerIcons(
  double pixelRatio,
) async {
  return <AsmMapMarkerStyle, gm.BitmapDescriptor>{
    for (final style in AsmMapMarkerStyle.values)
      style: await _render(_art[style]!, pixelRatio),
  };
}

Future<gm.BitmapDescriptor> _render(_MarkerArt art, double pixelRatio) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(pixelRatio);
  final centre = Offset(art.size / 2, art.size / 2);

  if (art.icon == null) {
    // Device location: blue dot, white ring, soft shadow.
    canvas.drawCircle(
      centre,
      art.size / 2 - 1,
      Paint()
        ..color = const Color(0x33000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawCircle(centre, art.size / 2 - 3, Paint()..color = Colors.white);
    canvas.drawCircle(centre, art.size / 2 - 6, Paint()..color = art.color);
  } else {
    if (art.disc != null) {
      canvas.drawCircle(centre, art.size / 2, Paint()..color = art.disc!);
    }
    final glyph = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(
        text: String.fromCharCode(art.icon!.codePoint),
        style: TextStyle(
          fontFamily: art.icon!.fontFamily,
          package: art.icon!.fontPackage,
          fontSize: art.iconSize,
          color: art.color,
        ),
      ),
    )..layout();
    glyph.paint(canvas, centre - Offset(glyph.width / 2, glyph.height / 2));
  }

  final pixels = (art.size * pixelRatio).ceil();
  final image = await recorder.endRecording().toImage(pixels, pixels);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return gm.BitmapDescriptor.bytes(
    png!.buffer.asUint8List(),
    imagePixelRatio: pixelRatio,
  );
}
