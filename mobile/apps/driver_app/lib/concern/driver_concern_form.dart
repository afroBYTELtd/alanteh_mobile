import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';

import 'driver_concern_draft.dart';
import 'driver_concern_status_row.dart';

class DriverConcernForm extends StatelessWidget {
  const DriverConcernForm({
    required this.marketLabel,
    required this.formKey,
    required this.category,
    required this.attentionLevel,
    required this.descriptionController,
    required this.onCategoryChanged,
    required this.onAttentionLevelChanged,
    required this.onReview,
    super.key,
  });

  final String marketLabel;
  final GlobalKey<FormState> formKey;
  final DriverConcernCategory? category;
  final DriverConcernAttentionLevel? attentionLevel;
  final TextEditingController descriptionController;
  final ValueChanged<DriverConcernCategory?> onCategoryChanged;
  final ValueChanged<DriverConcernAttentionLevel?> onAttentionLevelChanged;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: ListView(
        key: const Key('concern-form'),
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
            "What's the issue?",
            style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: AsmSpacing.space8),
          const Text(
            'Select a category so ALANTEH can respond appropriately.',
            style: TextStyle(
              color: AsmColors.driverTextSecondary,
              fontSize: 16,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AsmSpacing.space20),
          DropdownButtonFormField<DriverConcernCategory>(
            key: const Key('concern-category'),
            initialValue: category,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Issue category',
              prefixIcon: Icon(Icons.report_problem_outlined),
            ),
            items: DriverConcernCategory.values
                .map(
                  (value) => DropdownMenuItem<DriverConcernCategory>(
                    value: value,
                    child: Text(
                      _categoryDisplayLabel(value),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(growable: false),
            onChanged: onCategoryChanged,
            validator: (value) =>
                value == null ? 'Choose what the issue is.' : null,
          ),
          const SizedBox(height: AsmSpacing.space16),
          DropdownButtonFormField<DriverConcernAttentionLevel>(
            key: const Key('concern-attention'),
            initialValue: attentionLevel,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Attention needed',
              prefixIcon: Icon(Icons.priority_high_outlined),
            ),
            items: DriverConcernAttentionLevel.values
                .map(
                  (value) => DropdownMenuItem<DriverConcernAttentionLevel>(
                    value: value,
                    child: Text(
                      value.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(growable: false),
            onChanged: onAttentionLevelChanged,
            validator: (value) =>
                value == null ? 'Choose how urgent this is.' : null,
          ),
          const SizedBox(height: AsmSpacing.space16),
          TextFormField(
            key: const Key('concern-description'),
            controller: descriptionController,
            minLines: 4,
            maxLines: 6,
            maxLength: 240,
            decoration: const InputDecoration(
              labelText: 'Describe what happened',
              alignLabelWithHint: true,
              hintText: 'Add the important details.',
              prefixIcon: Icon(Icons.notes_outlined),
            ),
            validator: (value) {
              final description = value?.trim() ?? '';

              if (description.isEmpty) {
                return 'Describe the issue.';
              }

              if (description.length > 240) {
                return 'Description must be 240 characters or fewer.';
              }

              return null;
            },
          ),
          const SizedBox(height: AsmSpacing.space12),
          Container(
            padding: const EdgeInsets.all(AsmSpacing.space16),
            decoration: BoxDecoration(
              color: AsmColors.driverCardElevated,
              borderRadius: BorderRadius.circular(AsmRadii.radius24),
              border: Border.all(color: AsmColors.driverLine),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Safety first',
                  style: TextStyle(
                    color: AsmColors.driverMintAction,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: AsmSpacing.space8),
                Text(
                  'This report is not sent from the app yet. For emergencies, '
                  'follow approved local safety procedures.',
                  style: TextStyle(
                    color: AsmColors.driverTextSecondary,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: AsmSpacing.space8),
                Text(
                  'If there is immediate danger, do not drive and follow '
                  'approved local safety procedures.',
                  style: TextStyle(
                    color: AsmColors.driverTextSecondary,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AsmSpacing.space20),
          FilledButton.icon(
            key: const Key('review-concern'),
            onPressed: onReview,
            icon: const Icon(Icons.arrow_forward_outlined),
            label: const Text('Submit report'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
            ),
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
