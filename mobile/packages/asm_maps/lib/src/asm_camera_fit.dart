import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

/// Points farther than this from the first point are left out of the frame.
///
/// Framing two far-apart points needs a zoom below the map's minimum (5);
/// Google then keeps the zoom at 5 over the middle of the two, so neither
/// is in view (seen on a phone: Accra and a phone in China put the camera
/// over the Arabian Sea). 50 km covers Greater Accra end to end and frames
/// at about zoom 10, well above the minimum.
const fitMaxSpanMetres = 50000.0;

/// Points closer than this to the first point are shown close up on it:
/// at [fitSinglePointZoom] the map shows several hundred metres around the
/// point, so they stay in view without zooming in to street furniture.
const fitCloseUpMetres = 150.0;

/// The zoom a close-up uses.
const fitSinglePointZoom = 16.0;

/// How the camera frames a list of points.
@immutable
sealed class AsmCameraFit {
  const AsmCameraFit();
}

/// Close up on one point, at [fitSinglePointZoom].
final class AsmCameraCloseUp extends AsmCameraFit {
  const AsmCameraCloseUp(this.point);

  final LatLng point;

  @override
  bool operator ==(Object other) =>
      other is AsmCameraCloseUp && other.point == point;

  @override
  int get hashCode => point.hashCode;

  @override
  String toString() => 'AsmCameraCloseUp($point)';
}

/// Every point inside the box from [southwest] to [northeast].
final class AsmCameraBounds extends AsmCameraFit {
  const AsmCameraBounds(this.southwest, this.northeast);

  final LatLng southwest;
  final LatLng northeast;

  LatLng get centre => LatLng(
    (southwest.latitude + northeast.latitude) / 2,
    (southwest.longitude + northeast.longitude) / 2,
  );

  @override
  bool operator ==(Object other) =>
      other is AsmCameraBounds &&
      other.southwest == southwest &&
      other.northeast == northeast;

  @override
  int get hashCode => Object.hash(southwest, northeast);

  @override
  String toString() => 'AsmCameraBounds($southwest, $northeast)';
}

const _distance = Distance(calculator: Haversine(), roundResult: false);

/// How to frame [points], or null for none. The first point is always in
/// view; points more than [fitMaxSpanMetres] from it are left out, and if
/// the rest are within [fitCloseUpMetres] of it the camera shows it close
/// up.
AsmCameraFit? asmCameraFit(List<LatLng> points) {
  if (points.isEmpty) {
    return null;
  }
  final first = points.first;
  final framed = [
    first,
    for (final point in points.skip(1))
      if (_distance(first, point) <= fitMaxSpanMetres) point,
  ];
  if (framed.every((point) => _distance(first, point) < fitCloseUpMetres)) {
    return AsmCameraCloseUp(first);
  }
  double least(Iterable<double> values) =>
      values.reduce((a, b) => a < b ? a : b);
  double most(Iterable<double> values) =>
      values.reduce((a, b) => a > b ? a : b);
  final latitudes = framed.map((point) => point.latitude);
  final longitudes = framed.map((point) => point.longitude);
  return AsmCameraBounds(
    LatLng(least(latitudes), least(longitudes)),
    LatLng(most(latitudes), most(longitudes)),
  );
}
