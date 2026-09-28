import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_app_config/asm_app_config.dart';
import 'package:asm_ride_domain/asm_ride_domain.dart';
import 'package:flutter/material.dart';

import '../account/passenger_payment_setup_screen.dart';
import '../map/osrm_route.dart';
import '../network/passenger_cancellation_gateway.dart';
import '../payment_rating/passenger_payment_rating_contract.dart';
import 'booking_draft.dart';
import 'booking_form.dart';
import 'booking_review.dart';
import 'booking_submission.dart';
import 'passenger_fare_estimate.dart';
import 'scheduled_pickup.dart';
import '../ride_requests/ride_request_history.dart';
import '../safety/passenger_trip_safety.dart';

import '../tracking/ride_tracking_screen.dart';

class BookingPage extends StatefulWidget {
  const BookingPage({
    required this.market,
    this.initialPickupDescription = '',
    this.initialPickupLatitude,
    this.initialPickupLongitude,
    this.initialDestinationDescription = '',
    this.rideRequestSubmitter,
    this.idempotencyKeyFactory,
    this.onSignInRequired,
    this.requestNotificationPermission,
    this.rideRequestHistoryRepository,
    this.paymentRatingRepository,
    this.fareEstimateRepository,
    this.trustedContactRepository,
    this.cancellationGateway,
    this.phoneNumber,
    this.initialPaymentNetwork = PassengerMobileMoneyNetwork.mtn,
    this.routeService = const OsrmPassengerRouteService(),
    this.clock,
    this.passengerName,
    this.showFareEstimate = false,
    super.key,
  });

  final MarketConfig market;
  final String initialPickupDescription;
  final double? initialPickupLatitude;
  final double? initialPickupLongitude;
  final String initialDestinationDescription;
  final PassengerRideRequestSubmitter? rideRequestSubmitter;
  final String Function()? idempotencyKeyFactory;
  final VoidCallback? onSignInRequired;
  final Future<bool> Function()? requestNotificationPermission;
  final PassengerRideRequestHistoryRepository? rideRequestHistoryRepository;
  final PassengerPaymentRatingRepository? paymentRatingRepository;
  final PassengerFareEstimateRepository? fareEstimateRepository;
  final PassengerTrustedContactRepository? trustedContactRepository;
  final PassengerCancellationGateway? cancellationGateway;
  final String? phoneNumber;
  final PassengerMobileMoneyNetwork initialPaymentNetwork;
  final PassengerRouteService routeService;

  /// Current time; injectable so scheduled-ride limits can be tested.
  final DateTime Function()? clock;

  /// Pre-fills support forms opened from the ride this page books.
  final String? passengerName;

  /// Off until destinations have real coordinates: the route behind the
  /// estimate is between two fixed Accra points, so every booking got the
  /// same fare. The review shows a neutral fare line instead.
  final bool showFareEstimate;

  @override
  State<BookingPage> createState() => _BookingPageState();
}

class _BookingPageState extends State<BookingPage> {
  static const _internalServiceContext =
      RideServiceContextCode.otherApprovedRequest;

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _pickupController;
  late final TextEditingController _destinationController;
  final _assistanceController = TextEditingController();
  final _passengerNoteController = TextEditingController();

  int _passengerCount = 1;
  BookingDraft? _draft;
  late final PassengerRideRequestSubmitter _rideRequestSubmitter;
  BookingSubmissionStatus _submissionStatus = BookingSubmissionStatus.idle;
  PassengerRideRequestResult? _submissionResult;
  String? _submissionErrorMessage;
  bool _submissionRequiresSignIn = false;
  String? _idempotencyKey;
  String? _passengerCountErrorMessage;
  PassengerBookingFareEstimate? _fareEstimate;
  int _fareRequestGeneration = 0;

  bool _scheduleForLater = false;
  DateTime? _scheduledDate;
  DateTime? _scheduledPickup;
  String? _pickupTimeErrorMessage;
  String? _pickupErrorCode;

  DateTime _now() => (widget.clock ?? DateTime.now)();

  DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  @override
  void initState() {
    super.initState();
    _pickupController = TextEditingController(
      text: widget.initialPickupDescription,
    );
    _destinationController = TextEditingController(
      text: widget.initialDestinationDescription,
    );
    _rideRequestSubmitter =
        widget.rideRequestSubmitter ??
        ApiPassengerRideRequestSubmitter.withDefaultClient();
  }

  @override
  void dispose() {
    _pickupController.dispose();
    _destinationController.dispose();
    _assistanceController.dispose();
    _passengerNoteController.dispose();
    super.dispose();
  }

