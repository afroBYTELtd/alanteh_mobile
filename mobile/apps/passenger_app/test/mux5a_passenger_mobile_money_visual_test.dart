import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passenger_app/account/passenger_payment_setup_screen.dart';
import 'package:passenger_app/payment_rating/passenger_payment_rating_contract.dart';
import 'package:passenger_app/payment_rating/passenger_payment_rating_page.dart';

void main() {
  testWidgets('payment request advances only to the waiting-for-phone state', (
    tester,
  ) async {
    final repository = _PaymentVisualRepository(
      payment: _payment(status: 'not_started'),
      initiatedPayment: _payment(status: 'pending'),
    );

    await _pumpPaymentPage(tester, repository);

    expect(find.byKey(const Key('payment-prompt-state')), findsOneWidget);
    expect(find.text('Pay with Mobile Money'), findsOneWidget);
    expect(find.text('GHS 45'), findsWidgets);
    expect(find.text('+233 55 999 1234'), findsOneWidget);
    expect(find.text('MTN Mobile Money'), findsOneWidget);
    expect(find.text('Telecel Cash'), findsOneWidget);
    expect(find.text('AirtelTigo Money'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const Key('passenger-payment-flow-network-telecel')),
    );
    await tester.tap(
      find.byKey(const Key('passenger-payment-flow-network-telecel')),
    );
    await tester.pump();

    await tester.ensureVisible(find.byKey(const Key('initiate-payment')));
    await tester.tap(find.byKey(const Key('initiate-payment')));
    await tester.pumpAndSettle();

    expect(repository.initiationCalls, 1);
    expect(find.byKey(const Key('payment-pending-state')), findsOneWidget);
    expect(find.text('Check your phone'), findsOneWidget);
    expect(find.text('WAITING FOR APPROVAL…'), findsOneWidget);
    expect(find.byKey(const Key('payment-pin-safety-message')), findsOneWidget);
    expect(find.byKey(const Key('payment-confirmed-state')), findsNothing);
    expect(find.byKey(const Key('payment-receipt-state')), findsNothing);
    expect(repository.receiptCalls, 0);
  });

  testWidgets('pending payment supports safe resend and local cancellation', (
    tester,
  ) async {
    final repository = _PaymentVisualRepository(
      payment: _payment(status: 'pending'),
      initiatedPayment: _payment(status: 'pending'),
    );

    await _pumpPaymentPage(tester, repository);

    expect(find.byKey(const Key('payment-pending-state')), findsOneWidget);
    expect(find.byKey(const Key('refresh-payment-status')), findsOneWidget);
    expect(find.byKey(const Key('payment-resend-prompt')), findsOneWidget);
    expect(find.byKey(const Key('payment-cancel-local')), findsOneWidget);
    expect(find.byKey(const Key('payment-confirmed-state')), findsNothing);

    await tester.ensureVisible(find.byKey(const Key('payment-resend-prompt')));
    await tester.tap(find.byKey(const Key('payment-resend-prompt')));
    await tester.pumpAndSettle();

    expect(repository.initiationCalls, 1);
    expect(find.byKey(const Key('payment-confirmed-state')), findsNothing);

    await tester.ensureVisible(find.byKey(const Key('payment-cancel-local')));
    await tester.tap(find.byKey(const Key('payment-cancel-local')));
    await tester.pump();

    expect(
      find.text('Payment request cancelled. No charge was made.'),
      findsOneWidget,
    );
  });

  testWidgets('failed payment shows no-charge state and safe retry', (
    tester,
  ) async {
    final repository = _PaymentVisualRepository(
      payment: _payment(status: 'failed'),
      initiatedPayment: _payment(status: 'pending'),
    );

    await _pumpPaymentPage(tester, repository);

    expect(find.byKey(const Key('payment-failed-state')), findsOneWidget);
    expect(find.text('Payment didn’t go through'), findsOneWidget);
    expect(
      find.byKey(const Key('payment-failed-no-charge-message')),
      findsOneWidget,
    );
    expect(find.textContaining('No charge was made.'), findsOneWidget);
    expect(find.byKey(const Key('retry-payment')), findsOneWidget);
    expect(find.byKey(const Key('payment-confirmed-state')), findsNothing);
  });

  testWidgets('payment visual flow hides internal and fake-success wording', (
    tester,
  ) async {
    final repository = _PaymentVisualRepository(
      payment: _payment(status: 'not_started'),
      initiatedPayment: _payment(status: 'pending'),
    );

    await _pumpPaymentPage(tester, repository);

    expect(find.textContaining('demo'), findsNothing);
    expect(find.textContaining('placeholder'), findsNothing);
    expect(find.textContaining('Paystack'), findsNothing);
    expect(find.textContaining('wallet'), findsNothing);
    expect(find.textContaining('payment successful'), findsNothing);
    expect(find.textContaining('payment succeeded'), findsNothing);
    expect(find.textContaining('Control Center'), findsNothing);
  });
}

