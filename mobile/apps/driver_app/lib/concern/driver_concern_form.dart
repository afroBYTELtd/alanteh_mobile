import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    final colors = Theme.of(context).colorScheme;

    return Form(
      key: formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AsmSpacing.space20,
          AsmSpacing.space12,
          AsmSpacing.space20,
          AsmSpacing.space24,
        ),
        children: [
          DriverConcernStatusRow(marketLabel: marketLabel),
          const SizedBox(height: AsmSpacing.space20),
          Container(
            padding: const EdgeInsets.all(AsmSpacing.space16),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AsmRadii.radius8),
              border: Border.all(color: colors.outlineVariant),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: AsmColors.solarYellow),
                SizedBox(width: AsmSpacing.space12),
                Expanded(
                  child: Text(
                    'This report is not sent from the app yet. For emergencies, follow approved local safety procedures.',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AsmSpacing.space12),
          const Text(
            'If there is immediate danger, do not drive and follow approved local safety procedures.',
            style: TextStyle(color: Color(0xFFB7C0C4), height: 1.4),
          ),
          const SizedBox(height: AsmSpacing.space20),
          DropdownButtonFormField<DriverConcernCategory>(
            key: const Key('concern-category'),
            initialValue: category,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'What is the issue?'),
            items: [
              for (final category in DriverConcernCategory.values)
                DropdownMenuItem(
                  value: category,
                  child: Text(category.label, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: onCategoryChanged,
            validator: (value) =>
                value == null ? 'Choose what the issue is.' : null,
          ),
          const SizedBox(height: AsmSpacing.space16),
          DropdownButtonFormField<DriverConcernAttentionLevel>(
            key: const Key('concern-attention'),
            initialValue: attentionLevel,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'How urgent?'),
            items: [
              for (final level in DriverConcernAttentionLevel.values)
                DropdownMenuItem(
                  value: level,
                  child: Text(level.label, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: onAttentionLevelChanged,
            validator: (value) =>
                value == null ? 'Choose how urgent this is.' : null,
          ),
          const SizedBox(height: AsmSpacing.space16),
          TextFormField(
            key: const Key('concern-description'),
            controller: descriptionController,
            decoration: const InputDecoration(
              labelText: 'Describe the issue...',
              alignLabelWithHint: true,
            ),
            minLines: 3,
            maxLines: 5,
            maxLength: 240,
            inputFormatters: [LengthLimitingTextInputFormatter(240)],
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.newline,
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Describe the issue.'
                : null,
          ),
          const SizedBox(height: AsmSpacing.space16),
          FilledButton.icon(
            key: const Key('review-concern'),
            onPressed: onReview,
            icon: const Icon(Icons.fact_check_outlined),
            label: const Text('Send report'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
          ),
        ],
      ),
    );
  }
}
