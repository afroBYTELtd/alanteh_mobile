import 'package:asm_app_config/asm_app_config.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';
import 'package:passenger_app/passenger_route_planner.dart';

class PassengerHome extends StatelessWidget {
  const PassengerHome({
    required this.market,
    required this.pickupDescription,
    required this.destinationDescription,
    required this.canContinue,
    required this.locationsMatch,
    required this.canSwap,
    required this.hasRoute,
    required this.onChoosePickup,
    required this.onChooseDestination,
    required this.onContinue,
    required this.onSwap,
    required this.onClear,
    super.key,
  });

  final MarketConfig market;
  final String? pickupDescription;
  final String? destinationDescription;
  final bool canContinue;
  final bool locationsMatch;
  final bool canSwap;
  final bool hasRoute;
  final VoidCallback onChoosePickup;
  final VoidCallback onChooseDestination;
  final VoidCallback onContinue;
  final VoidCallback onSwap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return AsmScreenSurface(
      scrollable: true,
      padding: const EdgeInsets.fromLTRB(
        AsmSpacing.space16,
        AsmSpacing.space12,
        AsmSpacing.space16,
        AsmSpacing.space20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AsmScreenHeader(
            leading: const AsmAppBrandMark(),
            title: 'ALANTEH',
            titleStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AsmSpacing.space12),
          AsmLocalMapPreviewSurface(
            key: const Key('local-map-preview'),
            icon: Icons.map_outlined,
            title: 'Map preview unavailable.',
            minHeight: 190,
            titleStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AsmSpacing.space16),
          Text(
            'Book a ride',
            style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: AsmSpacing.space4),
          Text(
            'Where are you?',
            style: textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AsmSpacing.space12),
          PassengerRoutePlanner(
            pickupDescription: pickupDescription,
            destinationDescription: destinationDescription,
            canContinue: canContinue,
            locationsMatch: locationsMatch,
            canSwap: canSwap,
            hasRoute: hasRoute,
            onChoosePickup: onChoosePickup,
            onChooseDestination: onChooseDestination,
            onContinue: onContinue,
            onSwap: onSwap,
            onClear: onClear,
          ),
        ],
      ),
    );
  }
}
