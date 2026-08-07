import 'dart:async';

import 'package:asm_app_config/asm_app_config.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';

import 'concern/driver_concern_page.dart';
import 'driver_duty_trips.dart';
import 'driver_home.dart';
import 'foundation/driver_foundation_widgets.dart';
import 'network/driver_offer_response_resilience.dart';
import 'network/driver_trip_action_resilience.dart';
import 'readiness/driver_readiness_page.dart';
import 'readiness/driver_shift_check_submission.dart';
import 'ride_offer/driver_ride_offer_page.dart';
import 'shift/driver_shift_history.dart';

class DriverShell extends StatefulWidget {
  const DriverShell({
    this.configuration = AsmAppConfig.localGhana,
    this.localQaEnabled = false,
    this.onSignOut,
    this.driverDutyGateway,
    this.driverTripActionControllerFactory,
    this.driverOfferResponseControllerFactory,
    this.driverShiftCheckController,
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
  DriverDutySummary? _dutySummary;
  Object? _dutyError;

  DateTime get _now => widget.deviceNow?.call() ?? DateTime.now();

  bool get _shiftCheckCompletedToday {
    if (widget.driverDutyGateway == null) {
      return _localChecklistComplete;
    }

    return _dutySummary?.shiftCheckCompletedOnCalendarDay(_now) ?? false;
  }

  bool get _isOnline =>
      _shiftCheckCompletedToday && (_dutySummary?.isOnline ?? false);

  @override
  void initState() {
    super.initState();

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

    if (oldWidget.driverDutyGateway != widget.driverDutyGateway) {
      _startupShiftCheckConsidered = false;

      if (widget.driverDutyGateway == null) {
        setState(() {
          _dutySummary = null;
          _dutyError = null;
          _dutyLoading = false;
        });
      } else {
        unawaited(_loadDuty());
      }
    }
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
      return;
    }

    setState(() {
      _dutyLoading = true;
      _dutyError = null;
    });

    try {
      final duty = await gateway.fetchDuty();

      if (!mounted) {
        return;
      }

      setState(() {
        _dutySummary = duty;
        _dutyLoading = false;
        _dutyError = null;
      });

      _openStartupShiftCheckIfRequired();
    } on Object catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _dutyLoading = false;
        _dutyError = error;
      });
    }
  }

  void _openStartupShiftCheckIfRequired() {
    if (_startupShiftCheckConsidered ||
        widget.driverDutyGateway == null ||
        _dutySummary == null) {
      return;
    }

    _startupShiftCheckConsidered = true;

    if (_dutySummary!.dutyStatus == 'offline' && !_shiftCheckCompletedToday) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _selectedIndex != 0 || _shiftCheckCompletedToday) {
          return;
        }

        unawaited(_openReadiness());
      });
    }
  }

  void _openAssignedTrips() {
    setState(() => _selectedIndex = 1);
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
    if (_shiftCheckCompletedToday) {
      return;
    }

    final disposition = await Navigator.of(context)
        .push<DriverShiftCheckSubmissionDisposition>(
          MaterialPageRoute<DriverShiftCheckSubmissionDisposition>(
            builder: (_) => DriverReadinessPage(
              market: widget.configuration.market,
              submissionController: widget.driverShiftCheckController,
              deviceNow: widget.deviceNow,
              navigationDelay: widget.driverDutyGateway == null
                  ? const Duration(seconds: 2)
                  : Duration.zero,
            ),
          ),
        );

    if (!mounted || disposition == null) {
      return;
    }

    if (widget.driverDutyGateway == null) {
      setState(() {
        _localChecklistComplete = true;
        _selectedIndex = 0;
      });
      return;
    }

    if (disposition != DriverShiftCheckSubmissionDisposition.submitted) {
      setState(() {
        _selectedIndex = 0;
      });
      return;
    }

    await _confirmOnlineAfterShiftCheck();
  }

  Future<void> _confirmOnlineAfterShiftCheck() async {
    final gateway = widget.driverDutyGateway;
    if (gateway == null) {
      return;
    }

    setState(() {
      _dutyLoading = true;
      _dutyError = null;
      _selectedIndex = 0;
    });

    try {
      final refreshed = await gateway.fetchDuty();

      if (!mounted) {
        return;
      }

      if (!refreshed.isOnline) {
        setState(() {
          _dutyLoading = false;
          _dutyError = const DriverDutyApiException(
            DriverDutyApiFailureType.badResponse,
            'Driver online status could not be confirmed.',
          );
        });
        return;
      }

      setState(() {
        _dutySummary = refreshed;
        _dutyLoading = false;
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

      setState(() {
        _dutyLoading = false;
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
        builder: (_) => DriverConcernPage(market: widget.configuration.market),
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
    setState(() {
      _localChecklistComplete = false;
      _dutySummary = null;
      _dutyError = null;
      _dutyLoading = false;
      _dutyActionInFlight = false;
      _showOnlineTransition = false;
      _startupShiftCheckConsidered = false;
      _selectedIndex = 0;
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

    if (_dutyLoading && _dutySummary == null) {
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
          setState(() => _selectedIndex = index);
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
