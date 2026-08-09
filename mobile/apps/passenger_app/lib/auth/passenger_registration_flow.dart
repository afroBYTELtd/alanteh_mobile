import 'package:asm_auth/asm_auth.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';

import 'passenger_registration.dart';

enum _RegistrationStage { phone, details, pending }

class PassengerRegistrationFlow extends StatefulWidget {
  const PassengerRegistrationFlow({
    required this.submitter,
    required this.onBackToSignIn,
    this.idempotencyKeyFactory = PassengerRegistrationIdempotencyKey.generate,
    super.key,
  });

  final PassengerRegistrationSubmitter submitter;
  final VoidCallback onBackToSignIn;
  final String Function() idempotencyKeyFactory;

  @override
  State<PassengerRegistrationFlow> createState() =>
      _PassengerRegistrationFlowState();
}

class _PassengerRegistrationFlowState extends State<PassengerRegistrationFlow> {
  final _phoneFormKey = GlobalKey<FormState>();
  final _detailsFormKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _pinController = TextEditingController();
  final _confirmPinController = TextEditingController();

  _RegistrationStage _stage = _RegistrationStage.phone;
  String? _idempotencyKey;
  String? _registrationReference;
  String? _submissionError;
  bool _isSubmitting = false;
  bool _offlineRetryState = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _fullNameController.dispose();
    _pinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }

  void _continueToDetails() {
    final form = _phoneFormKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();

    setState(() {
      _idempotencyKey ??= widget.idempotencyKeyFactory();
      _stage = _RegistrationStage.details;
      _submissionError = null;
      _offlineRetryState = false;
    });
  }

  Future<void> _submitRegistration() async {
    final form = _detailsFormKey.currentState;
    if (form == null || !form.validate() || _isSubmitting) {
      return;
    }

    final idempotencyKey = _idempotencyKey;
    if (idempotencyKey == null || idempotencyKey.trim().isEmpty) {
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();

    setState(() {
      _isSubmitting = true;
      _submissionError = null;
      _offlineRetryState = false;
    });

    try {
      final result = await widget.submitter.submit(
        phoneNumber: _phoneController.text,
        fullName: _fullNameController.text,
        pin: _pinController.text,
        idempotencyKey: idempotencyKey,
      );

      if (!mounted) {
        return;
      }

      _pinController.clear();
      _confirmPinController.clear();

      setState(() {
        _registrationReference = result.registrationReference;
        _stage = _RegistrationStage.pending;
        _isSubmitting = false;
        _submissionError = null;
        _offlineRetryState = false;
      });
    } on PassengerRegistrationException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isSubmitting = false;
        _submissionError = error.message;
        _offlineRetryState =
            error.type == PassengerRegistrationFailureType.offline;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isSubmitting = false;
        _submissionError =
            ApiPassengerRegistrationSubmitter.invalidResponseMessage;
        _offlineRetryState = false;
      });
    }
  }

  void _backToSignIn() {
    FocusManager.instance.primaryFocus?.unfocus();
    _pinController.clear();
    _confirmPinController.clear();
    _idempotencyKey = null;
    widget.onBackToSignIn();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('passenger-registration-flow'),
      backgroundColor: AsmColors.passengerSurface,
      body: AsmScreenSurface(
        scrollable: true,
        padding: const EdgeInsets.fromLTRB(
          AsmSpacing.space16,
          AsmSpacing.space20,
          AsmSpacing.space16,
          AsmSpacing.space24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Image.asset(
              'assets/brand/alanteh_header_dark.png',
              key: const Key('passenger-registration-brand-logo'),
              width: 176,
              height: 56,
              fit: BoxFit.contain,
              alignment: Alignment.centerLeft,
              semanticLabel: 'ALANTEH passenger logo',
            ),
            const SizedBox(height: AsmSpacing.space16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AsmSpacing.space20),
              decoration: BoxDecoration(
                color: AsmColors.passengerCard,
                borderRadius: BorderRadius.circular(AsmRadii.radius28),
                border: Border.all(color: AsmColors.passengerLine),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x16000000),
                    blurRadius: 28,
                    offset: Offset(0, 14),
                  ),
                ],
              ),
              child: switch (_stage) {
                _RegistrationStage.phone => _buildPhoneStage(context),
                _RegistrationStage.details => _buildDetailsStage(context),
                _RegistrationStage.pending => _buildPendingStage(context),
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhoneStage(BuildContext context) {
    return Form(
      key: _phoneFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Create your account',
            key: Key('registration-phone-title'),
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              height: 1.08,
            ),
          ),
          const SizedBox(height: AsmSpacing.space8),
          Text(
            'Enter your Ghana phone number to get started.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AsmSpacing.space20),
          TextFormField(
            key: const Key('registration-phone-field'),
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _continueToDetails(),
            decoration: const InputDecoration(
              labelText: 'Phone number',
              hintText: '+233XXXXXXXXX',
              border: OutlineInputBorder(),
            ),
            validator: (value) => validateGhanaPhoneNumberForLogin(value ?? ''),
          ),
          const SizedBox(height: AsmSpacing.space20),
          AsmPrimaryActionButton(
            key: const Key('registration-continue'),
            onPressed: _continueToDetails,
            label: 'Continue',
          ),
          const SizedBox(height: AsmSpacing.space8),
          AsmPrimaryActionButton(
            key: const Key('registration-existing-account-sign-in'),
            onPressed: _backToSignIn,
            variant: AsmActionButtonVariant.text,
            label: 'Already have an account? Sign in',
            minimumHeight: 48,
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsStage(BuildContext context) {
    return Form(
      key: _detailsFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Your details',
            key: Key('registration-details-title'),
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              height: 1.08,
            ),
          ),
          const SizedBox(height: AsmSpacing.space8),
          Text(
            'Tell us your name and choose a PIN.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AsmSpacing.space20),
          TextFormField(
            key: const Key('registration-full-name-field'),
            controller: _fullNameController,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Full name',
              border: OutlineInputBorder(),
            ),
            validator: (value) =>
                validatePassengerRegistrationName(value ?? ''),
          ),
          const SizedBox(height: AsmSpacing.space12),
          TextFormField(
            key: const Key('registration-pin-field'),
            controller: _pinController,
            obscureText: true,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'PIN',
              border: OutlineInputBorder(),
            ),
            validator: (value) => validatePassengerRegistrationPin(value ?? ''),
          ),
          const SizedBox(height: AsmSpacing.space12),
          TextFormField(
            key: const Key('registration-confirm-pin-field'),
            controller: _confirmPinController,
            obscureText: true,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _submitRegistration(),
            decoration: const InputDecoration(
              labelText: 'Confirm PIN',
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              final pinValidation = validatePassengerRegistrationPin(
                value ?? '',
              );
              if (pinValidation != null) {
                return pinValidation;
              }
              return validatePassengerRegistrationPinConfirmation(
                _pinController.text,
                value ?? '',
              );
            },
          ),
          if (_submissionError != null) ...[
            const SizedBox(height: AsmSpacing.space12),
            _RegistrationErrorPanel(message: _submissionError!),
          ],
          const SizedBox(height: AsmSpacing.space20),
          AsmPrimaryActionButton(
            key: const Key('registration-create-account'),
            onPressed: _isSubmitting ? null : _submitRegistration,
            label: _isSubmitting ? 'Creating account...' : 'Create account',
          ),
          if (_offlineRetryState) ...[
            const SizedBox(height: AsmSpacing.space8),
            AsmPrimaryActionButton(
              key: const Key('registration-offline-retry'),
              onPressed: _isSubmitting ? null : _submitRegistration,
              variant: AsmActionButtonVariant.outlined,
              label: 'Retry',
              minimumHeight: 48,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPendingStage(BuildContext context) {
    final reference = _registrationReference ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Account submitted',
          key: Key('registration-pending-title'),
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w900,
            height: 1.08,
          ),
        ),
        const SizedBox(height: AsmSpacing.space16),
        const Text(
          'Your account is being reviewed.',
          key: Key('registration-pending-review-message'),
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            height: 1.35,
          ),
        ),
        const SizedBox(height: AsmSpacing.space8),
        Text(
          'We will notify you when it is approved — usually within a few hours.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            height: 1.45,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AsmSpacing.space20),
        Text(
          'Reference: $reference',
          key: const Key('registration-reference'),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: AsmSpacing.space20),
        AsmPrimaryActionButton(
          key: const Key('registration-back-to-sign-in'),
          onPressed: _backToSignIn,
          label: 'Back to sign in',
        ),
      ],
    );
  }
}

class _RegistrationErrorPanel extends StatelessWidget {
  const _RegistrationErrorPanel({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    const backgroundColor = Color(0xFFFFF3E0);
    const foregroundColor = Color(0xFF8A4B00);

    return Container(
      key: const Key('registration-error'),
      width: double.infinity,
      padding: const EdgeInsets.all(AsmSpacing.space12),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(AsmRadii.radius8),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: foregroundColor,
          fontWeight: FontWeight.w700,
          height: 1.35,
        ),
      ),
    );
  }
}
