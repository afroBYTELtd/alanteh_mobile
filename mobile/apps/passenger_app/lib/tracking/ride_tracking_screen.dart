import '../booking/scheduled_pickup.dart';
import 'dart:async';

import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_auth/asm_auth.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../account/passenger_payment_setup_screen.dart';
import '../map/measured_height.dart';
import '../map/passenger_map.dart';
import '../network/passenger_cancellation_gateway.dart';
import '../payment_rating/passenger_payment_rating_contract.dart';
import '../payment_rating/passenger_payment_rating_page.dart';
import '../ride_requests/ride_request_history.dart';
import '../safety/passenger_trip_safety.dart';
import '../support/new_message_form.dart';
import 'passenger_tracking_screens.dart';

/// Mirrors the backend's eligible-status sets exactly
/// (RIDE_REQUEST_CANCEL_ELIGIBLE_STATUSES / TRIP_PASSENGER_CANCEL_ELIGIBLE_STATUSES
/// in backend/dashboard/api_rides.py and api_trips.py) - checked against the raw
/// status string, not PassengerRideState, since that derived enum has gaps for
/// some raw statuses (e.g. passenger_onboard falls through to "looking") that
/// would make an already-uncancellable trip look cancellable here.
bool passengerCanCancelTrip({required bool tripCreated, required String rawStatus}) {
  final normalized = rawStatus.trim().toLowerCase();
  if (!tripCreated) {
    return normalized == 'requested' || normalized == 'under_review';
  }
  return const <String>{
    'requested',
    'under_review',
    'fare_confirmed',
    'awaiting_payment',
    'payment_confirmed',
    'driver_offer_sent',
    'driver_accepted',
    'driver_declined',
    'assigned',
    'dispatched',
    'driver_en_route',
    'arrived_at_pickup',
  }.contains(normalized);
}

/// How long "Cancelling…" waits before saying the connection is slow.
const passengerCancelSlowAfter = Duration(seconds: 10);

class RideTrackingScreen extends StatefulWidget {
  const RideTrackingScreen({
    required this.repository,
    required this.requestReference,
    this.initialRecord,
    this.tripRepository,
    this.pollInterval = const Duration(seconds: 10),
    this.clock,
    this.paymentRatingRepository,
    this.trustedContactRepository,
    this.safetyUriLauncher = const PlatformPassengerSafetyUriLauncher(),
    this.safetyShareGateway = const PlatformPassengerSafetyShareGateway(),
    this.cancellationGateway,
    this.phoneNumber,
    this.initialPaymentNetwork = PassengerMobileMoneyNetwork.mtn,
    this.onSignInRequired,
    this.onBookAgain,
    this.passengerName,
    this.supportMessageSubmitter,
    this.signInEndsSoon,
    super.key,
  });

  final PassengerRideRequestHistoryRepository repository;
  final String requestReference;
  final PassengerRideRequestRecord? initialRecord;
  final PassengerTripLifecycleRepository? tripRepository;
  final Duration pollInterval;

  /// Current time; injectable so scheduled rides can be tested.
  final DateTime Function()? clock;
  final PassengerPaymentRatingRepository? paymentRatingRepository;
  final PassengerTrustedContactRepository? trustedContactRepository;
  final PassengerSafetyUriLauncher safetyUriLauncher;
  final PassengerSafetyShareGateway safetyShareGateway;
  final PassengerCancellationGateway? cancellationGateway;
  final String? phoneNumber;
  final PassengerMobileMoneyNetwork initialPaymentNetwork;
  final VoidCallback? onSignInRequired;

  /// Opens a new booking pre-filled from a request staff could not accept.
  /// When null, "Book again" just closes this screen.
  final ValueChanged<PassengerRideRequestRecord>? onBookAgain;

  /// Pre-fills the support form's name field.
  final String? passengerName;
  final PassengerSupportMessageSubmitter? supportMessageSubmitter;

  /// Right after a booking: true when the sign-in ends soon, shown as a
  /// banner with "Sign in again". The booking never waits for it.
  final Future<bool>? signInEndsSoon;

  @override
  State<RideTrackingScreen> createState() => _RideTrackingScreenState();
}

class _RideTrackingScreenState extends State<RideTrackingScreen> {
  Timer? _timer;
  PassengerRideRequestRecord? _record;
  String? _tripReference;
  bool _tripTerminal = false;
  bool _loading = true;
  bool _offline = false;
  bool _reconnecting = false;
  double _bottomSheetHeight = 0;
  bool _cancelling = false;
  bool _signInEndsSoonShown = false;

  /// "Still cancelling — the connection is slow."
  bool _cancelSlow = false;
  Timer? _cancelSlowTimer;

  /// A cancel whose answer never came. "Try cancelling again" sends it
  /// again with the same key and reason, so one that did land answers as
  /// a duplicate.
  _PendingCancellation? _unconfirmedCancel;

  /// Each load takes the next number; an answer older than the newest one
  /// shown is dropped, so overlapping loads never step back.
  int _loadsStarted = 0;
  int _newestShown = 0;

  /// This screen in the app's list of open tracking screens.
  PassengerTrackingScreens? _screens;
  PassengerOpenTrackingScreen? _registration;
  String? _registeredReference;

