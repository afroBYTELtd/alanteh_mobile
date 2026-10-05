import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import 'asm_map_view.dart';

/// How long [AsmFakeMapState.animateTo] takes.
const asmFakeMapAnimationDuration = Duration(milliseconds: 300);

Widget asmFakeMapBuilder(BuildContext context, AsmMapView view) {
  return AsmFakeMap(view: view);
}

/// Stands in for the Google map in widget tests and fires camera events the
/// way it does: after loading, one idle at the starting camera; for a drag
/// or [animateTo], move started once, one or more moves, then one idle.
///
/// Tests drive it through its state: [AsmFakeMapState.dragTo] and
/// [AsmFakeMapState.release]. Each marker is drawn as an empty box keyed by
/// its id, so tests can find markers by key.
class AsmFakeMap extends StatefulWidget {
  const AsmFakeMap({required this.view, super.key});

  final AsmMapView view;

  @override
  State<AsmFakeMap> createState() => AsmFakeMapState();
}

class AsmFakeMapState extends State<AsmFakeMap> implements AsmMapController {
  late AsmMapCamera _camera = widget.view.initialCamera;
  bool _moving = false;

  @override
  AsmMapCamera get camera => _camera;

  AsmMapView get view => widget.view;

  List<AsmMapMarker> get markers => widget.view.markers;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      widget.view.onMapCreated?.call(this);
      widget.view.onCameraIdle?.call(_camera);
    });
  }

  /// A finger drags the map so [center] is under the camera target and
  /// stays down.
  void dragTo(LatLng center) {
    if (!_moving) {
      _moving = true;
      widget.view.onCameraMoveStarted?.call();
    }
    _camera = AsmMapCamera(center: center, zoom: _camera.zoom);
    widget.view.onCameraMove?.call(_camera);
  }

  /// The finger lifts and the camera stops.
  void release() {
    _moving = false;
    widget.view.onCameraIdle?.call(_camera);
  }

  @override
  Future<void> animateTo(LatLng target) async {
    final start = _camera.center;
    const steps = 3;
    for (var step = 1; step <= steps; step += 1) {
      await Future<void>.delayed(asmFakeMapAnimationDuration ~/ steps);
      if (!mounted) {
        return;
      }
      final t = step / steps;
      dragTo(
        step == steps
            ? target
            : LatLng(
                start.latitude + (target.latitude - start.latitude) * t,
                start.longitude + (target.longitude - start.longitude) * t,
              ),
      );
    }
    release();
  }

  /// The points of the last [fitPoints], for tests.
  List<LatLng> get fittedPoints => _fittedPoints;
  List<LatLng> _fittedPoints = const [];

  @override
  Future<void> fitPoints(List<LatLng> points) async {
    if (points.isEmpty) {
      return;
    }
    _fittedPoints = List.unmodifiable(points);
    final latitudes = points.map((point) => point.latitude).toList();
    final longitudes = points.map((point) => point.longitude).toList();
    double middle(List<double> values) =>
        (values.reduce((a, b) => a < b ? a : b) +
            values.reduce((a, b) => a > b ? a : b)) /
        2;
    await animateTo(LatLng(middle(latitudes), middle(longitudes)));
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFE7F1EA),
      child: Stack(
        children: [
          for (final marker in widget.view.markers)
            SizedBox.shrink(key: Key(marker.id)),
        ],
      ),
    );
  }
}
