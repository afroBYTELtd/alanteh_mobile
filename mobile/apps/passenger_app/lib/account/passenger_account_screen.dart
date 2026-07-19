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
    this.paymentMethodLabel = 'MTN MoMo',
    this.onOpenPaymentSetup,
    this.onHelp,
    this.onOpenSettings,
    super.key,
  });

  final String? phoneNumber;
  final VoidCallback onOpenTrips;
  final VoidCallback onSignOut;
  final String paymentMethodLabel;
  final VoidCallback? onOpenPaymentSetup;
  final VoidCallback? onHelp;
  final VoidCallback? onOpenSettings;

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

  void _openProfileInfo(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('passenger-account-profile-dialog'),
        title: const Text('Your ALANTEH profile'),
        content: const Text(
          'Your phone number is linked to your ALANTEH passenger account.',
        ),
        actions: [
          TextButton(
            key: const Key('passenger-account-profile-close'),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  void _openSettings(BuildContext context) {
    final customSettings = onOpenSettings;

    if (customSettings != null) {
      customSettings();
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          key: const Key('passenger-account-settings-sheet'),
          padding: const EdgeInsets.fromLTRB(
            AsmSpacing.space20,
            AsmSpacing.space8,
            AsmSpacing.space20,
            AsmSpacing.space24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Settings',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: AsmSpacing.space16),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.notifications_outlined),
                title: Text('Notifications'),
                trailing: Text('On'),
              ),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.language_outlined),
                title: Text('Language'),
                trailing: Text('English'),
              ),
              const SizedBox(height: AsmSpacing.space12),
              FilledButton(
                key: const Key('passenger-account-settings-close'),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
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
      padding: const EdgeInsets.fromLTRB(
        AsmSpacing.space20,
        AsmSpacing.space20,
        AsmSpacing.space20,
        AsmSpacing.space32,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Account',
            style: TextStyle(
              color: Color(0xFF171B12),
              fontSize: 28,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: AsmSpacing.space20),
          Container(
            padding: const EdgeInsets.all(AsmSpacing.space20),
            decoration: BoxDecoration(
              color: AsmColors.passengerCard,
              borderRadius: BorderRadius.circular(AsmRadii.radius20),
              border: Border.all(color: AsmColors.passengerLine),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const CircleAvatar(
                      key: Key('passenger-account-avatar'),
                      radius: 32,
                      backgroundColor: AsmColors.brandDeepGreen,
                      child: Text(
                        'M',
                        style: TextStyle(
                          color: AsmColors.brandWhite,
                          fontSize: 25,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: AsmSpacing.space16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ALANTEH Member',
                            key: const Key('passenger-account-name'),
                            style: textTheme.titleLarge?.copyWith(
                              color: const Color(0xFF171B12),
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Riding clean with ALANTEH.',
                            key: const Key('passenger-account-tagline'),
                            style: textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      key: const Key('passenger-account-edit'),
                      onPressed: () => _openProfileInfo(context),
                      child: const Text('Edit'),
                    ),
                  ],
                ),
                const SizedBox(height: AsmSpacing.space20),
                const Divider(height: 1),
                Material(
                  color: Colors.transparent,
                  child: ListTile(
                    key: const Key('passenger-account-phone-row'),
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.phone_outlined),
                    title: const Text('Phone number'),
                    subtitle: Text(
                      maskedPhoneNumber,
                      key: const Key('passenger-account-phone'),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openProfileInfo(context),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AsmSpacing.space16),
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
                  key: const Key('passenger-account-payment-method'),
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFFFCB05),
                    foregroundColor: Colors.black,
                    child: Text(
                      'MTN',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  title: const Text('Payment method'),
                  subtitle: const Text('Default for ride requests'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        paymentMethodLabel,
                        key: const Key(
                          'passenger-account-payment-method-label',
                        ),
                        style: const TextStyle(
                          color: AsmColors.brandDeepGreen,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                  onTap: onOpenPaymentSetup,
                ),
                const Divider(height: 1),
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
                ListTile(
                  key: const Key('passenger-account-settings'),
                  leading: const Icon(Icons.settings_outlined),
                  title: const Text('Settings'),
                  subtitle: const Text('Notifications, language'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openSettings(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: AsmSpacing.space16),
          FilledButton.icon(
            key: const Key('passenger-account-sign-out'),
            onPressed: onSignOut,
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
          ),
        ],
      ),
    );
  }
}
