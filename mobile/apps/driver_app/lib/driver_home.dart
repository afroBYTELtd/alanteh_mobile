import 'package:asm_app_config/asm_app_config.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';

import 'driver_duty_trips.dart';
import 'foundation/driver_foundation_widgets.dart';

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
    required this.onOpenShiftSummary,
    this.onDutyChanged,
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
  final VoidCallback onOpenShiftSummary;
  final ValueChanged<bool>? onDutyChanged;
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
            style: TextStyle(
              color: AsmColors.driverMintAction,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: AsmSpacing.space8),
          const Text(
            'Good morning, Driver',
            key: Key('driver-home-greeting'),
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w900,
              height: 1.05,
            ),
          ),
          const SizedBox(height: AsmSpacing.space8),
          Text(
            isOnShift
                ? 'Today’s shift · online now'
                : 'Today’s shift · not yet started',
            key: const Key('driver-shift-summary'),
            style: const TextStyle(
              color: AsmColors.driverTextSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AsmSpacing.space16),
          _DriverDutyStatusCard(
            isOnline: isOnShift,
            localQaEnabled: localQaEnabled,
            onOpenReadiness: onOpenReadiness,
            onDutyChanged: onDutyChanged,
          ),
          if (isOnShift) ...[
            const SizedBox(height: AsmSpacing.space16),
            DriverWaitingForOfferPanel(
              onPreviewIncomingOffer: localQaEnabled
                  ? onPreviewIncomingRequest
                  : null,
            ),
          ],
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
                  key: const Key('driver-home-open-shift-summary'),
                  onPressed: onOpenShiftSummary,
                  variant: AsmActionButtonVariant.outlined,
                  icon: Icons.schedule_outlined,
                  label: 'Shift summary',
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
                if (localQaEnabled && !isOnShift) ...[
                  const SizedBox(height: AsmSpacing.space4),
                  AsmPrimaryActionButton(
                    key: const Key('open-ride-offer-preview'),
                    onPressed: onPreviewIncomingRequest,
                    variant: AsmActionButtonVariant.text,
                    icon: Icons.notifications_none_outlined,
                    label: 'Preview incoming offer',
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

class _DriverDutyStatusCard extends StatelessWidget {
  const _DriverDutyStatusCard({
    required this.isOnline,
    required this.localQaEnabled,
    required this.onOpenReadiness,
    required this.onDutyChanged,
  });

  final bool isOnline;
  final bool localQaEnabled;
  final VoidCallback onOpenReadiness;
  final ValueChanged<bool>? onDutyChanged;

  @override
  Widget build(BuildContext context) {
    final readinessButton = AsmPrimaryActionButton(
      key: const Key('driver-start-readiness'),
      onPressed: onOpenReadiness,
      icon: Icons.fact_check_outlined,
      label: localQaEnabled
          ? 'Local QA readiness preview'
          : 'Complete readiness check',
    );

    return Container(
      key: const Key('driver-duty-status-panel'),
      width: double.infinity,
      padding: const EdgeInsets.all(AsmSpacing.space20),
      decoration: BoxDecoration(
        color: isOnline ? AsmColors.driverCardElevated : AsmColors.driverCard,
        borderRadius: BorderRadius.circular(AsmRadii.radius24),
        border: Border.all(
          color: isOnline ? AsmColors.driverMintAction : AsmColors.driverLine,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 25,
                backgroundColor: isOnline
                    ? AsmColors.driverMintAction
                    : AsmColors.driverScaffold,
                foregroundColor: isOnline
                    ? AsmColors.driverScaffold
                    : AsmColors.driverTextSecondary,
                child: Icon(
                  isOnline ? Icons.online_prediction : Icons.power_settings_new,
                ),
              ),
              const SizedBox(width: AsmSpacing.space12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isOnline ? 'You’re online' : 'You’re offline',
                      key: Key(
                        isOnline
                            ? 'driver-online-status'
                            : 'driver-offline-status',
                      ),
                      style: const TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: AsmSpacing.space4),
                    Text(
                      isOnline
                          ? 'Ready to receive nearby ride offers.'
                          : 'Complete readiness before starting your shift.',
                      style: const TextStyle(
                        color: AsmColors.driverTextSecondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              if (isOnline)
                Switch(
                  key: const Key('driver-duty-toggle'),
                  value: true,
                  onChanged: onDutyChanged,
                ),
            ],
          ),
          if (!isOnline) ...[
            const SizedBox(height: AsmSpacing.space20),
            if (localQaEnabled)
              KeyedSubtree(
                key: const Key('open-readiness'),
                child: readinessButton,
              )
            else
              readinessButton,
          ],
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
