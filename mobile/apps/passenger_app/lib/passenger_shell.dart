import 'package:asm_app_config/asm_app_config.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';

import 'booking/booking_page.dart';
import 'location/location_search_page.dart';
import 'location/session_location_history.dart';
import 'passenger_home.dart';

class PassengerShell extends StatefulWidget {
  const PassengerShell({
    this.configuration = AsmAppConfig.localGhana,
    super.key,
  });

  final AsmAppConfig configuration;

  @override
  State<PassengerShell> createState() => _PassengerShellState();
}

class _PassengerShellState extends State<PassengerShell> {
  int _selectedIndex = 0;
  String? _pickupDescription;
  String? _destinationDescription;
  late SessionLocationHistory _locationHistory;

  @override
  void initState() {
    super.initState();
    _locationHistory = SessionLocationHistory.empty(
      marketCode: widget.configuration.market.marketCode,
    );
  }

  bool get _canContinue {
    final pickup = _pickupDescription?.trim() ?? '';
    final destination = _destinationDescription?.trim() ?? '';
    return pickup.isNotEmpty &&
        destination.isNotEmpty &&
        pickup.toLowerCase() != destination.toLowerCase();
  }

  bool get _locationsMatch {
    final pickup = _pickupDescription?.trim() ?? '';
    final destination = _destinationDescription?.trim() ?? '';
    return pickup.isNotEmpty &&
        destination.isNotEmpty &&
        pickup.toLowerCase() == destination.toLowerCase();
  }

  Future<void> _chooseLocation(LocationSearchKind kind) async {
    final initialDescription = switch (kind) {
      LocationSearchKind.pickup => _pickupDescription,
      LocationSearchKind.destination => _destinationDescription,
    };
    final description = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => LocationSearchPage(
          kind: kind,
          market: widget.configuration.market,
          initialDescription: initialDescription,
          recentDescriptions: _locationHistory.entries,
        ),
      ),
    );

    if (description == null || !mounted) {
      return;
    }

    setState(() {
      _locationHistory = _locationHistory.record(description);
      if (kind == LocationSearchKind.pickup) {
        _pickupDescription = description;
      } else {
        _destinationDescription = description;
      }
    });
  }

  void _swapRoute() {
    if (_pickupDescription == null || _destinationDescription == null) {
      return;
    }

    setState(() {
      final pickup = _pickupDescription;
      _pickupDescription = _destinationDescription;
      _destinationDescription = pickup;
    });
  }

  void _clearRoute() {
    setState(() {
      _pickupDescription = null;
      _destinationDescription = null;
    });
  }

  Future<void> _continueToDraft() async {
    if (!_canContinue) {
      return;
    }

    final closed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => BookingPage(
          market: widget.configuration.market,
          initialPickupDescription: _pickupDescription!,
          initialDestinationDescription: _destinationDescription!,
        ),
      ),
    );

    if (closed == true && mounted) {
      setState(() {
        _pickupDescription = null;
        _destinationDescription = null;
      });
    }
  }

  Widget get _selectedPage {
    return switch (_selectedIndex) {
      0 => PassengerHome(
        market: widget.configuration.market,
        pickupDescription: _pickupDescription,
        destinationDescription: _destinationDescription,
        canContinue: _canContinue,
        locationsMatch: _locationsMatch,
        canSwap: _pickupDescription != null && _destinationDescription != null,
        hasRoute: _pickupDescription != null || _destinationDescription != null,
        onChoosePickup: () => _chooseLocation(LocationSearchKind.pickup),
        onChooseDestination: () =>
            _chooseLocation(LocationSearchKind.destination),
        onContinue: _continueToDraft,
        onSwap: _swapRoute,
        onClear: _clearRoute,
      ),
      1 => const AsmDemoPlaceholder(
        icon: Icons.route_outlined,
        title: 'No trips connected',
        message:
            'Trip history will appear after secure services are connected.',
      ),
      _ => const AsmDemoPlaceholder(
        icon: Icons.support_agent_outlined,
        title: 'Support not connected',
        message: 'Live support is unavailable in this local demo.',
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _selectedPage,
      bottomNavigationBar: AsmBottomNavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() => _selectedIndex = index);
        },
        destinations: const [
          AsmBottomNavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          AsmBottomNavigationDestination(
            icon: Icon(Icons.route_outlined),
            selectedIcon: Icon(Icons.route),
            label: 'Trips',
          ),
          AsmBottomNavigationDestination(
            icon: Icon(Icons.support_agent_outlined),
            selectedIcon: Icon(Icons.support_agent),
            label: 'Support',
          ),
        ],
      ),
    );
  }
}
