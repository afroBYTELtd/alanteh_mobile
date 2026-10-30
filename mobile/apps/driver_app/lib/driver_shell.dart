import 'dart:async';

import 'package:asm_app_config/asm_app_config.dart';
import 'package:asm_auth/asm_auth.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';

import 'concern/driver_concern_page.dart';
import 'driver_back_to_work.dart';
import 'driver_duty_trips.dart';
import 'network/driver_rating_gateway.dart';
import 'driver_home.dart';
import 'foundation/driver_foundation_widgets.dart';
import 'network/driver_offer_response_resilience.dart';
import 'network/driver_report_gateway.dart';
import 'network/driver_trip_action_resilience.dart';
import 'offers/driver_offer_layer.dart';
import 'readiness/driver_readiness_page.dart';
import 'readiness/driver_shift_check_submission.dart';
import 'ride_offer/driver_ride_offer_page.dart';
import 'safety/driver_safety_settings_screen.dart';
import 'safety/driver_trip_safety.dart';
import 'shift/driver_shift_history.dart';

void _startupGateDiag(String message) {
  debugPrint('STARTUP_GATE_DIAG $message');
}

void _startupGateDiagBoolTransition({
  required String field,
  required bool oldValue,
  required bool newValue,
  required String reason,
}) {
  _startupGateDiag(
    'transition field=$field old=$oldValue new=$newValue reason=$reason',
  );
}

void _startupGateDiagIndexTransition({
  required int oldValue,
  required int newValue,
  required String reason,
}) {
  _startupGateDiag(
    'transition field=selected_index '
    'old=$oldValue new=$newValue reason=$reason',
  );
}

void _startupGateDiagDutySummary(
  DriverDutySummary? summary, {
  required String reason,
}) {
  _startupGateDiag(
    'duty_summary_assignment reason=$reason '
    'duty_status=${summary?.dutyStatus ?? 'null'} '
    'shift_check_today=${summary?.shiftCheckToday ?? 'null'}',
  );
}

String _startupGateDiagSanitizedErrorMessage(Object error) {
  return 'sanitized_exception_details_redacted';
}

/// At the shift check, a sign-in ending sooner than this is renewed first.
const driverSignInRenewalWindow = Duration(hours: 12);

/// How often Work, in front, asks the server for the duty summary again.
const driverDutyReloadInterval = Duration(minutes: 3);

/// After midnight in Accra (UTC), how long to wait before asking again, so
/// the server's day has changed too.
const driverDutyDayChangeDelay = Duration(seconds: 10);

/// GO OFFLINE got no answer from the server.
const driverGoOfflineNoAnswerMessage =
    "Couldn't go offline. You may still get trip offers. Check your "
    'connection and tap Retry.';

/// GO OFFLINE was answered with an error.
const driverGoOfflineFailedMessage =
    "Couldn't go offline. You may still get trip offers. Tap Retry.";

class DriverShell extends StatefulWidget {
  const DriverShell({
    this.configuration = AsmAppConfig.localGhana,
    this.localQaEnabled = false,
    this.onSignOut,
    this.requestNotificationPermission,
    this.driverDutyGateway,
    this.driverTripActionControllerFactory,
    this.driverOfferResponseControllerFactory,
    this.driverShiftCheckController,
    this.driverReportGateway,
    this.driverRatingGateway,
    this.driverTrustedContactRepository,
    this.driverSafetyAlertRepository,
    this.deviceNow,
    this.onlineTransitionDuration = const Duration(seconds: 2),
    this.pendingOffersPanelBuilder,
    this.onDutyChanged,
    this.signInTimeLeft,
    super.key,
  });

  final AsmAppConfig configuration;
  final bool localQaEnabled;
  final Future<void> Function()? onSignOut;
  final Future<bool> Function()? requestNotificationPermission;
  final DriverDutyGateway? driverDutyGateway;
  final DriverTripActionControllerFactory? driverTripActionControllerFactory;
  final DriverOfferResponseControllerFactory?
  driverOfferResponseControllerFactory;
  final DriverShiftCheckSubmissionController? driverShiftCheckController;
  final DriverReportGateway? driverReportGateway;
  final ApiDriverRatingGateway? driverRatingGateway;
  final DriverTrustedContactRepository? driverTrustedContactRepository;
  final DriverSafetyAlertRepository? driverSafetyAlertRepository;
  final DateTime Function()? deviceNow;
  final Duration onlineTransitionDuration;

  /// See [DriverHome.pendingOffersPanelBuilder].
  final Widget Function(Widget waitingPanel)? pendingOffersPanelBuilder;

  /// Told after every change of on-duty (online with today's shift check).
  final ValueChanged<bool>? onDutyChanged;

  /// How long the sign-in has left (the refresh token's own expiry); null
  /// when unknown. Checked when the shift check opens.
  final Future<Duration?> Function()? signInTimeLeft;

  @override
  State<DriverShell> createState() => _DriverShellState();
}

class _DriverShellState extends State<DriverShell> {
  int _selectedIndex = 0;
  bool _localChecklistComplete = false;
  bool _dutyLoading = false;
  bool _dutyActionInFlight = false;
  bool _showOnlineTransition = false;

  /// A shift check was submitted and the app is confirming the driver is
  /// online; Work must not show the old "offline" screen meanwhile.
  bool _confirmingShiftCheck = false;
  bool _startupShiftCheckConsidered = false;
  bool _startupShiftCheckNavigationPending = false;
  DriverDutySummary? _dutySummary;
  Object? _dutyError;

