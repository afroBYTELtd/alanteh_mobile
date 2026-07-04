import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:asm_ride_domain/asm_ride_domain.dart';
import 'package:flutter/material.dart';

import 'booking_draft.dart';
import 'booking_submission.dart';

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
  final VoidCallback? onSignInRequired;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final isSubmitting = submissionStatus == BookingSubmissionStatus.submitting;
    final isSuccess = submissionStatus == BookingSubmissionStatus.success;
    final isFailure = submissionStatus == BookingSubmissionStatus.failure;

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
        const SizedBox(height: AsmSpacing.space24),
        AsmRideDetailRow(
          label: 'Pickup',
          value: draft.rideDraft.pickupDisplayText,
          selectableValue: true,
        ),
        AsmRideDetailRow(
          label: 'Destination',
          value: draft.rideDraft.destinationDisplayText,
          selectableValue: true,
        ),
        AsmRideDetailRow(
          label: 'Passenger count',
          value: '${draft.passengerCount.value}',
          selectableValue: true,
        ),
        const AsmRideDetailRow(
          label: 'Payment method',
          value: 'MTN MoMo',
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
            'Sending ride request...',
            key: Key('ride-request-loading-message'),
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AsmSpacing.space16),
        ],
        if (isSuccess) ...[
          _SubmissionPanel.success(result: submissionResult),
          const SizedBox(height: AsmSpacing.space16),
          FilledButton.icon(
            key: const Key('finish-ride-request'),
            onPressed: onFinish,
            icon: const Icon(Icons.home_outlined),
            label: const Text('Back to home'),
            style: FilledButton.styleFrom(
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
            label: Text(isSubmitting ? 'Sending...' : 'Confirm and request'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
          ),
        ],
      ],
    );
  }
}

class _SubmissionPanel extends StatelessWidget {
  const _SubmissionPanel._({
    required this.icon,
    required this.title,
    required this.message,
    this.reference,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.keyValue,
  }) : super(key: keyValue);

  factory _SubmissionPanel.success({PassengerRideRequestResult? result}) {
    return _SubmissionPanel._(
      keyValue: const Key('ride-request-success'),
      icon: Icons.check_circle_outline,
      title: 'Ride request sent',
      message: 'Your request has been received by the Control Center.',
      reference: result?.requestReference,
      backgroundColor: const Color(0xFFE8F5E9),
      foregroundColor: const Color(0xFF1B5E20),
    );
  }

  factory _SubmissionPanel.error({String? message}) {
    return _SubmissionPanel._(
      keyValue: const Key('ride-request-error'),
      icon: Icons.error_outline,
      title: 'Could not send ride request.',
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

    const titlePrefix = 'Could not send ride request.';
    if (cleaned.startsWith(titlePrefix)) {
      final passengerMessage = cleaned.substring(titlePrefix.length).trim();
      if (passengerMessage.isNotEmpty) {
        return passengerMessage;
      }
    }

    return cleaned;
  }

  final IconData icon;
  final String title;
  final String message;
  final String? reference;
  final Color backgroundColor;
  final Color foregroundColor;
  final Key keyValue;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AsmSpacing.space16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(AsmRadii.radius8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: foregroundColor),
          const SizedBox(height: AsmSpacing.space8),
          Text(
            title,
            style: TextStyle(
              color: foregroundColor,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AsmSpacing.space8),
          Text(message, style: TextStyle(color: foregroundColor, height: 1.35)),
          if (reference != null) ...[
            const SizedBox(height: AsmSpacing.space8),
            Text(
              'Reference: $reference',
              key: const Key('ride-request-reference'),
              style: TextStyle(
                color: foregroundColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
