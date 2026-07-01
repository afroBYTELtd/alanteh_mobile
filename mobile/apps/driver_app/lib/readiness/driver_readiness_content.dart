import 'package:asm_app_config/asm_app_config.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';

import 'driver_readiness_check.dart';

class DriverReadinessContent extends StatelessWidget {
  const DriverReadinessContent({
    required this.market,
    required this.check,
    required this.onToggle,
    required this.onReset,
    required this.onOpenConcern,
    super.key,
  });

  final MarketConfig market;
  final DriverReadinessCheck check;
  final ValueChanged<DriverReadinessItem> onToggle;
  final VoidCallback onReset;
  final VoidCallback onOpenConcern;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final marketLabel = '${market.city}, ${market.countryName}';
    final totalCount = DriverReadinessItem.values.length;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AsmSpacing.space20,
          AsmSpacing.space12,
          AsmSpacing.space20,
          AsmSpacing.space24,
        ),
        children: [
          Row(
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
              const Spacer(),
              Flexible(
                child: Text(
                  marketLabel,
                  key: const Key('readiness-market'),
                  textAlign: TextAlign.end,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
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
                    'This local checklist does not start a shift or connect dispatch.',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AsmSpacing.space20),
          Text(
            '${check.completedCount} of $totalCount checks complete',
            key: const Key('readiness-count'),
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: AsmSpacing.space8),
          for (final item in DriverReadinessItem.values)
            Card(
              margin: const EdgeInsets.only(bottom: AsmSpacing.space8),
              child: CheckboxListTile(
                key: ValueKey('readiness-${item.name}'),
                value: check.completedItems.contains(item),
                onChanged: (_) => onToggle(item),
                title: Text(item.label),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AsmSpacing.space12,
                  vertical: AsmSpacing.space4,
                ),
              ),
            ),
          if (check.isComplete) ...[
            const SizedBox(height: AsmSpacing.space8),
            Container(
              key: const Key('readiness-complete'),
              padding: const EdgeInsets.all(AsmSpacing.space12),
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(AsmRadii.radius8),
              ),
              child: Text(
                'Local checklist complete',
                style: TextStyle(
                  color: colors.onPrimaryContainer,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
          const SizedBox(height: AsmSpacing.space12),
          const Text(
            'No driver service has been activated.',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AsmSpacing.space8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('reset-readiness'),
              onPressed: onReset,
              icon: const Icon(Icons.restart_alt),
              label: const Text('Reset checklist'),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('readiness-open-concern'),
              onPressed: onOpenConcern,
              icon: const Icon(Icons.report_problem_outlined),
              label: const Text('Record a local concern'),
            ),
          ),
        ],
      ),
    );
  }
}
