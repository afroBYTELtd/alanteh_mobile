import 'package:asm_app_config/asm_app_config.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';

import 'map/passenger_map.dart';

class PassengerHome extends StatelessWidget {
  const PassengerHome({
    required this.market,
    required this.localQaEnabled,
    required this.pickupDescription,
    required this.destinationDescription,
    required this.canContinue,
    required this.locationsMatch,
    required this.canSwap,
    required this.hasRoute,
    required this.onChoosePickup,
    required this.onChooseDestination,
    required this.onContinue,
    required this.onStartRequest,
    required this.onOpenRequests,
    required this.onSwap,
    required this.onClear,
    super.key,
  });

  final MarketConfig market;
  final bool localQaEnabled;
  final String? pickupDescription;
  final String? destinationDescription;
  final bool canContinue;
  final bool locationsMatch;
  final bool canSwap;
  final bool hasRoute;
  final VoidCallback onChoosePickup;
  final VoidCallback onChooseDestination;
  final VoidCallback onContinue;
  final VoidCallback onStartRequest;
  final VoidCallback onOpenRequests;
  final VoidCallback onSwap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Stack(
      key: const Key('passenger-home-full-screen-map-layout'),
      children: [
        const Positioned.fill(
          child: AsmPassengerMap(
            center: accraHomeCenter,
            zoom: initialZoom,
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AsmSpacing.space16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  key: const Key('passenger-home-floating-logo'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AsmSpacing.space12,
                    vertical: AsmSpacing.space8,
                  ),
                  decoration: _floatingDecoration(),
                  child: Image.asset(
                    'assets/brand/alanteh_header_dark.png',
                    width: 132,
                    height: 28,
                    fit: BoxFit.contain,
                    semanticLabel: 'ALANTEH passenger logo',
                  ),
                ),
                const Spacer(),
                Container(
                  key: const Key('passenger-home-floating-account'),
                  width: 44,
                  height: 44,
                  decoration: _floatingDecoration(shape: BoxShape.circle),
                  child: const Icon(Icons.person_outline),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          left: AsmSpacing.space16,
          right: AsmSpacing.space16,
          top: 92,
          child: Container(
            key: const Key('passenger-home-solar-banner'),
            padding: const EdgeInsets.all(AsmSpacing.space12),
            decoration: BoxDecoration(
              color: AsmColors.brandDeepGreen,
              borderRadius: BorderRadius.circular(AsmRadii.radius16),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: const Row(
              children: [
                Icon(Icons.wb_sunny_outlined, color: AsmColors.solarYellow),
                SizedBox(width: AsmSpacing.space8),
                Expanded(
                  child: Text(
                    "Ghana's first solar electric ride service. Clean, quiet, and reliable.",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            key: const Key('passenger-home-bottom-sheet'),
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(
              AsmSpacing.space20,
              AsmSpacing.space12,
              AsmSpacing.space20,
              AsmSpacing.space20,
            ),
            decoration: const BoxDecoration(
              color: AsmColors.passengerCard,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(AsmRadii.radius28),
              ),
              boxShadow: [
                BoxShadow(
                  color: Color(0x26000000),
                  blurRadius: 28,
                  offset: Offset(0, -10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AsmColors.passengerLine,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: AsmSpacing.space16),
                FilledButton.icon(
                  key: const Key('open-live-request'),
                  onPressed: onStartRequest,
                  icon: const Icon(Icons.electric_car),
                  label: const Text('Request ride'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                  ),
                ),
                const SizedBox(height: AsmSpacing.space12),
                OutlinedButton.icon(
                  key: const Key('open-ride-request-history'),
                  onPressed: onOpenRequests,
                  icon: const Icon(Icons.route_outlined),
                  label: const Text('My Ride Requests'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  BoxDecoration _floatingDecoration({BoxShape shape = BoxShape.rectangle}) {
    return BoxDecoration(
      color: const Color(0xF2FFFFFF),
      shape: shape,
      borderRadius: shape == BoxShape.rectangle
          ? BorderRadius.circular(AsmRadii.radius20)
          : null,
      boxShadow: const [
        BoxShadow(
          color: Color(0x26000000),
          blurRadius: 16,
          offset: Offset(0, 6),
        ),
      ],
    );
  }
}
