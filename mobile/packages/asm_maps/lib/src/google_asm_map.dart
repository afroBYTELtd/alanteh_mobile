import 'dart:async';
import 'dart:math' as math;
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
  late final GoogleCameraRelay _relay = GoogleCameraRelay.forView(widget.view);
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

  @override
  void didUpdateWidget(GoogleAsmMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.view.padding != widget.view.padding &&
        _relay.paddingChanged()) {
      // The plugin sends the new padding to the map from a microtask after
      // this frame's build, so move the camera back to the target only
      // after that has run; earlier, the padding lands after the move and
      // shifts the target again (seen on a phone).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Timer.run(() {
          if (mounted) {
            _relay.restoreTarget();
          }
        });
      });
    }
  }

  @override
  void dispose() {
    _relay.dispose();
    super.dispose();
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
      onMapCreated: (controller) {
        _relay.moveCameraTo = (target) =>
            controller.moveCamera(gm.CameraUpdate.newLatLng(_google(target)));
        widget.view.onMapCreated?.call(
          _GoogleAsmMapController(controller, _relay),
        );
      },
    );
  }
}

/// Passes Google's camera events to the view, with two corrections.
///
/// Google's idle carries no position, so the camera is tracked from the
/// moves and handed to idle.
///
/// Padding must not move the camera target (it is the pickup on the home
/// map), but Google keeps the view still when padding changes, so the
/// target jumps to whatever is now at the padded centre. Measured on a
/// phone: padding applied before the map has loaded shows up as a move
/// (with no move started) and an idle at the shifted target; padding
/// changed after loading moves the target with no events at all. Either
/// way the adapter moves the camera back to the target and holds back the
/// events of the shift and of that correction, apart from the final idle.
/// A move started while waiting for the shift is a gesture or animation,
/// so it cancels the hold and passes through.
class GoogleCameraRelay {
  GoogleCameraRelay(this._camera, {bool paddingPending = false})
    : _paddingPending = paddingPending;

  /// Google applies initial padding after creating the map, so padding
  /// present from the start is pending too.
  GoogleCameraRelay.forView(AsmMapView view)
    : this(view.initialCamera, paddingPending: view.padding != EdgeInsets.zero);

  AsmMapCamera _camera;
  bool _paddingPending;
  LatLng? _shiftedTo;
  bool _restoring = false;
  bool _loaded = false;
  Timer? _restoreTimeout;

  /// Moves the camera without animation; set once the map exists.
  Future<void> Function(LatLng target)? moveCameraTo;

  AsmMapCamera get camera => _camera;

  /// Returns true when the caller must call [restoreTarget] once the new
  /// padding is applied; before loading, Google's own shift events are
  /// awaited instead.
  bool paddingChanged() {
    if (_loaded) {
      return true;
    }
    _paddingPending = true;
    return false;
  }

  void restoreTarget() {
    final restore = moveCameraTo;
    if (restore != null) {
      _startRestoring(restore);
    }
  }

  void _startRestoring(Future<void> Function(LatLng target) restore) {
    _restoring = true;
    // If Google never reports the correction, stop holding events back
    // rather than swallow the next gesture.
    _restoreTimeout?.cancel();
    _restoreTimeout = Timer(
      const Duration(seconds: 1),
      () => _restoring = false,
    );
    restore(_camera.center);
  }

  void moveStarted(AsmMapView view) {
    if (_restoring) {
      return;
    }
    _paddingPending = false;
    view.onCameraMoveStarted?.call();
  }

  void move(AsmMapView view, gm.CameraPosition position) {
    if (_restoring) {
      return;
    }
    if (_paddingPending) {
      _shiftedTo = LatLng(position.target.latitude, position.target.longitude);
      return;
    }
    _camera = AsmMapCamera(
      center: LatLng(position.target.latitude, position.target.longitude),
      zoom: position.zoom,
    );
    view.onCameraMove?.call(_camera);
  }

  void idle(AsmMapView view) {
    final shiftedTo = _shiftedTo;
    final restore = moveCameraTo;
    if (_paddingPending &&
        shiftedTo != null &&
        !_samePlace(shiftedTo, _camera.center) &&
        restore != null) {
      _paddingPending = false;
      _shiftedTo = null;
      _startRestoring(restore);
      return;
    }
    _paddingPending = false;
    _shiftedTo = null;
    _restoring = false;
    _loaded = true;
    _restoreTimeout?.cancel();
    view.onCameraIdle?.call(_camera);
  }

  void dispose() => _restoreTimeout?.cancel();
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

