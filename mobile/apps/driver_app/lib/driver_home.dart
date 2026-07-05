import 'package:asm_app_config/asm_app_config.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';

class DriverHome extends StatelessWidget {
  const DriverHome({
    required this.market,
    required this.isOnShift,
    required this.onOpenReadiness,
    required this.onRecordConcern,
    required this.onPreviewIncomingRequest,
    required this.localQaEnabled,
    this.onSignOut,
    super.key,
  });

  final MarketConfig market;
  final bool isOnShift;
  final VoidCallback onOpenReadiness;
  final VoidCallback onRecordConcern;
  final VoidCallback onPreviewIncomingRequest;
  final bool localQaEnabled;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final marketLabel = market.countryName;
    final shiftLabel = isOnShift ? 'On shift' : 'Off shift';

    return AsmScreenSurface(
      scrollable: true,
      expandToViewport: true,
      padding: const EdgeInsets.fromLTRB(
        22,
        AsmSpacing.space20,
        22,
        AsmSpacing.space24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AsmScreenHeader(
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: colors.primary,
                borderRadius: BorderRadius.circular(AsmRadii.radius8),
              ),
              child: const Icon(
                Icons.electric_car_outlined,
                color: AsmColors.driverScaffold,
              ),
            ),
            title: 'ALANTEH',
            subtitle: 'Field workspace',
            compact: true,
            titleStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
            subtitleStyle: const TextStyle(color: Color(0xFFAEB8BD)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onSignOut != null) ...[
                  TextButton.icon(
                    key: const Key('driver-sign-out'),
                    onPressed: onSignOut,
                    icon: const Icon(Icons.exit_to_app_outlined, size: 16),
                    label: const Text('Sign out'),
                  ),
                  const SizedBox(width: 6),
                ],
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AsmColors.driverPanelMuted,
                    borderRadius: BorderRadius.circular(AsmRadii.radius6),
                  ),
                  child: Text(
                    shiftLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 64),
          const Icon(
            Icons.verified_user_outlined,
            color: AsmColors.brandGreen,
            size: 44,
          ),
          const SizedBox(height: AsmSpacing.space20),
          const Text(
            'Approved drivers only',
            style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 14),
          const Text(
            'This workspace is reserved for approved ALANTEH drivers.',
            style: TextStyle(
              color: Color(0xFFB7C0C4),
              fontSize: 17,
              height: 1.45,
            ),
          ),
          const SizedBox(height: AsmSpacing.space20),
          AsmSectionLabel(
            key: const Key('driver-market'),
            text: marketLabel,
            icon: Icons.location_on_outlined,
            iconColor: AsmColors.brandGreen,
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
            textMaxLines: null,
          ),
          const SizedBox(height: AsmSpacing.space16),
          const Text(
            'Today',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: AsmSpacing.space8),
          const AsmEmptyStatePanel(
            key: Key('driver-live-safe-waiting'),
            compact: true,
            padding: EdgeInsets.all(18),
            backgroundColor: Color(0xFF20272B),
            borderColor: Color(0xFF3A4449),
            icon: Icons.route_outlined,
            iconColor: AsmColors.brandGreen,
            title: 'No trip assigned yet.',
            message: 'Stay ready for the Control Center.',
            titleStyle: TextStyle(fontWeight: FontWeight.w700),
            messageStyle: TextStyle(color: Color(0xFFB7C0C4)),
            textSpacing: 3,
          ),
          const SizedBox(height: AsmSpacing.space16),
          AsmPrimaryActionButton(
            key: const Key('open-readiness'),
            onPressed: onOpenReadiness,
            variant: AsmActionButtonVariant.outlined,
            icon: Icons.fact_check_outlined,
            label: 'Start shift check',
          ),
          const SizedBox(height: AsmSpacing.space8),
          AsmPrimaryActionButton(
            key: const Key('open-concern'),
            onPressed: onRecordConcern,
            variant: AsmActionButtonVariant.text,
            icon: Icons.report_problem_outlined,
            label: 'Report an issue',
            minimumHeight: 48,
          ),
          if (localQaEnabled) ...[
            const SizedBox(height: AsmSpacing.space4),
            AsmPrimaryActionButton(
              key: const Key('open-ride-offer-preview'),
              onPressed: onPreviewIncomingRequest,
              variant: AsmActionButtonVariant.text,
              icon: Icons.notifications_none_outlined,
              label: 'Local QA trip preview',
              minimumHeight: 48,
            ),
          ],
          const SizedBox(height: AsmSpacing.space16),
          const AsmSectionLabel(
            text: 'Driver app foundation',
            textStyle: TextStyle(color: Color(0xFF8F9A9F), fontSize: 13),
          ),
        ],
      ),
    );
  }
}
