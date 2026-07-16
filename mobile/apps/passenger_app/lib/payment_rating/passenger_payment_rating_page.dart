import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';

import 'passenger_payment_rating_contract.dart';

class PassengerPaymentRatingPage extends StatefulWidget {
  const PassengerPaymentRatingPage({
    required this.repository,
    required this.requestReference,
    this.onSignInRequired,
    this.idempotencyKeyFactory,
    super.key,
  });

  final PassengerPaymentRatingRepository repository;
  final String requestReference;
  final VoidCallback? onSignInRequired;
  final String Function()? idempotencyKeyFactory;

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

  PassengerFareSnapshot? _fare;
  PassengerPaymentSnapshot? _payment;
  PassengerPaymentReceiptSnapshot? _receipt;
  PassengerRatingSnapshot? _rating;
  PassengerPaymentRatingException? _pageError;
  String? _actionError;
  String? _paymentIdempotencyKey;

  int? _overallScore;
  int? _comfortScore;
  int? _conductScore;
  int? _cleanlinessScore;

  @override
  void initState() {
    super.initState();
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
        final receiptResult = await _fetchReceipt();
        receipt = receiptResult.receipt;
        receiptUnavailable = receiptResult.unavailable;
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
        _pageError = null;
      });
    } on PassengerPaymentRatingException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _pageError = error;
      });
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
      if (error.statusCode == 404 || error.statusCode == 409) {
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
      final result = await widget.repository.fetchPayment(
        widget.requestReference,
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

  Future<void> _submitRating() async {
    if (_ratingBusy) {
      return;
    }

    final overallScore = _overallScore;
    final comfortScore = _comfortScore;
    final conductScore = _conductScore;
    final cleanlinessScore = _cleanlinessScore;

    if (overallScore == null ||
        comfortScore == null ||
        conductScore == null ||
        cleanlinessScore == null) {
      setState(() {
        _actionError = 'Choose all four ratings before submitting.';
      });
      return;
    }

    final submission = PassengerRatingSubmission(
      overallScore: overallScore,
      comfortScore: comfortScore,
      conductScore: conductScore,
      cleanlinessScore: cleanlinessScore,
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
        _rating = result;
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
            _rating = storedRating;
          });
          return;
        } on Object {
          // The safe backend error state below remains authoritative.
        }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Payment and rating')),
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
      padding: const EdgeInsets.all(AsmSpacing.space16),
      children: [
        _FarePanel(fare: fare),
        const SizedBox(height: AsmSpacing.space12),
        _buildPaymentPanel(fare, payment),
        if (payment.isConfirmed) ...[
          const SizedBox(height: AsmSpacing.space12),
          _ReceiptPanel(receipt: _receipt, unavailable: _receiptUnavailable),
        ],
        const SizedBox(height: AsmSpacing.space12),
        _buildRatingPanel(rating),
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
    if (payment.isConfirmed) {
      return _StatePanel(
        key: const Key('payment-confirmed-state'),
        icon: Icons.verified_outlined,
        title: 'Payment confirmed',
        message:
            _safeBackendMessage(payment.message) ??
            'ALANTEH confirmed this payment.',
      );
    }

    if (payment.isPending) {
      return _StatePanel(
        key: const Key('payment-pending-state'),
        icon: Icons.schedule_outlined,
        title: 'Payment pending',
        message:
            _safeBackendMessage(payment.message) ??
            'Waiting for confirmation from ALANTEH.',
        action: FilledButton.icon(
          key: const Key('refresh-payment-status'),
          onPressed: _paymentBusy ? null : _refreshPayment,
          icon: const Icon(Icons.refresh),
          label: Text(_paymentBusy ? 'Checking...' : 'Check status'),
        ),
      );
    }

    if (payment.isFailed) {
      return _StatePanel(
        key: const Key('payment-failed-state'),
        icon: Icons.error_outline,
        title: _paymentFailureTitle(payment.normalizedPaymentStatus),
        message:
            _safeBackendMessage(payment.message) ??
            'The payment was not confirmed.',
        action: payment.canRetry && payment.canPay && fare.canPay
            ? FilledButton.icon(
                key: const Key('retry-payment'),
                onPressed: _paymentBusy ? null : _initiatePayment,
                icon: const Icon(Icons.refresh),
                label: Text(
                  _paymentBusy ? 'Trying again...' : 'Try payment again',
                ),
              )
            : null,
      );
    }

    if (fare.isNotReady ||
        !fare.hasAuthoritativeAmount ||
        !fare.canPay ||
        !payment.canPay) {
      return _StatePanel(
        key: const Key('payment-not-available-state'),
        icon: Icons.payments_outlined,
        title: fare.isNotReady ? 'Fare not ready yet' : 'Payment not available',
        message:
            _safeBackendMessage(payment.message) ??
            _safeBackendMessage(fare.message) ??
            'Please check again later.',
      );
    }

    final methodLabel = payment.paymentMethodLabel?.trim().isNotEmpty == true
        ? payment.paymentMethodLabel!.trim()
        : 'Mobile money';

    return Card(
      key: const Key('payment-prompt-state'),
      child: Padding(
        padding: const EdgeInsets.all(AsmSpacing.space16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.phone_android_outlined),
            const SizedBox(height: AsmSpacing.space8),
            Text(
              'Pay with $methodLabel',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: AsmSpacing.space8),
            Text(
              fare.formattedAmount!,
              key: const Key('backend-fare-amount'),
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: AsmSpacing.space8),
            const Text('ALANTEH will use the confirmed fare shown above.'),
            const SizedBox(height: AsmSpacing.space16),
            FilledButton.icon(
              key: const Key('initiate-payment'),
              onPressed: _paymentBusy ? null : _initiatePayment,
              icon: const Icon(Icons.lock_outline),
              label: Text(
                _paymentBusy
                    ? 'Starting payment...'
                    : 'Continue with $methodLabel',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRatingPanel(PassengerRatingSnapshot rating) {
    if (rating.isSubmitted && rating.hasStoredScores) {
      return _SubmittedRatingPanel(rating: rating);
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

    return Card(
      key: const Key('rating-open-state'),
      child: Padding(
        padding: const EdgeInsets.all(AsmSpacing.space16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Rate your ride',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: AsmSpacing.space12),
            _ScorePicker(
              label: 'Overall',
              value: _overallScore,
              onChanged: (value) {
                setState(() => _overallScore = value);
              },
            ),
            _ScorePicker(
              label: 'Comfort',
              value: _comfortScore,
              onChanged: (value) {
                setState(() => _comfortScore = value);
              },
            ),
            _ScorePicker(
              label: 'Driver conduct',
              value: _conductScore,
              onChanged: (value) {
                setState(() => _conductScore = value);
              },
            ),
            _ScorePicker(
              label: 'Cleanliness',
              value: _cleanlinessScore,
              onChanged: (value) {
                setState(() => _cleanlinessScore = value);
              },
            ),
            const SizedBox(height: AsmSpacing.space12),
            TextField(
              key: const Key('rating-feedback-note'),
              controller: _feedbackController,
              maxLength: 240,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Feedback (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AsmSpacing.space12),
            FilledButton.icon(
              key: const Key('submit-rating'),
              onPressed: _ratingBusy ? null : _submitRating,
              icon: const Icon(Icons.star_outline),
              label: Text(_ratingBusy ? 'Submitting...' : 'Submit rating'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FarePanel extends StatelessWidget {
  const _FarePanel({required this.fare});

  final PassengerFareSnapshot fare;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('fare-state'),
      child: Padding(
        padding: const EdgeInsets.all(AsmSpacing.space16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Fare', style: TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: AsmSpacing.space8),
            Text(
              fare.formattedAmount ?? 'Not available',
              key: const Key('fare-display'),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
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
      ),
    );
  }
}

class _ReceiptPanel extends StatelessWidget {
  const _ReceiptPanel({required this.receipt, required this.unavailable});

  final PassengerPaymentReceiptSnapshot? receipt;
  final bool unavailable;

  @override
  Widget build(BuildContext context) {
    final value = receipt;

    if (unavailable || value == null || !value.isAvailable) {
      return const _StatePanel(
        key: Key('receipt-not-available-state'),
        icon: Icons.receipt_long_outlined,
        title: 'Receipt not available',
        message: 'ALANTEH has not provided a receipt for this payment.',
      );
    }

    return Card(
      key: const Key('payment-receipt-state'),
      child: Padding(
        padding: const EdgeInsets.all(AsmSpacing.space16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Payment receipt',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            if (value.formattedAmount != null)
              _ReceiptRow(label: 'Amount', value: value.formattedAmount!),
            if (value.paymentMethodLabel != null)
              _ReceiptRow(label: 'Method', value: value.paymentMethodLabel!),
            if (value.paymentProvider != null)
              _ReceiptRow(label: 'Provider', value: value.paymentProvider!),
            if (value.paymentReference != null)
              _ReceiptRow(label: 'Reference', value: value.paymentReference!),
            if (value.updatedAt != null)
              _ReceiptRow(
                label: 'Confirmed',
                value: _formatDateTime(value.updatedAt!),
              ),
          ],
        ),
      ),
    );
  }
}

class _SubmittedRatingPanel extends StatelessWidget {
  const _SubmittedRatingPanel({required this.rating});

  final PassengerRatingSnapshot rating;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('rating-submitted-state'),
      child: Padding(
        padding: const EdgeInsets.all(AsmSpacing.space16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your rating',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            _ReceiptRow(label: 'Overall', value: '${rating.overallScore}/5'),
            _ReceiptRow(label: 'Comfort', value: '${rating.comfortScore}/5'),
            _ReceiptRow(
              label: 'Driver conduct',
              value: '${rating.conductScore}/5',
            ),
            _ReceiptRow(
              label: 'Cleanliness',
              value: '${rating.cleanlinessScore}/5',
            ),
            if (rating.feedbackNote != null)
              _ReceiptRow(label: 'Feedback', value: rating.feedbackNote!),
          ],
        ),
      ),
    );
  }
}

class _ScorePicker extends StatelessWidget {
  const _ScorePicker({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int? value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AsmSpacing.space12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: AsmSpacing.space8),
          Wrap(
            spacing: AsmSpacing.space8,
            children: [
              for (var score = 1; score <= 5; score += 1)
                ChoiceChip(
                  key: Key(
                    'rating-${label.toLowerCase().replaceAll(' ', '-')}-$score',
                  ),
                  label: Text('$score'),
                  selected: value == score,
                  onSelected: (_) => onChanged(score),
                ),
            ],
          ),
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
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AsmSpacing.space16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon),
            const SizedBox(height: AsmSpacing.space8),
            Text(
              title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: AsmSpacing.space8),
            Text(message),
            if (action != null) ...[
              const SizedBox(height: AsmSpacing.space16),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

class _ReceiptRow extends StatelessWidget {
  const _ReceiptRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AsmSpacing.space12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: Theme.of(context).textTheme.labelMedium),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
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
    return Card(
      key: const Key('payment-rating-action-error'),
      child: Padding(
        padding: const EdgeInsets.all(AsmSpacing.space16),
        child: Text(message),
      ),
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
            Text(error.message, textAlign: TextAlign.center),
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
        child: Text(
          'Payment and rating details are not available.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

String _paymentFailureTitle(String status) {
  return switch (status) {
    'expired' => 'Payment expired',
    'cancelled' || 'canceled' => 'Payment cancelled',
    _ => 'Payment failed',
  };
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

String _formatDateTime(DateTime value) {
  final local = value.toLocal();

  String twoDigits(int number) {
    return number.toString().padLeft(2, '0');
  }

  return '${local.year}-'
      '${twoDigits(local.month)}-'
      '${twoDigits(local.day)} '
      '${twoDigits(local.hour)}:'
      '${twoDigits(local.minute)}';
}
