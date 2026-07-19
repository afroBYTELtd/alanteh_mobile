import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import 'driver_trip_route.dart';

const driverOsmTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const driverOsmUserAgentPackageName = 'io.alanteh.driver';

class DriverTripMap extends StatelessWidget {
  const DriverTripMap({
    required this.route,
    required this.showPickup,
    required this.showDestination,
    super.key,
  });

  final DriverTripRouteEstimate route;
  final bool showPickup;
  final bool showDestination;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      key: const Key('driver-trip-map'),
      color: AsmColors.driverCard,
      child: FlutterMap(
        options: MapOptions(
          initialCenter: route.center,
          initialZoom: route.zoom,
          minZoom: 5,
          maxZoom: 18,
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.all,
          ),
        ),
        children: [
          TileLayer(
            urlTemplate: driverOsmTileUrl,
            userAgentPackageName: driverOsmUserAgentPackageName,
          ),
          PolylineLayer(
            polylines: [
              Polyline(
                points: route.points,
                strokeWidth: 6,
                color: AsmColors.driverMintAction,
              ),
            ],
          ),
          MarkerLayer(
            markers: [
              if (showPickup)
                const Marker(
                  point: driverPickupPosition,
                  width: 46,
                  height: 46,
                  child: Icon(
                    Icons.trip_origin,
                    key: Key('driver-pickup-position-pin'),
                    color: AsmColors.driverMintAction,
                    size: 38,
                  ),
                ),
              if (showDestination)
                const Marker(
                  point: driverDestinationPosition,
                  width: 48,
                  height: 48,
                  child: Icon(
                    Icons.location_on,
                    key: Key('driver-destination-position-pin'),
                    color: Colors.white,
                    size: 42,
                  ),
                ),
              Marker(
                point: route.vehiclePosition,
                width: 52,
                height: 52,
                child: Container(
                  key: const Key('driver-static-position-pin'),
                  decoration: const BoxDecoration(
                    color: AsmColors.driverMintAction,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: Color(0x52000000), blurRadius: 12),
                    ],
                  ),
                  child: const Icon(
                    Icons.electric_car,
                    color: AsmColors.driverScaffold,
                    size: 29,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
