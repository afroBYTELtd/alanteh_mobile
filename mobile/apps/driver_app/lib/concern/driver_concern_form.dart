import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';

import 'driver_concern_draft.dart';
import 'driver_concern_status_row.dart';

class DriverConcernForm extends StatelessWidget {
  const DriverConcernForm({
    required this.marketLabel,
    required this.formKey,
    required this.categories,
    required this.category,
    required this.attentionLevel,
    required this.descriptionController,
    required this.categoriesLoading,
    required this.categoriesError,
    required this.submitting,
    required this.submissionError,
    required this.onCategoryChanged,
    required this.onAttentionLevelChanged,
    required this.onRetryCategories,
    required this.onSend,
    required this.onRetrySubmission,
    super.key,
  });

  final String marketLabel;
  final GlobalKey<FormState> formKey;
  final List<String> categories;
  final String? category;
  final DriverConcernAttentionLevel? attentionLevel;
  final TextEditingController descriptionController;
  final bool categoriesLoading;
  final String? categoriesError;
  final bool submitting;
  final String? submissionError;
  final ValueChanged<String?> onCategoryChanged;
  final ValueChanged<DriverConcernAttentionLevel?> onAttentionLevelChanged;
  final VoidCallback onRetryCategories;
  final VoidCallback onSend;
  final VoidCallback onRetrySubmission;

  @override
  Widget build(BuildContext context) {
    final selectedCategory = category != null && categories.contains(category)
        ? category
        : null;
    final categorySelectionEnabled =
        !categoriesLoading && categoriesError == null && categories.isNotEmpty;

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
          if (categoriesLoading)
            const _ConcernLoadingPanel()
          else if (categoriesError != null)
            _ConcernErrorPanel(
              key: const Key('concern-categories-error'),
              message: categoriesError!,
              onRetry: onRetryCategories,
              retryKey: const Key('retry-concern-categories'),
            )
          else
            DropdownButtonFormField<String>(
              key: const Key('concern-category'),
              initialValue: selectedCategory,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Issue category',
                prefixIcon: Icon(Icons.report_problem_outlined),
              ),
              items: categories
                  .map(
                    (value) => DropdownMenuItem<String>(
                      value: value,
                      child: Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(growable: false),
              onChanged: categorySelectionEnabled && !submitting
                  ? onCategoryChanged
                  : null,
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
            onChanged: submitting ? null : onAttentionLevelChanged,
            validator: (value) =>
                value == null ? 'Choose how urgent this is.' : null,
          ),
          const SizedBox(height: AsmSpacing.space16),
          TextFormField(
            key: const Key('concern-description'),
            controller: descriptionController,
            enabled: !submitting,
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
          if (submissionError != null) ...[
            const SizedBox(height: AsmSpacing.space16),
            _ConcernErrorPanel(
              key: const Key('concern-submission-error'),
              message: submissionError!,
              onRetry: onRetrySubmission,
              retryKey: const Key('retry-concern-submission'),
            ),
          ],
          const SizedBox(height: AsmSpacing.space20),
          FilledButton.icon(
            key: const Key('send-concern'),
            onPressed:
                categoriesLoading ||
                    categoriesError != null ||
                    categories.isEmpty ||
                    submitting
                ? null
                : onSend,
            icon: submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_outlined),
            label: Text(submitting ? 'Sending...' : 'Send'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConcernLoadingPanel extends StatelessWidget {
  const _ConcernLoadingPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('concern-categories-loading'),
      padding: EdgeInsets.all(AsmSpacing.space16),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: AsmSpacing.space12),
          Expanded(
            child: Text(
              'Loading report categories...',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConcernErrorPanel extends StatelessWidget {
  const _ConcernErrorPanel({
    required this.message,
    required this.onRetry,
    required this.retryKey,
    super.key,
  });

  final String message;
  final VoidCallback onRetry;
  final Key retryKey;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AsmSpacing.space16),
      decoration: BoxDecoration(
        color: AsmColors.driverCardElevated,
        borderRadius: BorderRadius.circular(AsmRadii.radius16),
        border: Border.all(color: AsmColors.driverWarningSurface),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: const TextStyle(
              color: AsmColors.driverTextSecondary,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
          const SizedBox(height: AsmSpacing.space12),
          OutlinedButton.icon(
            key: retryKey,
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