  /// Why the last GO OFFLINE failed; the driver is still online meanwhile.
  String? _goOfflineError;

  // Quiet reloads (resume, every few minutes on Work, the Accra day
  // change): one at a time, and an answer that started before a newer duty
  // change is dropped.
  int _dutyGeneration = 0;
  bool _quietReloadInFlight = false;
  bool _appInFront = true;
  AppLifecycleListener? _lifecycle;
  Timer? _workReloadTimer;
  Timer? _dayChangeTimer;

  bool get _shiftCheckCompletedToday {
    if (widget.driverDutyGateway == null) {
      return _localChecklistComplete;
    }

    return _dutySummary?.shiftCheckToday == true;
  }

  bool get _isOnline =>
      _shiftCheckCompletedToday && (_dutySummary?.isOnline ?? false);

  /// Online on the server without today's shift check (left online from an
  /// earlier day): no automatic trips until the driver does it.
  bool get _onlineWithoutShiftCheck =>
      widget.driverDutyGateway != null &&
      (_dutySummary?.isOnline ?? false) &&
      !_shiftCheckCompletedToday;

  @override
  void initState() {
    super.initState();
    DriverBackToWork.selectWorkTab = _selectWorkTab;
    DriverBackToWork.selectTripsTab = _openAssignedTrips;

    _startupGateDiag(
      'shell_init '
      'pending=$_startupShiftCheckNavigationPending '
      'considered=$_startupShiftCheckConsidered '
      'duty_loading=$_dutyLoading '
      'selected_index=$_selectedIndex',
    );

    final controller = widget.driverShiftCheckController;
    if (controller != null) {
      unawaited(controller.startAutomaticSync());
    }

    if (widget.driverDutyGateway != null) {
      unawaited(_loadDuty());
    }

    _lifecycle = AppLifecycleListener(
      onStateChange: (state) =>
          _appInFront = state == AppLifecycleState.resumed,
      onResume: () => unawaited(_reloadDutyQuietly()),
    );
    _workReloadTimer = Timer.periodic(driverDutyReloadInterval, (_) {
      final workInFront =
          _selectedIndex == 0 &&
          _appInFront &&
          (ModalRoute.of(context)?.isCurrent ?? true);
      if (workInFront) {
        unawaited(_reloadDutyQuietly());
      }
    });
    _setDayChangeTimer();
  }

  /// Just after the next midnight in Accra (UTC), when today's shift check
  /// is due again.
  void _setDayChangeTimer() {
    final now = (widget.deviceNow?.call() ?? DateTime.now()).toUtc();
    final nextDay = DateTime.utc(now.year, now.month, now.day + 1);
    _dayChangeTimer = Timer(
      nextDay.difference(now) + driverDutyDayChangeDelay,
      () {
        unawaited(_reloadDutyQuietly());
        _setDayChangeTimer();
      },
    );
  }

  /// Asks the server for the duty summary again, without disturbing Work:
  /// a failure keeps what Work shows, except an ended session, shown as
  /// before.
  Future<void> _reloadDutyQuietly() async {
    final gateway = widget.driverDutyGateway;
    if (gateway == null ||
        !mounted ||
        _dutyLoading ||
        _quietReloadInFlight ||
        _dutyActionInFlight ||
        _confirmingShiftCheck ||
        _showOnlineTransition) {
      return;
    }
    final generation = _dutyGeneration;
    _quietReloadInFlight = true;
    try {
      final duty = await gateway.fetchDuty();
      if (!mounted || generation != _dutyGeneration) {
        return;
      }
      setState(() {
        _dutySummary = duty;
        _startupGateDiagDutySummary(_dutySummary, reason: 'quiet_reload');
        _dutyError = null;
        if (!duty.isOnline) {
          _goOfflineError = null;
        }
      });
    } on Object catch (error) {
      if (!mounted || generation != _dutyGeneration) {
        return;
      }
      if (error is DriverDutyApiException && error.isSessionExpired) {
        setState(() => _dutyError = error);
      }
    } finally {
      _quietReloadInFlight = false;
    }
  }

  @override
  void didUpdateWidget(covariant DriverShell oldWidget) {
    super.didUpdateWidget(oldWidget);

    final gatewayIdentityChanged =
        oldWidget.driverDutyGateway != widget.driverDutyGateway;
    _startupGateDiag(
      'did_update_widget invocation '
      'gateway_identity_changed=$gatewayIdentityChanged '
      'pending=$_startupShiftCheckNavigationPending '
      'considered=$_startupShiftCheckConsidered '
      'duty_loading=$_dutyLoading',
    );

    if (oldWidget.driverShiftCheckController !=
        widget.driverShiftCheckController) {
      final previous = oldWidget.driverShiftCheckController;
      if (previous != null) {
        unawaited(previous.stopAutomaticSync());
      }

      final current = widget.driverShiftCheckController;
      if (current != null) {
        unawaited(current.startAutomaticSync());
      }
    }

    if (gatewayIdentityChanged) {
      final oldConsidered = _startupShiftCheckConsidered;
      final oldPending = _startupShiftCheckNavigationPending;
      _startupShiftCheckConsidered = false;
      _startupShiftCheckNavigationPending = false;
      _startupGateDiagBoolTransition(
        field: 'startup_shift_check_considered',
        oldValue: oldConsidered,
        newValue: _startupShiftCheckConsidered,
        reason: 'did_update_widget_gateway_identity_change',
      );
      _startupGateDiagBoolTransition(
        field: 'startup_shift_check_navigation_pending',
        oldValue: oldPending,
        newValue: _startupShiftCheckNavigationPending,
        reason: 'did_update_widget_gateway_identity_change',
      );

      if (widget.driverDutyGateway == null) {
        final oldDutyLoading = _dutyLoading;
        setState(() {
          _dutySummary = null;
          _startupGateDiagDutySummary(
            _dutySummary,
            reason: 'did_update_widget_gateway_removed',
          );
          _dutyError = null;
          _dutyLoading = false;
          _startupGateDiagBoolTransition(
            field: 'duty_loading',
            oldValue: oldDutyLoading,
            newValue: _dutyLoading,
            reason: 'did_update_widget_gateway_removed',
          );
        });
      } else {
        unawaited(_loadDuty());
      }
    }

    _startupGateDiag(
      'did_update_widget after '
      'gateway_identity_changed=$gatewayIdentityChanged '
      'pending=$_startupShiftCheckNavigationPending '
      'considered=$_startupShiftCheckConsidered '
      'duty_loading=$_dutyLoading',
    );
  }

