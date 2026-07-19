import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';

import '../account/passenger_payment_setup_screen.dart';
import 'passenger_local_rating_store.dart';
import 'passenger_mobile_money_flow.dart';
import 'passenger_payment_rating_contract.dart';
import 'passenger_post_trip_flow.dart';

class PassengerPaymentRatingPage extends StatefulWidget {
  const PassengerPaymentRatingPage({
    required this.repository,
    required this.requestReference,
    this.onSignInRequired,
    this.idempotencyKeyFactory,
    this.phoneNumber,
    this.initialPaymentNetwork = PassengerMobileMoneyNetwork.mtn,
    this.pickupDescription,
    this.destinationDescription,
    this.tripCompletedAt,
    this.localRatingStore,
    this.onBackToHome,
    super.key,
  });

  final PassengerPaymentRatingRepository repository;
  final String requestReference;
  final VoidCallback? onSignInRequired;
  final String Function()? idempotencyKeyFactory;
  final String? phoneNumber;
  final PassengerMobileMoneyNetwork initialPaymentNetwork;
  final String? pickupDescription;
  final String? destinationDescription;
  final DateTime? tripCompletedAt;
  final PassengerLocalRatingStore? localRatingStore;
  final VoidCallback? onBackToHome;

  @override
  State<PassengerPaymentRatingPage> createState() =>
      _PassengerPaymentRatingPageState();
}

