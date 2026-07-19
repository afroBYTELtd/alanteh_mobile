import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passenger_app/auth/passenger_otp_verification_screen.dart';

void main() {
  testWidgets('OTP accepts a complete six-digit code', (tester) async {
    var verified = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: PassengerOtpVerificationScreen(
          phoneNumber: '+233559991234',
          onVerified: () => verified = true,
          onUseAnotherNumber: () async {},
        ),
      ),
    );

    expect(find.byKey(const Key('passenger-otp-screen')), findsOneWidget);
    expect(find.text('+233 55 ****234'), findsOneWidget);
    expect(find.text('+233559991234'), findsNothing);

    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('passenger-otp-input')),
        matching: find.byType(EditableText),
      ),
      '123456',
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('passenger-otp-verify')));
    await tester.pump();

    expect(verified, isTrue);
  });

  testWidgets('OTP blocks incomplete input', (tester) async {
    var verified = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: PassengerOtpVerificationScreen(
          onVerified: () => verified = true,
          onUseAnotherNumber: () async {},
        ),
      ),
    );

    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('passenger-otp-input')),
        matching: find.byType(EditableText),
      ),
      '12345',
    );
    await tester.pump();

    final button = tester.widget<FilledButton>(
      find.byKey(const Key('passenger-otp-verify')),
    );

    expect(button.onPressed, isNull);
    expect(verified, isFalse);
  });

  testWidgets('OTP can return to phone sign in', (tester) async {
    var returned = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: PassengerOtpVerificationScreen(
          phoneNumber: '+233559991234',
          onVerified: () {},
          onUseAnotherNumber: () async {
            returned = true;
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('passenger-otp-use-another-number')));
    await tester.pump();

    expect(returned, isTrue);
  });

  testWidgets('OTP screen contains no internal implementation wording', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: PassengerOtpVerificationScreen(
          phoneNumber: '+233559991234',
          onVerified: () {},
          onUseAnotherNumber: () async {},
        ),
      ),
    );

    expect(find.textContaining('demo'), findsNothing);
    expect(find.textContaining('placeholder'), findsNothing);
    expect(find.textContaining('backend'), findsNothing);
    expect(find.textContaining('local QA'), findsNothing);
  });
}
