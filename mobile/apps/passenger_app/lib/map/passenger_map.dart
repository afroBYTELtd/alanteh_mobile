import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

const accraHomeCenter = LatLng(5.6052, -0.1719);
const accraPickup = LatLng(5.6037, -0.1737);
const accraDestination = LatLng(5.5495, -0.2069);
const initialZoom = 14.0;
const osmTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
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

  @override
  Widget build(BuildContext context) {
    final map = FlutterMap(
      options: MapOptions(
        initialCenter: center,
        initialZoom: zoom,
        minZoom: 5,
        maxZoom: 18,
        interactionOptions: InteractionOptions(
          flags: interactive ? InteractiveFlag.all : InteractiveFlag.none,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: osmTileUrl,
          userAgentPackageName: osmUserAgentPackageName,
        ),
        if (route.length > 1)
          PolylineLayer(
            polylines: [
              Polyline(
                points: route,
                strokeWidth: 5,
                color: AsmColors.brandDeepGreen,
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            if (pickup != null)
              Marker(
                point: pickup!,
                width: 44,
                height: 44,
                child: const Icon(
                  Icons.trip_origin,
                  key: Key('passenger-map-pickup-marker'),
                  color: AsmColors.brandDeepGreen,
                  size: 34,
                ),
              ),
            if (destination != null)
              Marker(
                point: destination!,
                width: 44,
                height: 44,
                child: const Icon(
                  Icons.location_on,
                  key: Key('passenger-map-destination-marker'),
                  color: Color(0xFF151A15),
                  size: 40,
                ),
              ),
            if (vehicle != null)
              Marker(
                point: vehicle!,
                width: 48,
                height: 48,
                child: Container(
                  key: const Key('passenger-map-static-vehicle-marker'),
                  decoration: const BoxDecoration(
                    color: AsmColors.brandDeepGreen,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.electric_car,
                    color: Colors.white,
                    size: 27,
                  ),
                ),
              ),
          ],
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
