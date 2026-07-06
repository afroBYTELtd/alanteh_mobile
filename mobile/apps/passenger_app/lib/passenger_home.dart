import 'package:asm_app_config/asm_app_config.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';
import 'package:passenger_app/passenger_route_planner.dart';

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
          Image.asset(
            'assets/brand/alanteh_header_dark.png',
            key: const Key('passenger-home-brand-logo'),
            height: 36,
            fit: BoxFit.contain,
            alignment: Alignment.centerLeft,
            semanticLabel: 'ALANTEH passenger logo',
          ),
          const SizedBox(height: AsmSpacing.space12),
          Text(
            'Book a ride',
            style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: AsmSpacing.space8),
          Text(
            'The Control Center will review your request and confirm pickup details.',
            key: const Key('passenger-live-request-safety-copy'),
            style: textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AsmSpacing.space16),
          if (localQaEnabled) ...[
            Text(
              'Local QA route preview',
              key: const Key('local-qa-route-preview-label'),
              style: textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AsmSpacing.space8),
            AsmLocalMapPreviewSurface(
              key: const Key('local-map-preview'),
              icon: Icons.map_outlined,
              title: 'Map preview unavailable.',
              minHeight: 190,
              titleStyle: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AsmSpacing.space16),
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
          ] else
            FilledButton.icon(
              key: const Key('open-live-request'),
              onPressed: onStartRequest,
              icon: const Icon(Icons.directions_car_filled_outlined),
              label: const Text('Request ride'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
        ],
      ),
    );
  }
}
