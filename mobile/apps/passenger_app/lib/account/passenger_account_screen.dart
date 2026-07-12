import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';

const passengerAccountContactEmail = 'contact@alanteh.io';

String formatPassengerPhoneNumber(String? phoneNumber) {
  final value = phoneNumber?.trim();
  if (value == null || value.isEmpty) {
    return 'Phone number unavailable';
  }

  final normalized = value.replaceAll(RegExp(r'[\s-]'), '');
  final match = RegExp(
    r'^\+(\d{3})(\d{2})(\d{4})(\d{3})$',
  ).firstMatch(normalized);

  if (match == null) {
    return 'Phone number unavailable';
  }

  return '+${match.group(1)} ${match.group(2)} ****${match.group(4)}';
}

class PassengerAccountScreen extends StatelessWidget {
  const PassengerAccountScreen({
    required this.phoneNumber,
    required this.onOpenTrips,
    required this.onSignOut,
    this.onHelp,
    super.key,
  });

  final String? phoneNumber;
  final VoidCallback onOpenTrips;
  final VoidCallback onSignOut;
  final VoidCallback? onHelp;

  void _openHelp(BuildContext context) {
    final customHelp = onHelp;
    if (customHelp != null) {
      customHelp();
      return;
    }

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('passenger-account-help-dialog'),
        title: const Text('Help'),
        content: const Text('Contact us at $passengerAccountContactEmail'),
        actions: [
          TextButton(
            key: const Key('passenger-account-help-close'),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final maskedPhoneNumber = formatPassengerPhoneNumber(phoneNumber);

    return AsmScreenSurface(
      key: const Key('passenger-account-screen'),
      scrollable: true,
      padding: const EdgeInsets.all(AsmSpacing.space20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: CircleAvatar(
              key: const Key('passenger-account-avatar'),
              radius: 36,
              backgroundColor: AsmColors.brandDeepGreen,
              child: const Icon(
                Icons.person,
                color: AsmColors.brandWhite,
                size: 36,
              ),
            ),
          ),
          const SizedBox(height: AsmSpacing.space16),
          Text(
            'Account',
            textAlign: TextAlign.center,
            style: textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              height: 1.08,
            ),
          ),
          const SizedBox(height: AsmSpacing.space8),
          Text(
            maskedPhoneNumber,
            key: const Key('passenger-account-phone'),
            textAlign: TextAlign.center,
            style: textTheme.titleMedium?.copyWith(
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Riding clean with ALANTEH.',
            key: const Key('passenger-account-tagline'),
            textAlign: TextAlign.center,
            style: textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AsmSpacing.space24),
          Card(
            elevation: 0,
            color: AsmColors.passengerCard,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AsmRadii.radius20),
              side: const BorderSide(color: AsmColors.passengerLine),
            ),
            child: Column(
              children: [
                ListTile(
                  key: const Key('passenger-account-my-trips'),
                  leading: const Icon(Icons.route_outlined),
                  title: const Text('My Trips'),
                  subtitle: const Text('View your ride requests'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: onOpenTrips,
                ),
                const Divider(height: 1),
                ListTile(
                  key: const Key('passenger-account-help'),
                  leading: const Icon(Icons.help_outline),
                  title: const Text('Help'),
                  subtitle: const Text(passengerAccountContactEmail),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openHelp(context),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(AsmSpacing.space16),
                  child: FilledButton.icon(
                    key: const Key('passenger-account-sign-out'),
                    onPressed: onSignOut,
                    icon: const Icon(Icons.logout),
                    label: const Text('Sign out'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
