import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';

import 'passenger_local_rating_store.dart';
import 'passenger_payment_rating_contract.dart';

class PassengerPostTripReceipt extends StatelessWidget {
  const PassengerPostTripReceipt({
    required this.fare,
    required this.payment,
    required this.receipt,
    required this.requestReference,
    this.pickupDescription,
    this.destinationDescription,
    this.tripCompletedAt,
    this.onRateRide,
    super.key,
  });

  final PassengerFareSnapshot fare;
  final PassengerPaymentSnapshot payment;
  final PassengerPaymentReceiptSnapshot receipt;
  final String requestReference;
  final String? pickupDescription;
  final String? destinationDescription;
  final DateTime? tripCompletedAt;
  final VoidCallback? onRateRide;

  @override
  Widget build(BuildContext context) {
    final confirmedAmount = receipt.formattedAmount ?? fare.formattedAmount;
    final paymentMethod =
        _nonEmpty(receipt.paymentMethodLabel) ??
        _nonEmpty(payment.paymentMethodLabel);
    final confirmedAt =
        receipt.updatedAt ??
        receipt.createdAt ??
        payment.updatedAt ??
        payment.createdAt ??
        tripCompletedAt;
    final tripReference =
        _nonEmpty(receipt.tripReference) ??
        _nonEmpty(payment.tripReference) ??
        _nonEmpty(fare.tripReference);

    return Container(
      key: const Key('payment-receipt-state'),
      padding: const EdgeInsets.all(AsmSpacing.space20),
      decoration: BoxDecoration(
        color: AsmColors.passengerCard,
        borderRadius: BorderRadius.circular(AsmRadii.radius20),
        border: Border.all(color: AsmColors.passengerLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const CircleAvatar(
            radius: 31,
            backgroundColor: Color(0xFFEAF4EC),
            foregroundColor: AsmColors.brandDeepGreen,
            child: Icon(Icons.receipt_long_outlined, size: 31),
          ),
          const SizedBox(height: AsmSpacing.space16),
          const Text(
            'Trip receipt',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF171B12),
              fontSize: 25,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: AsmSpacing.space8),
          const Text(
            'Your trip and payment details',
            textAlign: TextAlign.center,
            style: TextStyle(height: 1.4),
          ),
          if (_hasRoute) ...[
            const SizedBox(height: AsmSpacing.space20),
            Container(
              key: const Key('receipt-trip-route'),
              padding: const EdgeInsets.all(AsmSpacing.space16),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F7F2),
                borderRadius: BorderRadius.circular(AsmRadii.radius16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Trip details',
                    style: TextStyle(
                      color: AsmColors.brandDeepGreen,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: AsmSpacing.space12),
                  _RoutePoint(
                    icon: Icons.radio_button_checked,
                    label: 'From',
                    value: pickupDescription!.trim(),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(left: 10),
                    child: SizedBox(
                      height: 18,
                      child: VerticalDivider(
                        color: AsmColors.passengerLine,
                        thickness: 2,
                      ),
                    ),
                  ),
                  _RoutePoint(
                    icon: Icons.location_on,
                    label: 'To',
                    value: destinationDescription!.trim(),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AsmSpacing.space16),
          if (confirmedAmount != null)
            _ReceiptDetailRow(
              key: const Key('receipt-confirmed-fare'),
              label: 'Confirmed fare',
              value: confirmedAmount,
              emphasized: true,
            ),
          if (paymentMethod != null)
            _ReceiptDetailRow(
              key: const Key('receipt-payment-method'),
              label: 'Payment method',
              value: paymentMethod,
            ),
          if (confirmedAt != null)
            _ReceiptDetailRow(
              key: const Key('receipt-date-time'),
              label: 'Date and time',
              value: formatPostTripDateTime(confirmedAt),
            ),
          if (tripReference != null)
            _ReceiptDetailRow(
              key: const Key('receipt-trip-reference'),
              label: 'Trip reference',
              value: tripReference,
            ),
          _ReceiptDetailRow(
            key: const Key('receipt-request-reference'),
            label: 'Ride reference',
            value: requestReference.trim(),
          ),
          if (_nonEmpty(receipt.paymentReference) != null)
            _ReceiptDetailRow(
              key: const Key('receipt-payment-reference'),
              label: 'Payment reference',
              value: receipt.paymentReference!.trim(),
            ),
          if (onRateRide != null) ...[
            const SizedBox(height: AsmSpacing.space20),
            FilledButton.icon(
              key: const Key('open-rating-from-receipt'),
              onPressed: onRateRide,
              icon: const Icon(Icons.star_rounded),
              label: const Text('Rate your ride'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
              ),
            ),
          ],
        ],
      ),
    );
  }

  bool get _hasRoute =>
      _nonEmpty(pickupDescription) != null &&
      _nonEmpty(destinationDescription) != null;
}

class PassengerRideRatingForm extends StatelessWidget {
  const PassengerRideRatingForm({
    required this.overallScore,
    required this.comfortScore,
    required this.conductScore,
    required this.cleanlinessScore,
    required this.feedbackController,
    required this.busy,
    required this.onOverallChanged,
    required this.onComfortChanged,
    required this.onConductChanged,
    required this.onCleanlinessChanged,
    required this.onSubmit,
    this.pickupDescription,
    this.destinationDescription,
    super.key,
  });

