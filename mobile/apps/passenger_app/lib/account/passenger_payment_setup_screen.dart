import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';

enum PassengerMobileMoneyNetwork {
  mtn,
  telecel,
  airtelTigo;

  String get title => switch (this) {
    PassengerMobileMoneyNetwork.mtn => 'MTN Mobile Money',
    PassengerMobileMoneyNetwork.telecel => 'Telecel Cash',
    PassengerMobileMoneyNetwork.airtelTigo => 'AirtelTigo Money',
  };

  String get accountLabel => switch (this) {
    PassengerMobileMoneyNetwork.mtn => 'MTN MoMo',
    PassengerMobileMoneyNetwork.telecel => 'Telecel Cash',
    PassengerMobileMoneyNetwork.airtelTigo => 'AirtelTigo Money',
  };

  String get shortLabel => switch (this) {
    PassengerMobileMoneyNetwork.mtn => 'MTN',
    PassengerMobileMoneyNetwork.telecel => 'TC',
    PassengerMobileMoneyNetwork.airtelTigo => 'AT',
  };

  Color get badgeColor => switch (this) {
    PassengerMobileMoneyNetwork.mtn => const Color(0xFFFFCB05),
    PassengerMobileMoneyNetwork.telecel => const Color(0xFFE60000),
    PassengerMobileMoneyNetwork.airtelTigo => const Color(0xFF0057A8),
  };

  Color get badgeForeground => switch (this) {
    PassengerMobileMoneyNetwork.mtn => Colors.black,
    PassengerMobileMoneyNetwork.telecel ||
    PassengerMobileMoneyNetwork.airtelTigo => Colors.white,
  };
}

class PassengerPaymentSetupScreen extends StatefulWidget {
  const PassengerPaymentSetupScreen({
    this.initialNetwork = PassengerMobileMoneyNetwork.mtn,
    this.phoneNumber,
    this.onSaved,
    super.key,
  });

  final PassengerMobileMoneyNetwork initialNetwork;
  final String? phoneNumber;
  final ValueChanged<PassengerMobileMoneyNetwork>? onSaved;

  @override
  State<PassengerPaymentSetupScreen> createState() =>
      _PassengerPaymentSetupScreenState();
}

class _PassengerPaymentSetupScreenState
    extends State<PassengerPaymentSetupScreen> {
  late PassengerMobileMoneyNetwork _selectedNetwork;

  @override
  void initState() {
    super.initState();
    _selectedNetwork = widget.initialNetwork;
  }

  void _save() {
    widget.onSaved?.call(_selectedNetwork);

    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(_selectedNetwork);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('passenger-payment-setup-screen'),
      backgroundColor: AsmColors.passengerSurface,
      appBar: AppBar(title: const Text('Payment setup')),
      body: AsmScreenSurface(
        scrollable: true,
        padding: const EdgeInsets.fromLTRB(
          AsmSpacing.space20,
          AsmSpacing.space16,
          AsmSpacing.space20,
          AsmSpacing.space32,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Choose your Mobile Money network',
              style: TextStyle(
                color: Color(0xFF171B12),
                fontSize: 25,
                fontWeight: FontWeight.w900,
                height: 1.1,
              ),
            ),
            const SizedBox(height: AsmSpacing.space8),
            Text(
              'This method will be selected when you prepare a ride payment.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
            const SizedBox(height: AsmSpacing.space20),
            Container(
              padding: const EdgeInsets.all(AsmSpacing.space16),
              decoration: BoxDecoration(
                color: AsmColors.passengerCard,
                borderRadius: BorderRadius.circular(AsmRadii.radius16),
                border: Border.all(color: AsmColors.passengerLine),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Mobile Money number',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: AsmSpacing.space8),
                  Text(
                    _paymentPhoneNumber(widget.phoneNumber),
                    key: const Key('passenger-payment-setup-phone'),
                    style: const TextStyle(
                      color: Color(0xFF171B12),
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AsmSpacing.space16),
            for (final network in PassengerMobileMoneyNetwork.values) ...[
              _NetworkCard(
                network: network,
                selected: _selectedNetwork == network,
                onTap: () {
                  setState(() => _selectedNetwork = network);
                },
              ),
              const SizedBox(height: AsmSpacing.space12),
            ],
            const SizedBox(height: AsmSpacing.space8),
            Container(
              padding: const EdgeInsets.all(AsmSpacing.space16),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF4EC),
                borderRadius: BorderRadius.circular(AsmRadii.radius16),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lock_outline, color: AsmColors.brandDeepGreen),
                  SizedBox(width: AsmSpacing.space12),
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
            ),
            const SizedBox(height: AsmSpacing.space24),
            FilledButton.icon(
              key: const Key('passenger-payment-setup-save'),
              onPressed: _save,
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Save payment method'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NetworkCard extends StatelessWidget {
  const _NetworkCard({
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
      color: selected ? const Color(0xFFE2F2E6) : AsmColors.passengerCard,
      borderRadius: BorderRadius.circular(AsmRadii.radius16),
      child: InkWell(
        key: Key('passenger-payment-network-${network.name}'),
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

String _paymentPhoneNumber(String? phoneNumber) {
  final value = phoneNumber?.trim();

  if (value == null || value.isEmpty) {
    return 'Phone number unavailable';
  }

  final normalized = value.replaceAll(RegExp(r'[\s-]'), '');
  final match = RegExp(
    r'^\+(\d{3})(\d{2})(\d{3})(\d{4})$',
  ).firstMatch(normalized);

  if (match == null) {
    return 'Phone number unavailable';
  }

  return '+${match.group(1)} '
      '${match.group(2)} '
      '${match.group(3)} '
      '${match.group(4)}';
}
