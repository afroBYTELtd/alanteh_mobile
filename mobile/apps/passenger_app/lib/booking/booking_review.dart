import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:asm_ride_domain/asm_ride_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../map/osrm_route.dart';
import 'booking_draft.dart';
import 'booking_submission.dart';
import 'passenger_fare_estimate.dart';
import 'route_preview_card.dart';

class BookingReview extends StatelessWidget {
  const BookingReview({
    required this.draft,
    required this.submissionStatus,
    required this.submissionResult,
    required this.submissionErrorMessage,
    required this.submissionRequiresSignIn,
    required this.onEdit,
    required this.onConfirm,
    required this.onFinish,
    required this.onStartNewRequest,
    this.routeService = const OsrmPassengerRouteService(),
    this.onAuthoritativeRouteEstimateChanged,
    this.fareEstimate,
    this.onSignInRequired,
    super.key,
  });

  final BookingDraft draft;
  final BookingSubmissionStatus submissionStatus;
  final PassengerRideRequestResult? submissionResult;
  final String? submissionErrorMessage;
  final bool submissionRequiresSignIn;
  final VoidCallback onEdit;
  final VoidCallback onConfirm;
  final VoidCallback onFinish;
  final VoidCallback onStartNewRequest;
  final PassengerRouteService routeService;
  final ValueChanged<PassengerRouteEstimate?>?
  onAuthoritativeRouteEstimateChanged;
  final PassengerBookingFareEstimate? fareEstimate;
  final VoidCallback? onSignInRequired;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final isSubmitting = submissionStatus == BookingSubmissionStatus.submitting;
    final isSuccess =
        submissionStatus == BookingSubmissionStatus.success &&
        submissionResult != null;
    final isFailure =
        submissionStatus == BookingSubmissionStatus.failure ||
        (submissionStatus == BookingSubmissionStatus.success &&
            submissionResult == null);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AsmSpacing.space20,
        AsmSpacing.space16,
        AsmSpacing.space20,
        AsmSpacing.space32,
      ),
      children: [
        Text(
          'Confirm your ride',
          style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: AsmSpacing.space8),
        Text(
          'Check your ride details before requesting.',
          style: textTheme.bodyLarge?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            height: 1.4,
          ),
        ),
        const SizedBox(height: AsmSpacing.space20),
        RoutePreviewCard(
          routeService: routeService,
          onAuthoritativeEstimateChanged: onAuthoritativeRouteEstimateChanged,
        ),
        const SizedBox(height: AsmSpacing.space16),
        PassengerFareEstimatePanel(estimate: fareEstimate),
        const SizedBox(height: AsmSpacing.space24),
        AsmRideDetailRow(
          key: const Key('booking-review-from'),
          label: 'From',
          value: draft.rideDraft.pickupDisplayText,
          selectableValue: true,
        ),
        AsmRideDetailRow(
          key: const Key('booking-review-to'),
          label: 'To',
          value: draft.rideDraft.destinationDisplayText,
          selectableValue: true,
        ),
        AsmRideDetailRow(
          key: const Key('booking-review-passengers'),
          label: 'Passengers',
          value: '${draft.passengerCount.value}',
          selectableValue: true,
        ),
        if (draft.assistanceNote != null)
          AsmRideDetailRow(
            label: 'Special request',
            value: draft.assistanceNote!.value,
            selectableValue: true,
          ),
        const SizedBox(height: AsmSpacing.space16),
        if (isSubmitting) ...[
          const LinearProgressIndicator(key: Key('ride-request-loading')),
          const SizedBox(height: AsmSpacing.space12),
          const Text(
            'Sending request...',
            key: Key('ride-request-loading-message'),
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AsmSpacing.space16),
        ],
        Container(
          key: const Key('mtn-momo-selected'),
          padding: const EdgeInsets.all(AsmSpacing.space16),
          decoration: BoxDecoration(
            color: const Color(0xFFE2F2E6),
            borderRadius: BorderRadius.circular(AsmRadii.radius16),
            border: Border.all(color: AsmColors.brandDeepGreen),
          ),
          child: const Row(
            children: [
              CircleAvatar(
                backgroundColor: Color(0xFFFFCB05),
                foregroundColor: Colors.black,
                child: Text(
                  'MTN',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900),
                ),
              ),
              SizedBox(width: AsmSpacing.space12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'MTN Mobile Money',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    Text(
                      'Selected payment method · payment is not collected in this step',
                    ),
                  ],
                ),
              ),
              Icon(Icons.check_circle, color: AsmColors.brandDeepGreen),
            ],
          ),
        ),
        const SizedBox(height: AsmSpacing.space16),
        if (isSuccess) ...[
          _SubmissionPanel.success(result: submissionResult!),
          const SizedBox(height: AsmSpacing.space16),
          FilledButton.icon(
            key: const Key('start-new-request'),
            onPressed: onStartNewRequest,
            icon: const Icon(Icons.add_circle_outline),
            label: const Text('Start new request'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
          ),
          const SizedBox(height: AsmSpacing.space12),
          OutlinedButton.icon(
            key: const Key('finish-ride-request'),
            onPressed: onFinish,
            icon: const Icon(Icons.receipt_long_outlined),
            label: const Text('View my requests'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
          ),
        ] else ...[
          if (isFailure) ...[
            _SubmissionPanel.error(message: submissionErrorMessage),
            const SizedBox(height: AsmSpacing.space12),
            if (submissionRequiresSignIn && onSignInRequired != null)
              FilledButton.icon(
                key: const Key('back-to-sign-in'),
                onPressed: onSignInRequired,
                icon: const Icon(Icons.login_outlined),
                label: const Text('Back to sign in'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
              )
            else
              OutlinedButton.icon(
                key: const Key('retry-ride-request'),
                onPressed: onConfirm,
                icon: const Icon(Icons.refresh_outlined),
                label: const Text('Try again'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
              ),
            const SizedBox(height: AsmSpacing.space12),
          ],
          OutlinedButton.icon(
            key: const Key('edit-booking-details'),
            onPressed: isSubmitting ? null : onEdit,
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Edit details'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
          ),
          const SizedBox(height: AsmSpacing.space12),
          FilledButton.icon(
            key: const Key('confirm-and-request'),
            onPressed: isSubmitting ? null : onConfirm,
            icon: const Icon(Icons.check_circle_outline),
            label: Text(
              isSubmitting ? 'Sending request...' : 'Confirm and request',
            ),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
          ),
        ],
      ],
    );
  }
}