  final int? overallScore;
  final int? comfortScore;
  final int? conductScore;
  final int? cleanlinessScore;
  final TextEditingController feedbackController;
  final bool busy;
  final ValueChanged<int> onOverallChanged;
  final ValueChanged<int> onComfortChanged;
  final ValueChanged<int> onConductChanged;
  final ValueChanged<int> onCleanlinessChanged;
  final VoidCallback onSubmit;
  final String? pickupDescription;
  final String? destinationDescription;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('rating-open-state'),
      padding: const EdgeInsets.all(AsmSpacing.space20),
      decoration: BoxDecoration(
        color: AsmColors.passengerCard,
        borderRadius: BorderRadius.circular(AsmRadii.radius20),
        border: Border.all(color: AsmColors.passengerLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const CircleAvatar(
            radius: 30,
            backgroundColor: Color(0xFFFFF3C9),
            foregroundColor: Color(0xFF7A5900),
            child: Icon(Icons.star_rounded, size: 34),
          ),
          const SizedBox(height: AsmSpacing.space16),
          const Text(
            'How was your trip?',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF171B12),
              fontSize: 25,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (_routeText != null) ...[
            const SizedBox(height: AsmSpacing.space8),
            Text(
              _routeText!,
              key: const Key('rating-trip-route'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AsmColors.brandDeepGreen,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
          const SizedBox(height: AsmSpacing.space20),
          _StarScorePicker(
            label: 'Overall',
            keySlug: 'overall',
            value: overallScore,
            onChanged: onOverallChanged,
            large: true,
          ),
          _StarScorePicker(
            label: 'Comfort',
            keySlug: 'comfort',
            value: comfortScore,
            onChanged: onComfortChanged,
          ),
          _StarScorePicker(
            label: 'Driver conduct',
            keySlug: 'driver-conduct',
            value: conductScore,
            onChanged: onConductChanged,
          ),
          _StarScorePicker(
            label: 'Cleanliness',
            keySlug: 'cleanliness',
            value: cleanlinessScore,
            onChanged: onCleanlinessChanged,
          ),
          const SizedBox(height: AsmSpacing.space8),
          TextField(
            key: const Key('rating-feedback-note'),
            controller: feedbackController,
            maxLength: 240,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Add a comment (optional)',
              hintText: 'Share anything that would help us improve.',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: AsmSpacing.space12),
          FilledButton.icon(
            key: const Key('submit-rating'),
            onPressed: busy ? null : onSubmit,
            icon: const Icon(Icons.send_outlined),
            label: Text(busy ? 'Submitting...' : 'Submit rating'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
            ),
          ),
        ],
      ),
    );
  }

  String? get _routeText {
    final pickup = _nonEmpty(pickupDescription);
    final destination = _nonEmpty(destinationDescription);

    if (pickup == null || destination == null) {
      return null;
    }

    return '$pickup → $destination';
  }
}

class PassengerRatingThanks extends StatelessWidget {
  const PassengerRatingThanks({
    required this.onBackToHome,
    this.backendRating,
    this.localRating,
    super.key,
  });

