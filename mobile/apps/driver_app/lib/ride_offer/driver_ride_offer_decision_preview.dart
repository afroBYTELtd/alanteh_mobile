import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';

import 'driver_ride_offer_preview.dart';

class DriverRideOfferDecisionPreview extends StatelessWidget {
  const DriverRideOfferDecisionPreview({
    required this.preview,
    required this.onClosePreview,
    this.onNavigateToPickup,
    super.key,
  });

  final DriverRideOfferPreview preview;
  final VoidCallback onClosePreview;
  final VoidCallback? onNavigateToPickup;

  @override
  Widget build(BuildContext context) {
    final accepted =
        preview.status == DriverRideOfferPreviewStatus.acceptedPreview;

    final title = switch (preview.status) {
      DriverRideOfferPreviewStatus.acceptedPreview => 'Ride accepted',
      DriverRideOfferPreviewStatus.declinedPreview => 'Offer declined',
      DriverRideOfferPreviewStatus.expiredPreview => 'Offer expired',
      DriverRideOfferPreviewStatus.pending => 'New ride offer',
    };

    final message = switch (preview.status) {
      DriverRideOfferPreviewStatus.acceptedPreview =>
        'Head to ${preview.pickupDescription.value} to pick up your passenger.',
      DriverRideOfferPreviewStatus.declinedPreview =>
        "You'll continue receiving new ride offers while online.",
      DriverRideOfferPreviewStatus.expiredPreview =>
        "You didn't respond in time, so this ride was offered to another "
            'driver nearby.',
      DriverRideOfferPreviewStatus.pending =>
        'Review the ride offer before responding.',
    };

    final icon = switch (preview.status) {
      DriverRideOfferPreviewStatus.acceptedPreview =>
        Icons.check_circle_outline,
      DriverRideOfferPreviewStatus.declinedPreview => Icons.cancel_outlined,
      DriverRideOfferPreviewStatus.expiredPreview => Icons.schedule_outlined,
      DriverRideOfferPreviewStatus.pending => Icons.notifications_outlined,
    };

    final iconColor = switch (preview.status) {
      DriverRideOfferPreviewStatus.acceptedPreview =>
        AsmColors.driverMintAction,
      DriverRideOfferPreviewStatus.declinedPreview =>
        AsmColors.driverTextSecondary,
      DriverRideOfferPreviewStatus.expiredPreview => Colors.amber,
      DriverRideOfferPreviewStatus.pending => AsmColors.driverMintAction,
    };

    final stateKey = switch (preview.status) {
      DriverRideOfferPreviewStatus.acceptedPreview => 'ride-offer-accepted',
      DriverRideOfferPreviewStatus.declinedPreview => 'ride-offer-declined',
      DriverRideOfferPreviewStatus.expiredPreview => 'ride-offer-expired',
      DriverRideOfferPreviewStatus.pending => 'ride-offer-pending',
    };

    return Column(
      key: ValueKey(stateKey),
      children: [
        const SizedBox(height: AsmSpacing.space32),
        CircleAvatar(
          radius: 39,
          backgroundColor: AsmColors.driverCardElevated,
          foregroundColor: iconColor,
          child: Icon(icon, size: 42),
        ),
        const SizedBox(height: AsmSpacing.space20),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 29, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: AsmSpacing.space12),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AsmColors.driverTextSecondary,
            fontSize: 16,
            height: 1.45,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AsmSpacing.space32),
        if (accepted && onNavigateToPickup != null) ...[
          FilledButton.icon(
            key: const Key('navigate-to-pickup-from-accepted'),
            onPressed: onNavigateToPickup,
            icon: const Icon(Icons.navigation_outlined),
            label: const Text('Navigate to pickup'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
            ),
          ),
          const SizedBox(height: AsmSpacing.space8),
        ],
        OutlinedButton.icon(
          key: const Key('close-ride-offer-preview'),
          onPressed: onClosePreview,
          icon: const Icon(Icons.arrow_back_outlined),
          label: const Text('Back to home'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(54),
          ),
        ),
      ],
    );
  }
}