  @override
  void initState() {
    super.initState();
    _record = widget.initialRecord;
    _load();
    widget.signInEndsSoon?.then((soon) {
      if (soon && mounted) {
        setState(() => _signInEndsSoonShown = true);
      }
    }, onError: (Object _) {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _register();
  }

  void _register() {
    final screens = PassengerTrackingScope.maybeOf(context);
    final reference = widget.requestReference;
    if (identical(screens, _screens) && reference == _registeredReference) {
      return;
    }
    _unregister();
    if (screens == null) {
      return;
    }
    final registration = PassengerOpenTrackingScreen(
      route: ModalRoute.of(context),
      refresh: () {
        if (mounted) {
          _refreshNow();
        }
      },
    );
    screens.register(reference, registration);
    _screens = screens;
    _registration = registration;
    _registeredReference = reference;
  }

  void _unregister() {
    final screens = _screens;
    final registration = _registration;
    final reference = _registeredReference;
    if (screens != null && registration != null && reference != null) {
      screens.unregister(reference, registration);
    }
    _screens = null;
    _registration = null;
    _registeredReference = null;
  }

  @override
  void didUpdateWidget(covariant RideTrackingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    final requestChanged =
        oldWidget.repository != widget.repository ||
        oldWidget.requestReference != widget.requestReference;

    if (requestChanged) {
      _register();
      _timer?.cancel();
      _record = widget.initialRecord;
      _tripReference = null;
      _tripTerminal = false;
      _loading = true;
      _offline = false;
      _reconnecting = false;
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
    _unregister();
    _timer?.cancel();
    _cancelSlowTimer?.cancel();
    super.dispose();
  }

  PassengerTripLifecycleRepository? get _resolvedTripRepository {
    final explicitRepository = widget.tripRepository;
    if (explicitRepository != null) {
      return explicitRepository;
    }

    final requestRepository = widget.repository;
    return requestRepository is PassengerTripLifecycleRepository
        ? requestRepository as PassengerTripLifecycleRepository
        : null;
  }

  Future<void> _load() async {
    final load = _loadsStarted += 1;
    bool stale() => load < _newestShown;
    try {
      final activeTripReference = _tripReference;
      if (activeTripReference != null) {
        final tripRepository = _resolvedTripRepository;
        if (tripRepository == null) {
          throw const PassengerRideRequestHistoryException.unknown();
        }

        final trip = await tripRepository.fetchTrip(activeTripReference);
        if (!mounted || stale()) return;
        _newestShown = load;

        final requestRecord = _record;
        if (requestRecord == null) {
          throw const PassengerRideRequestHistoryException.unknown();
        }

        final record = requestRecord.withTrip(trip);
        setState(() {
          _record = record;
          _tripTerminal = trip.isTerminal;
          _loading = false;
          _offline = false;
          _reconnecting = false;
        });
        _schedule(record);
        return;
      }

      final requestRecord = await widget.repository.fetchRequest(
        widget.requestReference,
      );
      if (!mounted || stale()) return;

      final tripReference =
          requestRecord.status.trim().toLowerCase() == 'converted'
          ? requestRecord.normalizedTripReference
          : null;
      final tripRepository = _resolvedTripRepository;

      if (tripReference != null && tripRepository != null) {
        _record = requestRecord;
        _tripReference = tripReference;
        final trip = await tripRepository.fetchTrip(tripReference);
        if (!mounted || stale()) return;
        _newestShown = load;

        final record = requestRecord.withTrip(trip);
        setState(() {
          _record = record;
          _tripTerminal = trip.isTerminal;
          _loading = false;
          _offline = false;
          _reconnecting = false;
        });
        _schedule(record);
        return;
      }

      _newestShown = load;
      setState(() {
        _record = requestRecord;
        _tripReference = null;
        _tripTerminal = false;
        _loading = false;
        _offline = false;
        _reconnecting = false;
      });
      _schedule(requestRecord);
    } on Object catch (error) {
      if (!mounted || stale()) return;

      // The server ended the session (the refresh was refused): that is
      // not a connection problem. Send the passenger to sign in; polling
      // stops, as the next poll is only scheduled after a load.
      final signIn = widget.onSignInRequired;
      if (signIn != null &&
          error is PassengerRideRequestHistoryException &&
          error.requiresSignIn) {
        signIn();
        return;
      }

      final record = _record;
      if (record != null && !_reconnecting) {
        setState(() {
          _loading = false;
          _offline = false;
          _reconnecting = true;
        });
        _schedule(record);
        return;
      }

      setState(() {
        _loading = false;
        _offline = true;
        _reconnecting = false;
      });
    }
  }

  /// A push for this trip: the next poll, now. The screen stays as it is
  /// until the answer comes.
  void _refreshNow() {
    _timer?.cancel();
    _load();
  }

  void _manualRetry() {
    _timer?.cancel();
    setState(() {
      _reconnecting = false;
      _offline = false;
      _loading = _record == null;
    });
    _load();
  }

  void _schedule(PassengerRideRequestRecord record) {
    _timer?.cancel();
    final terminal = _tripReference == null ? record.isTerminal : _tripTerminal;
    if (terminal) return;
    _timer = Timer(widget.pollInterval, _load);
  }

  PassengerTripSafetySummary _buildSafetySummary(
    PassengerRideRequestRecord record,
  ) {
    return PassengerTripSafetySummary(
      tripReference: record.normalizedTripReference,
      tripStatus: record.status,
      driverFirstName: _driverFirstName(record.shownDriverName),
      vehicleType: record.shownVehicleType,
      vehicleColour: record.shownVehicleColour,
      plate: record.shownPlateNumber,
      pickup: record.pickupLocation,
      destination: record.destination,
    );
  }

  Future<void> _openEmergency191() async {
    final canLaunch = await widget.safetyUriLauncher.canLaunch(
      passengerEmergency191Uri,
    );

    if (!canLaunch) {
      return;
    }

    await widget.safetyUriLauncher.launch(passengerEmergency191Uri);
  }

  Future<void> _shareTripSafety() async {
    final record = _record;

    if (record == null) {
      return;
    }

    await widget.safetyShareGateway.shareText(
      _buildSafetySummary(record).build(),
    );
  }

  Future<void> _showShareTripChoices() async {
    if (_record == null) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          key: const Key('tracking-safety-share-choice-surface'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                key: const Key('tracking-safety-message-contact'),
                enabled: widget.trustedContactRepository != null,
                leading: const Icon(Icons.sms_outlined),
                title: const Text('Message trusted contact'),
                onTap: widget.trustedContactRepository == null
                    ? null
                    : () async {
                        Navigator.of(sheetContext).pop();
                        await _messageTrustedContact();
                      },
              ),
              ListTile(
                key: const Key('tracking-safety-share-another-way'),
                leading: const Icon(Icons.share_outlined),
                title: const Text('Share another way'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _shareTripSafety();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _messageTrustedContact() async {
    final repository = widget.trustedContactRepository;

    if (repository == null) {
      return;
    }

    final record = _record;

    if (record == null) {
      return;
    }

    final contact = await repository.fetch();

    if (!contact.isConfigured) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Add a trusted contact in Safety & emergency settings to send this trip by message.',
            ),
          ),
        );
      return;
    }

    final uri = buildTrustedContactSmsUri(
      phone: contact.phone,
      summary: _buildSafetySummary(record).build(),
    );

    final canLaunch = await widget.safetyUriLauncher.canLaunch(uri);

    if (!canLaunch) {
      return;
    }

    await widget.safetyUriLauncher.launch(uri);
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

  Future<void> _openCancelFlow({required bool vehicleEnRoute}) async {
    final gateway = widget.cancellationGateway;
    final record = _record;
    if (gateway == null || record == null || _cancelling) {
      return;
    }

    final selection = await showModalBottomSheet<_PassengerCancellationSelection>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _PassengerCancellationReasonSheet(
        vehicleEnRoute: vehicleEnRoute,
        includeFareReason: record.hasFare,
      ),
    );

    if (selection == null || !mounted) {
      return;
    }

    String? tripReference;
    if (record.tripCreated) {
      tripReference = _tripReference ?? record.normalizedTripReference;
      if (tripReference == null) {
        _showCancellationError(const PassengerCancellationException.unknown());
        return;
      }
    }

    await _submitCancellation(
      gateway: gateway,
      attempt: _PendingCancellation(
        selection: selection,
        idempotencyKey: PassengerRideRequestIdempotencyKey.generate(),
        tripReference: tripReference,
      ),
    );
  }

  void _retryCancellation() {
    final gateway = widget.cancellationGateway;
    final attempt = _unconfirmedCancel;
    if (gateway == null || attempt == null || _cancelling) {
      return;
    }
    unawaited(_submitCancellation(gateway: gateway, attempt: attempt));
  }

  Future<void> _submitCancellation({
    required PassengerCancellationGateway gateway,
    required _PendingCancellation attempt,
  }) async {
    // No polls while the cancel is out, and the answer of a reload already
    // running is dropped: it was read before the cancel.
    _timer?.cancel();
    _dropLoadsInFlight();
    _cancelSlowTimer?.cancel();
    _cancelSlowTimer = Timer(passengerCancelSlowAfter, () {
      if (mounted && _cancelling) {
        setState(() => _cancelSlow = true);
      }
    });
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    setState(() {
      _cancelling = true;
      _cancelSlow = false;
    });

    final PassengerCancellationResult result;
    try {
      final tripReference = attempt.tripReference;
      result = tripReference != null
          ? await gateway.cancelTripBooking(
              tripReference: tripReference,
              reason: attempt.selection.reason,
              reasonNote: attempt.selection.reasonNote,
              idempotencyKey: attempt.idempotencyKey,
            )
          : await gateway.cancelRideRequest(
              requestReference: widget.requestReference,
              reason: attempt.selection.reason,
              reasonNote: attempt.selection.reasonNote,
              idempotencyKey: attempt.idempotencyKey,
            );
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      await _cancellationFailed(
        attempt,
        error is PassengerCancellationException
            ? error
            : const PassengerCancellationException.unknown(),
      );
      return;
    }

    if (!mounted) {
      return;
    }
    _cancellationAnswered(attempt, result);
  }

  /// The cancel's own answer shows the card at once, without waiting for a
  /// reload. Any other status: reload, and show what the server says.
  void _cancellationAnswered(
    _PendingCancellation attempt,
    PassengerCancellationResult result,
  ) {
    final tripReference = attempt.tripReference;
    final cancelledStatus = tripReference != null
        ? 'cancelled_by_passenger'
        : 'cancelled';
    final record = _record;
    if (record == null ||
        result.status.trim().toLowerCase() != cancelledStatus) {
      unawaited(_reloadThenStopCancelling());
      return;
    }

    // Anything still loading was read before this answer.
    _dropLoadsInFlight();
    final cancelled = tripReference != null
        ? record.withTrip(
            PassengerTripRecord(
              tripReference: tripReference,
              status: result.status,
            ),
          )
        : record.withStatus(result.status);
    _cancelSlowTimer?.cancel();
    setState(() {
      _record = cancelled;
      if (tripReference != null) {
        _tripReference = tripReference;
        _tripTerminal = true;
      }
      _cancelling = false;
      _cancelSlow = false;
      _unconfirmedCancel = null;
      _loading = false;
      _offline = false;
      _reconnecting = false;
    });
    // One load to confirm it, with the server's own wording.
    unawaited(_load());
  }

  Future<void> _cancellationFailed(
    _PendingCancellation attempt,
    PassengerCancellationException error,
  ) async {
    switch (error.type) {
      case PassengerCancellationFailureType.temporarilyUnavailable:
      case PassengerCancellationFailureType.badResponse:
        // The cancel may have landed: the reload decides. A trip that has
        // ended any way (cancelled, dispatch cancelled, completed) shows its
        // own card, with nothing to try again.
        await _reloadThenStopCancelling();
        if (!mounted) {
          return;
        }
        if (_showsEnded) {
          setState(() => _unconfirmedCancel = null);
          return;
        }
        setState(() => _unconfirmedCancel = attempt);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              key: Key('cancel-unconfirmed-snackbar'),
              content: Text(
                "We couldn't confirm the cancel. Check your connection and "
                'try again.',
              ),
            ),
          );
      case PassengerCancellationFailureType.notEligible:
      case PassengerCancellationFailureType.conflict:
        // The trip has moved on: show where it is first, then the reason,
        // unless it has already ended (a dispatch cancel says it all).
        await _reloadThenStopCancelling();
        if (!mounted) {
          return;
        }
        setState(() => _unconfirmedCancel = null);
        if (!_showsEnded) {
          _showCancellationError(error);
        }
      case PassengerCancellationFailureType.signInRequired:
      case PassengerCancellationFailureType.passengerRequired:
      case PassengerCancellationFailureType.clientFailure:
        _cancelSlowTimer?.cancel();
        setState(() {
          _cancelling = false;
          _cancelSlow = false;
          _unconfirmedCancel = null;
        });
        final record = _record;
        if (record != null) {
          _schedule(record);
        }
        _showCancellationError(error);
    }
  }