  @override
  void dispose() {
    if (DriverBackToWork.selectWorkTab == _selectWorkTab) {
      DriverBackToWork.selectWorkTab = null;
    }
    if (DriverBackToWork.selectTripsTab == _openAssignedTrips) {
      DriverBackToWork.selectTripsTab = null;
    }
    final controller = widget.driverShiftCheckController;
    if (controller != null) {
      unawaited(controller.stopAutomaticSync());
    }
    _lifecycle?.dispose();
    _workReloadTimer?.cancel();
    _dayChangeTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadDuty() async {
    final gateway = widget.driverDutyGateway;
    if (gateway == null || _dutyLoading) {
      _startupGateDiag(
        'load_duty skipped '
        'gateway_null=${gateway == null} duty_loading=$_dutyLoading',
      );
      return;
    }
    _dutyGeneration += 1;

    final oldDutyLoading = _dutyLoading;
    setState(() {
      _dutyLoading = true;
      _startupGateDiagBoolTransition(
        field: 'duty_loading',
        oldValue: oldDutyLoading,
        newValue: _dutyLoading,
        reason: 'load_duty_start',
      );
      _dutyError = null;
    });

    try {
      final duty = await gateway.fetchDuty();
      _startupGateDiag(
        'shell_me_decoded_result '
        'duty_status=${duty.dutyStatus} '
        'shift_check_today=${duty.shiftCheckToday}',
      );

      if (!mounted) {
        _startupGateDiag('load_duty success_but_unmounted=true');
        return;
      }

      final startupShiftCheckRequired =
          !_startupShiftCheckConsidered &&
          duty.dutyStatus == 'offline' &&
          duty.shiftCheckToday != true;
      _startupGateDiag(
        'startup_gate_initial_duty_decision '
        'required=$startupShiftCheckRequired '
        'considered=$_startupShiftCheckConsidered '
        'duty_status=${duty.dutyStatus} '
        'shift_check_today=${duty.shiftCheckToday}',
      );

      final previousDutyLoading = _dutyLoading;
      final previousPending = _startupShiftCheckNavigationPending;
      setState(() {
        _dutySummary = duty;
        _startupGateDiagDutySummary(
          _dutySummary,
          reason: 'shell_load_duty_success',
        );
        _dutyLoading = false;
        _startupGateDiagBoolTransition(
          field: 'duty_loading',
          oldValue: previousDutyLoading,
          newValue: _dutyLoading,
          reason: 'load_duty_success',
        );
        _dutyError = null;
        _startupShiftCheckNavigationPending = startupShiftCheckRequired;
        _startupGateDiagBoolTransition(
          field: 'startup_shift_check_navigation_pending',
          oldValue: previousPending,
          newValue: _startupShiftCheckNavigationPending,
          reason: 'initial_duty_result_decision',
        );
      });

      _openStartupShiftCheckIfRequired();
    } on Object catch (error) {
      _startupGateDiag(
        'load_duty failure '
        'type=${error.runtimeType} '
        'message=${_startupGateDiagSanitizedErrorMessage(error)}',
      );
      if (!mounted) {
        return;
      }

      final previousDutyLoading = _dutyLoading;
      setState(() {
        _dutyLoading = false;
        _startupGateDiagBoolTransition(
          field: 'duty_loading',
          oldValue: previousDutyLoading,
          newValue: _dutyLoading,
          reason: 'load_duty_failure',
        );
        _dutyError = error;
      });
    }
  }

  void _openStartupShiftCheckIfRequired() {
    final gatewayNull = widget.driverDutyGateway == null;
    final summaryNull = _dutySummary == null;
    final alreadyConsidered = _startupShiftCheckConsidered;

    _startupGateDiag(
      'open_startup entry '
      'already_considered=$alreadyConsidered '
      'gateway_null=$gatewayNull '
      'summary_null=$summaryNull '
      'pending=$_startupShiftCheckNavigationPending '
      'duty_loading=$_dutyLoading '
      'selected_index=$_selectedIndex '
      'duty_status=${_dutySummary?.dutyStatus ?? 'null'} '
      'shift_check_today=${_dutySummary?.shiftCheckToday ?? 'null'}',
    );
    _startupGateDiag(
      'open_startup guard_already_considered result=$alreadyConsidered',
    );
    _startupGateDiag('open_startup guard_gateway_null result=$gatewayNull');
    _startupGateDiag('open_startup guard_summary_null result=$summaryNull');

    if (_startupShiftCheckConsidered ||
        widget.driverDutyGateway == null ||
        _dutySummary == null) {
      final skipReason = alreadyConsidered
          ? 'already_considered'
          : gatewayNull
          ? 'driver_duty_gateway_null'
          : 'duty_summary_null';
      _startupGateDiag(
        'open_startup navigation_required=NO '
        'schedule_readiness=NO skip_reason=$skipReason',
      );
      return;
    }

    final oldConsidered = _startupShiftCheckConsidered;
    _startupShiftCheckConsidered = true;
    _startupGateDiagBoolTransition(
      field: 'startup_shift_check_considered',
      oldValue: oldConsidered,
      newValue: _startupShiftCheckConsidered,
      reason: 'open_startup_mark_considered',
    );

    final navigationRequired =
        _dutySummary!.dutyStatus == 'offline' && !_shiftCheckCompletedToday;
    _startupGateDiag(
      'open_startup decision '
      'navigation_required=$navigationRequired '
      'duty_status=${_dutySummary!.dutyStatus} '
      'shift_check_today=${_dutySummary!.shiftCheckToday} '
      'pending=$_startupShiftCheckNavigationPending '
      'selected_index=$_selectedIndex',
    );

    if (_dutySummary!.dutyStatus == 'offline' && !_shiftCheckCompletedToday) {
      _startupGateDiag('open_startup schedule_readiness=YES skip_reason=none');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _startupGateDiag(
          'post_frame_callback entered '
          'mounted=$mounted '
          'pending=$_startupShiftCheckNavigationPending '
          'considered=$_startupShiftCheckConsidered',
        );
        if (!mounted) {
          _startupGateDiag(
            'post_frame_callback guard_mounted result=false '
            'open_readiness=NO skip_reason=unmounted',
          );
          return;
        }

        final shiftCheckCompletedToday = _shiftCheckCompletedToday;
        _startupGateDiag(
          'post_frame_callback state '
          'selected_index=$_selectedIndex '
          'shift_check_completed_today=$shiftCheckCompletedToday '
          'pending=$_startupShiftCheckNavigationPending '
          'considered=$_startupShiftCheckConsidered',
        );
        _startupGateDiag(
          'post_frame_callback guard_selected_index_nonzero '
          'result=${_selectedIndex != 0}',
        );
        _startupGateDiag(
          'post_frame_callback guard_shift_check_completed '
          'result=$shiftCheckCompletedToday',
        );

        if (_selectedIndex != 0 || _shiftCheckCompletedToday) {
          final skipReason = _selectedIndex != 0
              ? 'selected_index_nonzero'
              : 'shift_check_completed_today';
          final oldPending = _startupShiftCheckNavigationPending;
          setState(() {
            _startupShiftCheckNavigationPending = false;
            _startupGateDiagBoolTransition(
              field: 'startup_shift_check_navigation_pending',
              oldValue: oldPending,
              newValue: _startupShiftCheckNavigationPending,
              reason: 'post_frame_guard_clear_$skipReason',
            );
          });
          _startupGateDiag(
            'post_frame_callback open_readiness=NO '
            'skip_reason=$skipReason',
          );
          return;
        }

        _startupGateDiag(
          'post_frame_callback open_readiness=YES skip_reason=none',
        );
        unawaited(
          _openReadiness().whenComplete(() {
            _startupGateDiag(
              'post_frame_callback readiness_future_completed '
              'mounted=$mounted',
            );
            if (!mounted) {
              _startupGateDiag(
                'post_frame_callback readiness_clear_skipped '
                'reason=unmounted',
              );
              return;
            }
            final oldPending = _startupShiftCheckNavigationPending;
            setState(() {
              _startupShiftCheckNavigationPending = false;
              _startupGateDiagBoolTransition(
                field: 'startup_shift_check_navigation_pending',
                oldValue: oldPending,
                newValue: _startupShiftCheckNavigationPending,
                reason: 'readiness_completion_or_failure_clear',
              );
            });
          }),
        );
      });
    } else {
      final skipReason = _dutySummary!.dutyStatus != 'offline'
          ? 'duty_status_not_offline'
          : 'shift_check_completed_today';
      _startupGateDiag(
        'open_startup schedule_readiness=NO skip_reason=$skipReason',
      );
    }
  }

  void _selectWorkTab() {
    if (!mounted || _selectedIndex == 0) {
      return;
    }
    final oldSelectedIndex = _selectedIndex;
    setState(() {
      _selectedIndex = 0;
      _startupGateDiagIndexTransition(
        oldValue: oldSelectedIndex,
        newValue: _selectedIndex,
        reason: 'back_to_work',
      );
    });
  }

  void _openAssignedTrips() {
    final oldSelectedIndex = _selectedIndex;
    setState(() {
      _selectedIndex = 1;
      _startupGateDiagIndexTransition(
        oldValue: oldSelectedIndex,
        newValue: _selectedIndex,
        reason: 'open_assigned_trips',
      );
    });
  }

  DriverShiftRecord get _currentShift {
    return DriverShiftRecord(
      id: 'current',
      dateLabel: 'Today',
      dutyLabel: !_shiftCheckCompletedToday
          ? 'Shift check not submitted'
          : _isOnline
          ? 'Online'
          : 'Offline',
      status: _isOnline
          ? DriverShiftStatus.inProgress
          : DriverShiftStatus.notStarted,
      onlineDurationLabel: _isOnline ? 'In progress' : 'Pre-shift',
      completedTrips: 0,
      vehicleLabel: driverEmptyValue,
      serviceAreaLabel: widget.configuration.market.countryName,
    );
  }

  Future<void> _openShiftSummary() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => DriverShiftSummaryPage(currentShift: _currentShift),
      ),
    );
  }

  Future<void> _openShiftHistory() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => DriverShiftHistoryPage(currentShift: _currentShift),
      ),
    );
  }

  Future<void> _openSafetySettings() async {
    final repository = widget.driverTrustedContactRepository;
    if (repository == null) {
      return;
    }

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => DriverSafetySettingsScreen(repository: repository),
      ),
    );
  }

  /// A sign-in that ends within [driverSignInRenewalWindow] is renewed
  /// before the shift check, so it does not end in the middle of a trip.
  /// True when the driver chose to sign in again (the shell signs out).
  Future<bool> _renewSignInFirst() async {
    final timeLeft = widget.signInTimeLeft;
    if (timeLeft == null) {
      return false;
    }
    final Duration? left;
    try {
      left = await timeLeft();
    } on Object {
      return false;
    }
    if (left == null || left > driverSignInRenewalWindow || !mounted) {
      return false;
    }
    final renew = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        content: const Text(authSignInEndsSoonMessage),
        actions: [
          TextButton(
            key: const Key('driver-renew-sign-in-later'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Later'),
          ),
          FilledButton(
            key: const Key('driver-renew-sign-in-now'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Sign in again'),
          ),
        ],
      ),
    );
    if (renew != true || !mounted) {
      return false;
    }
    await _signOut();
    return true;
  }

  Future<void> _openReadiness() async {
    _startupGateDiag(
      'open_readiness invoked '
      'shift_check_completed_today=$_shiftCheckCompletedToday '
      'pending=$_startupShiftCheckNavigationPending '
      'considered=$_startupShiftCheckConsidered '
      'selected_index=$_selectedIndex',
    );

    if (_shiftCheckCompletedToday) {
      _startupGateDiag(
        'open_readiness early_return=YES '
        'reason=shift_check_completed_today completion=early_return',
      );
      return;
    }

    if (await _renewSignInFirst() || !mounted) {
      return;
    }

    DriverShiftCheckSubmissionDisposition? disposition;
    try {
      _startupGateDiag('open_readiness navigator_push_about_to_start');
      final navigation = Navigator.of(context)
          .push<DriverShiftCheckSubmissionDisposition>(
            MaterialPageRoute<DriverShiftCheckSubmissionDisposition>(
              builder: (_) => DriverReadinessPage(
                market: widget.configuration.market,
                submissionController: widget.driverShiftCheckController,
                driverReportGateway: widget.driverReportGateway,
                deviceNow: widget.deviceNow,
                navigationDelay: widget.driverDutyGateway == null
                    ? const Duration(seconds: 2)
                    : Duration.zero,
              ),
            ),
          );
      _startupGateDiag(
        'open_readiness navigator_push_successfully_initiated=YES',
      );
      disposition = await navigation;
      _startupGateDiag(
        'open_readiness navigator_push_returned '
        'disposition=${disposition?.name ?? 'null'}',
      );
    } on Object catch (error) {
      _startupGateDiag(
        'open_readiness failure '
        'type=${error.runtimeType} '
        'message=${_startupGateDiagSanitizedErrorMessage(error)}',
      );
      _startupGateDiag('open_readiness completion=exception');
      rethrow;
    }

    if (!mounted || disposition == null) {
      _startupGateDiag(
        'open_readiness completion=without_disposition '
        'mounted=$mounted disposition_null=${disposition == null}',
      );
      return;
    }

    if (widget.driverDutyGateway == null) {
      final oldSelectedIndex = _selectedIndex;
      setState(() {
        _localChecklistComplete = true;
        _selectedIndex = 0;
        _startupGateDiagIndexTransition(
          oldValue: oldSelectedIndex,
          newValue: _selectedIndex,
          reason: 'readiness_local_checklist_completion',
        );
      });
      _startupGateDiag('open_readiness completion=local_checklist');
      return;
    }

    if (disposition != DriverShiftCheckSubmissionDisposition.submitted) {
      final oldSelectedIndex = _selectedIndex;
      setState(() {
        _selectedIndex = 0;
        _startupGateDiagIndexTransition(
          oldValue: oldSelectedIndex,
          newValue: _selectedIndex,
          reason: 'readiness_non_submitted_disposition',
        );
      });
      _startupGateDiag(
        'open_readiness completion=non_submitted_disposition '
        'disposition=${disposition.name}',
      );
      return;
    }

    _startupGateDiag(
      'open_readiness submitted_disposition '
      'confirm_online_after_shift_check=YES',
    );
    await _confirmOnlineAfterShiftCheck();

    final requestNotificationPermission = widget.requestNotificationPermission;
    if (requestNotificationPermission != null) {
      try {
        await requestNotificationPermission();
      } on Object {
        // Notification permission must never invalidate readiness.
      }
    }

    _startupGateDiag('open_readiness completion=submitted');
  }

  Future<void> _confirmOnlineAfterShiftCheck() async {
    final gateway = widget.driverDutyGateway;
    if (gateway == null) {
      return;
    }
    _dutyGeneration += 1;

    final oldDutyLoading = _dutyLoading;
    final oldSelectedIndex = _selectedIndex;
    setState(() {
      _dutyLoading = true;
      _startupGateDiagBoolTransition(
        field: 'duty_loading',
        oldValue: oldDutyLoading,
        newValue: _dutyLoading,
        reason: 'confirm_online_after_shift_check_start',
      );
      _dutyError = null;
      // Runs once per submission (one readiness pop): transition untouched.
      _confirmingShiftCheck = true;
      _selectedIndex = 0;
      _startupGateDiagIndexTransition(
        oldValue: oldSelectedIndex,
        newValue: _selectedIndex,
        reason: 'confirm_online_after_shift_check_start',
      );
    });

    try {
      final refreshed = await gateway.fetchDuty();

      if (!mounted) {
        return;
      }

      if (!refreshed.isOnline) {
        // The server answered: show Work as it is, offline, with the shift
        // check saved and Go online.
        final oldDutyLoading = _dutyLoading;
        setState(() {
          _dutySummary = refreshed;
          _startupGateDiagDutySummary(
            _dutySummary,
            reason: 'confirm_online_server_not_online',
          );
          _dutyLoading = false;
          _startupGateDiagBoolTransition(
            field: 'duty_loading',
            oldValue: oldDutyLoading,
            newValue: _dutyLoading,
            reason: 'confirm_online_server_not_online',
          );
          _dutyError = null;
          _confirmingShiftCheck = false;
        });
        return;
      }

      final oldDutyLoading = _dutyLoading;
      setState(() {
        _dutySummary = refreshed;
        _startupGateDiagDutySummary(
          _dutySummary,
          reason: 'confirm_online_refreshed_summary',
        );
        _dutyLoading = false;
        _startupGateDiagBoolTransition(
          field: 'duty_loading',
          oldValue: oldDutyLoading,
          newValue: _dutyLoading,
          reason: 'confirm_online_success',
        );
        _dutyError = null;
        _showOnlineTransition = true;
        _confirmingShiftCheck = false;
      });

      await Future<void>.delayed(widget.onlineTransitionDuration);

      if (!mounted) {
        return;
      }

      setState(() {
        _showOnlineTransition = false;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }

      final oldDutyLoading = _dutyLoading;
      setState(() {
        _dutyLoading = false;
        _startupGateDiagBoolTransition(
          field: 'duty_loading',
          oldValue: oldDutyLoading,
          newValue: _dutyLoading,
          reason: 'confirm_online_failure',
        );
        _dutyError = _OnlineNotConfirmed(error);
        _confirmingShiftCheck = false;
      });
    }
  }

  Future<void> _changeDuty(DriverOperationalDutyStatus status) async {
    if (_dutyActionInFlight) {
      return;
    }

    final gateway = widget.driverDutyGateway;
    final DriverDutyStatusGateway? statusGateway =
        gateway is DriverDutyStatusGateway
        ? gateway as DriverDutyStatusGateway
        : null;

    if (statusGateway == null) {
      setState(() {
        _dutyError = const DriverDutyApiException(
          DriverDutyApiFailureType.badResponse,
          'Driver duty action is not configured.',
        );
      });
      return;
    }

    _dutyGeneration += 1;
    setState(() {
      _dutyActionInFlight = true;
      _dutyError = null;
      _goOfflineError = null;
    });

    try {
      final transition = await statusGateway.updateDutyStatus(status);

      if (!mounted) {
        return;
      }

      final current = _dutySummary ?? DriverDutySummary.empty();

      setState(() {
        _dutySummary = current.withDutyTransition(transition);
        _startupGateDiagDutySummary(
          _dutySummary,
          reason: 'duty_status_transition',
        );
        _dutyActionInFlight = false;
        _dutyError = null;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }

      final sessionEnded =
          error is DriverDutyApiException && error.isSessionExpired;
      setState(() {
        _dutyActionInFlight = false;
        if (status == DriverOperationalDutyStatus.offline && !sessionEnded) {
          // The driver is still online: say so on Work, with Retry, instead
          // of the "You're offline" screen.
          _goOfflineError = error is DriverDutyApiException && !error.noAnswer
              ? driverGoOfflineFailedMessage
              : driverGoOfflineNoAnswerMessage;
        } else {
          _dutyError = error;
        }
      });
    }
  }

  Future<void> _openConcern() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => DriverConcernPage(
          market: widget.configuration.market,
          gateway: widget.driverReportGateway,
        ),
      ),
    );
  }

  Future<void> _openRideOfferPreview() async {
    if (!widget.localQaEnabled) {
      return;
    }

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) =>
            DriverRideOfferPage(market: widget.configuration.market),
      ),
    );
  }

  Future<void> _signOut() async {
    final oldDutyLoading = _dutyLoading;
    final oldConsidered = _startupShiftCheckConsidered;
    final oldSelectedIndex = _selectedIndex;
    _dutyGeneration += 1;
    setState(() {
      _localChecklistComplete = false;
      _dutySummary = null;
      _goOfflineError = null;
      _startupGateDiagDutySummary(_dutySummary, reason: 'sign_out');
      _dutyError = null;
      _dutyLoading = false;
      _startupGateDiagBoolTransition(
        field: 'duty_loading',
        oldValue: oldDutyLoading,
        newValue: _dutyLoading,
        reason: 'sign_out',
      );
      _dutyActionInFlight = false;
      _showOnlineTransition = false;
      _confirmingShiftCheck = false;
      _startupShiftCheckConsidered = false;
      _startupGateDiagBoolTransition(
        field: 'startup_shift_check_considered',
        oldValue: oldConsidered,
        newValue: _startupShiftCheckConsidered,
        reason: 'sign_out',
      );
      _selectedIndex = 0;
      _startupGateDiagIndexTransition(
        oldValue: oldSelectedIndex,
        newValue: _selectedIndex,
        reason: 'sign_out',
      );
    });
    await widget.onSignOut?.call();
  }

  Widget get _workPage {
    if (_showOnlineTransition) {
      return const _DriverOnlineTransitionState();
    }

    if (_confirmingShiftCheck) {
      return const _DriverShiftCheckConfirmingState();
    }

    if (_dutyError != null && widget.driverDutyGateway != null) {
      return _dutyError is _OnlineNotConfirmed
          ? DriverOfflineState(
              onRetry: _loadDuty,
              title: "Couldn't confirm you're online",
              message:
                  'Your shift check is saved. Check your connection and tap '
                  'Retry.',
            )
          : DriverOfflineState(onRetry: _loadDuty);
    }

    if (_startupShiftCheckNavigationPending ||
        (_dutyLoading && _dutySummary == null)) {
      return const Center(
        key: Key('driver-duty-startup-loading'),
        child: CircularProgressIndicator(),
      );
    }

    return DriverHome(
      market: widget.configuration.market,
      isOnShift: _isOnline,
      shiftCheckCompletedToday: _shiftCheckCompletedToday,
      dutyActionInFlight: _dutyActionInFlight,
      onOpenReadiness: _openReadiness,
      onGoOnline: _shiftCheckCompletedToday && !_isOnline
          ? () => unawaited(_changeDuty(DriverOperationalDutyStatus.online))
          : null,
      onGoOffline: _isOnline || _onlineWithoutShiftCheck
          ? () => unawaited(_changeDuty(DriverOperationalDutyStatus.offline))
          : null,
      onlineWithoutShiftCheck: _onlineWithoutShiftCheck,
      goOfflineError: _goOfflineError,
      onRecordConcern: _openConcern,
      onPreviewIncomingRequest: _openRideOfferPreview,
      localQaEnabled: widget.localQaEnabled,
      dutyGateway: widget.driverDutyGateway,
      onOpenAssignedTrips: _openAssignedTrips,
      onOpenShiftSummary: _openShiftSummary,
      onSignOut: widget.onSignOut == null ? null : _signOut,
      pendingOffersPanelBuilder: widget.pendingOffersPanelBuilder,
    );
  }

  bool? _reportedOnDuty;

  void _reportDuty() {
    final onDuty = _isOnline;
    final report = widget.onDutyChanged;
    if (report == null || onDuty == _reportedOnDuty) {
      return;
    }
    _reportedOnDuty = onDuty;
    WidgetsBinding.instance.addPostFrameCallback((_) => report(onDuty));
  }

  Widget get _selectedPage {
    return switch (_selectedIndex) {
      0 => _workPage,
      1 => DriverAssignedTripsScreen(
        gateway: widget.driverDutyGateway,
        actionControllerFactory: widget.driverTripActionControllerFactory,
        offerResponseControllerFactory:
            widget.driverOfferResponseControllerFactory,
        ratingGateway: widget.driverRatingGateway,
        driverTrustedContactRepository: widget.driverTrustedContactRepository,
        driverSafetyAlertRepository: widget.driverSafetyAlertRepository,
      ),
      _ => _DriverAccountPage(
        currentShift: _currentShift,
        onOpenShiftHistory: _openShiftHistory,
        onOpenSafetySettings: widget.driverTrustedContactRepository == null
            ? null
            : _openSafetySettings,
        onSignOut: widget.onSignOut == null ? null : _signOut,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    _reportDuty();
    return Scaffold(
      // The page ends above an offer card on the tabs, so it covers nothing.
      body: Padding(
        key: const Key('driver-shell-body'),
        padding: EdgeInsets.only(bottom: DriverOfferTabsInset.of(context)),
        child: _selectedPage,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          final oldSelectedIndex = _selectedIndex;
          setState(() {
            _selectedIndex = index;
            _startupGateDiagIndexTransition(
              oldValue: oldSelectedIndex,
              newValue: _selectedIndex,
              reason: 'bottom_navigation_destination_selected',
            );
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.work_outline),
            selectedIcon: Icon(Icons.work),
            label: 'Work',
          ),
          NavigationDestination(
            icon: Icon(Icons.route_outlined),
            selectedIcon: Icon(Icons.route),
            label: 'Trips',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_circle_outlined),
            selectedIcon: Icon(Icons.account_circle),
            label: 'Account',
          ),
        ],
      ),
    );
  }
}

