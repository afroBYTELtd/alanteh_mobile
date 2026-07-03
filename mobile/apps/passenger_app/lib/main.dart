import 'package:asm_app_config/asm_app_config.dart';
import 'package:asm_auth/asm_auth.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';

import 'passenger_shell.dart';

void main() {
  final configuration = AsmAppConfigLoader.fromCompileTimeEnvironment();
  runApp(PassengerApp(configuration: configuration, showLoginShell: true));
}

class PassengerApp extends StatelessWidget {
  const PassengerApp({
    this.configuration = AsmAppConfig.localGhana,
    this.showLoginShell = false,
    super.key,
  });

  final AsmAppConfig configuration;
  final bool showLoginShell;

  @override
  Widget build(BuildContext context) {
    assert(AuthState.unauthenticated().status == AuthStatus.unauthenticated);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ASM Passenger',
      theme: AsmThemes.passenger,
      home: showLoginShell
          ? PassengerLoginShell(configuration: configuration)
          : PassengerShell(configuration: configuration),
    );
  }
}

class PassengerLoginShell extends StatefulWidget {
  const PassengerLoginShell({
    this.configuration = AsmAppConfig.localGhana,
    super.key,
  });

  final AsmAppConfig configuration;

  @override
  State<PassengerLoginShell> createState() => _PassengerLoginShellState();
}

class _PassengerLoginShellState extends State<PassengerLoginShell> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _pinController = TextEditingController();
  bool _localDemoOpened = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  void _continueLocalDemo() {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _localDemoOpened = true);
  }

  void _clearForm() {
    FocusManager.instance.primaryFocus?.unfocus();
    _phoneController.clear();
    _pinController.clear();
    _formKey.currentState?.reset();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_localDemoOpened) {
      return PassengerShell(configuration: widget.configuration);
    }

    final market = widget.configuration.market;

    return Scaffold(
      body: AsmScreenSurface(
        scrollable: true,
        padding: const EdgeInsets.fromLTRB(
          AsmSpacing.space16,
          AsmSpacing.space20,
          AsmSpacing.space16,
          AsmSpacing.space24,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AsmScreenHeader(
                leading: const AsmAppBrandMark(),
                title: 'Passenger access',
                subtitle: '${market.city}, ${market.countryName}',
              ),
              const SizedBox(height: AsmSpacing.space20),
              const Text(
                'Pilot access',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: AsmSpacing.space8),
              const Text('Enter your phone number and PIN to continue.'),
              const SizedBox(height: AsmSpacing.space20),
              TextFormField(
                key: const Key('passenger-phone-field'),
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'phone number',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if ((value ?? '').trim().isEmpty) {
                    return 'Phone number cannot be blank.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: AsmSpacing.space12),
              TextFormField(
                key: const Key('passenger-pin-field'),
                controller: _pinController,
                obscureText: true,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _continueLocalDemo(),
                decoration: const InputDecoration(
                  labelText: 'PIN',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if ((value ?? '').trim().isEmpty) {
                    return 'PIN cannot be blank.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: AsmSpacing.space20),
              AsmPrimaryActionButton(
                key: const Key('passenger-continue-local-demo'),
                onPressed: _continueLocalDemo,
                icon: Icons.play_arrow_outlined,
                label: 'Continue',
              ),
              const SizedBox(height: AsmSpacing.space8),
              AsmPrimaryActionButton(
                key: const Key('passenger-clear-form'),
                onPressed: _clearForm,
                variant: AsmActionButtonVariant.text,
                icon: Icons.clear_outlined,
                label: 'Clear form',
                minimumHeight: 48,
              ),
              const SizedBox(height: AsmSpacing.space20),
              const AsmPilotNoticeBanner(
                message:
                    'This screen checks the phone and PIN format before '
                    'opening the passenger app.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
