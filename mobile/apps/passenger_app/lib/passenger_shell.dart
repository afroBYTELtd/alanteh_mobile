import 'package:asm_app_config/asm_app_config.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';

import 'account/passenger_account_screen.dart';
import 'account/passenger_payment_setup_screen.dart';
import 'booking/booking_page.dart';
import 'booking/booking_submission.dart';
import 'booking/passenger_fare_estimate.dart';
import 'location/location_search_page.dart';
import 'location/session_location_history.dart';
import 'passenger_home.dart';
import 'payment_rating/passenger_payment_rating_contract.dart';
import 'ride_requests/ride_request_history.dart';

class PassengerShell extends StatefulWidget {
  const PassengerShell({
    this.configuration = AsmAppConfig.localGhana,
    this.localQaEnabled = false,
    this.rideRequestSubmitter,
    this.rideRequestHistoryRepository,
    this.paymentRatingRepository,
    this.fareEstimateRepository,
    this.phoneNumber,
    this.onSignInRequired,
    this.onSignOut,
    super.key,
  });

  final AsmAppConfig configuration;
  final bool localQaEnabled;
  final PassengerRideRequestSubmitter? rideRequestSubmitter;
  final PassengerRideRequestHistoryRepository? rideRequestHistoryRepository;
  final PassengerPaymentRatingRepository? paymentRatingRepository;
  final PassengerFareEstimateRepository? fareEstimateRepository;
  final String? phoneNumber;
  final VoidCallback? onSignInRequired;
  final Future<void> Function()? onSignOut;

  @override
  State<PassengerShell> createState() => _PassengerShellState();
}

class _PassengerShellState extends State<PassengerShell> {
  int _selectedIndex = 0;
  String? _pickupDescription;
  String? _destinationDescription;
  PassengerMobileMoneyNetwork _paymentNetwork = PassengerMobileMoneyNetwork.mtn;
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

  void _openTripsTab() {
    setState(() => _selectedIndex = 1);
  }

  Future<void> _openPaymentSetup() async {
    final selected = await Navigator.of(context)
        .push<PassengerMobileMoneyNetwork>(
          MaterialPageRoute<PassengerMobileMoneyNetwork>(
            builder: (_) => PassengerPaymentSetupScreen(
              initialNetwork: _paymentNetwork,
              phoneNumber: widget.phoneNumber,
            ),
          ),
        );

    if (selected == null || !mounted) {
      return;
    }

    setState(() => _paymentNetwork = selected);
  }

  Future<void> _signOut() async {
    setState(() {
      _selectedIndex = 0;
      _pickupDescription = null;
      _destinationDescription = null;
      _paymentNetwork = PassengerMobileMoneyNetwork.mtn;
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
          rideRequestHistoryRepository: widget.rideRequestHistoryRepository,
          paymentRatingRepository: widget.paymentRatingRepository,
          phoneNumber: widget.phoneNumber,
          initialPaymentNetwork: _paymentNetwork,
          fareEstimateRepository: widget.fareEstimateRepository,
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
          rideRequestHistoryRepository: widget.rideRequestHistoryRepository,
          paymentRatingRepository: widget.paymentRatingRepository,
          phoneNumber: widget.phoneNumber,
          initialPaymentNetwork: _paymentNetwork,
          fareEstimateRepository: widget.fareEstimateRepository,
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

  Future<void> _openBookAgain(PassengerRideRequestRecord record) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => BookingPage(
          market: widget.configuration.market,
          initialPickupDescription: record.pickupLocation,
          initialDestinationDescription: record.destination,
          rideRequestSubmitter: widget.rideRequestSubmitter,
          onSignInRequired: widget.onSignInRequired,
          rideRequestHistoryRepository: widget.rideRequestHistoryRepository,
          paymentRatingRepository: widget.paymentRatingRepository,
          phoneNumber: widget.phoneNumber,
          initialPaymentNetwork: _paymentNetwork,
          fareEstimateRepository: widget.fareEstimateRepository,
        ),
      ),
    );
  }

  Future<void> _openRideRequests() {
    final repository =
        widget.rideRequestHistoryRepository ??
        const UnavailablePassengerRideRequestHistoryRepository();

    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => PassengerRideRequestHistoryPage(
          repository: repository,
          paymentRatingRepository: widget.paymentRatingRepository,
          onSignInRequired: widget.onSignInRequired,
          onBookRide: () {
            Navigator.of(context).pop();
            setState(() => _selectedIndex = 0);
          },
          onBookAgain: _openBookAgain,
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
        paymentRatingRepository: widget.paymentRatingRepository,
        onSignInRequired: widget.onSignInRequired,
        onBookRide: () => setState(() => _selectedIndex = 0),
        onBookAgain: _openBookAgain,
      ),
      _ => PassengerAccountScreen(
        phoneNumber: widget.phoneNumber,
        paymentMethodLabel: _paymentNetwork.accountLabel,
        onOpenPaymentSetup: _openPaymentSetup,
        onOpenTrips: _openTripsTab,
        onSignOut: _signOut,
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
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Account',
          ),
        ],
      ),
    );
  }
}