  final VoidCallback onBackToHome;
  final PassengerRatingSnapshot? backendRating;
  final PassengerLocalRatingRecord? localRating;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('rating-submitted-state'),
      padding: const EdgeInsets.all(AsmSpacing.space24),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF4EC),
        borderRadius: BorderRadius.circular(AsmRadii.radius20),
        border: Border.all(color: const Color(0xFFB9D8C0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const CircleAvatar(
            radius: 34,
            backgroundColor: Colors.white,
            foregroundColor: AsmColors.brandDeepGreen,
            child: Icon(Icons.check_rounded, size: 38),
          ),
          const SizedBox(height: AsmSpacing.space16),
          const Text(
            'Thanks for your feedback',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AsmColors.brandDeepGreen,
              fontSize: 25,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: AsmSpacing.space8),
          const Text(
            'Your rating helps ALANTEH keep every ride solar-powered, '
            'safe, and reliable.',
            textAlign: TextAlign.center,
            style: TextStyle(height: 1.45),
          ),
          if (localRating != null)
            const SizedBox(key: Key('rating-local-session-state'), height: 1),
          const SizedBox(height: AsmSpacing.space20),
          FilledButton(
            key: const Key('rating-back-to-home'),
            onPressed: onBackToHome,
            child: const Text('Back to home'),
          ),
        ],
      ),
    );
  }
}

class _StarScorePicker extends StatelessWidget {
  const _StarScorePicker({
    required this.label,
    required this.keySlug,
    required this.value,
    required this.onChanged,
    this.large = false,
  });

  final String label;
  final String keySlug;
  final int? value;
  final ValueChanged<int> onChanged;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AsmSpacing.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: const Color(0xFF171B12),
              fontSize: large ? 17 : 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: AsmSpacing.space8),
          KeyedSubtree(
            key: Key('rating-$keySlug-bar'),
            child: RatingBar.builder(
              initialRating: value?.toDouble() ?? 0,
              minRating: 1,
              direction: Axis.horizontal,
              allowHalfRating: false,
              itemCount: 5,
              itemSize: large ? 43 : 36,
              itemPadding: const EdgeInsets.only(right: 3),
              unratedColor: const Color(0xFFD8D8D0),
              itemBuilder: (context, index) {
                return Icon(
                  Icons.star_rounded,
                  key: Key('rating-$keySlug-${index + 1}'),
                  color: const Color(0xFFF1B928),
                );
              },
              onRatingUpdate: (rating) => onChanged(rating.round()),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoutePoint extends StatelessWidget {
  const _RoutePoint({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AsmColors.brandDeepGreen, size: 21),
        const SizedBox(width: AsmSpacing.space12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  color: Color(0xFF171B12),
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReceiptDetailRow extends StatelessWidget {
  const _ReceiptDetailRow({
    required super.key,
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AsmSpacing.space12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 125,
            child: Text(label, style: Theme.of(context).textTheme.labelMedium),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: emphasized
                    ? AsmColors.brandDeepGreen
                    : const Color(0xFF171B12),
                fontSize: emphasized ? 19 : 15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String formatPostTripDateTime(DateTime value) {
  final local = value.toLocal();
  const months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final period = local.hour >= 12 ? 'PM' : 'AM';

  return '${months[local.month - 1]} ${local.day}, ${local.year} '
      '• $hour:$minute $period';
}

String? _nonEmpty(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}
