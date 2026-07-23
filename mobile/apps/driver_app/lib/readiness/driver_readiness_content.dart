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
    required this.onReady,
    required this.onOpenConcern,
    this.batteryNeedsAttention = false,
    this.onBatteryNeedsAttention,
    this.onRecheckBattery,
    super.key,
  });

  final MarketConfig market;
  final DriverReadinessCheck check;
  final ValueChanged<DriverReadinessItem> onToggle;
  final VoidCallback onReset;
  final VoidCallback onReady;
  final VoidCallback onOpenConcern;
  final bool batteryNeedsAttention;
  final VoidCallback? onBatteryNeedsAttention;
  final VoidCallback? onRecheckBattery;

  @override
  Widget build(BuildContext context) {
    final totalCount = DriverReadinessItem.values.length;
    final canCompleteLocally = check.isComplete && !batteryNeedsAttention;

    return SafeArea(
      child: ListView(
        key: const Key('driver-shift-readiness-screen'),
        padding: const EdgeInsets.fromLTRB(
          AsmSpacing.space20,
          AsmSpacing.space12,
          AsmSpacing.space20,
          AsmSpacing.space24,
        ),
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              market.countryName,
              key: const Key('readiness-market'),
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: AsmSpacing.space16),
          Container(
            key: const Key('readiness-local-only'),
            width: double.infinity,
            padding: const EdgeInsets.all(AsmSpacing.space16),
            decoration: BoxDecoration(
              color: AsmColors.driverCardElevated,
              borderRadius: BorderRadius.circular(AsmRadii.radius16),
              border: Border.all(color: AsmColors.driverMintAction),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'LOCAL ONLY',
                  style: TextStyle(
                    color: AsmColors.driverMintAction,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: AsmSpacing.space8),
                Text(
                  'Completing this checklist updates this device only. '
                  'It is not submitted to the Control Center.',
                  style: TextStyle(
                    color: AsmColors.driverTextSecondary,
                    height: 1.4,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AsmSpacing.space16),
          const Text(
            'Shift check',
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: AsmSpacing.space8),
          const Text(
            'Local pre-shift checklist',
            style: TextStyle(
              color: AsmColors.driverMintAction,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: AsmSpacing.space8),
          const Text(
            'Use these checks as a local device reminder before driving.',
            style: TextStyle(
              color: AsmColors.driverTextSecondary,
              height: 1.4,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AsmSpacing.space20),
          Container(
            key: const Key('driver-pre-shift-vehicle-check'),
            padding: const EdgeInsets.all(AsmSpacing.space16),
            decoration: BoxDecoration(
              color: AsmColors.driverCardElevated,
              borderRadius: BorderRadius.circular(AsmRadii.radius24),
              border: Border.all(color: AsmColors.driverLine),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${check.completedCount} of $totalCount checks complete',
                  key: const Key('readiness-count'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: AsmSpacing.space12),
                for (final item in DriverReadinessItem.values) ...[
                  Card(
                    margin: const EdgeInsets.only(bottom: AsmSpacing.space8),
                    color: AsmColors.driverCard,
                    surfaceTintColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AsmRadii.radius16),
                      side: const BorderSide(color: AsmColors.driverLine),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: CheckboxListTile(
                      key: ValueKey('readiness-${item.name}'),
                      value: check.completedItems.contains(item),
                      onChanged: (_) => onToggle(item),
                      title: Text(
                        item.label,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      subtitle: Text(item.description),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AsmSpacing.space12,
                        vertical: AsmSpacing.space4,
                      ),
                    ),
                  ),
                  if (item == DriverReadinessItem.vehicleExterior &&
                      !batteryNeedsAttention &&
                      onBatteryNeedsAttention != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        key: const Key('readiness-battery-needs-attention'),
                        onPressed: onBatteryNeedsAttention,
                        icon: const Icon(Icons.battery_alert_outlined),
                        label: const Text('Battery needs attention'),
                      ),
                    ),
                ],
              ],
            ),
          ),
          if (batteryNeedsAttention) ...[
            const SizedBox(height: AsmSpacing.space16),
            Container(
              key: const Key('readiness-failed'),
              padding: const EdgeInsets.all(AsmSpacing.space16),
              decoration: BoxDecoration(
                color: AsmColors.driverCard,
                borderRadius: BorderRadius.circular(AsmRadii.radius16),
                border: Border.all(color: AsmColors.driverWarningSurface),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: AsmColors.driverWarningSurface,
                      ),
                      SizedBox(width: AsmSpacing.space8),
                      Expanded(
                        child: Text(
                          'One check needs attention',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AsmSpacing.space8),
                  const Text(
                    'Battery must be above 30% to complete this local checklist. '
                    'Please charge before starting your shift.',
                    style: TextStyle(height: 1.4),
                  ),
                  const SizedBox(height: AsmSpacing.space12),
                  TextButton.icon(
                    key: const Key('readiness-recheck-battery'),
                    onPressed: onRecheckBattery,
                    icon: const Icon(Icons.refresh_outlined),
                    label: const Text('Recheck battery'),
                  ),
                ],
              ),
            ),
          ],
          if (canCompleteLocally) ...[
            const SizedBox(height: AsmSpacing.space16),
            Container(
              key: const Key('readiness-complete'),
              padding: const EdgeInsets.all(AsmSpacing.space20),
              decoration: BoxDecoration(
                color: AsmColors.driverCardElevated,
                borderRadius: BorderRadius.circular(AsmRadii.radius20),
                border: Border.all(color: AsmColors.driverMintAction),
              ),
              child: const Column(
                children: [
                  CircleAvatar(
                    radius: 29,
                    backgroundColor: AsmColors.driverMintAction,
                    foregroundColor: AsmColors.driverScaffold,
                    child: Icon(Icons.check_rounded, size: 34),
                  ),
                  SizedBox(height: AsmSpacing.space12),
                  Text(
                    'Local checklist complete',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                  ),
                  SizedBox(height: AsmSpacing.space8),
                  Text(
                    'These checks remain on this device and do not place you online.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AsmColors.driverTextSecondary,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AsmSpacing.space16),
          const Text(
            'Review your vehicle and route before starting work.',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AsmSpacing.space12),
          FilledButton.icon(
            key: const Key('readiness-ready'),
            onPressed: canCompleteLocally ? onReady : null,
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Complete local checklist'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
            ),
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
              label: const Text('Report an issue'),
            ),
          ),
        ],
      ),
    );
  }
}
