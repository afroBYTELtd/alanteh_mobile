import 'dart:async';

import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../account/passenger_payment_setup_screen.dart';
import '../map/passenger_map.dart';
import '../payment_rating/passenger_payment_rating_contract.dart';
import '../payment_rating/passenger_payment_rating_page.dart';
import '../ride_requests/ride_request_history.dart';

class RideTrackingScreen extends StatefulWidget {
  const RideTrackingScreen({
    required this.repository,
    required this.requestReference,
    this.initialRecord,
    this.pollInterval = const Duration(seconds: 10),
    this.paymentRatingRepository,
    this.phoneNumber,
    this.initialPaymentNetwork = PassengerMobileMoneyNetwork.mtn,
    this.onSignInRequired,
    super.key,
  });

  final PassengerRideRequestHistoryRepository repository;
  final String requestReference;
  final PassengerRideRequestRecord? initialRecord;
  final Duration pollInterval;
  final PassengerPaymentRatingRepository? paymentRatingRepository;
  final String? phoneNumber;
  final PassengerMobileMoneyNetwork initialPaymentNetwork;
  final VoidCallback? onSignInRequired;

  @override
  State<RideTrackingScreen> createState() => _RideTrackingScreenState();
}

class _RideTrackingScreenState extends State<RideTrackingScreen> {
  Timer? _timer;
  PassengerRideRequestRecord? _record;
  bool _loading = true;
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    _record = widget.initialRecord;
    _load();
  }

  @override
  void didUpdateWidget(covariant RideTrackingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    final requestChanged =
        oldWidget.repository != widget.repository ||
        oldWidget.requestReference != widget.requestReference;

    if (requestChanged) {
      _timer?.cancel();
      _record = widget.initialRecord;
      _loading = true;
      _offline = false;
      _load();
      return;
    }

    if (oldWidget.pollInterval != widget.pollInterval) {
      final record = _record;

      if (record != null && !record.isTerminal) {
        _schedule(record);
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final record = await widget.repository.fetchRequest(
        widget.requestReference,
      );
      if (!mounted) return;
      setState(() {
        _record = record;
        _loading = false;
        _offline = false;
      });
      _schedule(record);
    } on Object {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _offline = true;
      });
    }
  }

  void _schedule(PassengerRideRequestRecord record) {
    _timer?.cancel();
    if (record.isTerminal) return;
    _timer = Timer(widget.pollInterval, _load);
  }

  Future<void> _openPaymentRating() {
    final repository = widget.paymentRatingRepository;

    if (repository == null) {
      return Future<void>.value();
    }

    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => PassengerPaymentRatingPage(
          repository: repository,
          requestReference: widget.requestReference,
          phoneNumber: widget.phoneNumber,
          initialPaymentNetwork: widget.initialPaymentNetwork,
          pickupDescription: _record?.pickupLocation,
          destinationDescription: _record?.destination,
          tripCompletedAt: _record?.updatedAt,
          onSignInRequired: widget.onSignInRequired,
        ),
      ),
    );
  }

  Future<void> _showCancelDialog({required bool vehicleEnRoute}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        key: Key(
          vehicleEnRoute
              ? 'cancel-vehicle-en-route-dialog'
              : 'cancel-confirmation-dialog',
        ),
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              vehicleEnRoute
                  ? 'Cancel after driver dispatch?'
                  : 'Cancel this request?',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            Text(
              vehicleEnRoute
                  ? 'Your driver is already on the way. Cancellation may affect availability for other passengers.'
                  : 'Your request will remain active unless cancellation is completed through an approved service.',
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Keep my ride'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const Key('cancel-dialog-no-backend-mutation'),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _record == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_offline && _record == null) {
      return Scaffold(body: _OfflineState(onRetry: _load));
    }

    final record = _record!;
    final view = _TrackingView.from(record);

    if (view.rejected) {
      return Scaffold(
        appBar: AppBar(title: const Text('Ride request')),
        body: PassengerNoVehiclesAvailableState(
          onRetry: () => Navigator.of(context).maybePop(),
          onContactSupport: () {},
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: AsmPassengerMap(
              center: view.vehicle ?? accraHomeCenter,
              pickup: accraPickup,
              destination: view.showDestination ? accraDestination : null,
              vehicle: view.vehicle,
              route: view.route,
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: CircleAvatar(
                  backgroundColor: Colors.white,
                  child: IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back),
                  ),
                ),
              ),
            ),
          ),
          if (_offline)
            Positioned(
              top: 96,
              left: 16,
              right: 16,
              child: Material(
                borderRadius: BorderRadius.circular(14),
                color: const Color(0xFFFFF3E0),
                child: ListTile(
                  leading: const Icon(Icons.cloud_off_outlined),
                  title: const Text('Connection interrupted'),
                  subtitle: const Text('Showing the last safe update.'),
                  trailing: TextButton(
                    onPressed: _load,
                    child: const Text('Retry'),
                  ),
                ),
              ),
            ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              key: Key(view.key),
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                boxShadow: [
                  BoxShadow(color: Color(0x26000000), blurRadius: 28),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AsmColors.passengerLine,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Icon(view.icon, color: view.color, size: 30),
                  const SizedBox(height: 10),
                  Text(
                    view.title,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(view.message),
                  if (record.plateNumber != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      record.plateNumber!,
                      key: const Key('tracking-safe-plate-number'),
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                  if (view.reassigned) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Your vehicle has been reassigned.',
                      key: Key('vehicle-reassigned-state'),
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                  if (record.passengerState == PassengerRideState.arrived &&
                      widget.paymentRatingRepository != null) ...[
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      key: const Key('open-payment-rating-from-tracking'),
                      onPressed: _openPaymentRating,
                      icon: const Icon(Icons.payments_outlined),
                      label: const Text('Payment and rating'),
                    ),
                  ],
                  if (view.rejected) ...[
                    const SizedBox(height: 18),
                    FilledButton(
                      key: const Key('rejected-book-again'),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Book again'),
                    ),
                    TextButton(
                      key: const Key('rejected-contact-support'),
                      onPressed: () {},
                      child: const Text('Contact support'),
                    ),
                  ] else if (!record.isTerminal) ...[
                    const SizedBox(height: 18),
                    OutlinedButton.icon(
                      key: const Key('open-cancel-confirmation'),
                      onPressed: () => _showCancelDialog(
                        vehicleEnRoute: view.vehicleEnRoute,
                      ),
                      icon: const Icon(Icons.close),
                      label: const Text('Cancel request'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PassengerNoVehiclesAvailableState extends StatelessWidget {
  const PassengerNoVehiclesAvailableState({
    required this.onRetry,
    required this.onContactSupport,
    super.key,
  });

  final VoidCallback onRetry;
  final VoidCallback onContactSupport;

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: const Key('request-rejected-state'),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AsmSpacing.space24),
          child: Container(
            key: const Key('passenger-no-vehicles-state'),
            width: double.infinity,
            padding: const EdgeInsets.all(AsmSpacing.space24),
            decoration: BoxDecoration(
              color: AsmColors.passengerCard,
              borderRadius: BorderRadius.circular(AsmRadii.radius28),
              border: Border.all(color: AsmColors.passengerLine),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.directions_car_filled_outlined,
                  size: 58,
                  color: AsmColors.brandDeepGreen,
                ),
                const SizedBox(height: AsmSpacing.space16),
                const Text(
                  'No vehicles available right now',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    height: 1.15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: AsmSpacing.space12),
                const Text(
                  'All ALANTEH vehicles nearby are currently in use. '
                  'Please try again shortly, or request for a later time.',
                  textAlign: TextAlign.center,
                  style: TextStyle(height: 1.45),
                ),
                const SizedBox(height: AsmSpacing.space24),
                FilledButton.icon(
                  key: const Key('rejected-book-again'),
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                ),
                const SizedBox(height: AsmSpacing.space8),
                TextButton.icon(
                  key: const Key('rejected-contact-support'),
                  onPressed: onContactSupport,
                  icon: const Icon(Icons.support_agent_outlined),
                  label: const Text('Contact support'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OfflineState extends StatelessWidget {
  const _OfflineState({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const Key('offline-state'),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 64),
            const SizedBox(height: 16),
            const Text(
              'You’re offline',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            const Text(
              'Check your connection and try again.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrackingView {
  const _TrackingView({
    required this.key,
    required this.title,
    required this.message,
    required this.icon,
    required this.color,
    required this.route,
    this.vehicle,
    this.showDestination = false,
    this.vehicleEnRoute = false,
    this.reassigned = false,
    this.rejected = false,
  });

  final String key;
  final String title;
  final String message;
  final IconData icon;
  final Color color;
  final List<LatLng> route;
  final LatLng? vehicle;
  final bool showDestination;
  final bool vehicleEnRoute;
  final bool reassigned;
  final bool rejected;

  factory _TrackingView.from(PassengerRideRequestRecord record) {
    final status = record.passengerState;
    final message = record.safeMessage;
    final vehicle = record.vehiclePosition;

    List<LatLng> routeToPickup() {
      if (vehicle == null) {
        return const <LatLng>[];
      }

      return <LatLng>[vehicle, accraPickup];
    }

    List<LatLng> routeToDestination() {
      if (vehicle == null) {
        return const <LatLng>[accraPickup, accraDestination];
      }

      return <LatLng>[accraPickup, vehicle, accraDestination];
    }

    switch (status) {
      case PassengerRideState.driverAssigned:
        return _TrackingView(
          key: 'driver-assigned-state',
          title: 'Driver assigned',
          message: message,
          icon: Icons.person_pin_circle,
          color: AsmColors.brandDeepGreen,
          route: routeToPickup(),
          vehicle: vehicle,
        );

      case PassengerRideState.vehicleEnRoute:
        return _TrackingView(
          key: 'vehicle-en-route-state',
          title: 'Your vehicle is on the way',
          message: message,
          icon: Icons.electric_car,
          color: AsmColors.brandDeepGreen,
          route: routeToPickup(),
          vehicle: vehicle,
          vehicleEnRoute: true,
        );

      case PassengerRideState.driverArrived:
        return _TrackingView(
          key: 'driver-arrived-state',
          title: 'Your driver is outside',
          message: message,
          icon: Icons.notifications_active_outlined,
          color: AsmColors.brandDeepGreen,
          route: const <LatLng>[],
          vehicle: vehicle,
          vehicleEnRoute: true,
        );

      case PassengerRideState.inProgress:
        return _TrackingView(
          key: 'trip-in-progress-state',
          title: 'Trip in progress',
          message: message,
          icon: Icons.route,
          color: AsmColors.brandDeepGreen,
          route: routeToDestination(),
          vehicle: vehicle,
          showDestination: true,
        );

      case PassengerRideState.arrived:
        return _TrackingView(
          key: 'arrived-at-destination-state',
          title: 'You’ve arrived',
          message: message,
          icon: Icons.check_circle,
          color: AsmColors.brandDeepGreen,
          route: const <LatLng>[accraPickup, accraDestination],
          vehicle: vehicle,
          showDestination: true,
        );

      case PassengerRideState.reassigned:
        return _TrackingView(
          key: 'vehicle-reassigned-state',
          title: 'New vehicle assigned',
          message: message,
          icon: Icons.swap_horiz,
          color: AsmColors.brandDeepGreen,
          route: routeToPickup(),
          vehicle: vehicle,
          vehicleEnRoute: true,
          reassigned: true,
        );

      case PassengerRideState.rejected:
        return _TrackingView(
          key: 'request-rejected-state',
          title: 'No vehicles available right now',
          message: message,
          icon: Icons.no_transfer_outlined,
          color: Colors.redAccent,
          route: const <LatLng>[],
          rejected: true,
        );

      case PassengerRideState.looking:
        return _TrackingView(
          key: 'looking-for-driver-state',
          title: 'Looking for a driver',
          message: message,
          icon: Icons.radar,
          color: const Color(0xFFC8971F),
          route: const <LatLng>[],
        );
    }
  }
}
