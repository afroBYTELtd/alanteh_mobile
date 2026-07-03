import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';

import 'driver_ride_offer_preview.dart';

class DriverRideOfferDecisionPreview extends StatelessWidget {
  const DriverRideOfferDecisionPreview({
    required this.preview,
    required this.onClosePreview,
    super.key,
  });

  final DriverRideOfferPreview preview;
  final VoidCallback onClosePreview;

  @override
  Widget build(BuildContext context) {
    final accepted =
        preview.status == DriverRideOfferPreviewStatus.acceptedPreview;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          accepted ? Icons.check_circle_outline : Icons.cancel_outlined,
          size: 52,
          color: AsmColors.solarYellow,
        ),
        const SizedBox(height: AsmSpacing.space16),
        Text(
          accepted ? 'Accepted' : 'Declined',
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: AsmSpacing.space16),
        AsmLocalInfoPanel(
          message: accepted
              ? 'Trip marked accepted on this screen.'
              : 'Trip marked declined on this screen.',
          backgroundColor: const Color(0xFF343026),
          borderColor: const Color(0xFF554C39),
          iconColor: AsmColors.solarYellow,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: AsmSpacing.space24),
        FilledButton.icon(
          key: const Key('close-ride-offer-preview'),
          onPressed: onClosePreview,
          icon: const Icon(Icons.close_outlined),
          label: const Text('Close'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        ),
      ],
    );
  }
}
