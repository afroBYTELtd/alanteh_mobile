import 'package:asm_app_config/asm_app_config.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';

import 'concern/driver_concern_page.dart';
import 'driver_duty_trips.dart';
import 'driver_home.dart';
import 'network/driver_trip_action_resilience.dart';
import 'readiness/driver_readiness_page.dart';
import 'ride_offer/driver_ride_offer_page.dart';
import 'shift/driver_shift_history.dart';

class DriverShell extends StatefulWidget {
  const DriverShell({
    this.configuration = AsmAppConfig.localGhana,
    this.localQaEnabled = false,
    this.onSignOut,
    this.driverDutyGateway,
    this.driverTripActionControllerFactory,
    super.key,
  });

  final AsmAppConfig configuration;
  final bool localQaEnabled;
  final Future<void> Function()? onSignOut;
  final DriverDutyGateway? driverDutyGateway;
  final DriverTripActionControllerFactory? driverTripActionControllerFactory;

  @override
  State<DriverShell> createState() => _DriverShellState();
}

class _DriverShellState extends State<DriverShell> {
  int _selectedIndex = 0;
  bool _localChecklistComplete = false;

  void _openAssignedTrips() {
    setState(() => _selectedIndex = 1);
  }

  DriverShiftRecord get _currentShift {
    return DriverShiftRecord(
      id: 'current',
      dateLabel: 'Today',
      dutyLabel: _localChecklistComplete
          ? 'Local checklist complete'
          : 'Local checklist not completed',
      status: DriverShiftStatus.notStarted,
      onlineDurationLabel: 'LOCAL ONLY',
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
    final completed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) =>
            DriverReadinessPage(market: widget.configuration.market),
      ),
    );

    if (!mounted || completed != true) {
      return;
    }

    setState(() {
      _localChecklistComplete = true;
      _selectedIndex = 0;
    });
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
      _selectedIndex = 0;
    });
    await widget.onSignOut?.call();
  }

  Widget get _selectedPage {
    return switch (_selectedIndex) {
      0 => DriverHome(
        market: widget.configuration.market,
        isOnShift: false,
        onOpenReadiness: _openReadiness,
        onRecordConcern: _openConcern,
        onPreviewIncomingRequest: _openRideOfferPreview,
        localQaEnabled: widget.localQaEnabled,
        dutyGateway: widget.driverDutyGateway,
        onOpenAssignedTrips: _openAssignedTrips,
        onOpenShiftSummary: _openShiftSummary,
        onDutyChanged: null,
        onSignOut: widget.onSignOut == null ? null : _signOut,
      ),
      1 => DriverAssignedTripsScreen(
        gateway: widget.driverDutyGateway,
        actionControllerFactory: widget.driverTripActionControllerFactory,
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
