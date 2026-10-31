import 'package:asm_app_config/asm_app_config.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';

import 'driver_duty_trips.dart';
import 'foundation/driver_foundation_widgets.dart';

String _driverGreeting({DateTime Function()? now}) {
  final hour = (now?.call() ?? DateTime.now()).hour;

  if (hour < 12) {
    return 'Good morning, Driver';
  } else if (hour < 18) {
    return 'Good afternoon, Driver';
  } else {
    return 'Good evening, Driver';
  }
}

/// Online on the server, without today's shift check.
const driverShiftCheckNeededMessage =
    "You're online, but today's shift check isn't done. You won't get "
    'automatic trips until you do it.';

class DriverHome extends StatelessWidget {
  const DriverHome({
    required this.market,
    required this.isOnShift,
    required this.shiftCheckCompletedToday,
    required this.dutyActionInFlight,
    required this.onOpenReadiness,
    this.onlineWithoutShiftCheck = false,
    this.goOfflineError,
    required this.onGoOnline,
    required this.onGoOffline,
    required this.onRecordConcern,
    required this.onPreviewIncomingRequest,
    required this.localQaEnabled,
    this.dutySummary,
    this.onRefreshDuty,
    required this.onOpenAssignedTrips,
    required this.onOpenShiftSummary,
    this.onSignOut,
    this.greetingNow,
    this.pendingOffersPanelBuilder,
    super.key,
  });

  final MarketConfig market;
  final bool isOnShift;
  final bool shiftCheckCompletedToday;
  final bool dutyActionInFlight;
  final VoidCallback onOpenReadiness;

  /// Online on the server without today's shift check: the driver gets no
  /// automatic trips until doing it.
  final bool onlineWithoutShiftCheck;

  /// Why the last GO OFFLINE failed; the driver is still online.
  final String? goOfflineError;
  final VoidCallback? onGoOnline;
  final VoidCallback? onGoOffline;
  final VoidCallback onRecordConcern;
  final VoidCallback onPreviewIncomingRequest;
  final bool localQaEnabled;

  /// The shell's duty summary, shown in "Driver duty summary"; null
  /// without a server.
  final DriverDutySummary? dutySummary;

  /// Asks the shell to reload [dutySummary].
  final VoidCallback? onRefreshDuty;
  final VoidCallback onOpenAssignedTrips;
  final VoidCallback onOpenShiftSummary;
  final VoidCallback? onSignOut;
  final DateTime Function()? greetingNow;

  /// Live pending offers in place of the static waiting panel, which it
  /// receives to show when there is no offer.
  final Widget Function(Widget waitingPanel)? pendingOffersPanelBuilder;

  Widget _offersPanel(Widget waitingPanel) =>
      pendingOffersPanelBuilder?.call(waitingPanel) ?? waitingPanel;

  @override
  Widget build(BuildContext context) {
    debugPrint(
      'STARTUP_GATE_DIAG driver_home_build '
      'is_on_shift=$isOnShift '
      'shift_check_completed_today=$shiftCheckCompletedToday',
    );
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
          Text(
            _driverGreeting(now: greetingNow),
            key: const Key('driver-home-greeting'),
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w900,
              height: 1.05,
            ),
          ),
          const SizedBox(height: AsmSpacing.space8),
          Text(
            isOnShift
                ? "Today's shift · online now"
                : onlineWithoutShiftCheck
                ? "Today's shift · online · shift check needed"
                : shiftCheckCompletedToday
                ? "Today's shift · offline"
                : "Today's shift · not yet started",
            key: const Key('driver-shift-summary'),
            style: const TextStyle(
              color: AsmColors.driverTextSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (onlineWithoutShiftCheck) ...[
            const SizedBox(height: AsmSpacing.space16),
            _DriverShiftCheckNeededBanner(onStart: onOpenReadiness),
          ],
          const SizedBox(height: AsmSpacing.space16),
          _DriverDutyStatusCard(
            isOnline: isOnShift || onlineWithoutShiftCheck,
            shiftCheckNeeded: onlineWithoutShiftCheck,
            shiftCheckCompletedToday: shiftCheckCompletedToday,
            dutyActionInFlight: dutyActionInFlight,
            localQaEnabled: localQaEnabled,
            onOpenReadiness: onOpenReadiness,
            onGoOnline: onGoOnline,
            onGoOffline: onGoOffline,
            goOfflineError: goOfflineError,
          ),
          if (isOnShift) ...[
            const SizedBox(height: AsmSpacing.space16),
            _offersPanel(
              DriverWaitingForOfferPanel(
                onPreviewIncomingOffer: localQaEnabled
                    ? onPreviewIncomingRequest
                    : null,
              ),
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
          DriverDutySummaryPanel(
            summary: dutySummary,
            onRefresh: onRefreshDuty,
          ),
        ],
      ),
    );
  }
}

