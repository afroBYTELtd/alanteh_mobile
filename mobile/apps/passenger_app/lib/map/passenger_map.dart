import 'package:asm_design_system/asm_design_system.dart';
import 'package:asm_maps/asm_maps.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

const accraHomeCenter = LatLng(5.6052, -0.1719);
const accraPickup = LatLng(5.6037, -0.1737);
const accraDestination = LatLng(5.5495, -0.2069);
const initialZoom = 14.0;
// Identifies the app to the OSRM route service.
const osmUserAgentPackageName = 'io.alanteh.passenger';

class AsmPassengerMap extends StatelessWidget {
  const AsmPassengerMap({
    this.center = accraHomeCenter,
    this.zoom = initialZoom,
    this.height,
    this.pickup,
    this.destination,
    this.vehicle,
    this.route = const <LatLng>[],
    this.borderRadius,
    this.interactive = true,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  final LatLng center;
  final double zoom;
  final double? height;
  final LatLng? pickup;
  final LatLng? destination;
  final LatLng? vehicle;
  final List<LatLng> route;
  final BorderRadius? borderRadius;
  final bool interactive;

  /// Space covered by overlays; see [AsmMapView.padding].
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final map = AsmMapView(
      initialCamera: AsmMapCamera(center: center, zoom: zoom),
      interactive: interactive,
      padding: padding,
      polylines: [
        if (route.length > 1)
          AsmMapPolyline(
            id: 'passenger-map-route',
            points: route,
            color: AsmColors.brandDeepGreen,
          ),
      ],
      markers: [
        if (pickup != null)
          AsmMapMarker(
            id: 'passenger-map-pickup-marker',
            position: pickup!,
            style: AsmMapMarkerStyle.pickup,
          ),
        if (destination != null)
          AsmMapMarker(
            id: 'passenger-map-destination-marker',
            position: destination!,
            style: AsmMapMarkerStyle.destination,
          ),
        if (vehicle != null)
          AsmMapMarker(
            id: 'passenger-map-static-vehicle-marker',
            position: vehicle!,
            style: AsmMapMarkerStyle.vehicle,
          ),
      ],
    );

    final content = ColoredBox(color: const Color(0xFFE7F1EA), child: map);
    final clipped = borderRadius == null
        ? content
        : ClipRRect(borderRadius: borderRadius!, child: content);
    return SizedBox(
      key: const Key('passenger-map'),
      height: height,
      width: double.infinity,
      child: clipped,
    );
  }
}