class _PassengerPaymentRatingPageState
    extends State<PassengerPaymentRatingPage> {
  final TextEditingController _feedbackController = TextEditingController();

  bool _loading = true;
  bool _paymentBusy = false;
  bool _ratingBusy = false;
  bool _receiptUnavailable = false;
  bool _ratingEntryOpen = false;

  PassengerFareSnapshot? _fare;
  PassengerPaymentSnapshot? _payment;
  PassengerPaymentReceiptSnapshot? _receipt;
  PassengerRatingSnapshot? _rating;
  PassengerLocalRatingRecord? _localRating;
  PassengerPaymentRatingException? _pageError;
  String? _actionError;
  String? _paymentIdempotencyKey;

  late PassengerMobileMoneyNetwork _selectedPaymentNetwork;
  late PassengerLocalRatingStore _localRatingStore;

  int? _overallScore;
  int? _comfortScore;
  int? _conductScore;
  int? _cleanlinessScore;

  @override
  void initState() {
    super.initState();
    _selectedPaymentNetwork = widget.initialPaymentNetwork;
    _localRatingStore =
        widget.localRatingStore ?? PassengerSessionRatingStore.instance;
    _localRating = _localRatingStore.read(widget.requestReference);
    _load();
  }

  @override
  void dispose() {
    _feedbackController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _pageError = null;
        _actionError = null;
      });
    }

    try {
      final fare = await widget.repository.fetchFare(widget.requestReference);
      final payment = await widget.repository.fetchPayment(
        widget.requestReference,
      );
      final rating = await widget.repository.fetchRating(
        widget.requestReference,
      );

      PassengerPaymentReceiptSnapshot? receipt;
      var receiptUnavailable = false;

      if (payment.isConfirmed) {
        final result = await _fetchReceipt();
        receipt = result.receipt;
        receiptUnavailable = result.unavailable;
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _fare = fare;
        _payment = payment;
        _rating = rating;
        _receipt = receipt;
        _receiptUnavailable = receiptUnavailable;
        _localRating = _localRatingStore.read(widget.requestReference);
      });
    } on PassengerPaymentRatingException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _pageError = error;
      });

      if (error.requiresSignIn) {
        widget.onSignInRequired?.call();
      }
    } on Object {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _pageError = const PassengerPaymentRatingException.unknown();
      });
    }
  }

  Future<({PassengerPaymentReceiptSnapshot? receipt, bool unavailable})>
  _fetchReceipt() async {
    try {
      final receipt = await widget.repository.fetchReceipt(
        widget.requestReference,
      );

      return (receipt: receipt, unavailable: !receipt.isAvailable);
    } on PassengerPaymentRatingException catch (error) {
      if (error.statusCode == 404) {
        return (receipt: null, unavailable: true);
      }

      rethrow;
    }
  }

  Future<void> _initiatePayment() async {
    final fare = _fare;
    final payment = _payment;

    if (_paymentBusy ||
        fare == null ||
        payment == null ||
        !fare.hasAuthoritativeAmount ||
        !fare.canPay ||
        !payment.canPay) {
      return;
    }

    final idempotencyKey =
        _paymentIdempotencyKey ??
        (widget.idempotencyKeyFactory ??
            PassengerPaymentIdempotencyKey.generate)();

    setState(() {
      _paymentBusy = true;
      _paymentIdempotencyKey = idempotencyKey;
      _actionError = null;
    });

    try {
      final result = await widget.repository.initiatePayment(
        widget.requestReference,
        idempotencyKey: idempotencyKey,
      );

      PassengerPaymentReceiptSnapshot? receipt;
      var receiptUnavailable = false;

      if (result.isConfirmed) {
        final receiptResult = await _fetchReceipt();
        receipt = receiptResult.receipt;
        receiptUnavailable = receiptResult.unavailable;
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _paymentBusy = false;
        _payment = result;
        _receipt = receipt;
        _receiptUnavailable = receiptUnavailable;
      });
    } on PassengerPaymentRatingException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _paymentBusy = false;
        _actionError = error.message;
      });

      if (error.requiresSignIn) {
        widget.onSignInRequired?.call();
      }
    } on Object {
      if (!mounted) {
        return;
      }

      setState(() {
        _paymentBusy = false;
        _actionError = PassengerPaymentRatingException.unknownMessage;
      });
    }
  }

  Future<void> _refreshPayment() async {
    if (_paymentBusy) {
      return;
    }

    setState(() {
      _paymentBusy = true;
      _actionError = null;
    });

    try {
      final payment = await widget.repository.fetchPayment(
        widget.requestReference,
      );
      final rating = await widget.repository.fetchRating(
        widget.requestReference,
      );

      PassengerPaymentReceiptSnapshot? receipt;
      var receiptUnavailable = false;

      if (payment.isConfirmed) {
        final receiptResult = await _fetchReceipt();
        receipt = receiptResult.receipt;
        receiptUnavailable = receiptResult.unavailable;
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _paymentBusy = false;
        _payment = payment;
        _rating = rating;
        _receipt = receipt;
        _receiptUnavailable = receiptUnavailable;
      });
    } on PassengerPaymentRatingException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _paymentBusy = false;
        _actionError = error.message;
      });

      if (error.requiresSignIn) {
        widget.onSignInRequired?.call();
      }
    } on Object {
      if (!mounted) {
        return;
      }

      setState(() {
        _paymentBusy = false;
        _actionError = PassengerPaymentRatingException.unknownMessage;
      });
    }
  }

  void _cancelPaymentView() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }

    setState(() {
      _actionError = 'Payment request cancelled. No charge was made.';
    });
  }

  Future<void> _submitRating() async {
    final overall = _overallScore;
    final comfort = _comfortScore;
    final conduct = _conductScore;
    final cleanliness = _cleanlinessScore;

    if (_ratingBusy) {
      return;
    }

    if (overall == null ||
        comfort == null ||
        conduct == null ||
        cleanliness == null) {
      setState(() {
        _actionError = 'Choose a score from 1 to 5 for every rating category.';
      });
      return;
    }

    final submission = PassengerRatingSubmission(
      overallScore: overall,
      comfortScore: comfort,
      conductScore: conduct,
      cleanlinessScore: cleanliness,
      feedbackNote: _feedbackController.text,
    );

    setState(() {
      _ratingBusy = true;
      _actionError = null;
    });

    try {
      final result = await widget.repository.submitRating(
        widget.requestReference,
        submission,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _ratingBusy = false;
        _ratingEntryOpen = false;
        _rating = result;
        _localRating = null;
      });
    } on PassengerPaymentRatingException catch (error) {
      if (error.statusCode == 409) {
        try {
          final storedRating = await widget.repository.fetchRating(
            widget.requestReference,
          );

          if (!mounted) {
            return;
          }

          setState(() {
            _ratingBusy = false;
            _ratingEntryOpen = false;
            _rating = storedRating;
          });
          return;
        } on Object {
          // The accepted service state below remains authoritative.
        }
      }

      if (error.message == AsmApiClient.connectionNotConfiguredMessage) {
        final record = PassengerLocalRatingRecord(
          requestReference: widget.requestReference,
          overallScore: overall,
          comfortScore: comfort,
          conductScore: conduct,
          cleanlinessScore: cleanliness,
          feedbackNote: submission.feedbackNote,
          savedAt: DateTime.now(),
        );

        // Future connection point: retry this session-side rating through the
        // accepted rating repository when queued submission support is added.
        _localRatingStore.save(record);

        if (!mounted) {
          return;
        }

        setState(() {
          _ratingBusy = false;
          _ratingEntryOpen = false;
          _localRating = record;
        });
        return;
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _ratingBusy = false;
        _actionError = error.message;
      });

      if (error.requiresSignIn) {
        widget.onSignInRequired?.call();
      }
    } on Object {
      if (!mounted) {
        return;
      }

      setState(() {
        _ratingBusy = false;
        _actionError = PassengerPaymentRatingException.unknownMessage;
      });
    }
  }

  void _backToHome() {
    final callback = widget.onBackToHome;

    if (callback != null) {
      callback();
      return;
    }

    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_ratingEntryOpen ? 'Rate your trip' : 'Payment and rating'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        key: Key('payment-rating-loading'),
        child: CircularProgressIndicator(),
      );
    }

    final pageError = _pageError;

    if (pageError != null) {
      return _PageErrorState(
        error: pageError,
        onRetry: _load,
        onSignInRequired: widget.onSignInRequired,
      );
    }

    final fare = _fare;
    final payment = _payment;
    final rating = _rating;

    if (fare == null || payment == null || rating == null) {
      return const _UnavailableState();
    }

    return ListView(
      key: const Key('payment-rating-loaded'),
      padding: const EdgeInsets.fromLTRB(
        AsmSpacing.space16,
        AsmSpacing.space16,
        AsmSpacing.space16,
        AsmSpacing.space32,
      ),
      children: [
        _FarePanel(fare: fare),
        const SizedBox(height: AsmSpacing.space12),
        _buildPaymentPanel(fare, payment),
        if (payment.isConfirmed) ...[
          const SizedBox(height: AsmSpacing.space12),
          _buildReceiptPanel(fare, payment, rating),
        ],
        const SizedBox(height: AsmSpacing.space12),
        _buildRatingPanel(rating, payment),
        if (_actionError != null) ...[
          const SizedBox(height: AsmSpacing.space12),
          _ActionError(message: _actionError!),
        ],
      ],
    );
  }

  Widget _buildPaymentPanel(
    PassengerFareSnapshot fare,
    PassengerPaymentSnapshot payment,
  ) {
    // Future connection point: include the selected network and saved number
    // when the accepted payment contract supports those request fields.
    return PassengerMobileMoneyFlow(
      fare: fare,
      payment: payment,
      selectedNetwork: _selectedPaymentNetwork,
      phoneNumber: widget.phoneNumber,
      busy: _paymentBusy,
      onNetworkChanged: (network) {
        setState(() => _selectedPaymentNetwork = network);
      },
      onRequestPayment: _initiatePayment,
      onRefreshPayment: _refreshPayment,
      onResend: _initiatePayment,
      onCancel: _cancelPaymentView,
    );
  }

  Widget _buildReceiptPanel(
    PassengerFareSnapshot fare,
    PassengerPaymentSnapshot payment,
    PassengerRatingSnapshot rating,
  ) {
    final receipt = _receipt;

    if (_receiptUnavailable || receipt == null || !receipt.isAvailable) {
      return const _StatePanel(
        key: Key('receipt-not-available-state'),
        icon: Icons.receipt_long_outlined,
        title: 'Receipt not available',
        message: 'ALANTEH has not provided a receipt for this payment.',
      );
    }

    final ratingAlreadySubmitted = _localRating != null || rating.isSubmitted;

    return PassengerPostTripReceipt(
      fare: fare,
      payment: payment,
      receipt: receipt,
      requestReference: widget.requestReference,
      pickupDescription: widget.pickupDescription,
      destinationDescription: widget.destinationDescription,
      tripCompletedAt: widget.tripCompletedAt,
      onRateRide: rating.isOpen && !ratingAlreadySubmitted
          ? () {
              setState(() {
                _ratingEntryOpen = true;
                _actionError = null;
              });
            }
          : null,
    );
  }

  Widget _buildRatingPanel(
    PassengerRatingSnapshot rating,
    PassengerPaymentSnapshot payment,
  ) {
    final localRating = _localRating;

    if (localRating != null) {
      return PassengerRatingThanks(
        localRating: localRating,
        onBackToHome: _backToHome,
      );
    }

    if (rating.isSubmitted) {
      return PassengerRatingThanks(
        backendRating: rating,
        onBackToHome: _backToHome,
      );
    }

    if (!rating.isOpen) {
      return _StatePanel(
        key: const Key('rating-not-eligible-state'),
        icon: Icons.star_border_outlined,
        title: 'Rating not available',
        message:
            _safeBackendMessage(rating.message) ??
            'Rating will open when ALANTEH marks the ride as eligible.',
      );
    }

    final hasReceiptEntryPoint =
        payment.isConfirmed &&
        _receipt != null &&
        _receipt!.isAvailable &&
        !_receiptUnavailable;

    if (hasReceiptEntryPoint && !_ratingEntryOpen) {
      return const SizedBox.shrink();
    }

    return PassengerRideRatingForm(
      overallScore: _overallScore,
      comfortScore: _comfortScore,
      conductScore: _conductScore,
      cleanlinessScore: _cleanlinessScore,
      feedbackController: _feedbackController,
      busy: _ratingBusy,
      pickupDescription: widget.pickupDescription,
      destinationDescription: widget.destinationDescription,
      onOverallChanged: (value) {
        setState(() => _overallScore = value);
      },
      onComfortChanged: (value) {
        setState(() => _comfortScore = value);
      },
      onConductChanged: (value) {
        setState(() => _conductScore = value);
      },
      onCleanlinessChanged: (value) {
        setState(() => _cleanlinessScore = value);
      },
      onSubmit: _submitRating,
    );
  }
}

