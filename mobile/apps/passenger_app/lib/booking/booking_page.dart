import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_app_config/asm_app_config.dart';
import 'package:asm_ride_domain/asm_ride_domain.dart';
import 'package:flutter/material.dart';

import '../map/osrm_route.dart';
import '../payment_rating/passenger_payment_rating_contract.dart';
import 'booking_draft.dart';
import 'booking_form.dart';
import 'booking_review.dart';
import 'booking_submission.dart';
import 'passenger_fare_estimate.dart';
import '../ride_requests/ride_request_history.dart';
import '../tracking/ride_tracking_screen.dart';

class BookingPage extends StatefulWidget {
  const BookingPage({
    required this.market,
    this.initialPickupDescription = '',
    this.initialDestinationDescription = '',
    this.rideRequestSubmitter,
    this.idempotencyKeyFactory,
    this.onSignInRequired,
    this.rideRequestHistoryRepository,
    this.paymentRatingRepository,
    this.fareEstimateRepository,
    this.routeService = const OsrmPassengerRouteService(),
    super.key,
  });

  final MarketConfig market;
  final String initialPickupDescription;
  final String initialDestinationDescription;
  final PassengerRideRequestSubmitter? rideRequestSubmitter;
  final String Function()? idempotencyKeyFactory;
  final VoidCallback? onSignInRequired;
  final PassengerRideRequestHistoryRepository? rideRequestHistoryRepository;
  final PassengerPaymentRatingRepository? paymentRatingRepository;
  final PassengerFareEstimateRepository? fareEstimateRepository;
  final PassengerRouteService routeService;

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

    setState(() {
      _passengerCountErrorMessage = null;
      _fareRequestGeneration += 1;
      _fareEstimate = null;
      _draft = BookingDraft(
        marketCode: widget.market.marketCode,
        serviceContext: _internalServiceContext,
        pickupDescription: _pickupController.text,
        destinationDescription: _destinationController.text,
        passengerCount: _passengerCount,
        assistanceNote: _assistanceController.text,
      );
    });
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

      setState(() {
        _submissionStatus = BookingSubmissionStatus.success;
        _submissionResult = result;
        _idempotencyKey = null;
      });

      final reference = result.requestReference?.trim();
      final repository = widget.rideRequestHistoryRepository;
      if (reference != null &&
          reference.isNotEmpty &&
          repository != null &&
          mounted) {
        await Navigator.of(context).pushReplacement<void, void>(
          MaterialPageRoute<void>(
            builder: (_) => RideTrackingScreen(
              repository: repository,
              requestReference: reference,
              paymentRatingRepository: widget.paymentRatingRepository,
              onSignInRequired: widget.onSignInRequired,
            ),
          ),
        );
      }
    } on PassengerRideRequestSubmissionException catch (error) {
      if (!mounted) {
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
                passengerCount: _passengerCount,
                onPassengerCountChanged: (value) {
                  setState(() {
                    _passengerCount = value;
                    _passengerCountErrorMessage = null;
                  });
                },
                onReview: _reviewDraft,
                passengerCountErrorMessage: _passengerCountErrorMessage,
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
                onSignInRequired: _returnToSignIn,
              ),
      ),
    );
  }
}
