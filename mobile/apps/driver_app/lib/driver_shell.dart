import 'package:asm_app_config/asm_app_config.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';

import 'concern/driver_concern_page.dart';
import 'driver_home.dart';
import 'readiness/driver_readiness_page.dart';
import 'ride_offer/driver_ride_offer_page.dart';

class DriverShell extends StatefulWidget {
  const DriverShell({
    this.configuration = AsmAppConfig.localGhana,
    this.localQaEnabled = false,
    this.onSignOut,
    super.key,
  });

  final AsmAppConfig configuration;
  final bool localQaEnabled;
  final Future<void> Function()? onSignOut;

  @override
  State<DriverShell> createState() => _DriverShellState();
}

class _DriverShellState extends State<DriverShell> {
  int _selectedIndex = 0;
  bool _isOnShift = false;

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
        onSignOut: widget.onSignOut == null ? null : _signOut,
      ),
      1 => const AsmDemoPlaceholder(
        icon: Icons.route_outlined,
        title: 'No trips yet',
        message: 'Trip assignments will appear here.',
      ),
      _ => const AsmDemoPlaceholder(
        icon: Icons.support_agent_outlined,
        title: 'Support not connected',
        message: 'Support is not available yet.',
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
            icon: Icon(Icons.support_agent_outlined),
            selectedIcon: Icon(Icons.support_agent),
            label: 'Support',
          ),
        ],
      ),
    );
  }
}