class _FarePanel extends StatelessWidget {
  const _FarePanel({required this.fare});

  final PassengerFareSnapshot fare;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('fare-state'),
      padding: const EdgeInsets.all(AsmSpacing.space16),
      decoration: BoxDecoration(
        color: AsmColors.passengerCard,
        borderRadius: BorderRadius.circular(AsmRadii.radius16),
        border: Border.all(color: AsmColors.passengerLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Fare', style: TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: AsmSpacing.space8),
          Text(
            fare.formattedAmount ?? 'Not available',
            key: const Key('fare-display'),
            style: const TextStyle(
              color: AsmColors.brandDeepGreen,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (!fare.hasAuthoritativeAmount) ...[
            const SizedBox(height: AsmSpacing.space8),
            Text(
              _safeBackendMessage(fare.message) ??
                  'The final fare is not ready yet.',
            ),
          ],
        ],
      ),
    );
  }
}

class _StatePanel extends StatelessWidget {
  const _StatePanel({
    required super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AsmSpacing.space20),
      decoration: BoxDecoration(
        color: AsmColors.passengerCard,
        borderRadius: BorderRadius.circular(AsmRadii.radius20),
        border: Border.all(color: AsmColors.passengerLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 38),
          const SizedBox(height: AsmSpacing.space12),
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF171B12),
              fontSize: 21,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: AsmSpacing.space8),
          Text(message),
        ],
      ),
    );
  }
}

