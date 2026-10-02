import 'package:flutter/widgets.dart';
import 'package:latlong2/latlong.dart';

import 'google_asm_map.dart';

/// Where the map camera is looking.
@immutable
class AsmMapCamera {
  const AsmMapCamera({required this.center, required this.zoom});

  final LatLng center;
  final double zoom;

  @override
  bool operator ==(Object other) =>
      other is AsmMapCamera && other.center == center && other.zoom == zoom;

  @override
  int get hashCode => Object.hash(center, zoom);

  @override
  String toString() => 'AsmMapCamera($center, zoom $zoom)';
}

enum AsmMapMarkerStyle { deviceLocation, pickup, destination, vehicle }

@immutable
class AsmMapMarker {
  const AsmMapMarker({
    required this.id,
    required this.position,
    required this.style,
  });

  /// Unique within one map.
  final String id;
  final LatLng position;
  final AsmMapMarkerStyle style;
}

@immutable
class AsmMapPolyline {
  const AsmMapPolyline({
    required this.id,
    required this.points,
    required this.color,
    this.width = 5,
  });

  final String id;
  final List<LatLng> points;
  final Color color;
  final int width;
}

abstract interface class AsmMapController {
  AsmMapCamera get camera;

  /// Moves the camera to [target] at the current zoom. Camera events fire as
  /// for a gesture: move started, moves, then idle.
  Future<void> animateTo(LatLng target);
}

typedef AsmMapViewBuilder =
    Widget Function(BuildContext context, AsmMapView view);

/// A map. In the app it is a Google map; widget tests swap in a stand-in
/// through [debugBuilderOverride], since tests have no native map.
///
/// Camera events follow the Google map: [onCameraMoveStarted] once when a
/// gesture or animation begins, [onCameraMove] as the camera moves, and
/// [onCameraIdle] once when it stops, including once after the map loads.
class AsmMapView extends StatelessWidget {
  const AsmMapView({
    required this.initialCamera,
    this.markers = const <AsmMapMarker>[],
    this.polylines = const <AsmMapPolyline>[],
    this.interactive = true,
    this.minZoom = 5,
    this.maxZoom = 18,
    this.padding = EdgeInsets.zero,
    this.onMapCreated,
    this.onCameraMoveStarted,
    this.onCameraMove,
    this.onCameraIdle,
    super.key,
  });

  /// Read once, when the map is created.
  final AsmMapCamera initialCamera;
  final List<AsmMapMarker> markers;
  final List<AsmMapPolyline> polylines;
  final bool interactive;
  final double minZoom;
  final double maxZoom;

  /// Keeps the map's own marks (the Google logo) clear of overlays. The
  /// camera target is the centre of the padded area, so anything drawn over
  /// the target must be drawn there too; see [cameraTargetIn].
  final EdgeInsets padding;
  final ValueChanged<AsmMapController>? onMapCreated;
  final VoidCallback? onCameraMoveStarted;
  final ValueChanged<AsmMapCamera>? onCameraMove;
  final ValueChanged<AsmMapCamera>? onCameraIdle;

  /// Builds the map in place of the Google map. Each app's
  /// test/flutter_test_config.dart sets it; it is null in the app.
  static AsmMapViewBuilder? debugBuilderOverride;

  /// Where the camera target sits in a map of [size] with [padding].
  static Offset cameraTargetIn(Size size, EdgeInsets padding) {
    return Offset(
      padding.left + (size.width - padding.horizontal) / 2,
      padding.top + (size.height - padding.vertical) / 2,
    );
  }

  @override
  Widget build(BuildContext context) {
    return (debugBuilderOverride ?? buildGoogleAsmMap)(context, this);
  }
}
