import 'package:asm_app_config/asm_app_config.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:asm_ride_domain/asm_ride_domain.dart';
import 'package:flutter/material.dart';

import 'booking_draft.dart';

class BookingReview extends StatelessWidget {
  const BookingReview({
    required this.draft,
    required this.market,
    required this.onEdit,
    required this.onClose,
    super.key,
  });

  final BookingDraft draft;
  final MarketConfig market;
  final VoidCallback onEdit;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AsmSpacing.space20,
        AsmSpacing.space16,
        AsmSpacing.space20,
        AsmSpacing.space32,
      ),
      children: [
        const _LocalDemoHeading(
          message: 'Review this draft before closing or editing it.',
        ),
        const SizedBox(height: AsmSpacing.space20),
        const AsmLocalInfoPanel(message: 'No ride request has been sent.'),
        const SizedBox(height: AsmSpacing.space24),
        AsmRideDetailRow(
          label: 'Operating market',
          value: '${market.city}, ${market.countryName}',
          selectableValue: true,
        ),
        AsmRideDetailRow(
          label: 'Service context',
          value: draft.serviceContext.label,
          selectableValue: true,
        ),
        AsmRideDetailRow(
          label: 'Pickup',
          value: draft.rideDraft.pickupDisplayText,
          selectableValue: true,
        ),
        AsmRideDetailRow(
          label: 'Destination',
          value: draft.rideDraft.destinationDisplayText,
          selectableValue: true,
        ),
        AsmRideDetailRow(
          label: 'Passengers',
          value: '${draft.passengerCount.value}',
          selectableValue: true,
        ),
        if (draft.assistanceNote != null)
          AsmRideDetailRow(
            label: 'Assistance note',
            value: draft.assistanceNote!.value,
            selectableValue: true,
          ),
        const SizedBox(height: AsmSpacing.space16),
        OutlinedButton.icon(
          key: const Key('edit-booking-draft'),
          onPressed: onEdit,
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Edit details'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
          ),
        ),
        const SizedBox(height: AsmSpacing.space12),
        FilledButton.icon(
          key: const Key('close-booking-draft'),
          onPressed: onClose,
          icon: const Icon(Icons.close),
          label: const Text('Close draft'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        ),
      ],
    );
  }
}

class _LocalDemoHeading extends StatelessWidget {
  const _LocalDemoHeading({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AsmSpacing.space12,
            vertical: AsmSpacing.space8,
          ),
          decoration: BoxDecoration(
            color: colors.primaryContainer,
            borderRadius: BorderRadius.circular(AsmRadii.radius6),
          ),
          child: Text(
            'LOCAL DEMO',
            style: TextStyle(
              color: colors.onPrimaryContainer,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: AsmSpacing.space12),
        Text(
          message,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: colors.onSurfaceVariant,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}
