import 'dart:async';

import 'package:asm_app_config/asm_app_config.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';

import 'concern/driver_concern_page.dart';
import 'driver_duty_trips.dart';
import 'driver_home.dart';
import 'foundation/driver_foundation_widgets.dart';
import 'network/driver_offer_response_resilience.dart';
import 'network/driver_report_gateway.dart';
import 'network/driver_trip_action_resilience.dart';
import 'readiness/driver_readiness_page.dart';
import 'readiness/driver_shift_check_submission.dart';
import 'ride_offer/driver_ride_offer_page.dart';
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

class DriverShell extends StatefulWidget {
  const DriverShell({
    this.configuration = AsmAppConfig.localGhana,
    this.localQaEnabled = false,
    this.onSignOut,
    this.driverDutyGateway,
    this.driverTripActionControllerFactory,
    this.driverOfferResponseControllerFactory,
    this.driverShiftCheckController,
    this.driverReportGateway,
    this.deviceNow,
    this.onlineTransitionDuration = const Duration(seconds: 2),
    super.key,
  });

  final AsmAppConfig configuration;
  final bool localQaEnabled;
  final Future<void> Function()? onSignOut;
  final DriverDutyGateway? driverDutyGateway;
  final DriverTripActionControllerFactory? driverTripActionControllerFactory;
  final DriverOfferResponseControllerFactory?
  driverOfferResponseControllerFactory;
  final DriverShiftCheckSubmissionController? driverShiftCheckController;
  final DriverReportGateway? driverReportGateway;
  final DateTime Function()? deviceNow;
  final Duration onlineTransitionDuration;

  @override
  State<DriverShell> createState() => _DriverShellState();
}

class _DriverShellState extends State<DriverShell> {
  int _selectedIndex = 0;
  bool _localChecklistComplete = false;
  bool _dutyLoading = false;
  bool _dutyActionInFlight = false;
  bool _showOnlineTransition = false;
  bool _startupShiftCheckConsidered = false;
  bool _startupShiftCheckNavigationPending = false;
  DriverDutySummary? _dutySummary;
  Object? _dutyError;

  bool get _shiftCheckCompletedToday {
    if (widget.driverDutyGateway == null) {
      return _localChecklistComplete;
    }

    return _dutySummary?.shiftCheckToday == true;
  }

  bool get _isOnline =>
      _shiftCheckCompletedToday && (_dutySummary?.isOnline ?? false);

  @override
  void initState() {
    super.initState();

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
    final controller = widget.driverShiftCheckController;
    if (controller != null) {
      unawaited(controller.stopAutomaticSync());
    }
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
    _startupGateDiag('open_readiness completion=submitted');
  }

  Future<void> _confirmOnlineAfterShiftCheck() async {
    final gateway = widget.driverDutyGateway;
    if (gateway == null) {
      return;
    }

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
        final oldDutyLoading = _dutyLoading;
        setState(() {
          _dutyLoading = false;
          _startupGateDiagBoolTransition(
            field: 'duty_loading',
            oldValue: oldDutyLoading,
            newValue: _dutyLoading,
            reason: 'confirm_online_server_not_online',
          );
          _dutyError = const DriverDutyApiException(
            DriverDutyApiFailureType.badResponse,
            'Driver online status could not be confirmed.',
          );
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
        _dutyError = error;
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

    setState(() {
      _dutyActionInFlight = true;
      _dutyError = null;
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

      setState(() {
        _dutyActionInFlight = false;
        _dutyError = error;
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
    setState(() {
      _localChecklistComplete = false;
      _dutySummary = null;
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

    if (_dutyError != null && widget.driverDutyGateway != null) {
      return DriverOfflineState(onRetry: _loadDuty);
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
      onGoOffline: _isOnline
          ? () => unawaited(_changeDuty(DriverOperationalDutyStatus.offline))
          : null,
      onRecordConcern: _openConcern,
      onPreviewIncomingRequest: _openRideOfferPreview,
      localQaEnabled: widget.localQaEnabled,
      dutyGateway: widget.driverDutyGateway,
      onOpenAssignedTrips: _openAssignedTrips,
      onOpenShiftSummary: _openShiftSummary,
      onSignOut: widget.onSignOut == null ? null : _signOut,
    );
  }

  Widget get _selectedPage {
    return switch (_selectedIndex) {
      0 => _workPage,
      1 => DriverAssignedTripsScreen(
        gateway: widget.driverDutyGateway,
        actionControllerFactory: widget.driverTripActionControllerFactory,
        offerResponseControllerFactory:
            widget.driverOfferResponseControllerFactory,
      ),
      _ => _DriverAccountPage(
        currentShift: _currentShift,
        onOpenShiftHistory: _openShiftHistory,
        onSignOut: widget.onSignOut == null ? null : _signOut,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _selectedPage,
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
  });

  final DriverShiftRecord currentShift;
  final VoidCallback onOpenShiftHistory;
  final Future<void> Function()? onSignOut;

  @override
  Widget build(BuildContext context) {
    return AsmScreenSurface(
      key: const Key('driver-account-screen'),
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
