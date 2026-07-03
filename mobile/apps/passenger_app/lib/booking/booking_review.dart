import 'package:asm_design_system/asm_design_system.dart';
import 'package:asm_ride_domain/asm_ride_domain.dart';
import 'package:flutter/material.dart';

import 'booking_draft.dart';

class BookingReview extends StatelessWidget {
  const BookingReview({
    required this.draft,
    required this.onEdit,
    required this.onConfirm,
    super.key,
  });

  final BookingDraft draft;
  final VoidCallback onEdit;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AsmSpacing.space20,
        AsmSpacing.space16,
        AsmSpacing.space20,
        AsmSpacing.space32,
      ),
      children: [
        Text(
          'Confirm your ride',
          style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: AsmSpacing.space8),
        Text(
          'Check your ride details before requesting.',
          style: textTheme.bodyLarge?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            height: 1.4,
          ),
        ),
        const SizedBox(height: AsmSpacing.space24),
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
          label: 'Passenger count',
          value: '${draft.passengerCount.value}',
          selectableValue: true,
        ),
        const AsmRideDetailRow(
          label: 'Payment method',
          value: 'MTN MoMo',
          selectableValue: true,
        ),
        if (draft.assistanceNote != null)
          AsmRideDetailRow(
            label: 'Special request',
            value: draft.assistanceNote!.value,
            selectableValue: true,
          ),
        const SizedBox(height: AsmSpacing.space16),
        OutlinedButton.icon(
          key: const Key('edit-booking-details'),
          onPressed: onEdit,
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Edit details'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
          ),
        ),
        const SizedBox(height: AsmSpacing.space12),
        FilledButton.icon(
          key: const Key('confirm-and-request'),
          onPressed: onConfirm,
          icon: const Icon(Icons.check_circle_outline),
          label: const Text('Confirm and request'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        ),
      ],
    );
  }
}
