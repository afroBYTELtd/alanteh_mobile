import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passenger_app/account/passenger_account_screen.dart';
import 'package:passenger_app/account/passenger_payment_setup_screen.dart';
import 'package:passenger_app/passenger_shell.dart';

void main() {
  testWidgets('Account shows approved member and payment details', (
    tester,
  ) async {
    var openedPaymentSetup = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: PassengerAccountScreen(
          phoneNumber: '+233559991234',
          onOpenTrips: () {},
          onOpenPaymentSetup: () {
            openedPaymentSetup = true;
          },
          onSignOut: () {},
        ),
      ),
    );

    expect(find.text('ALANTEH Member'), findsOneWidget);
    expect(find.text('Riding clean with ALANTEH.'), findsOneWidget);
    expect(find.text('+233 55 ****234'), findsOneWidget);
    expect(find.text('+233559991234'), findsNothing);
    expect(find.text('MTN MoMo'), findsOneWidget);

    expect(
      find.byKey(const Key('passenger-account-payment-method')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('passenger-account-my-trips')), findsOneWidget);
    expect(find.byKey(const Key('passenger-account-help')), findsOneWidget);
    expect(find.byKey(const Key('passenger-account-settings')), findsOneWidget);
    expect(find.byKey(const Key('passenger-account-sign-out')), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const Key('passenger-account-payment-method')),
    );
    await tester.tap(find.byKey(const Key('passenger-account-payment-method')));

    expect(openedPaymentSetup, isTrue);
  });

  testWidgets('Payment setup defaults safely to MTN Mobile Money', (
    tester,
  ) async {
    PassengerMobileMoneyNetwork? savedNetwork;

    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: PassengerPaymentSetupScreen(
          phoneNumber: '+233559991234',
          onSaved: (network) {
            savedNetwork = network;
          },
        ),
      ),
    );

    expect(
      find.byKey(const Key('passenger-payment-setup-screen')),
      findsOneWidget,
    );
    expect(find.text('MTN Mobile Money'), findsOneWidget);
    expect(find.text('Telecel Cash'), findsOneWidget);
    expect(find.text('AirtelTigo Money'), findsOneWidget);
    expect(find.text('+233 55 999 1234'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const Key('passenger-payment-setup-save')),
    );
    await tester.tap(find.byKey(const Key('passenger-payment-setup-save')));
    await tester.pump();

    expect(savedNetwork, PassengerMobileMoneyNetwork.mtn);
  });

  testWidgets('Passenger shell retains payment choice for the session', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: const PassengerShell(phoneNumber: '+233559991234'),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Account'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('passenger-account-screen')), findsOneWidget);
    expect(find.text('MTN MoMo'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const Key('passenger-account-payment-method')),
    );
    await tester.tap(find.byKey(const Key('passenger-account-payment-method')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.byKey(const Key('passenger-payment-setup-screen')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('passenger-payment-network-telecel')),
    );
    await tester.pump();

    await tester.ensureVisible(
      find.byKey(const Key('passenger-payment-setup-save')),
    );
    await tester.tap(find.byKey(const Key('passenger-payment-setup-save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('passenger-account-screen')), findsOneWidget);
    expect(
      find.byKey(const Key('passenger-account-payment-method-label')),
      findsOneWidget,
    );

    final paymentMethodLabel = tester.widget<Text>(
      find.byKey(const Key('passenger-account-payment-method-label')),
    );

    expect(paymentMethodLabel.data, 'Telecel Cash');
  });

  testWidgets('Account and payment setup hide internal wording', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: PassengerAccountScreen(
          phoneNumber: '+233559991234',
          onOpenTrips: () {},
          onOpenPaymentSetup: () {},
          onSignOut: () {},
        ),
      ),
    );

    expect(find.textContaining('demo'), findsNothing);
    expect(find.textContaining('placeholder'), findsNothing);
    expect(find.textContaining('backend'), findsNothing);
    expect(find.textContaining('Control Center'), findsNothing);
    expect(find.textContaining('Paystack'), findsNothing);
  });
}
