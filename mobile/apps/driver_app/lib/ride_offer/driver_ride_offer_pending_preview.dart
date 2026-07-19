import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';

import 'driver_ride_offer_preview.dart';

class DriverRideOfferPendingPreview extends StatelessWidget {
  const DriverRideOfferPendingPreview({
    required this.preview,
    required this.countdownSeconds,
    required this.countdownTotalSeconds,
    required this.showDetails,
    required this.onViewDetails,
    required this.onAcceptPreview,
    required this.onDeclinePreview,
    super.key,
  });

  final DriverRideOfferPreview preview;
  final int countdownSeconds;
  final int countdownTotalSeconds;
  final bool showDetails;
  final VoidCallback onViewDetails;
  final VoidCallback onAcceptPreview;
  final VoidCallback onDeclinePreview;

  @override
  Widget build(BuildContext context) {
    final route =
        '${preview.pickupDescription.value} → '
        '${preview.destinationDescription.value}';

    if (!showDetails) {
      return Column(
        key: const Key('ride-offer-preview-state'),
        children: [
          _CountdownRing(
            seconds: countdownSeconds,
            totalSeconds: countdownTotalSeconds,
          ),
          const SizedBox(height: AsmSpacing.space16),
          const Text(
            'New ride offer',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: AsmSpacing.space20),
          _OfferCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  route,
                  key: const Key('ride-offer-route-summary'),
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: AsmSpacing.space20),
                const Wrap(
                  spacing: AsmSpacing.space12,
                  runSpacing: AsmSpacing.space12,
                  children: [
                    _OfferMetric(label: 'Distance', value: '9.5 km'),
                    _OfferMetric(label: 'Pickup', value: '1.2 km away'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AsmSpacing.space20),
          FilledButton(
            key: const Key('view-ride-offer-details'),
            onPressed: onViewDetails,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
            ),
            child: const Text('View details'),
          ),
        ],
      );
    }

    return Column(
      key: const Key('ride-offer-detail-state'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Ride offer',
          style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: AsmSpacing.space16),
        _OfferCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                route,
                key: const Key('ride-offer-detail-route'),
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: AsmSpacing.space20),
              AsmRideDetailRow(
                contained: true,
                icon: Icons.trip_origin,
                label: 'Pickup',
                value: preview.pickupDescription.value,
                iconColor: AsmColors.driverMintAction,
                backgroundColor: AsmColors.driverCard,
                borderColor: AsmColors.driverLine,
                labelStyle: const TextStyle(
                  color: AsmColors.driverTextSecondary,
                ),
                valueStyle: const TextStyle(fontWeight: FontWeight.w800),
                key: const Key('ride-offer-pickup'),
              ),
              const SizedBox(height: AsmSpacing.space12),
              AsmRideDetailRow(
                contained: true,
                icon: Icons.location_on_outlined,
                label: 'Destination',
                value: preview.destinationDescription.value,
                iconColor: AsmColors.driverTextSecondary,
                backgroundColor: AsmColors.driverCard,
                borderColor: AsmColors.driverLine,
                labelStyle: const TextStyle(
                  color: AsmColors.driverTextSecondary,
                ),
                valueStyle: const TextStyle(fontWeight: FontWeight.w800),
                key: const Key('ride-offer-destination'),
              ),
              const SizedBox(height: AsmSpacing.space20),
              const Wrap(
                spacing: AsmSpacing.space12,
                runSpacing: AsmSpacing.space12,
                children: [
                  _OfferMetric(label: 'Distance', value: '9.5 km'),
                  _OfferMetric(label: 'Est. duration', value: '23 min'),
                  _OfferMetric(label: 'Passengers', value: '2'),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AsmSpacing.space20),
        FilledButton.icon(
          key: const Key('accept-ride-offer-preview'),
          onPressed: onAcceptPreview,
          icon: const Icon(Icons.check_outlined),
          label: const Text('Accept'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
        ),
        const SizedBox(height: AsmSpacing.space8),
        OutlinedButton.icon(
          key: const Key('decline-ride-offer-preview'),
          onPressed: onDeclinePreview,
          icon: const Icon(Icons.close_outlined),
          label: const Text('Decline'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(54),
          ),
        ),
      ],
    );
  }
}

class _CountdownRing extends StatelessWidget {
  const _CountdownRing({required this.seconds, required this.totalSeconds});

  final int seconds;
  final int totalSeconds;

  @override
  Widget build(BuildContext context) {
    final safeTotal = totalSeconds <= 0 ? 14 : totalSeconds;
    final progress = (seconds / safeTotal).clamp(0.0, 1.0);

    return SizedBox(
      key: const Key('ride-offer-countdown-ring'),
      width: 72,
      height: 72,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CircularProgressIndicator(
            value: progress,
            strokeWidth: 6,
            backgroundColor: AsmColors.driverLine,
          ),
          Center(
            child: Text(
              '${seconds}s',
              key: const Key('ride-offer-countdown'),
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

class _OfferCard extends StatelessWidget {
  const _OfferCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AsmSpacing.space20),
      decoration: BoxDecoration(
        color: AsmColors.driverCardElevated,
        borderRadius: BorderRadius.circular(AsmRadii.radius24),
        border: Border.all(color: AsmColors.driverLine),
      ),
      child: child,
    );
  }
}

class _OfferMetric extends StatelessWidget {
  const _OfferMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 104),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AsmColors.driverTextSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AsmSpacing.space4),
          Text(
            value,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}
