import 'package:latlong2/latlong.dart';

const driverMapCenter = LatLng(5.5820, -0.1900);
const driverPickupPosition = LatLng(5.6037, -0.1737);
const driverDestinationPosition = LatLng(5.5495, -0.2069);
const driverPickupStaticPosition = LatLng(5.5980, -0.1795);
const driverActiveStaticPosition = LatLng(5.5766, -0.1903);

final class DriverTripRouteEstimate {
  const DriverTripRouteEstimate({
    required this.points,
    required this.center,
    required this.vehiclePosition,
    required this.distanceKilometres,
    required this.durationMinutes,
    required this.usedFallback,
    required this.zoom,
  });

  final List<LatLng> points;
  final LatLng center;
  final LatLng vehiclePosition;
  final double distanceKilometres;
  final int durationMinutes;
  final bool usedFallback;
  final double zoom;
}

DriverTripRouteEstimate safeDriverPickupRouteFallback() {
  return const DriverTripRouteEstimate(
    points: <LatLng>[
      driverPickupStaticPosition,
      LatLng(5.6004, -0.1767),
      driverPickupPosition,
    ],
    center: LatLng(5.6009, -0.1768),
    vehiclePosition: driverPickupStaticPosition,
    distanceKilometres: 1.2,
    durationMinutes: 5,
    usedFallback: true,
    zoom: 14.2,
  );
}

DriverTripRouteEstimate safeDriverDestinationRouteFallback() {
  return const DriverTripRouteEstimate(
    points: <LatLng>[
      driverPickupPosition,
      driverActiveStaticPosition,
      LatLng(5.5627, -0.1988),
      driverDestinationPosition,
    ],
    center: driverMapCenter,
    vehiclePosition: driverActiveStaticPosition,
    distanceKilometres: 9.5,
    durationMinutes: 23,
    usedFallback: true,
    zoom: 12.8,
  );
}