  void _reviewDraft() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_passengerCount < 1 || _passengerCount > 6) {
      setState(() {
        _passengerCountErrorMessage =
            'Passenger count must be between 1 and 6.';
      });
      return;
    }

    DateTime? requestedPickupTime;
    if (_scheduleForLater) {
      final pickup = _scheduledPickup;
      final problem = pickup == null
          ? null
          : checkScheduledPickup(pickup, _now());
      final message = pickup == null
          ? PassengerRideRequestSubmissionException.pickupTimeRequiredMessage
          : switch (problem) {
              ScheduledPickupProblem.tooSoon =>
                PassengerRideRequestSubmissionException.pickupTooSoonMessage,
              ScheduledPickupProblem.tooFar =>
                PassengerRideRequestSubmissionException.pickupTooFarMessage,
              null => null,
            };
      if (message != null) {
        setState(() {
          _pickupTimeErrorMessage = message;
          _pickupErrorCode = null;
        });
        return;
      }
      requestedPickupTime = pickup;
    }

    setState(() {
      _pickupTimeErrorMessage = null;
      _pickupErrorCode = null;
      _passengerCountErrorMessage = null;
      _fareRequestGeneration += 1;
      _fareEstimate = null;
      _draft = BookingDraft(
        marketCode: widget.market.marketCode,
        serviceContext: _internalServiceContext,
        pickupDescription: _pickupController.text,
        destinationDescription: _destinationController.text,
        pickupLatitude: widget.initialPickupLatitude,
        pickupLongitude: widget.initialPickupLongitude,
        passengerCount: _passengerCount,
        assistanceNote: _assistanceController.text,
        passengerNote: _passengerNoteController.text,
        requestedPickupTime: requestedPickupTime,
      );
    });
  }

  void _setScheduleForLater(bool value) {
    setState(() {
      _scheduleForLater = value;
      _pickupTimeErrorMessage = null;
      _pickupErrorCode = null;
      if (value) {
        _scheduledDate ??= _dateOnly(earliestScheduledPickup(_now()));
      } else {
        _scheduledDate = null;
        _scheduledPickup = null;
      }
    });
  }

  Future<void> _pickScheduledDate() async {
    final now = _now();
    final firstDate = _dateOnly(earliestScheduledPickup(now));
    final lastDate = _dateOnly(latestScheduledPickup(now));
    final current = _scheduledDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: current == null || current.isBefore(firstDate)
          ? firstDate
          : current,
      firstDate: firstDate,
      lastDate: lastDate,
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      _scheduledDate = _dateOnly(picked);
      final pickup = _scheduledPickup;
      if (pickup != null && _dateOnly(pickup) != _scheduledDate) {
        _scheduledPickup = null;
      }
    });
  }

  Future<void> _pickScheduledTime() async {
    final day = _scheduledDate ?? _dateOnly(earliestScheduledPickup(_now()));
    final slots = scheduledPickupSlotsOn(day, _now());
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: slots.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No pickup times left on this day. Pick another date.',
                ),
              )
            : ListView.builder(
                itemCount: slots.length,
                itemBuilder: (_, index) {
                  final slot = slots[index];
                  final label = formatScheduledPickupClock(slot);
                  return ListTile(
                    key: Key('pickup-slot-$label'),
                    title: Text(label),
                    selected: slot == _scheduledPickup,
                    onTap: () => Navigator.of(sheetContext).pop(slot),
                  );
                },
              ),
      ),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      _scheduledDate = _dateOnly(picked);
      _scheduledPickup = picked;
      _pickupTimeErrorMessage = null;
      _pickupErrorCode = null;
    });
  }

  /// Back to the form with the pickup time flagged, everything else kept.
  void _returnToFormWithPickupError(String message, {String? code}) {
    setState(() {
      _draft = null;
      _submissionStatus = BookingSubmissionStatus.idle;
      _submissionResult = null;
      _submissionErrorMessage = null;
      _submissionRequiresSignIn = false;
      _idempotencyKey = null;
      _fareRequestGeneration += 1;
      _fareEstimate = null;
      _pickupTimeErrorMessage = message;
      _pickupErrorCode = code;
    });
  }

  void _openMyRides() {
    Navigator.of(context).pop(true);
  }

  void _editDraft() {
    setState(() {
      _draft = null;
      _submissionStatus = BookingSubmissionStatus.idle;
      _submissionResult = null;
      _submissionErrorMessage = null;
      _submissionRequiresSignIn = false;
      _idempotencyKey = null;
      _passengerCountErrorMessage = null;
      _fareRequestGeneration += 1;
      _fareEstimate = null;
    });
  }

  void _handleAuthoritativeRouteEstimate(
    PassengerRouteEstimate? routeEstimate,
  ) {
    if (!widget.showFareEstimate) {
      return;
    }

    final generation = ++_fareRequestGeneration;

    if (mounted) {
      setState(() => _fareEstimate = null);
    }

    final repository = widget.fareEstimateRepository;
    if (routeEstimate == null ||
        routeEstimate.usedFallback ||
        repository == null ||
        !routeEstimate.distanceKilometres.isFinite ||
        routeEstimate.distanceKilometres <= 0) {
      return;
    }

    _loadFareEstimate(repository, routeEstimate.distanceKilometres, generation);
  }

  Future<void> _loadFareEstimate(
    PassengerFareEstimateRepository repository,
    double tripKilometres,
    int generation,
  ) async {
    try {
      final estimate = await repository.fetchEstimate(tripKilometres);

      if (!mounted || generation != _fareRequestGeneration) {
        return;
      }

      setState(() => _fareEstimate = estimate);
    } on Object {
      if (!mounted || generation != _fareRequestGeneration) {
        return;
      }

      setState(() => _fareEstimate = null);
    }
  }

  Future<void> _confirmRequest() async {
    final draft = _draft;
    if (draft == null ||
        _submissionStatus == BookingSubmissionStatus.submitting) {
      return;
    }

    // Time passes on the review screen; don't send a pickup that has
    // slipped under the hour.
    final requestedPickupTime = draft.requestedPickupTime;
    if (requestedPickupTime != null &&
        checkScheduledPickup(requestedPickupTime, _now()) != null) {
      _returnToFormWithPickupError(
        PassengerRideRequestSubmissionException.pickupTooSoonMessage,
      );
      return;
    }

    final key =
        _idempotencyKey ??
        (widget.idempotencyKeyFactory ??
            PassengerRideRequestIdempotencyKey.generate)();

    setState(() {
      _idempotencyKey = key;
      _submissionStatus = BookingSubmissionStatus.submitting;
      _submissionResult = null;
      _submissionErrorMessage = null;
      _submissionRequiresSignIn = false;
    });

    try {
      final result = await _rideRequestSubmitter.submit(
        draft,
        idempotencyKey: key,
      );

      if (!mounted) {
        return;
      }

      if (!hasValidPassengerRideRequestReceipt(result)) {
        setState(() {
          _submissionStatus = BookingSubmissionStatus.failure;
          _submissionResult = null;
          _submissionErrorMessage =
              PassengerRideRequestSubmissionException.unknownErrorMessage;
          _submissionRequiresSignIn = false;
        });
        return;
      }

      final echoedPickup = result.requestedPickupTime;
      if (requestedPickupTime != null &&
          (echoedPickup == null ||
              !echoedPickup.isAtSameMomentAs(requestedPickupTime))) {
        // The backend did not record the pickup time: it may have booked
        // this as a ride now. Keep the idempotency key so "Try again"
        // replays this same request instead of creating another.
        setState(() {
          _submissionStatus = BookingSubmissionStatus.failure;
          _submissionResult = null;
          _submissionErrorMessage =
              PassengerRideRequestSubmissionException.pickupNotConfirmedMessage;
          _submissionRequiresSignIn = false;
        });
        return;
      }

      setState(() {
        _submissionStatus = BookingSubmissionStatus.success;
        _submissionResult = result;
        _idempotencyKey = null;
      });

      final requestNotificationPermission =
          widget.requestNotificationPermission;
      if (requestNotificationPermission != null) {
        try {
          await requestNotificationPermission();
        } on Object {
          // Notification permission must never invalidate a booked ride.
        }
      }

      final reference = result.requestReference?.trim();
      final repository = widget.rideRequestHistoryRepository;
      if (reference != null &&
          reference.isNotEmpty &&
          repository != null &&
          mounted) {
        // This page is replaced by the tracking screen, so "Book again"
        // must not depend on this page's context.
        final navigator = Navigator.of(context);
        final page = widget;
        await navigator.pushReplacement<void, void>(
          MaterialPageRoute<void>(
            builder: (_) => RideTrackingScreen(
              repository: repository,
              requestReference: reference,
              paymentRatingRepository: widget.paymentRatingRepository,
              trustedContactRepository: widget.trustedContactRepository,
              cancellationGateway: widget.cancellationGateway,
              phoneNumber: widget.phoneNumber,
              initialPaymentNetwork: widget.initialPaymentNetwork,
              onSignInRequired: widget.onSignInRequired,
              passengerName: widget.passengerName,
              onBookAgain: (record) => navigator.push<bool>(
                MaterialPageRoute<bool>(
                  builder: (_) => BookingPage(
                    market: page.market,
                    initialPickupDescription: record.pickupLocation,
                    initialDestinationDescription: record.destination,
                    rideRequestSubmitter: page.rideRequestSubmitter,
                    idempotencyKeyFactory: page.idempotencyKeyFactory,
                    onSignInRequired: page.onSignInRequired,
                    requestNotificationPermission:
                        page.requestNotificationPermission,
                    rideRequestHistoryRepository:
                        page.rideRequestHistoryRepository,
                    paymentRatingRepository: page.paymentRatingRepository,
                    fareEstimateRepository: page.fareEstimateRepository,
                    trustedContactRepository: page.trustedContactRepository,
                    cancellationGateway: page.cancellationGateway,
                    phoneNumber: page.phoneNumber,
                    initialPaymentNetwork: page.initialPaymentNetwork,
                    routeService: page.routeService,
                    clock: page.clock,
                    passengerName: page.passengerName,
                  ),
                ),
              ),
            ),
          ),
        );
      }
    } on PassengerRideRequestSubmissionException catch (error) {
      if (!mounted) {
        return;
      }

      if (error.isScheduledPickupError) {
        _returnToFormWithPickupError(error.message, code: error.code);
        return;
      }

      setState(() {
        _submissionStatus = BookingSubmissionStatus.failure;
        _submissionErrorMessage = error.message;
        _submissionRequiresSignIn = error.requiresSignIn;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _submissionStatus = BookingSubmissionStatus.failure;
        _submissionErrorMessage =
            PassengerRideRequestSubmissionException.unknownErrorMessage;
        _submissionRequiresSignIn = false;
      });
    }
  }

  void _finishSuccess() {
    Navigator.of(context).pop(true);
  }

  void _startNewRequest() {
    setState(() {
      _pickupController.clear();
      _destinationController.clear();
      _assistanceController.clear();
      _passengerNoteController.clear();
      _passengerCount = 1;
      _draft = null;
      _submissionStatus = BookingSubmissionStatus.idle;
      _submissionResult = null;
      _submissionErrorMessage = null;
      _submissionRequiresSignIn = false;
      _idempotencyKey = null;
      _passengerCountErrorMessage = null;
      _fareRequestGeneration += 1;
      _fareEstimate = null;
      _scheduleForLater = false;
      _scheduledDate = null;
      _scheduledPickup = null;
      _pickupTimeErrorMessage = null;
      _pickupErrorCode = null;
    });
  }

  void _returnToSignIn() {
    widget.onSignInRequired?.call();
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_draft == null ? 'Book a ride' : 'Confirm your ride'),
      ),
      body: SafeArea(
        child: _draft == null
            ? BookingForm(
                formKey: _formKey,
                pickupController: _pickupController,
                destinationController: _destinationController,
                assistanceController: _assistanceController,
                passengerNoteController: _passengerNoteController,
                passengerCount: _passengerCount,
                onPassengerCountChanged: (value) {
                  setState(() {
                    _passengerCount = value;
                    _passengerCountErrorMessage = null;
                  });
                },
                onReview: _reviewDraft,
                passengerCountErrorMessage: _passengerCountErrorMessage,
                scheduleForLater: _scheduleForLater,
                onScheduleChanged: _setScheduleForLater,
                scheduledDate: _scheduledDate,
                scheduledPickup: _scheduledPickup,
                onPickDate: _pickScheduledDate,
                onPickTime: _pickScheduledTime,
                pickupTimeErrorMessage: _pickupTimeErrorMessage,
                onBookForNow:
                    _pickupErrorCode ==
                        PassengerRideRequestSubmissionException
                            .scheduledRideLimitCode
                    ? () => _setScheduleForLater(false)
                    : null,
                onViewMyRides:
                    _pickupErrorCode ==
                        PassengerRideRequestSubmissionException
                            .scheduledRideLimitCode
                    ? _openMyRides
                    : null,
              )
            : BookingReview(
                draft: _draft!,
                submissionStatus: _submissionStatus,
                submissionResult: _submissionResult,
                submissionErrorMessage: _submissionErrorMessage,
                submissionRequiresSignIn: _submissionRequiresSignIn,
                onEdit: _editDraft,
                onConfirm: _confirmRequest,
                onFinish: _finishSuccess,
                onStartNewRequest: _startNewRequest,
                routeService: widget.routeService,
                onAuthoritativeRouteEstimateChanged:
                    _handleAuthoritativeRouteEstimate,
                fareEstimate: _fareEstimate,
                showFareEstimate: widget.showFareEstimate,
                onSignInRequired: _returnToSignIn,
              ),
      ),
    );
  }
}
