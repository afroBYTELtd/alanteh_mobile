import 'package:asm_app_config/asm_app_config.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';

import 'booking/booking_page.dart';
import 'booking/booking_submission.dart';
import 'location/location_search_page.dart';
import 'location/session_location_history.dart';
import 'passenger_home.dart';
import 'ride_requests/ride_request_history.dart';

class PassengerShell extends StatefulWidget {
  const PassengerShell({
    this.configuration = AsmAppConfig.localGhana,
    this.localQaEnabled = false,
    this.rideRequestSubmitter,
    this.rideRequestHistoryRepository,
    this.onSignInRequired,
    this.onSignOut,
    super.key,
  });

  final AsmAppConfig configuration;
  final bool localQaEnabled;
  final PassengerRideRequestSubmitter? rideRequestSubmitter;
  final PassengerRideRequestHistoryRepository? rideRequestHistoryRepository;
  final VoidCallback? onSignInRequired;
  final Future<void> Function()? onSignOut;

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

  Future<void> _signOut() async {
    setState(() {
      _selectedIndex = 0;
      _pickupDescription = null;
      _destinationDescription = null;
    });
    await widget.onSignOut?.call();
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
          rideRequestSubmitter: widget.rideRequestSubmitter,
          onSignInRequired: widget.onSignInRequired,
        ),
      ),
    );

    if (closed == true && mounted) {
      setState(() {
        _pickupDescription = null;
        _destinationDescription = null;
      });
      if (widget.rideRequestHistoryRepository != null) {
        await _openRideRequests();
      }
    }
  }

  Future<void> _openRequestForm() async {
    final closed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => BookingPage(
          market: widget.configuration.market,
          initialPickupDescription: _pickupDescription ?? '',
          initialDestinationDescription: _destinationDescription ?? '',
          rideRequestSubmitter: widget.rideRequestSubmitter,
          onSignInRequired: widget.onSignInRequired,
        ),
      ),
    );

    if (closed == true && mounted) {
      setState(() {
        _pickupDescription = null;
        _destinationDescription = null;
      });
      if (widget.rideRequestHistoryRepository != null) {
        await _openRideRequests();
      }
    }
  }

  Future<void> _openRideRequests() {
    final repository =
        widget.rideRequestHistoryRepository ??
        const UnavailablePassengerRideRequestHistoryRepository();

    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => PassengerRideRequestHistoryPage(
          repository: repository,
          onSignInRequired: widget.onSignInRequired,
          onBookRide: () {
            Navigator.of(context).pop();
            setState(() => _selectedIndex = 0);
          },
        ),
      ),
    );
  }

  Widget get _selectedPage {
    return switch (_selectedIndex) {
      0 => PassengerHome(
        market: widget.configuration.market,
        localQaEnabled: widget.localQaEnabled,
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
        onStartRequest: _openRequestForm,
        onOpenRequests: _openRideRequests,
        onSwap: _swapRoute,
        onClear: _clearRoute,
      ),
      1 => PassengerRideRequestHistoryPage(
        repository:
            widget.rideRequestHistoryRepository ??
            const EmptyPassengerRideRequestHistoryRepository(),
        onSignInRequired: widget.onSignInRequired,
        onBookRide: () => setState(() => _selectedIndex = 0),
      ),
      _ => _PassengerPlaceholder(
        icon: Icons.account_circle_outlined,
        title: 'Passenger account',
        message: 'Your account details are managed by the Control Center.',
        actionLabel: widget.onSignOut == null ? null : 'Sign out',
        actionKey: widget.onSignOut == null
            ? null
            : const Key('passenger-account-sign-out'),
        onActionPressed: widget.onSignOut == null ? null : _signOut,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _selectedPage,
      floatingActionButton: widget.onSignOut == null
          ? null
          : FloatingActionButton.extended(
              key: const Key('passenger-sign-out'),
              onPressed: _signOut,
              icon: const Icon(Icons.exit_to_app_outlined),
              label: const Text('Sign out'),
            ),
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
            icon: Icon(Icons.account_circle_outlined),
            selectedIcon: Icon(Icons.account_circle),
            label: 'Account',
          ),
        ],
      ),
    );
  }
}

class _PassengerPlaceholder extends StatelessWidget {
  const _PassengerPlaceholder({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.actionKey,
    this.onActionPressed,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final Key? actionKey;
  final VoidCallback? onActionPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return AsmScreenSurface(
      padding: const EdgeInsets.all(AsmSpacing.space20),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: colors.primary),
            const SizedBox(height: AsmSpacing.space16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: AsmSpacing.space8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: colors.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            if (actionLabel != null && onActionPressed != null) ...[
              const SizedBox(height: AsmSpacing.space16),
              FilledButton(
                key: actionKey,
                onPressed: onActionPressed,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
