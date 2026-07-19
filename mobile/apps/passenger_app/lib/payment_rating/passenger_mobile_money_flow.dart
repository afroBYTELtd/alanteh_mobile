import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';

import '../account/passenger_payment_setup_screen.dart';
import 'passenger_payment_rating_contract.dart';

class PassengerMobileMoneyFlow extends StatelessWidget {
  const PassengerMobileMoneyFlow({
    required this.fare,
    required this.payment,
    required this.selectedNetwork,
    required this.busy,
    required this.onNetworkChanged,
    required this.onRequestPayment,
    required this.onRefreshPayment,
    required this.onResend,
    required this.onCancel,
    this.phoneNumber,
    super.key,
  });

  final PassengerFareSnapshot fare;
  final PassengerPaymentSnapshot payment;
  final PassengerMobileMoneyNetwork selectedNetwork;
  final String? phoneNumber;
  final bool busy;
  final ValueChanged<PassengerMobileMoneyNetwork> onNetworkChanged;
  final VoidCallback onRequestPayment;
  final VoidCallback onRefreshPayment;
  final VoidCallback onResend;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    if (payment.isConfirmed) {
      return _PaymentConfirmedPanel(payment: payment);
    }

    if (payment.isPending) {
      return _PaymentWaitingPanel(
        amount: fare.formattedAmount,
        phoneNumber: phoneNumber,
        network: selectedNetwork,
        busy: busy,
        onRefresh: onRefreshPayment,
        onResend: onResend,
        onCancel: onCancel,
      );
    }

    if (payment.isFailed) {
      return _PaymentFailedPanel(
        amount: fare.formattedAmount,
        canRetry: payment.canRetry && payment.canPay && fare.canPay,
        busy: busy,
        onRetry: onRequestPayment,
      );
    }

    if (fare.isNotReady ||
        !fare.hasAuthoritativeAmount ||
        !fare.canPay ||
        !payment.canPay) {
      return _PaymentUnavailablePanel(
        title: fare.isNotReady ? 'Fare not ready yet' : 'Payment not available',
        message:
            _safePaymentMessage(payment.message) ??
            _safePaymentMessage(fare.message) ??
            'Please check again later.',
      );
    }

    return _PaymentRequestPanel(
      amount: fare.formattedAmount!,
      phoneNumber: phoneNumber,
      selectedNetwork: selectedNetwork,
      busy: busy,
      onNetworkChanged: onNetworkChanged,
      onRequestPayment: onRequestPayment,
    );
  }
}

class _PaymentRequestPanel extends StatelessWidget {
  const _PaymentRequestPanel({
    required this.amount,
    required this.phoneNumber,
    required this.selectedNetwork,
    required this.busy,
    required this.onNetworkChanged,
    required this.onRequestPayment,
  });

