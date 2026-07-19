import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pinput/pinput.dart';

class PassengerOtpVerificationScreen extends StatefulWidget {
  const PassengerOtpVerificationScreen({
    required this.onVerified,
    required this.onUseAnotherNumber,
    this.phoneNumber,
    super.key,
  });

  final String? phoneNumber;
  final VoidCallback onVerified;
  final Future<void> Function() onUseAnotherNumber;

  @override
  State<PassengerOtpVerificationScreen> createState() =>
      _PassengerOtpVerificationScreenState();
}

class _PassengerOtpVerificationScreenState
    extends State<PassengerOtpVerificationScreen> {
  final TextEditingController _controller = TextEditingController();

  String? _errorMessage;
  bool _isComplete = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _verify() {
    final code = _controller.text.trim();

    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() {
        _errorMessage = 'Enter the complete six-digit verification code.';
      });
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    widget.onVerified();
  }

  void _clearCode() {
    _controller.clear();
    setState(() {
      _isComplete = false;
      _errorMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final pinTheme = PinTheme(
      width: 44,
      height: 54,
      textStyle: const TextStyle(
        color: Color(0xFF171B12),
        fontSize: 20,
        fontWeight: FontWeight.w800,
      ),
      decoration: BoxDecoration(
        color: AsmColors.passengerCard,
        borderRadius: BorderRadius.circular(AsmRadii.radius16),
        border: Border.all(color: AsmColors.passengerLine, width: 1.4),
      ),
    );

    final focusedPinTheme = pinTheme.copyWith(
      decoration: pinTheme.decoration?.copyWith(
        border: Border.all(color: AsmColors.brandGreen, width: 2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x241C5C3C),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
    );

    return Scaffold(
      key: const Key('passenger-otp-screen'),
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
              key: const Key('passenger-otp-brand-logo'),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'SECURE ACCESS',
                    style: TextStyle(
                      color: AsmColors.brandGreen,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: AsmSpacing.space12),
                  const Text(
                    'Verify your phone',
                    style: TextStyle(
                      color: Color(0xFF171B12),
                      fontSize: 27,
                      fontWeight: FontWeight.w900,
                      height: 1.08,
                    ),
                  ),
                  const SizedBox(height: AsmSpacing.space8),
                  Text(
                    'Enter the six-digit verification code to continue.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      height: 1.45,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (_maskedPhone(widget.phoneNumber) case final phone?) ...[
                    const SizedBox(height: AsmSpacing.space8),
                    Text(
                      phone,
                      key: const Key('passenger-otp-masked-phone'),
                      style: const TextStyle(
                        color: AsmColors.brandGreen,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                  const SizedBox(height: AsmSpacing.space24),
                  Center(
                    child: Pinput(
                      key: const Key('passenger-otp-input'),
                      controller: _controller,
                      length: 6,
                      autofocus: false,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      defaultPinTheme: pinTheme,
                      focusedPinTheme: focusedPinTheme,
                      submittedPinTheme: focusedPinTheme,
                      onChanged: (value) {
                        setState(() {
                          _isComplete = value.length == 6;
                          _errorMessage = null;
                        });
                      },
                    ),
                  ),
                  if (_errorMessage case final message?) ...[
                    const SizedBox(height: AsmSpacing.space12),
                    Text(
                      message,
                      key: const Key('passenger-otp-error'),
                      style: const TextStyle(
                        color: Color(0xFF9F352E),
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                  ],
                  const SizedBox(height: AsmSpacing.space24),
                  AsmPrimaryActionButton(
                    key: const Key('passenger-otp-verify'),
                    onPressed: _isComplete ? _verify : null,
                    icon: Icons.verified_user_outlined,
                    label: 'Verify and continue',
                  ),
                  const SizedBox(height: AsmSpacing.space8),
                  AsmPrimaryActionButton(
                    key: const Key('passenger-otp-clear'),
                    onPressed: _controller.text.isEmpty ? null : _clearCode,
                    variant: AsmActionButtonVariant.text,
                    icon: Icons.backspace_outlined,
                    label: 'Clear code',
                    minimumHeight: 48,
                  ),
                  const SizedBox(height: AsmSpacing.space4),
                  AsmPrimaryActionButton(
                    key: const Key('passenger-otp-use-another-number'),
                    onPressed: () {
                      widget.onUseAnotherNumber();
                    },
                    variant: AsmActionButtonVariant.text,
                    icon: Icons.phone_outlined,
                    label: 'Use another number',
                    minimumHeight: 48,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AsmSpacing.space16),
            const AsmPilotNoticeBanner(
              message:
                  'Your verification code is private. Never share it with a driver.',
            ),
          ],
        ),
      ),
    );
  }
}

String? _maskedPhone(String? value) {
  final normalized = value?.trim();

  if (normalized == null || normalized.isEmpty) {
    return null;
  }

  final digits = normalized.replaceAll(RegExp(r'\D'), '');

  if (digits.startsWith('233') && digits.length >= 12) {
    final network = digits.substring(3, 5);
    final ending = digits.substring(digits.length - 3);
    return '+233 $network ****$ending';
  }

  if (digits.length >= 4) {
    return 'Phone ending ${digits.substring(digits.length - 4)}';
  }

  return 'Phone number verified';
}