Future<void> _pumpPaymentPage(
  WidgetTester tester,
  _PaymentVisualRepository repository,
) async {
  tester.view.physicalSize = const Size(430, 1200);
  tester.view.devicePixelRatio = 1;

  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    MaterialApp(
      theme: AsmThemes.passenger,
      home: PassengerPaymentRatingPage(
        repository: repository,
        requestReference: 'RR-APP-MUX5A',
        phoneNumber: '+233559991234',
        initialPaymentNetwork: PassengerMobileMoneyNetwork.mtn,
      ),
    ),
  );

  await tester.pumpAndSettle();
}

PassengerFareSnapshot _fare() {
  return const PassengerFareSnapshot(
    requestReference: 'RR-APP-MUX5A',
    fareStatus: 'fare_ready',
    amount: 45,
    currency: 'GHS',
    canPay: true,
  );
}

PassengerPaymentSnapshot _payment({required String status}) {
  return PassengerPaymentSnapshot(
    requestReference: 'RR-APP-MUX5A',
    paymentStatus: status,
    amount: 45,
    currency: 'GHS',
    canPay: true,
    canRetry: true,
    paymentMethodLabel: 'MTN Mobile Money',
  );
}

PassengerRatingSnapshot _rating() {
  return const PassengerRatingSnapshot(
    requestReference: 'RR-APP-MUX5A',
    ratingStatus: 'rating_not_open',
    canRate: false,
  );
}

class _PaymentVisualRepository implements PassengerPaymentRatingRepository {
  _PaymentVisualRepository({
    required this._payment,
    required this.initiatedPayment,
  });

  PassengerPaymentSnapshot _payment;
  final PassengerPaymentSnapshot initiatedPayment;

  int initiationCalls = 0;
  int receiptCalls = 0;

  @override
  Future<PassengerFareSnapshot> fetchFare(String requestReference) async {
    return _fare();
  }

  @override
  Future<PassengerPaymentSnapshot> fetchPayment(String requestReference) async {
    return _payment;
  }

  @override
  Future<PassengerPaymentSnapshot> initiatePayment(
    String requestReference, {
    required String idempotencyKey,
  }) async {
    initiationCalls += 1;
    _payment = initiatedPayment;
    return initiatedPayment;
  }

  @override
  Future<PassengerPaymentReceiptSnapshot> fetchReceipt(
    String requestReference,
  ) {
    receiptCalls += 1;

    return Future<PassengerPaymentReceiptSnapshot>.error(
      const PassengerPaymentRatingException.notFound(),
    );
  }

  @override
  Future<PassengerRatingSnapshot> fetchRating(String requestReference) async {
    return _rating();
  }

  @override
  Future<PassengerRatingSnapshot> submitRating(
    String requestReference,
    PassengerRatingSubmission submission,
  ) {
    return Future<PassengerRatingSnapshot>.error(
      StateError('Rating submission was not expected in the payment tests.'),
    );
  }
}