/// After a shift check, the duty check failed: the check itself is saved.
final class _OnlineNotConfirmed {
  const _OnlineNotConfirmed(this.cause);

  final Object cause;
}

/// "Going online…" adds "Still trying…" after this long. The duty check
/// can take about 74 s (4 tries of 15 s and the waits) before its error.
const driverGoingOnlineStillTryingAfter = Duration(seconds: 15);

class _DriverShiftCheckConfirmingState extends StatefulWidget {
  const _DriverShiftCheckConfirmingState();

  @override
  State<_DriverShiftCheckConfirmingState> createState() =>
      _DriverShiftCheckConfirmingStateState();
}

class _DriverShiftCheckConfirmingStateState
    extends State<_DriverShiftCheckConfirmingState> {
  Timer? _timer;
  bool _stillTrying = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(driverGoingOnlineStillTryingAfter, () {
      if (mounted) {
        setState(() => _stillTrying = true);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AsmScreenSurface(
      key: const Key('driver-shift-check-confirming'),
      expandToViewport: true,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Shift check submitted.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: AsmSpacing.space8),
            const Text(
              'Going online…',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AsmColors.driverTextSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AsmSpacing.space16),
            const CircularProgressIndicator(),
            if (_stillTrying) ...[
              const SizedBox(height: AsmSpacing.space12),
              const Text(
                'Still trying…',
                key: Key('driver-going-online-still-trying'),
                textAlign: TextAlign.center,
                style: TextStyle(color: AsmColors.driverTextSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DriverOnlineTransitionState extends StatelessWidget {
  const _DriverOnlineTransitionState();

  @override
  Widget build(BuildContext context) {
    return const AsmScreenSurface(
      key: Key('driver-online-transition'),
      expandToViewport: true,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 56,
              color: AsmColors.driverMintAction,
            ),
            SizedBox(height: AsmSpacing.space16),
            Text(
              'Shift check submitted.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900),
            ),
            SizedBox(height: AsmSpacing.space8),
            Text(
              'You are now online.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AsmColors.driverTextSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DriverAccountPage extends StatelessWidget {
  const _DriverAccountPage({
    required this.currentShift,
    required this.onOpenShiftHistory,
    required this.onSignOut,
    this.onOpenSafetySettings,
  });

  final DriverShiftRecord currentShift;
  final VoidCallback onOpenShiftHistory;
  final Future<void> Function()? onSignOut;
  final Future<void> Function()? onOpenSafetySettings;

  @override
  Widget build(BuildContext context) {
    // Not expandToViewport: its IntrinsicHeight measured this page too short
    // at large text sizes, and the page overflowed (168 px at 2.0), hiding
    // "Sign out". Nothing here needs the extra height.
    return AsmScreenSurface(
      key: const Key('driver-account-screen'),
      scrollable: true,
      padding: const EdgeInsets.fromLTRB(
        22,
        AsmSpacing.space20,
        22,
        AsmSpacing.space24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(
            child: CircleAvatar(
              radius: 34,
              backgroundColor: AsmColors.driverMintAction,
              foregroundColor: AsmColors.driverScaffold,
              child: Text(
                'D',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
              ),
            ),
          ),
          const SizedBox(height: AsmSpacing.space16),
          const Center(
            child: Text(
              'Driver account',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(height: AsmSpacing.space8),
          const Center(
            child: Text(
              'Signed in to ALANTEH Driver.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AsmColors.driverTextSecondary,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: AsmSpacing.space24),
          Container(
            key: const Key('driver-account-vehicle-card'),
            width: double.infinity,
            padding: const EdgeInsets.all(AsmSpacing.space16),
            decoration: BoxDecoration(
              color: AsmColors.driverCard,
              borderRadius: BorderRadius.circular(AsmRadii.radius24),
              border: Border.all(color: AsmColors.driverLine),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Assigned vehicle',
                  style: TextStyle(
                    color: AsmColors.driverTextSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AsmSpacing.space8),
                Text(
                  currentShift.vehicleLabel,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: AsmSpacing.space8),
                Text(
                  currentShift.serviceAreaLabel,
                  style: const TextStyle(
                    color: AsmColors.driverTextSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AsmSpacing.space16),
          Material(
            color: AsmColors.driverCard,
            borderRadius: BorderRadius.circular(AsmRadii.radius24),
            child: ListTile(
              key: const Key('driver-account-open-shift-history'),
              onTap: onOpenShiftHistory,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AsmRadii.radius24),
                side: const BorderSide(color: AsmColors.driverLine),
              ),
              leading: const Icon(
                Icons.history_outlined,
                color: AsmColors.driverMintAction,
              ),
              title: const Text(
                'Shift history',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: const Text('View past shifts and trip logs'),
              trailing: const Icon(Icons.chevron_right),
            ),
          ),
          if (onOpenSafetySettings != null) ...[
            const SizedBox(height: AsmSpacing.space16),
            Material(
              color: AsmColors.driverCard,
              borderRadius: BorderRadius.circular(AsmRadii.radius24),
              child: ListTile(
                key: const Key('driver-account-safety-emergency'),
                onTap: onOpenSafetySettings,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AsmRadii.radius24),
                  side: const BorderSide(color: AsmColors.driverLine),
                ),
                leading: const Icon(
                  Icons.health_and_safety_outlined,
                  color: AsmColors.driverMintAction,
                ),
                title: const Text(
                  'Safety & emergency',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: const Text('Trusted contact and trip safety'),
                trailing: const Icon(Icons.chevron_right),
              ),
            ),
          ],
          if (onSignOut != null) ...[
            const SizedBox(height: AsmSpacing.space24),
            AsmPrimaryActionButton(
              key: const Key('driver-account-sign-out'),
              onPressed: onSignOut,
              variant: AsmActionButtonVariant.outlined,
              icon: Icons.exit_to_app_outlined,
              label: 'Sign out',
            ),
          ],
        ],
      ),
    );
  }
}