/// Online without today's shift check: what that means, and the way to it.
class _DriverShiftCheckNeededBanner extends StatelessWidget {
  const _DriverShiftCheckNeededBanner({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('driver-shift-check-needed-banner'),
      width: double.infinity,
      padding: const EdgeInsets.all(AsmSpacing.space16),
      decoration: BoxDecoration(
        color: AsmColors.driverCardElevated,
        borderRadius: BorderRadius.circular(AsmRadii.radius24),
        border: Border.all(color: AsmColors.driverWarningSurface),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.fact_check_outlined,
                color: AsmColors.driverWarningSurface,
              ),
              SizedBox(width: AsmSpacing.space12),
              Expanded(
                child: Text(
                  driverShiftCheckNeededMessage,
                  style: TextStyle(fontWeight: FontWeight.w700, height: 1.35),
                ),
              ),
            ],
          ),
          const SizedBox(height: AsmSpacing.space12),
          AsmPrimaryActionButton(
            key: const Key('driver-shift-check-needed-start'),
            onPressed: onStart,
            icon: Icons.fact_check_outlined,
            label: 'Start shift check',
          ),
        ],
      ),
    );
  }
}

class _DriverDutyStatusCard extends StatelessWidget {
  const _DriverDutyStatusCard({
    required this.isOnline,
    required this.shiftCheckCompletedToday,
    required this.dutyActionInFlight,
    required this.localQaEnabled,
    required this.onOpenReadiness,
    required this.onGoOnline,
    required this.onGoOffline,
    this.shiftCheckNeeded = false,
    this.goOfflineError,
  });

  final bool isOnline;

  /// Online without today's shift check; the banner above explains it.
  final bool shiftCheckNeeded;
  final String? goOfflineError;
  final bool shiftCheckCompletedToday;
  final bool dutyActionInFlight;
  final bool localQaEnabled;
  final VoidCallback onOpenReadiness;
  final VoidCallback? onGoOnline;
  final VoidCallback? onGoOffline;

  @override
  Widget build(BuildContext context) {
    final actionLabel = isOnline
        ? 'GO OFFLINE'
        : shiftCheckCompletedToday
        ? 'GO ONLINE'
        : localQaEnabled
        ? 'Local QA readiness preview'
        : 'START SHIFT CHECK';

    final action = isOnline
        ? onGoOffline
        : shiftCheckCompletedToday
        ? onGoOnline
        : onOpenReadiness;

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
                      isOnline ? "You're online" : "You're offline",
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
                    if (!shiftCheckNeeded) ...[
                      const SizedBox(height: AsmSpacing.space4),
                      Text(
                        isOnline
                            ? 'Ready to receive nearby ride offers.'
                            : shiftCheckCompletedToday
                            ? "Today's shift check is already saved. Tap Go "
                                  'online to start getting trips.'
                            : 'Complete your pre-shift check to go online.',
                        style: const TextStyle(
                          color: AsmColors.driverTextSecondary,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (isOnline && goOfflineError != null) ...[
            const SizedBox(height: AsmSpacing.space16),
            Text(
              goOfflineError!,
              key: const Key('driver-go-offline-error'),
              style: const TextStyle(fontWeight: FontWeight.w700, height: 1.35),
            ),
            const SizedBox(height: AsmSpacing.space12),
            AsmPrimaryActionButton(
              key: const Key('driver-go-offline-retry'),
              onPressed: dutyActionInFlight ? null : onGoOffline,
              icon: Icons.refresh,
              label: 'Retry',
            ),
          ] else ...[
            const SizedBox(height: AsmSpacing.space20),
            KeyedSubtree(
              key: localQaEnabled && !isOnline && !shiftCheckCompletedToday
                  ? const Key('open-readiness')
                  : null,
              child: AsmPrimaryActionButton(
                key: Key(
                  isOnline
                      ? 'driver-go-offline'
                      : shiftCheckCompletedToday
                      ? 'driver-go-online'
                      : 'driver-start-readiness',
                ),
                onPressed: dutyActionInFlight ? null : action,
                icon: isOnline
                    ? Icons.power_settings_new
                    : shiftCheckCompletedToday
                    ? Icons.online_prediction
                    : Icons.fact_check_outlined,
                label: actionLabel,
              ),
            ),
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
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: AsmColors.brandWhite,
                borderRadius: BorderRadius.circular(AsmRadii.radius16),
              ),
              child: Image.asset(
                'assets/brand/alanteh-master-logo.png',
                key: const Key('driver-home-brand-logo'),
                width: 176,
                height: 48,
                fit: BoxFit.contain,
                alignment: Alignment.centerLeft,
                semanticLabel: 'ALANTEH driver logo',
              ),
            ),
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