  /// Every load started so far is now older than what is shown.
  void _dropLoadsInFlight() => _newestShown = _loadsStarted + 1;

  Future<void> _reloadThenStopCancelling() async {
    await _load();
    if (!mounted) {
      return;
    }
    _cancelSlowTimer?.cancel();
    setState(() {
      _cancelling = false;
      _cancelSlow = false;
    });
  }

  bool get _showsEnded {
    final record = _record;
    if (record == null) {
      return false;
    }
    return _tripReference == null ? record.isTerminal : _tripTerminal;
  }

  void _showCancellationError(PassengerCancellationException error) {
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();

    if (error.isNotEligible) {
      messenger.showSnackBar(
        SnackBar(
          key: const Key('cancel-not-eligible-snackbar'),
          content: Text(error.message),
          action: SnackBarAction(
            label: 'Contact support',
            onPressed: () {},
          ),
        ),
      );
      return;
    }

    messenger.showSnackBar(
      SnackBar(key: const Key('cancel-error-snackbar'), content: Text(error.message)),
    );
  }

  /// A request staff rejected, or a cancelled trip, is final, so booking
  /// again cannot duplicate it.
  void _bookAgain(PassengerRideRequestRecord record) {
    final navigator = Navigator.of(context);
    // Close this screen first, synchronously, so the new booking opens in
    // its place and backing out of it does not return here.
    if (navigator.canPop()) {
      navigator.pop();
    }
    widget.onBookAgain?.call(record);
  }