  @override
  Future<void> fitPoints(List<LatLng> points) async {
    if (points.isEmpty) {
      return;
    }
    if (points.length == 1) {
      return _controller.animateCamera(
        gm.CameraUpdate.newLatLngZoom(
          _google(points.single),
          fitSinglePointZoom,
        ),
      );
    }
    final latitudes = points.map((point) => point.latitude);
    final longitudes = points.map((point) => point.longitude);
    final bounds = gm.LatLngBounds(
      southwest: gm.LatLng(
        latitudes.reduce(math.min),
        longitudes.reduce(math.min),
      ),
      northeast: gm.LatLng(
        latitudes.reduce(math.max),
        longitudes.reduce(math.max),
      ),
    );
    try {
      await _controller.animateCamera(
        gm.CameraUpdate.newLatLngBounds(bounds, fitPaddingPixels),
      );
    } on Object {
      // Bounds need the map laid out; before then, centre on the points.
      await _controller.animateCamera(
        gm.CameraUpdate.newLatLng(
          gm.LatLng(
            (bounds.southwest.latitude + bounds.northeast.latitude) / 2,
            (bounds.southwest.longitude + bounds.northeast.longitude) / 2,
          ),
        ),
      );
    }
  }
}

/// The zoom [AsmMapController.fitPoints] uses for a single point.
const fitSinglePointZoom = 16.0;

/// The margin, in logical pixels, [AsmMapController.fitPoints] keeps
/// around several points.
const fitPaddingPixels = 64.0;

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
    onCameraMoveStarted: () => relay.moveStarted(view),
    onCameraMove: (position) => relay.move(view, position),
    onCameraIdle: () => relay.idle(view),
  );
}

// Within about a centimetre.
bool _samePlace(LatLng a, LatLng b) =>
    (a.latitude - b.latitude).abs() < 1e-7 &&
    (a.longitude - b.longitude).abs() < 1e-7;

gm.LatLng _google(LatLng point) => gm.LatLng(point.latitude, point.longitude);

class _MarkerArt {
  const _MarkerArt({
    required this.size,
    required this.icon,
    required this.color,
    this.iconSize,
  });

  final double size;
  final IconData? icon;
  final Color color;
  final double? iconSize;
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
      style: style == AsmMapMarkerStyle.vehicle
          ? await _renderCar(pixelRatio)
          : await _render(_art[style]!, pixelRatio),
  };
}

// A top-down electric car, nose up: white body, brand-green glass, side
// mirrors and headlights, on a soft shadow. 32 x 52 logical pixels.
Future<gm.BitmapDescriptor> _renderCar(double pixelRatio) async {
  const width = 32.0;
  const height = 52.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(pixelRatio);
  final body = RRect.fromLTRBR(5, 4, 27, 48, const Radius.circular(9));
  const glass = AsmColors.brandDeepGreen;
  const outline = Color(0xFF2C2C2A);

  canvas.drawRRect(
    body.shift(const Offset(0, 1.5)),
    Paint()
      ..color = const Color(0x4D000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
  );
  for (final x in <double>[2.5, 25.5]) {
    canvas.drawRRect(
      RRect.fromLTRBR(x, 16, x + 4, 20, const Radius.circular(1.5)),
      Paint()..color = outline,
    );
  }
  canvas.drawRRect(body, Paint()..color = Colors.white);
  canvas.drawRRect(
    body,
    Paint()
      ..color = outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2,
  );
  // Windscreen, wider at its base like a real one.
  canvas.drawPath(
    ui.Path()
      ..moveTo(9.5, 14)
      ..quadraticBezierTo(16, 11.5, 22.5, 14)
      ..lineTo(24, 22)
      ..quadraticBezierTo(16, 20.5, 8, 22)
      ..close(),
    Paint()..color = glass,
  );
  canvas.drawRRect(
    RRect.fromLTRBR(9, 37, 23, 42, const Radius.circular(2.5)),
    Paint()..color = glass,
  );
  // Side windows between the windscreen and the rear window.
  for (final x in <double>[7.2, 23.3]) {
    canvas.drawRRect(
      RRect.fromLTRBR(x, 23.5, x + 1.5, 34.5, const Radius.circular(0.75)),
      Paint()..color = glass,
    );
  }
  for (final x in <double>[11, 21]) {
    canvas.drawOval(
      Rect.fromCenter(center: Offset(x, 7), width: 4.5, height: 2.2),
      Paint()..color = const Color(0xFFFFE9A8),
    );
  }

  final image = await recorder.endRecording().toImage(
    (width * pixelRatio).ceil(),
    (height * pixelRatio).ceil(),
  );
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return gm.BitmapDescriptor.bytes(
    png!.buffer.asUint8List(),
    imagePixelRatio: pixelRatio,
  );
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
