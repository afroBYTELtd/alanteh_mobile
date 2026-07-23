import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';

import 'driver_concern_draft.dart';
import 'driver_concern_status_row.dart';

class DriverConcernReview extends StatelessWidget {
  const DriverConcernReview({
    required this.marketLabel,
    required this.draft,
    required this.onConfirm,
    required this.onEdit,
    required this.onClose,
    super.key,
  });

  final String marketLabel;
  final DriverConcernDraft draft;
  final VoidCallback onConfirm;
  final VoidCallback onEdit;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const Key('concern-review'),
      padding: const EdgeInsets.fromLTRB(
        AsmSpacing.space20,
        AsmSpacing.space12,
        AsmSpacing.space20,
        AsmSpacing.space24,
      ),
      children: [
        DriverConcernStatusRow(marketLabel: marketLabel),
        const SizedBox(height: AsmSpacing.space20),
        const Text(
          'Review report',
          style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: AsmSpacing.space8),
        const Text(
          'Review this local draft',
          style: TextStyle(
            color: AsmColors.driverTextSecondary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AsmSpacing.space20),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AsmSpacing.space20),
          decoration: BoxDecoration(
            color: AsmColors.driverCardElevated,
            borderRadius: BorderRadius.circular(AsmRadii.radius24),
            border: Border.all(color: AsmColors.driverLine),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This report is not sent from the app yet.',
                style: TextStyle(
                  color: AsmColors.driverTextSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AsmSpacing.space16),
              _ConcernReviewRow(
                label: 'Service area',
                value: marketLabel,
                valueKey: const Key('concern-review-market'),
              ),
              _ConcernReviewRow(
                label: 'Category',
                value: _categoryDisplayLabel(draft.category),
              ),
              const _ConcernReviewRow(
                label: 'Vehicle',
                value: 'Current assigned vehicle',
              ),
              _ConcernReviewRow(
                label: 'Attention',
                value: draft.attentionLevel.label,
              ),
              _ConcernReviewRow(label: 'Details', value: draft.description),
            ],
          ),
        ),
        const SizedBox(height: AsmSpacing.space20),
        FilledButton.icon(
          key: const Key('confirm-concern'),
          onPressed: onConfirm,
          icon: const Icon(Icons.info_outline),
          label: const Text('Continue without sending'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
        ),
        const SizedBox(height: AsmSpacing.space8),
        OutlinedButton.icon(
          key: const Key('edit-concern'),
          onPressed: onEdit,
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Edit'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
          ),
        ),
        const SizedBox(height: AsmSpacing.space8),
        TextButton(
          key: const Key('close-concern'),
          onPressed: onClose,
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _ConcernReviewRow extends StatelessWidget {
  const _ConcernReviewRow({
    required this.label,
    required this.value,
    this.valueKey,
  });

  final String label;
  final String value;
  final Key? valueKey;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AsmSpacing.space12),
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
            key: valueKey,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

String _categoryDisplayLabel(DriverConcernCategory category) {
  return switch (category) {
    DriverConcernCategory.vehicleCondition => 'Vehicle problem',
    DriverConcernCategory.batteryOrCharging => 'Battery / charging',
    DriverConcernCategory.cabinOrSafetyEquipment => 'Route / safety concern',
    DriverConcernCategory.shiftDetailsOrDocuments => 'Passenger issue',
    DriverConcernCategory.otherConcern => 'Other',
  };
}
