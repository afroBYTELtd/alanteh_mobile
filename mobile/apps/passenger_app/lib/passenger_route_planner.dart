import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';

class PassengerRoutePlanner extends StatelessWidget {
  const PassengerRoutePlanner({
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
    return AsmRoutePlannerPanel(
      pickupInputTile: AsmRouteInputTile(
        key: const Key('choose-pickup'),
        markerColor: AsmColors.green,
        placeholder: 'Choose pickup',
        description: pickupDescription,
        onTap: onChoosePickup,
      ),
      destinationInputTile: AsmRouteInputTile(
        key: const Key('choose-destination'),
        markerColor: AsmColors.solarYellow,
        placeholder: 'Where to?',
        description: destinationDescription,
        onTap: onChooseDestination,
      ),
      actionRow: AsmRouteActionRow(
        swapKey: const Key('swap-route'),
        clearKey: const Key('clear-route'),
        swapEnabled: canSwap,
        showClearAction: hasRoute,
        onSwapPressed: onSwap,
        onClearPressed: onClear,
      ),
      validationNotice: locationsMatch
          ? const AsmRouteValidationNotice(
              message: 'Pickup and destination must be different.',
            )
          : null,
      actionArea: AsmPrimaryActionButton(
        key: const Key('continue-local-draft'),
        onPressed: canContinue ? onContinue : null,
        label: 'Continue',
      ),
    );
  }
}
