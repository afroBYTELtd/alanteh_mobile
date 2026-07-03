import 'package:asm_design_system/asm_design_system.dart';
import 'package:asm_ride_domain/asm_ride_domain.dart';
import 'package:flutter/material.dart';

import 'driver_ride_offer_preview.dart';

class DriverRideOfferPendingPreview extends StatelessWidget {
  const DriverRideOfferPendingPreview({
    required this.preview,
    required this.onAcceptPreview,
    required this.onDeclinePreview,
    super.key,
  });

  final DriverRideOfferPreview preview;
  final VoidCallback onAcceptPreview;
  final VoidCallback onDeclinePreview;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AsmLocalInfoPanel(
          message: 'Review the route before accepting.',
          backgroundColor: Color(0xFF343026),
          borderColor: Color(0xFF554C39),
          iconColor: AsmColors.solarYellow,
          textStyle: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: AsmSpacing.space24),
        const Text(
          'Route card',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: AsmSpacing.space16),
        AsmRideDetailRow(
          label: 'Service context',
          value: preview.serviceContext.label,
          labelStyle: const TextStyle(color: Color(0xFFB7C0C4)),
          valueStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
        AsmRideDetailRow(
          contained: true,
          icon: Icons.trip_origin,
          label: 'Pickup',
          value: preview.rideOfferPreview.pickupDisplayText,
          iconColor: AsmColors.solarYellow,
          backgroundColor: const Color(0xFF20272B),
          borderColor: const Color(0xFF3A4449),
          labelStyle: const TextStyle(color: Color(0xFFB7C0C4)),
          valueStyle: const TextStyle(fontWeight: FontWeight.w700),
          key: const Key('ride-offer-pickup'),
        ),
        const SizedBox(height: AsmSpacing.space12),
        AsmRideDetailRow(
          contained: true,
          icon: Icons.location_on_outlined,
          label: 'Destination',
          value: preview.rideOfferPreview.destinationDisplayText,
          iconColor: AsmColors.solarYellow,
          backgroundColor: const Color(0xFF20272B),
          borderColor: const Color(0xFF3A4449),
          labelStyle: const TextStyle(color: Color(0xFFB7C0C4)),
          valueStyle: const TextStyle(fontWeight: FontWeight.w700),
          key: const Key('ride-offer-destination'),
        ),
        const SizedBox(height: AsmSpacing.space12),
        AsmRideDetailRow(
          label: 'Passengers',
          value: '${preview.passengerCount.value}',
          labelStyle: const TextStyle(color: Color(0xFFB7C0C4)),
          valueStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: AsmSpacing.space24),
        FilledButton.icon(
          key: const Key('accept-ride-offer-preview'),
          onPressed: onAcceptPreview,
          icon: const Icon(Icons.check_outlined),
          label: const Text('Accept'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        ),
        const SizedBox(height: AsmSpacing.space8),
        OutlinedButton.icon(
          key: const Key('decline-ride-offer-preview'),
          onPressed: onDeclinePreview,
          icon: const Icon(Icons.close_outlined),
          label: const Text('Decline'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
          ),
        ),
      ],
    );
  }
}