class _ActionError extends StatelessWidget {
  const _ActionError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('payment-rating-action-error'),
      padding: const EdgeInsets.all(AsmSpacing.space16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3F0),
        borderRadius: BorderRadius.circular(AsmRadii.radius16),
        border: Border.all(color: const Color(0xFFE7B8AF)),
      ),
      child: Text(message),
    );
  }
}

class _PageErrorState extends StatelessWidget {
  const _PageErrorState({
    required this.error,
    required this.onRetry,
    this.onSignInRequired,
  });

  final PassengerPaymentRatingException error;
  final Future<void> Function() onRetry;
  final VoidCallback? onSignInRequired;

  @override
  Widget build(BuildContext context) {
    return Center(
      key: Key(
        error.requiresSignIn
            ? 'payment-rating-session-expired'
            : 'payment-rating-error',
      ),
      child: Padding(
        padding: const EdgeInsets.all(AsmSpacing.space24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              error.requiresSignIn
                  ? Icons.lock_clock_outlined
                  : Icons.error_outline,
              size: 52,
            ),
            const SizedBox(height: AsmSpacing.space16),
            Text(
              error.requiresSignIn
                  ? 'Session expired'
                  : 'Could not load payment details',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: AsmSpacing.space8),
            Text(
              _safeBackendMessage(error.message) ??
                  PassengerPaymentRatingException.unknownMessage,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AsmSpacing.space16),
            if (error.requiresSignIn && onSignInRequired != null)
              FilledButton(
                key: const Key('payment-rating-sign-in-again'),
                onPressed: onSignInRequired,
                child: const Text('Sign in again'),
              )
            else
              FilledButton.icon(
                key: const Key('payment-rating-retry'),
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
          ],
        ),
      ),
    );
  }
}

class _UnavailableState extends StatelessWidget {
  const _UnavailableState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      key: Key('payment-rating-unavailable'),
      child: Padding(
        padding: EdgeInsets.all(AsmSpacing.space24),
        child: Text('Payment and rating details are not available.'),
      ),
    );
  }
}

String? _safeBackendMessage(String? value) {
  final normalized = value?.trim();

  if (normalized == null || normalized.isEmpty) {
    return null;
  }

  final lower = normalized.toLowerCase();

  if (lower.contains('authorization') ||
      lower.contains('access token') ||
      lower.contains('refresh token') ||
      lower.contains('control center') ||
      lower.contains('raw payload') ||
      lower.contains('traceback')) {
    return null;
  }

  return normalized;
}
