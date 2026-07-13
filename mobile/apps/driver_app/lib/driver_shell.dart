import 'package:asm_app_config/asm_app_config.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';

import 'concern/driver_concern_page.dart';
import 'driver_duty_trips.dart';
import 'driver_home.dart';
import 'readiness/driver_readiness_page.dart';
import 'ride_offer/driver_ride_offer_page.dart';

class DriverShell extends StatefulWidget {
  const DriverShell({
    this.configuration = AsmAppConfig.localGhana,
    this.localQaEnabled = false,
    this.onSignOut,
    this.driverDutyGateway,
    super.key,
  });

  final AsmAppConfig configuration;
  final bool localQaEnabled;
  final Future<void> Function()? onSignOut;
  final DriverDutyGateway? driverDutyGateway;

  @override
  State<DriverShell> createState() => _DriverShellState();
}

class _DriverShellState extends State<DriverShell> {
  int _selectedIndex = 0;
  bool _isOnShift = false;

  void _openAssignedTrips() {
    setState(() => _selectedIndex = 1);
  }

  Future<void> _openReadiness() async {
    if (!widget.localQaEnabled) {
      return;
    }

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
      _isOnShift = true;
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
      _isOnShift = false;
      _selectedIndex = 0;
    });
    await widget.onSignOut?.call();
  }

  Widget get _selectedPage {
    return switch (_selectedIndex) {
      0 => DriverHome(
        market: widget.configuration.market,
        isOnShift: _isOnShift,
        onOpenReadiness: _openReadiness,
        onRecordConcern: _openConcern,
        onPreviewIncomingRequest: _openRideOfferPreview,
        localQaEnabled: widget.localQaEnabled,
        dutyGateway: widget.driverDutyGateway,
        onOpenAssignedTrips: _openAssignedTrips,
        onSignOut: widget.onSignOut == null ? null : _signOut,
      ),
      1 => DriverAssignedTripsScreen(gateway: widget.driverDutyGateway),
      _ => _DriverAccountPage(
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
  const _DriverAccountPage({required this.onSignOut});

  final Future<void> Function()? onSignOut;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return AsmScreenSurface(
      padding: const EdgeInsets.all(AsmSpacing.space24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.account_circle_outlined,
              size: 48,
              color: colors.primary,
            ),
            const SizedBox(height: AsmSpacing.space16),
            Text(
              'Driver account',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: AsmSpacing.space8),
            Text(
              'Signed in to ALANTEH Driver.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: colors.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            if (onSignOut != null) ...[
              const SizedBox(height: AsmSpacing.space16),
              FilledButton.icon(
                key: const Key('driver-account-sign-out'),
                onPressed: onSignOut,
                icon: const Icon(Icons.exit_to_app_outlined),
                label: const Text('Sign out'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