  void _contactSupport(PassengerRideRequestRecord record) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => NewMessageForm(
          initialPassengerName: widget.passengerName,
          initialMessage:
              'About my ride request ${record.requestReference}, which '
              'could not be accepted: ',
          tripHistoryRepository: widget.repository,
          submitter:
              widget.supportMessageSubmitter ??
              ApiPassengerSupportMessageSubmitter.withDefaultClient(
                baseUrl: AsmApiClient.defaultBaseUrl,
              ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screen = _buildScreen(context);
    if (!_signInEndsSoonShown) {
      return screen;
    }
    // Above every state of the screen (loading, offline, refused, the map).
    return Material(
      color: AsmColors.passengerSurface,
      child: Column(
        children: [
          SafeArea(
            bottom: false,
            child: _SignInEndsSoonBanner(
              onSignIn: widget.onSignInRequired == null
                  ? null
                  : _confirmSignInAgain,
              onClose: () => setState(() => _signInEndsSoonShown = false),
            ),
          ),
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: screen,
            ),
          ),
        ],
      ),
    );
  }

  /// Signing in again first clears this phone's sign-in, with the ride
  /// booked, so it asks once.
  Future<void> _confirmSignInAgain() async {
    final signIn = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: const Text(passengerSignInAgainDuringRideMessage),
        actions: [
          TextButton(
            key: const Key('tracking-sign-in-again-stay'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Stay signed in'),
          ),
          FilledButton(
            key: const Key('tracking-sign-in-again-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Sign in again'),
          ),
        ],
      ),
    );
    if (signIn == true && mounted) {
      widget.onSignInRequired?.call();
    }
  }

  Widget _buildScreen(BuildContext context) {
    if (_loading && _record == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_offline && _record == null) {
      return Scaffold(body: _OfflineState(onRetry: _manualRetry));
    }

    final record = _record!;
    final theme = Theme.of(context);
    final driverFirstName = _driverFirstName(record.shownDriverName);
    final vehicleInfo = _vehicleInfo(
      record.shownVehicleColour,
      record.shownVehicleType,
    );
    final plateNumber = record.shownPlateNumber;
    final pickupCode = record.shownPickupVerificationCode;
    final driverDistanceKm = record.driverDistanceKm;
    // "converted" is the RideRequest's own placeholder status - it means
    // "this has a linked Trip now, look there for the real status," never
    // a real, displayable state on its own. It has no case in
    // PassengerRideState.fromStatus and would otherwise fall through to
    // "looking for a driver" - a confidently wrong answer for what's
    // actually just a not-yet-resolved fetch (the list screen enriches
    // this before handing off an initialRecord, but a push notification
    // can open this screen from just a request reference, and any single
    // trip fetch - initial or a later poll - can fail-soft and leave this
    // record's status exactly as "converted"). Substituting a neutral
    // view here, rather than short-circuiting build() entirely, keeps the
    // reconnecting/offline banners and safety actions working normally
    // while this resolves.
    final now = (widget.clock ?? DateTime.now)();
    final scheduledPickup = scheduledPickupAwaitingDriver(record, now);
    final pickupTime = record.requestedPickupTime;
    final baseView = record.status.trim().toLowerCase() == 'converted'
        ? _TrackingView.checkingStatus()
        : _TrackingView.from(record);
    final view = scheduledPickup != null
        ? _TrackingView.scheduled(scheduledPickup)
        // Accepted ahead of a scheduled pickup: not "on the way" yet.
        : pickupTime != null &&
              pickupTime.isAfter(now) &&
              record.status.trim().toLowerCase() == 'driver_accepted'
        ? baseView.confirmedFor(pickupTime)
        : baseView;
    final heading =
        scheduledPickup == null &&
            record.status.trim().toLowerCase() == 'under_review'
        ? 'Reviewing your request'
        : view.title;

    if (view.rejected) {
      return Scaffold(
        appBar: AppBar(title: const Text('Ride request')),
        body: PassengerNoVehiclesAvailableState(
          onRetry: () => _bookAgain(record),
          onContactSupport: () => _contactSupport(record),
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: AsmPassengerMap(
              center: view.vehicle ?? accraHomeCenter,
              // Ride data has no pickup or destination coordinates or road
              // route yet, so only the vehicle is shown.
              vehicle: view.vehicle,
              // Keeps the Google logo and the camera target above the sheet.
              padding: EdgeInsets.only(bottom: _bottomSheetHeight),
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
          if (_reconnecting)
            Positioned(
              top: 96,
              left: 16,
              right: 16,
              child: Material(
                key: const Key('tracking-reconnecting-banner'),
                borderRadius: BorderRadius.circular(14),
                color: const Color(0xFFFFF3E0),
                child: const ListTile(
                  leading: Icon(Icons.sync_outlined),
                  title: Text('Reconnecting…'),
                  subtitle: Text('Showing the last safe update.'),
                ),
              ),
            )
          else if (_offline)
            Positioned(
              top: 96,
              left: 16,
              right: 16,
              child: Material(
                key: const Key('tracking-connection-interrupted-banner'),
                borderRadius: BorderRadius.circular(14),
                color: const Color(0xFFFFF3E0),
                child: ListTile(
                  leading: const Icon(Icons.cloud_off_outlined),
                  title: const Text('Connection interrupted'),
                  subtitle: const Text('Showing the last safe update.'),
                  trailing: TextButton(
                    key: const Key('tracking-connection-retry'),
                    onPressed: _manualRetry,
                    child: const Text('Retry'),
                  ),
                ),
              ),
            ),
          Align(
            alignment: Alignment.bottomCenter,
            child: MeasuredHeight(
              key: const Key('tracking-bottom-sheet'),
              onHeight: (height) {
                if (mounted && height != _bottomSheetHeight) {
                  setState(() => _bottomSheetHeight = height);
                }
              },
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
                      heading,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(view.message),
                    if (driverFirstName != null ||
                        vehicleInfo != null ||
                        plateNumber != null ||
                        pickupCode != null) ...[
                      const SizedBox(height: AsmSpacing.space16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          if (driverFirstName != null) ...[
                            CircleAvatar(
                              key: const Key('tracking-driver-avatar'),
                              radius: 32,
                              backgroundColor: AsmColors.brandDeepGreen,
                              child: Text(
                                driverFirstName.substring(0, 1).toUpperCase(),
                                key: const Key('tracking-driver-avatar-initial'),
                                style: const TextStyle(
                                  color: AsmColors.brandWhite,
                                  fontSize: 25,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            const SizedBox(width: AsmSpacing.space16),
                          ],
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (driverFirstName != null)
                                  Text(
                                    driverFirstName,
                                    key: const Key('tracking-driver-first-name'),
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                if (driverFirstName != null &&
                                    vehicleInfo != null)
                                  const SizedBox(height: AsmSpacing.space4),
                                if (vehicleInfo != null)
                                  Text(
                                    vehicleInfo,
                                    key: const Key('tracking-vehicle-info'),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                if (plateNumber != null) ...[
                                  if (driverFirstName != null ||
                                      vehicleInfo != null)
                                    const SizedBox(height: AsmSpacing.space12),
                                  Container(
                                    key: const Key('tracking-plate-badge'),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: AsmSpacing.space12,
                                      vertical: AsmSpacing.space8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AsmColors.passengerSurface,
                                      borderRadius: BorderRadius.circular(
                                        AsmRadii.radius16,
                                      ),
                                      border: Border.all(
                                        color: AsmColors.passengerLine,
                                      ),
                                    ),
                                    child: Text(
                                      plateNumber,
                                      key: const Key(
                                        'tracking-safe-plate-number',
                                      ),
                                      style: const TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ],
                                if (pickupCode != null) ...[
                                  const SizedBox(height: AsmSpacing.space12),
                                  Container(
                                    key: const Key(
                                      'tracking-pickup-verification-code-badge',
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: AsmSpacing.space12,
                                      vertical: AsmSpacing.space8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AsmColors.passengerSurface,
                                      borderRadius: BorderRadius.circular(
                                        AsmRadii.radius16,
                                      ),
                                      border: Border.all(
                                        color: AsmColors.passengerLine,
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          'Pickup code',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                color: theme
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                        Text(
                                          pickupCode,
                                          key: const Key(
                                            'tracking-pickup-verification-code',
                                          ),
                                          style: const TextStyle(
                                            fontSize: 24,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: 4,
                                          ),
                                        ),
                                        Text(
                                          'Share this with your driver to start the trip.',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                color: theme
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: AsmSpacing.space16),

                    Container(
                      key: const Key('tracking-safety-card'),
                      width: double.infinity,
                      padding: const EdgeInsets.all(AsmSpacing.space16),
                      decoration: BoxDecoration(
                        color: AsmColors.passengerCard,
                        borderRadius: BorderRadius.circular(AsmRadii.radius20),
                        border: Border.all(color: AsmColors.passengerLine),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Safety',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: AsmSpacing.space12),
                          OutlinedButton.icon(
                            key: const Key('tracking-safety-emergency'),
                            onPressed: _openEmergency191,
                            icon: const Icon(Icons.emergency_outlined),
                            label: const Text('Emergency 191'),
                          ),
                          const SizedBox(height: AsmSpacing.space8),
                          OutlinedButton.icon(
                            key: const Key('tracking-safety-share'),
                            onPressed: _showShareTripChoices,
                            icon: const Icon(Icons.share_outlined),
                            label: const Text('Share trip'),
                          ),
                        ],
                      ),
                    ),

                    if (driverDistanceKm != null) ...[
                      const SizedBox(height: AsmSpacing.space12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.location_on_outlined,
                            key: Key('tracking-driver-distance-icon'),
                            color: AsmColors.brandDeepGreen,
                          ),
                          const SizedBox(width: AsmSpacing.space8),
                          Expanded(
                            child: Text(
                              'Driver is approximately ${driverDistanceKm.toStringAsFixed(1)} km away',
                              key: const Key('tracking-driver-distance'),
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
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
                    if (record.passengerState ==
                        PassengerRideState.cancelledByOperations) ...[
                      const SizedBox(height: 18),
                      FilledButton(
                        key: const Key('cancelled-by-operations-book-again'),
                        onPressed: () => _bookAgain(record),
                        child: const Text('Book again'),
                      ),
                    ] else if (record.passengerState ==
                        PassengerRideState.cancelledByPassenger) ...[
                      const SizedBox(height: 18),
                      FilledButton(
                        key: const Key('cancelled-by-passenger-book-again'),
                        onPressed: () => _bookAgain(record),
                        child: const Text('Book again'),
                      ),
                    ] else if (widget.cancellationGateway != null &&
                        passengerCanCancelTrip(
                          tripCreated: record.tripCreated,
                          rawStatus: record.status,
                        )) ...[
                      const SizedBox(height: 18),
                      OutlinedButton.icon(
                        key: const Key('open-cancel-confirmation'),
                        onPressed: _cancelling
                            ? null
                            : _unconfirmedCancel != null
                            ? _retryCancellation
                            : () => _openCancelFlow(
                                vehicleEnRoute: view.vehicleEnRoute,
                              ),
                        icon: _cancelling
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.close),
                        label: Text(
                          _cancelling
                              ? 'Cancelling…'
                              : _unconfirmedCancel != null
                              ? 'Try cancelling again'
                              : 'Cancel request',
                        ),
                      ),
                      if (_cancelSlow) ...[
                        const SizedBox(height: 8),
                        const Text(
                          'Still cancelling — the connection is slow.',
                          key: Key('cancel-slow-note'),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String? _driverFirstName(String? value) {
  final normalized = value?.trim();
  if (normalized == null || normalized.isEmpty) {
    return null;
  }

  return normalized.split(RegExp(r'\s+')).first;
}

String? _vehicleInfo(String? colour, String? type) {
  final normalizedColour = colour?.trim();
  final normalizedType = type?.trim();

  final parts = <String>[
    if (normalizedColour != null && normalizedColour.isNotEmpty)
      normalizedColour,
    if (normalizedType != null && normalizedType.isNotEmpty) normalizedType,
  ];

  return parts.isEmpty ? null : parts.join(' · ');
}

/// Shown when staff could not accept a ride request (a final outcome).
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
                  "We couldn't accept this ride request",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    height: 1.15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: AsmSpacing.space12),
                const Text(
                  "You can book again, or contact support if you'd like to "
                  'know more.',
                  textAlign: TextAlign.center,
                  style: TextStyle(height: 1.45),
                ),
                const SizedBox(height: AsmSpacing.space24),
                FilledButton.icon(
                  key: const Key('rejected-book-again'),
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Book again'),
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
    this.vehicle,
    this.vehicleEnRoute = false,
    this.reassigned = false,
    this.rejected = false,
  });

  final String key;
  final String title;
  final String message;
  final IconData icon;
  final Color color;
  final LatLng? vehicle;
  final bool vehicleEnRoute;
  final bool reassigned;
  final bool rejected;

  /// Booked for later; no driver is sought until an hour before pickup.
  factory _TrackingView.scheduled(DateTime pickup) {
    return _TrackingView(
      key: 'ride-scheduled-state',
      title: 'Ride scheduled',
      message:
          'Booked for ${formatScheduledPickup(pickup)}. We\'ll find you a '
          'driver about an hour before pickup and notify you when one '
          'accepts.',
      icon: Icons.event_available_outlined,
      color: AsmColors.brandDeepGreen,
    );
  }

  /// A driver took a scheduled ride ahead of its pickup time.
  _TrackingView confirmedFor(DateTime pickup) {
    final clock = formatScheduledPickupClock(pickup);
    return _TrackingView(
      key: key,
      title: 'Driver confirmed for $clock',
      message: 'Your driver will meet you at the pickup at $clock.',
      icon: icon,
      color: color,
      vehicle: vehicle,
      vehicleEnRoute: vehicleEnRoute,
      reassigned: reassigned,
      rejected: rejected,
    );
  }

  factory _TrackingView.checkingStatus() {
    return const _TrackingView(
      key: 'checking-trip-status-state',
      title: 'Checking your trip',
      message: 'We are confirming your trip\'s current status.',
      icon: Icons.hourglass_top_outlined,
      color: Color(0xFF6B7280),
    );
  }

  factory _TrackingView.from(PassengerRideRequestRecord record) {
    final status = record.passengerState;
    final message = record.safeMessage;
    final vehicle = record.vehiclePosition;

    switch (status) {
      case PassengerRideState.driverAssigned:
        return _TrackingView(
          key: 'driver-assigned-state',
          title: 'Driver assigned',
          message: message,
          icon: Icons.person_pin_circle,
          color: AsmColors.brandDeepGreen,
          vehicle: vehicle,
        );

      case PassengerRideState.vehicleEnRoute:
        return _TrackingView(
          key: 'vehicle-en-route-state',
          title: 'Your vehicle is on the way',
          message: message,
          icon: Icons.electric_car,
          color: AsmColors.brandDeepGreen,
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
          vehicle: vehicle,
        );

      case PassengerRideState.arrived:
        return _TrackingView(
          key: 'arrived-at-destination-state',
          title: 'You’ve arrived',
          message: message,
          icon: Icons.check_circle,
          color: AsmColors.brandDeepGreen,
          vehicle: vehicle,
        );

      case PassengerRideState.reassigned:
        return _TrackingView(
          key: 'vehicle-reassigned-state',
          title: 'New vehicle assigned',
          message: message,
          icon: Icons.swap_horiz,
          color: AsmColors.brandDeepGreen,
          vehicle: vehicle,
          vehicleEnRoute: true,
          reassigned: true,
        );

      case PassengerRideState.cancelledByOperations:
        return _TrackingView(
          key: 'trip-cancelled-state',
          title: 'Trip cancelled',
          message: message,
          icon: Icons.cancel_outlined,
          color: Colors.redAccent,
        );

      case PassengerRideState.cancelledByPassenger:
        return _TrackingView(
          key: 'trip-cancelled-by-passenger-state',
          title: 'Trip cancelled',
          message: message,
          icon: Icons.cancel_outlined,
          color: Colors.redAccent,
        );

      case PassengerRideState.rejected:
        return _TrackingView(
          key: 'request-rejected-state',
          title: 'No vehicles available right now',
          message: message,
          icon: Icons.no_transfer_outlined,
          color: Colors.redAccent,
          rejected: true,
        );

      case PassengerRideState.looking:
        return _TrackingView(
          key: 'looking-for-driver-state',
          title: 'Looking for a driver',
          message: message,
          icon: Icons.radar,
          color: const Color(0xFFC8971F),
        );
    }
  }
}

final class _PendingCancellation {
  const _PendingCancellation({
    required this.selection,
    required this.idempotencyKey,
    required this.tripReference,
  });

  final _PassengerCancellationSelection selection;
  final String idempotencyKey;

  /// Null for a request with no trip yet.
  final String? tripReference;
}

final class _PassengerCancellationSelection {
  const _PassengerCancellationSelection({required this.reason, this.reasonNote});

  final PassengerCancellationReason reason;
  final String? reasonNote;
}

class _PassengerCancellationReasonSheet extends StatefulWidget {
  const _PassengerCancellationReasonSheet({
    required this.vehicleEnRoute,
    required this.includeFareReason,
  });

  final bool vehicleEnRoute;
  final bool includeFareReason;

  @override
  State<_PassengerCancellationReasonSheet> createState() =>
      _PassengerCancellationReasonSheetState();
}

class _PassengerCancellationReasonSheetState
    extends State<_PassengerCancellationReasonSheet> {
  PassengerCancellationReason? _selected;
  final _noteController = TextEditingController();

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  bool get _canConfirm {
    final selected = _selected;
    if (selected == null) {
      return false;
    }
    return !selected.requiresNote || _noteController.text.trim().isNotEmpty;
  }

  List<PassengerCancellationReason> get _availableReasons {
    return PassengerCancellationReason.values
        .where(
          (reason) =>
              widget.includeFareReason ||
              reason != PassengerCancellationReason.priceOrFareConcern,
        )
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    // Built with SingleChildScrollView from the start: the driver-app
    // decline sheet shipped without one and overflowed under the
    // on-screen keyboard on a real device (RenderFlex overflow when
    // typing the "other" note). Same interaction shape here (radio list
    // + conditional note field), so the same fix applies preemptively.
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          child: Column(
            key: const Key('passenger-cancel-reason-sheet'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Why are you cancelling?',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              const Text(
                'This helps us improve. It does not affect other passengers.',
                style: TextStyle(color: Colors.black54),
              ),
              if (widget.vehicleEnRoute) ...[
                const SizedBox(height: 12),
                Container(
                  key: const Key('cancel-vehicle-en-route-notice'),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Your driver is already on the way.',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              for (final reason in _availableReasons)
                RadioListTile<PassengerCancellationReason>(
                  key: Key('passenger-cancel-reason-option-${reason.code}'),
                  contentPadding: EdgeInsets.zero,
                  value: reason,
                  groupValue: _selected,
                  onChanged: (value) {
                    setState(() {
                      _selected = value;
                    });
                  },
                  title: Text(reason.label),
                ),
              if (_selected?.requiresNote == true) ...[
                const SizedBox(height: 8),
                TextField(
                  key: const Key('passenger-cancel-reason-other-note'),
                  controller: _noteController,
                  maxLength: passengerCancellationReasonNoteLimit,
                  maxLines: 3,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: 'Tell us what happened',
                  ),
                ),
              ],
              const SizedBox(height: 12),
              FilledButton(
                key: const Key('passenger-cancel-reason-confirm'),
                onPressed: _canConfirm
                    ? () {
                        final reason = _selected!;
                        final note = _noteController.text.trim();
                        Navigator.of(context).pop(
                          _PassengerCancellationSelection(
                            reason: reason,
                            reasonNote: note.isEmpty ? null : note,
                          ),
                        );
                      }
                    : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                child: const Text('Confirm cancellation'),
              ),
              const SizedBox(height: 8),
              TextButton(
                key: const Key('passenger-cancel-reason-cancel'),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Never mind'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown before "Sign in again" on the trip screen. The phone can still
/// show notifications for the ride, but the app shows nothing of it until
/// the passenger signs in again.
const passengerSignInAgainDuringRideMessage =
    "You won't see updates about this ride in the app until you sign in "
    'again. Your ride stays booked.';

class _SignInEndsSoonBanner extends StatelessWidget {
  const _SignInEndsSoonBanner({required this.onSignIn, required this.onClose});

  final VoidCallback? onSignIn;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        key: const Key('tracking-sign-in-ends-soon'),
        children: [
          const Icon(Icons.lock_clock_outlined),
          const SizedBox(width: AsmSpacing.space12),
          const Expanded(child: Text(authSignInEndsSoonMessage)),
          if (onSignIn != null)
            TextButton(
              key: const Key('tracking-sign-in-again'),
              onPressed: onSignIn,
              child: const Text('Sign in again'),
            ),
          IconButton(
            key: const Key('tracking-sign-in-ends-soon-close'),
            tooltip: 'Close',
            onPressed: onClose,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}
