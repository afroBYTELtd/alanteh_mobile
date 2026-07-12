import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

const accraCenter = LatLng(5.6037, -0.1870);
const initialZoom = 13.0;
const osmTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const osmUserAgentPackageName = 'io.alanteh.passenger';

class AsmPassengerMap extends StatelessWidget {
  const AsmPassengerMap({
    this.pickupDescription,
    this.minHeight = 190,
    super.key,
  });

  final String? pickupDescription;
  final double minHeight;

  bool get _hasPickupDescription =>
      pickupDescription?.trim().isNotEmpty == true;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      key: const Key('passenger-map'),
      borderRadius: BorderRadius.circular(AsmRadii.radius20),
      child: SizedBox(
        height: minHeight,
        width: double.infinity,
        child: Stack(
          children: [
            const Positioned.fill(child: ColoredBox(color: Color(0xFFE7F1EA))),
            FlutterMap(
              options: const MapOptions(
                initialCenter: accraCenter,
                initialZoom: initialZoom,
                minZoom: 5,
                maxZoom: 18,
                interactionOptions: InteractionOptions(
                  flags:
                      InteractiveFlag.drag |
                      InteractiveFlag.pinchZoom |
                      InteractiveFlag.doubleTapZoom |
                      InteractiveFlag.scrollWheelZoom,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: osmTileUrl,
                  userAgentPackageName: osmUserAgentPackageName,
                ),
                if (_hasPickupDescription)
                  MarkerLayer(
                    markers: const [
                      Marker(
                        point: accraCenter,
                        width: 44,
                        height: 44,
                        child: Icon(
                          Icons.location_on,
                          key: Key('passenger-map-pickup-marker'),
                          color: AsmColors.brandDeepGreen,
                          size: 40,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
