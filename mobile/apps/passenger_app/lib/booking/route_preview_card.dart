import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../map/osrm_route.dart';
import '../map/passenger_map.dart';

class RoutePreviewCard extends StatefulWidget {
  const RoutePreviewCard({
    this.routeService = const OsrmPassengerRouteService(),
    this.onAuthoritativeEstimateChanged,
    super.key,
  });

  final PassengerRouteService routeService;
  final ValueChanged<PassengerRouteEstimate?>? onAuthoritativeEstimateChanged;

  @override
  State<RoutePreviewCard> createState() => _RoutePreviewCardState();
}

class _RoutePreviewCardState extends State<RoutePreviewCard> {
  PassengerRouteEstimate? _estimate;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    PassengerRouteEstimate estimate;
    try {
      estimate = await widget.routeService.route();
    } on Object {
      estimate = safeDirectRouteFallback();
    }

    if (!mounted) {
      return;
    }

    setState(() => _estimate = estimate);
    widget.onAuthoritativeEstimateChanged?.call(
      estimate.usedFallback ? null : estimate,
    );
  }

  @override
  Widget build(BuildContext context) {
    final estimate = _estimate;
    return Container(
      key: const Key('osrm-route-preview-card'),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AsmRadii.radius20),
        border: Border.all(color: AsmColors.passengerLine),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          AsmPassengerMap(
            height: 220,
            center: const LatLng(5.5766, -0.1903),
            zoom: 12.5,
            pickup: accraPickup,
            destination: accraDestination,
            route: estimate?.points ?? const [accraPickup, accraDestination],
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                const Icon(Icons.route, color: AsmColors.brandDeepGreen),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    estimate == null
                        ? 'Calculating route…'
                        : '${estimate.distanceKilometres.toStringAsFixed(1)} km · about ${estimate.durationMinutes} min',
                    key: const Key('route-distance-duration'),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                if (estimate?.usedFallback == true)
                  const Tooltip(
                    message:
                        'Route service unavailable. Showing a direct-line estimate.',
                    child: Icon(Icons.info_outline, size: 20),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
