import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';

import 'driver_concern_draft.dart';
import 'driver_concern_status_row.dart';

class DriverConcernReview extends StatelessWidget {
  const DriverConcernReview({
    required this.marketLabel,
    required this.draft,
    required this.onEdit,
    required this.onClose,
    super.key,
  });

  final String marketLabel;
  final DriverConcernDraft draft;
  final VoidCallback onEdit;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

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
        Container(
          padding: const EdgeInsets.all(AsmSpacing.space16),
          decoration: BoxDecoration(
            color: colors.primaryContainer,
            borderRadius: BorderRadius.circular(AsmRadii.radius8),
          ),
          child: Text(
            'No issue report has been sent.',
            style: TextStyle(
              color: colors.onPrimaryContainer,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: AsmSpacing.space20),
        _ReviewValue(label: 'Service area', value: marketLabel),
        _ReviewValue(label: 'What is the issue?', value: draft.category.label),
        _ReviewValue(label: 'How urgent?', value: draft.attentionLevel.label),
        _ReviewValue(label: 'Description', value: draft.description),
        const SizedBox(height: AsmSpacing.space16),
        OutlinedButton.icon(
          key: const Key('edit-concern'),
          onPressed: onEdit,
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Edit report'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
          ),
        ),
        const SizedBox(height: AsmSpacing.space8),
        FilledButton.icon(
          key: const Key('close-concern'),
          onPressed: onClose,
          icon: const Icon(Icons.close),
          label: const Text('Close'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        ),
      ],
    );
  }
}

class _ReviewValue extends StatelessWidget {
  const _ReviewValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AsmSpacing.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFFB7C0C4))),
          const SizedBox(height: AsmSpacing.space4),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