  final String amount;
  final String? phoneNumber;
  final PassengerMobileMoneyNetwork selectedNetwork;
  final bool busy;
  final ValueChanged<PassengerMobileMoneyNetwork> onNetworkChanged;
  final VoidCallback onRequestPayment;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('payment-prompt-state'),
      padding: const EdgeInsets.all(AsmSpacing.space20),
      decoration: BoxDecoration(
        color: AsmColors.passengerCard,
        borderRadius: BorderRadius.circular(AsmRadii.radius20),
        border: Border.all(color: AsmColors.passengerLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(
            Icons.phone_android_outlined,
            color: AsmColors.brandDeepGreen,
            size: 34,
          ),
          const SizedBox(height: AsmSpacing.space12),
          const Text(
            'Pay with Mobile Money',
            style: TextStyle(
              color: Color(0xFF171B12),
              fontSize: 23,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: AsmSpacing.space8),
          const Text(
            'Choose your network and confirm the number to pay from.',
            style: TextStyle(height: 1.4),
          ),
          const SizedBox(height: AsmSpacing.space20),
          Container(
            padding: const EdgeInsets.all(AsmSpacing.space16),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF4EC),
              borderRadius: BorderRadius.circular(AsmRadii.radius16),
            ),
            child: Column(
              children: [
                const Text(
                  'Amount due',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  amount,
                  key: const Key('backend-fare-amount'),
                  style: const TextStyle(
                    color: AsmColors.brandDeepGreen,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AsmSpacing.space16),
          for (final network in PassengerMobileMoneyNetwork.values) ...[
            _PaymentNetworkChoice(
              network: network,
              selected: selectedNetwork == network,
              onTap: () => onNetworkChanged(network),
            ),
            const SizedBox(height: AsmSpacing.space8),
          ],
          const SizedBox(height: AsmSpacing.space8),
          const Text(
            'Mobile Money number',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: AsmSpacing.space8),
          Container(
            key: const Key('payment-mobile-money-number'),
            padding: const EdgeInsets.all(AsmSpacing.space16),
            decoration: BoxDecoration(
              color: AsmColors.passengerSurface,
              borderRadius: BorderRadius.circular(AsmRadii.radius16),
              border: Border.all(color: AsmColors.passengerLine),
            ),
            child: Text(
              formatPaymentPhoneNumber(phoneNumber),
              style: const TextStyle(
                color: Color(0xFF171B12),
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: AsmSpacing.space20),
          FilledButton.icon(
            key: const Key('initiate-payment'),
            onPressed: busy ? null : onRequestPayment,
            icon: const Icon(Icons.lock_outline),
            label: Text(busy ? 'Requesting payment...' : 'Request payment'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
            ),
          ),
          const SizedBox(height: AsmSpacing.space12),
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.shield_outlined,
                color: AsmColors.brandDeepGreen,
                size: 20,
              ),
              SizedBox(width: AsmSpacing.space8),
              Expanded(
                child: Text(
                  'ALANTEH never asks for your Mobile Money PIN in the app.',
                  style: TextStyle(
                    color: AsmColors.brandDeepGreen,
                    fontWeight: FontWeight.w800,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PaymentWaitingPanel extends StatelessWidget {
  const _PaymentWaitingPanel({
    required this.amount,
    required this.phoneNumber,
    required this.network,
    required this.busy,
    required this.onRefresh,
    required this.onResend,
    required this.onCancel,
  });

  final String? amount;
  final String? phoneNumber;
  final PassengerMobileMoneyNetwork network;
  final bool busy;
  final VoidCallback onRefresh;
  final VoidCallback onResend;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final amountText = amount ?? 'the confirmed fare';
    final phoneText = formatPaymentPhoneNumber(phoneNumber);

    return Container(
      key: const Key('payment-pending-state'),
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
            backgroundColor: Color(0xFFEAF4EC),
            foregroundColor: AsmColors.brandDeepGreen,
            child: Icon(Icons.phone_iphone_outlined, size: 31),
          ),
          const SizedBox(height: AsmSpacing.space16),
          const Text(
            'Check your phone',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF171B12),
              fontSize: 25,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: AsmSpacing.space12),
          Text(
            'We’ve sent a ${network.title} payment prompt to',
            textAlign: TextAlign.center,
            style: const TextStyle(height: 1.4),
          ),
          const SizedBox(height: 4),
          Text(
            phoneText,
            key: const Key('payment-prompt-phone'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF171B12),
              fontSize: 19,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: AsmSpacing.space16),
          Text(
            'Enter your Mobile Money PIN on your phone to approve the '
            '$amountText payment. ALANTEH never asks for your PIN in the app.',
            key: const Key('payment-pin-safety-message'),
            textAlign: TextAlign.center,
            style: const TextStyle(height: 1.45),
          ),
          const SizedBox(height: AsmSpacing.space20),
          Container(
            padding: const EdgeInsets.all(AsmSpacing.space16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF6D8),
              borderRadius: BorderRadius.circular(AsmRadii.radius16),
            ),
            child: const Text(
              'WAITING FOR APPROVAL…',
              key: Key('payment-waiting-for-approval'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF6B5200),
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: AsmSpacing.space16),
          FilledButton.icon(
            key: const Key('refresh-payment-status'),
            onPressed: busy ? null : onRefresh,
            icon: const Icon(Icons.refresh),
            label: Text(busy ? 'Checking...' : 'Check payment status'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
          ),
          const SizedBox(height: AsmSpacing.space8),
          OutlinedButton(
            key: const Key('payment-resend-prompt'),
            onPressed: busy ? null : onResend,
            child: const Text('Didn’t get a prompt? Resend'),
          ),
          TextButton(
            key: const Key('payment-cancel-local'),
            onPressed: busy ? null : onCancel,
            child: const Text('Cancel payment'),
          ),
        ],
      ),
    );
  }
}

class _PaymentFailedPanel extends StatelessWidget {
  const _PaymentFailedPanel({
    required this.amount,
    required this.canRetry,
    required this.busy,
    required this.onRetry,
  });

  final String? amount;
  final bool canRetry;
  final bool busy;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final amountText = amount == null ? '' : ' of $amount';

    return Container(
      key: const Key('payment-failed-state'),
      padding: const EdgeInsets.all(AsmSpacing.space20),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3F0),
        borderRadius: BorderRadius.circular(AsmRadii.radius20),
        border: Border.all(color: const Color(0xFFE7B8AF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.error_outline, color: Color(0xFF9C2F1F), size: 42),
          const SizedBox(height: AsmSpacing.space12),
          const Text(
            'Payment didn’t go through',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF621D14),
              fontSize: 23,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: AsmSpacing.space8),
          Text(
            'Your Mobile Money payment$amountText was declined or timed out. '
            'No charge was made.',
            key: const Key('payment-failed-no-charge-message'),
            textAlign: TextAlign.center,
            style: const TextStyle(height: 1.45),
          ),
          if (canRetry) ...[
            const SizedBox(height: AsmSpacing.space20),
            FilledButton.icon(
              key: const Key('retry-payment'),
              onPressed: busy ? null : onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(busy ? 'Trying again...' : 'Try payment again'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PaymentConfirmedPanel extends StatelessWidget {
  const _PaymentConfirmedPanel({required this.payment});

  final PassengerPaymentSnapshot payment;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('payment-confirmed-state'),
      padding: const EdgeInsets.all(AsmSpacing.space20),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF4EC),
        borderRadius: BorderRadius.circular(AsmRadii.radius20),
        border: Border.all(color: const Color(0xFFB9D8C0)),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.verified_outlined,
            color: AsmColors.brandDeepGreen,
            size: 42,
          ),
          const SizedBox(height: AsmSpacing.space12),
          const Text(
            'Payment confirmed',
            style: TextStyle(
              color: AsmColors.brandDeepGreen,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: AsmSpacing.space8),
          Text(
            _safePaymentMessage(payment.message) ??
                'ALANTEH confirmed this payment.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _PaymentUnavailablePanel extends StatelessWidget {
  const _PaymentUnavailablePanel({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('payment-not-available-state'),
      padding: const EdgeInsets.all(AsmSpacing.space20),
      decoration: BoxDecoration(
        color: AsmColors.passengerCard,
        borderRadius: BorderRadius.circular(AsmRadii.radius20),
        border: Border.all(color: AsmColors.passengerLine),
      ),
      child: Column(
        children: [
          const Icon(Icons.payments_outlined, size: 38),
          const SizedBox(height: AsmSpacing.space12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF171B12),
              fontSize: 21,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: AsmSpacing.space8),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _PaymentNetworkChoice extends StatelessWidget {
  const _PaymentNetworkChoice({
    required this.network,
    required this.selected,
    required this.onTap,
  });

  final PassengerMobileMoneyNetwork network;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFFE2F2E6) : AsmColors.passengerSurface,
      borderRadius: BorderRadius.circular(AsmRadii.radius16),
      child: InkWell(
        key: Key('passenger-payment-flow-network-${network.name}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(AsmRadii.radius16),
        child: Container(
          padding: const EdgeInsets.all(AsmSpacing.space16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AsmRadii.radius16),
            border: Border.all(
              color: selected
                  ? AsmColors.brandDeepGreen
                  : AsmColors.passengerLine,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: network.badgeColor,
                foregroundColor: network.badgeForeground,
                child: Text(
                  network.shortLabel,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: AsmSpacing.space12),
              Expanded(
                child: Text(
                  network.title,
                  style: const TextStyle(
                    color: Color(0xFF171B12),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Icon(
                selected ? Icons.check_circle : Icons.radio_button_unchecked,
                color: selected
                    ? AsmColors.brandDeepGreen
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String formatPaymentPhoneNumber(String? phoneNumber) {
  final value = phoneNumber?.trim();

  if (value == null || value.isEmpty) {
    return 'Your saved Mobile Money number';
  }

  final normalized = value.replaceAll(RegExp(r'[\s-]'), '');
  final match = RegExp(
    r'^\+(\d{3})(\d{2})(\d{3})(\d{4})$',
  ).firstMatch(normalized);

  if (match == null) {
    return 'Your saved Mobile Money number';
  }

  return '+${match.group(1)} '
      '${match.group(2)} '
      '${match.group(3)} '
      '${match.group(4)}';
}

String? _safePaymentMessage(String? value) {
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