class _SubmissionPanel extends StatefulWidget {
  const _SubmissionPanel._({
    required this.icon,
    required this.title,
    required this.message,
    this.reference,
    this.status,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.keyValue,
  }) : super(key: keyValue);

  factory _SubmissionPanel.success({
    required PassengerRideRequestResult result,
  }) {
    return _SubmissionPanel._(
      keyValue: const Key('ride-request-success'),
      icon: Icons.check_circle_outline,
      title: 'Ride request received',
      message: result.message,
      reference: result.requestReference!,
      status: result.status,
      backgroundColor: const Color(0xFFE8F5E9),
      foregroundColor: const Color(0xFF1B5E20),
    );
  }

  factory _SubmissionPanel.error({String? message}) {
    return _SubmissionPanel._(
      keyValue: const Key('ride-request-error'),
      icon: Icons.error_outline,
      title: 'Request not sent',
      message: _passengerErrorMessage(message),
      backgroundColor: const Color(0xFFFFF3E0),
      foregroundColor: const Color(0xFF8A4B00),
    );
  }

  static String _passengerErrorMessage(String? message) {
    final cleaned = message?.trim();
    if (cleaned == null || cleaned.isEmpty) {
      return 'Please check your connection and try again.';
    }

    return cleaned;
  }

  final IconData icon;
  final String title;
  final String message;
  final String? reference;
  final String? status;
  final Color backgroundColor;
  final Color foregroundColor;
  final Key keyValue;

  @override
  State<_SubmissionPanel> createState() => _SubmissionPanelState();
}

class _SubmissionPanelState extends State<_SubmissionPanel> {
  bool _referenceCopied = false;

