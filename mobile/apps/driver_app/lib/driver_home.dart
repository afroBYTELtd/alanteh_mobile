import 'package:asm_app_config/asm_app_config.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';

import 'driver_duty_trips.dart';

class DriverHome extends StatelessWidget {
  const DriverHome({
    required this.market,
    required this.isOnShift,
    required this.onOpenReadiness,
    required this.onRecordConcern,
    required this.onPreviewIncomingRequest,
    required this.localQaEnabled,
    required this.dutyGateway,
    required this.onOpenAssignedTrips,
    this.onSignOut,
    super.key,
  });

  final MarketConfig market;
  final bool isOnShift;
  final VoidCallback onOpenReadiness;
  final VoidCallback onRecordConcern;
  final VoidCallback onPreviewIncomingRequest;
  final bool localQaEnabled;
  final DriverDutyGateway? dutyGateway;
  final VoidCallback onOpenAssignedTrips;
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
          const Text(
            'Driver app ready',
            key: Key('driver-home-title'),
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: AsmSpacing.space8),
          const AsmSectionLabel(
            key: Key('driver-market'),
            text: 'Accra, Ghana',
            icon: Icons.location_on_outlined,
            iconColor: AsmColors.driverMintAction,
            textStyle: TextStyle(fontWeight: FontWeight.w800),
            textMaxLines: null,
          ),
          const SizedBox(height: AsmSpacing.space16),
          Container(
            key: const Key('driver-home-assigned-trips-card'),
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
                AsmPrimaryActionButton(
                  key: const Key('open-assigned-trips'),
                  onPressed: onOpenAssignedTrips,
                  variant: AsmActionButtonVariant.outlined,
                  icon: Icons.route_outlined,
                  label: 'My Assigned Trips',
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
                  const SizedBox(height: AsmSpacing.space8),
                  AsmPrimaryActionButton(
                    key: const Key('open-readiness'),
                    onPressed: onOpenReadiness,
                    variant: AsmActionButtonVariant.text,
                    icon: Icons.fact_check_outlined,
                    label: 'Local QA readiness preview',
                    minimumHeight: 48,
                  ),
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
          const SizedBox(height: AsmSpacing.space16),
          DriverDutySummaryPanel(gateway: dutyGateway),
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
