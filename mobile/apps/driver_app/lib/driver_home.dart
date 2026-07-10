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
          _DriverHomeBrandHeader(onSignOut: onSignOut),
          const SizedBox(height: AsmSpacing.space20),
          Container(
            key: const Key('driver-home-ready-card'),
            width: double.infinity,
            padding: const EdgeInsets.all(AsmSpacing.space20),
            decoration: BoxDecoration(
              color: AsmColors.driverCard,
              borderRadius: BorderRadius.circular(AsmRadii.radius28),
              border: Border.all(color: AsmColors.driverLine),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.verified_user_outlined,
                  color: AsmColors.driverMintAction,
                  size: 44,
                ),
                SizedBox(height: AsmSpacing.space20),
                Text(
                  'Driver app ready',
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    height: 1.05,
                  ),
                ),
                SizedBox(height: 14),
                Text(
                  'Keep your phone nearby.',
                  style: TextStyle(
                    color: AsmColors.driverTextSecondary,
                    fontSize: 17,
                    height: 1.45,
                  ),
                ),
                SizedBox(height: AsmSpacing.space20),
                AsmSectionLabel(
                  key: Key('driver-market'),
                  text: 'Accra, Ghana',
                  icon: Icons.location_on_outlined,
                  iconColor: AsmColors.driverMintAction,
                  textStyle: TextStyle(fontWeight: FontWeight.w800),
                  textMaxLines: null,
                ),
              ],
            ),
          ),
          const SizedBox(height: AsmSpacing.space16),
          Container(
            key: const Key('driver-home-safe-tools-card'),
            width: double.infinity,
            padding: const EdgeInsets.all(AsmSpacing.space16),
            decoration: BoxDecoration(
              color: AsmColors.driverCardElevated,
              borderRadius: BorderRadius.circular(AsmRadii.radius24),
              border: Border.all(color: AsmColors.driverLine),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Today',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: AsmSpacing.space8),
                const AsmEmptyStatePanel(
                  key: Key('driver-live-safe-waiting'),
                  compact: true,
                  padding: EdgeInsets.all(18),
                  backgroundColor: AsmColors.driverCard,
                  borderColor: AsmColors.driverLine,
                  icon: Icons.route_outlined,
                  iconColor: AsmColors.driverMintAction,
                  title:
                      'Trip and shift tools will appear after Control Center activation.',
                  message: 'Keep your phone nearby.',
                  titleStyle: TextStyle(fontWeight: FontWeight.w700),
                  messageStyle: TextStyle(color: AsmColors.driverTextSecondary),
                  textSpacing: 3,
                ),
                const SizedBox(height: AsmSpacing.space16),
                if (localQaEnabled) ...[
                  AsmPrimaryActionButton(
                    key: const Key('open-readiness'),
                    onPressed: onOpenReadiness,
                    variant: AsmActionButtonVariant.outlined,
                    icon: Icons.fact_check_outlined,
                    label: 'Local QA readiness preview',
                  ),
                  const SizedBox(height: AsmSpacing.space8),
                ],
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
                    label: 'Local QA driver trip preview',
                    minimumHeight: 48,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DriverHomeBrandHeader extends StatelessWidget {
  const _DriverHomeBrandHeader({required this.onSignOut});

  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Image.asset(
            'assets/brand/alanteh_header_white.png',
            key: const Key('driver-home-brand-logo'),
            width: 176,
            height: 48,
            fit: BoxFit.contain,
            alignment: Alignment.centerLeft,
            semanticLabel: 'ALANTEH driver logo',
          ),
        ),
        if (onSignOut != null) ...[
          const SizedBox(width: AsmSpacing.space12),
          TextButton.icon(
            key: const Key('driver-sign-out'),
            onPressed: onSignOut,
            icon: const Icon(Icons.exit_to_app_outlined, size: 16),
            label: const Text('Sign out'),
          ),
        ],
      ],
    );
  }
}