  @override
  void didUpdateWidget(covariant _SubmissionPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reference != widget.reference) {
      _referenceCopied = false;
    }
  }

  Future<void> _copyReference() async {
    final reference = widget.reference?.trim();
    if (reference == null || reference.isEmpty) {
      return;
    }

    await Clipboard.setData(ClipboardData(text: reference));

    if (!mounted) {
      return;
    }

    setState(() {
      _referenceCopied = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final reference = widget.reference?.trim();
    final hasReference = reference != null && reference.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(AsmSpacing.space16),
      decoration: BoxDecoration(
        color: widget.backgroundColor,
        borderRadius: BorderRadius.circular(AsmRadii.radius8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(widget.icon, color: widget.foregroundColor),
          const SizedBox(height: AsmSpacing.space8),
          Text(
            widget.title,
            style: TextStyle(
              color: widget.foregroundColor,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AsmSpacing.space8),
          Text(
            _safeSubmissionMessage(widget.message, widget.status),
            style: TextStyle(color: widget.foregroundColor, height: 1.35),
          ),
          if (hasReference) ...[
            const SizedBox(height: AsmSpacing.space8),
            Text(
              'Reference: $reference',
              key: const Key('ride-request-reference'),
              style: TextStyle(
                color: widget.foregroundColor,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AsmSpacing.space8),
            Text(
              'Keep this reference. ALANTEH can use it to follow up.',
              key: const Key('ride-request-reference-support'),
              style: TextStyle(color: widget.foregroundColor, height: 1.35),
            ),
            const SizedBox(height: AsmSpacing.space8),
            OutlinedButton.icon(
              key: const Key('copy-ride-request-reference'),
              onPressed: _copyReference,
              icon: const Icon(Icons.copy_outlined),
              label: const Text('Copy reference'),
              style: OutlinedButton.styleFrom(
                foregroundColor: widget.foregroundColor,
                side: BorderSide(color: widget.foregroundColor),
              ),
            ),
            if (_referenceCopied) ...[
              const SizedBox(height: AsmSpacing.space8),
              Text(
                'Reference copied.',
                key: const Key('ride-request-reference-copied'),
                style: TextStyle(
                  color: widget.foregroundColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
          if (widget.status != null) ...[
            const SizedBox(height: AsmSpacing.space8),
            Text(
              _submissionStatusText(widget.status),
              key: const Key('ride-request-status'),
              style: TextStyle(
                color: widget.foregroundColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _safeSubmissionMessage(String? message, String? status) {
  final trimmed = message?.trim() ?? '';
  if (trimmed.isEmpty) {
    return _submissionDefaultMessage(status);
  }

  final lower = trimmed.toLowerCase();
  final mentionsInternalOps = RegExp(
    r'control\s+center',
    caseSensitive: false,
  ).hasMatch(trimmed);
  final isPassengerAppReceipt = lower.contains(
    'passenger app request received',
  );

  if (mentionsInternalOps || isPassengerAppReceipt) {
    return _submissionDefaultMessage(status);
  }

  return trimmed;
}

String _submissionDefaultMessage(String? status) {
  return switch ((status ?? '').trim().toLowerCase()) {
    'requested' => 'Your ride request was received.',
    'under_review' => 'Your ride request is being reviewed.',
    'accepted' || 'approved' => 'Your ride is being prepared.',
    'rejected' || 'declined' => 'This ride request could not be accepted.',
    'cancelled' || 'canceled' => 'This ride request was cancelled.',
    'trip_created' => 'Your trip record has been created.',
    _ => 'Your ride request was updated.',
  };
}

String _submissionStatusText(String? status) {
  return switch ((status ?? '').trim().toLowerCase()) {
    'requested' => 'Request status: Received by ALANTEH',
    'under_review' => 'Request status: Being reviewed',
    'accepted' || 'approved' => 'Request status: Accepted for trip preparation',
    'rejected' || 'declined' => 'Request status: Could not be accepted',
    'cancelled' || 'canceled' => 'Request status: Cancelled',
    'trip_created' => 'Request status: Trip record created',
    _ => 'Request status: Updated',
  };
}
