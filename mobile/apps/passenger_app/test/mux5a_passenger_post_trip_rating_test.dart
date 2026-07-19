import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passenger_app/payment_rating/passenger_local_rating_store.dart';
import 'package:passenger_app/payment_rating/passenger_payment_rating_contract.dart';
import 'package:passenger_app/payment_rating/passenger_payment_rating_page.dart';
import 'package:passenger_app/ride_requests/ride_request_history.dart';
import 'package:passenger_app/tracking/ride_tracking_screen.dart';

void main() {
  testWidgets(
    'confirmed backend receipt shows trip fare date method and rating entry',
    (tester) async {
      final repository = _PostTripRepository(
        fare: _fare(),
        payment: _confirmedPayment(),
        receipt: _receipt(),
        rating: _openRating(),
      );

      await _pumpPage(
        tester,
        repository,
        pickup: 'Accra Mall',
        destination: 'Accra Market',
      );

      expect(find.byKey(const Key('payment-confirmed-state')), findsOneWidget);
      expect(find.byKey(const Key('payment-receipt-state')), findsOneWidget);
      expect(find.text('Trip receipt'), findsOneWidget);
      expect(find.text('Accra Mall'), findsOneWidget);
      expect(find.text('Accra Market'), findsOneWidget);
      expect(find.text('GHS 45'), findsNWidgets(2));
      expect(find.text('MTN Mobile Money'), findsOneWidget);
      expect(find.text('PAY-BACKEND-MUX5A'), findsOneWidget);
      expect(find.text('Jul 17, 2026 • 4:33 PM'), findsOneWidget);
      expect(find.byKey(const Key('open-rating-from-receipt')), findsOneWidget);
      expect(find.byKey(const Key('rating-open-state')), findsNothing);

      await tester.ensureVisible(
        find.byKey(const Key('open-rating-from-receipt')),
      );
      await tester.tap(find.byKey(const Key('open-rating-from-receipt')));
      await tester.pump();

      expect(find.byKey(const Key('rating-open-state')), findsOneWidget);
      expect(find.text('How was your trip?'), findsOneWidget);
      expect(find.text('Accra Mall → Accra Market'), findsOneWidget);
    },
  );

  testWidgets('flutter rating bars preserve the accepted rating payload', (
    tester,
  ) async {
    final repository = _PostTripRepository(
      fare: _fare(ready: false),
      payment: _unavailablePayment(),
      receipt: _receipt(),
      rating: _openRating(),
      submittedRating: _submittedRating(),
    );

    await _pumpPage(tester, repository);

    await _selectScores(tester);

    await tester.enterText(
      find.byKey(const Key('rating-feedback-note')),
      '  Excellent ride.  ',
    );

    final submit = find.byKey(const Key('submit-rating'));
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(repository.submissions, hasLength(1));
    expect(repository.submissions.single.toJson(), <String, Object?>{
      'overall_score': 5,
      'comfort_score': 4,
      'conduct_score': 5,
      'cleanliness_score': 4,
      'feedback_note': 'Excellent ride.',
    });
    expect(find.byKey(const Key('rating-submitted-state')), findsOneWidget);
    expect(find.text('Thanks for your feedback'), findsOneWidget);
  });

  testWidgets(
    'unconfigured rating submission is stored only for the current session',
    (tester) async {
      final store = MemoryPassengerLocalRatingStore();
      final repository = _PostTripRepository(
        fare: _fare(ready: false),
        payment: _unavailablePayment(),
        receipt: _receipt(),
        rating: _openRating(),
        submissionError:
            const PassengerPaymentRatingException.connectionNotConfigured(),
      );

      await _pumpPage(tester, repository, localRatingStore: store);

      await _selectScores(tester);

      await tester.enterText(
        find.byKey(const Key('rating-feedback-note')),
        'Clean and comfortable.',
      );

      final submit = find.byKey(const Key('submit-rating'));
      await tester.ensureVisible(submit);
      await tester.pumpAndSettle();
      await tester.tap(submit);
      await tester.pumpAndSettle();

      final stored = store.read('RR-APP-MUX5A-RATING');

      expect(stored, isNotNull);
      expect(stored!.overallScore, 5);
      expect(stored.comfortScore, 4);
      expect(stored.conductScore, 5);
      expect(stored.cleanlinessScore, 4);
      expect(stored.feedbackNote, 'Clean and comfortable.');
      expect(
        find.byKey(const Key('rating-local-session-state')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('rating-submitted-state')), findsOneWidget);
      expect(find.byKey(const Key('payment-confirmed-state')), findsNothing);
    },
  );

  testWidgets('completed tracking opens the receipt with route context', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1200);
    tester.view.devicePixelRatio = 1;

    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final record = _completedRecord();
    final historyRepository = _TrackingHistoryRepository(record);
    final paymentRepository = _PostTripRepository(
      fare: _fare(),
      payment: _confirmedPayment(),
      receipt: _receipt(),
      rating: _openRating(),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: RideTrackingScreen(
          repository: historyRepository,
          requestReference: record.requestReference,
          initialRecord: record,
          pollInterval: const Duration(hours: 1),
          paymentRatingRepository: paymentRepository,
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final openReceipt = find.byKey(
      const Key('open-payment-rating-from-tracking'),
    );

    expect(openReceipt, findsOneWidget);

    await tester.ensureVisible(openReceipt);
    await tester.tap(openReceipt);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('payment-receipt-state')), findsOneWidget);
    expect(find.text('Accra Mall'), findsOneWidget);
    expect(find.text('Accra Market'), findsOneWidget);
    expect(find.byKey(const Key('open-rating-from-receipt')), findsOneWidget);
  });

  testWidgets('post-trip UI hides internal and prohibited wording', (
    tester,
  ) async {
    final repository = _PostTripRepository(
      fare: _fare(),
      payment: _confirmedPayment(),
      receipt: _receipt(),
      rating: _openRating(),
    );

    await _pumpPage(tester, repository);

    expect(find.textContaining('demo'), findsNothing);
    expect(find.textContaining('placeholder'), findsNothing);
    expect(find.textContaining('Paystack'), findsNothing);
    expect(find.textContaining('wallet'), findsNothing);
    expect(find.textContaining('driver earnings'), findsNothing);
    expect(find.textContaining('surge'), findsNothing);
    expect(find.textContaining('Control Center'), findsNothing);
  });
}

Future<void> _selectScores(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('rating-overall-5')));
  await tester.pump();

  await tester.tap(find.byKey(const Key('rating-comfort-4')));
  await tester.pump();

  await tester.tap(find.byKey(const Key('rating-driver-conduct-5')));
  await tester.pump();

  await tester.tap(find.byKey(const Key('rating-cleanliness-4')));
  await tester.pump();
}

Future<void> _pumpPage(
  WidgetTester tester,
  _PostTripRepository repository, {
  String? pickup,
  String? destination,
  PassengerLocalRatingStore? localRatingStore,
}) async {
  tester.view.physicalSize = const Size(430, 1300);
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
        requestReference: 'RR-APP-MUX5A-RATING',
        pickupDescription: pickup,
        destinationDescription: destination,
        tripCompletedAt: DateTime(2026, 7, 17, 16, 33),
        localRatingStore: localRatingStore,
      ),
    ),
  );

  await tester.pumpAndSettle();
}

PassengerFareSnapshot _fare({bool ready = true}) {
  return PassengerFareSnapshot(
    requestReference: 'RR-APP-MUX5A-RATING',
    tripReference: 'TRIP-MUX5A',
    fareStatus: ready ? 'fare_ready' : 'fare_not_ready',
    amount: ready ? 45 : null,
    currency: ready ? 'GHS' : null,
    canPay: ready,
  );
}

PassengerPaymentSnapshot _confirmedPayment() {
  return PassengerPaymentSnapshot(
    requestReference: 'RR-APP-MUX5A-RATING',
    tripReference: 'TRIP-MUX5A',
    paymentStatus: 'payment_confirmed',
    amount: 45,
    currency: 'GHS',
    canPay: false,
    canRetry: false,
    paymentProvider: 'accepted-provider',
    paymentMethodLabel: 'MTN Mobile Money',
    paymentReference: 'PAY-BACKEND-MUX5A',
    updatedAt: DateTime(2026, 7, 17, 16, 33),
  );
}

PassengerPaymentSnapshot _unavailablePayment() {
  return const PassengerPaymentSnapshot(
    requestReference: 'RR-APP-MUX5A-RATING',
    tripReference: 'TRIP-MUX5A',
    paymentStatus: 'payment_not_available',
    canPay: false,
    canRetry: false,
  );
}

PassengerPaymentReceiptSnapshot _receipt() {
  return PassengerPaymentReceiptSnapshot(
    requestReference: 'RR-APP-MUX5A-RATING',
    tripReference: 'TRIP-MUX5A',
    receiptStatus: 'receipt_available',
    amount: 45,
    currency: 'GHS',
    paymentStatus: 'payment_confirmed',
    paymentProvider: 'accepted-provider',
    paymentMethodLabel: 'MTN Mobile Money',
    paymentReference: 'PAY-BACKEND-MUX5A',
    updatedAt: DateTime(2026, 7, 17, 16, 33),
  );
}

PassengerRatingSnapshot _openRating() {
  return const PassengerRatingSnapshot(
    requestReference: 'RR-APP-MUX5A-RATING',
    tripReference: 'TRIP-MUX5A',
    ratingStatus: 'rating_open',
    canRate: true,
  );
}

PassengerRatingSnapshot _submittedRating() {
  return const PassengerRatingSnapshot(
    requestReference: 'RR-APP-MUX5A-RATING',
    tripReference: 'TRIP-MUX5A',
    ratingStatus: 'rating_submitted',
    canRate: false,
    overallScore: 5,
    comfortScore: 4,
    conductScore: 5,
    cleanlinessScore: 4,
    feedbackNote: 'Excellent ride.',
  );
}

PassengerRideRequestRecord _completedRecord() {
  return PassengerRideRequestRecord(
    requestReference: 'RR-APP-MUX5A-RATING',
    status: 'completed',
    pickupLocation: 'Accra Mall',
    destination: 'Accra Market',
    passengerCount: 1,
    createdAt: DateTime(2026, 7, 17, 16),
    updatedAt: DateTime(2026, 7, 17, 16, 33),
    hasMobileReceipt: true,
    tripCreated: true,
    latestStaffState: 'arrived at destination',
  );
}

class _TrackingHistoryRepository
    implements PassengerRideRequestHistoryRepository {
  const _TrackingHistoryRepository(this.record);

  final PassengerRideRequestRecord record;

  @override
  Future<List<PassengerRideRequestRecord>> fetchRequests() async {
    return <PassengerRideRequestRecord>[record];
  }

  @override
  Future<PassengerRideRequestRecord> fetchRequest(
    String requestReference,
  ) async {
    return record;
  }
}

class _PostTripRepository implements PassengerPaymentRatingRepository {
  _PostTripRepository({
    required this.fare,
    required this.payment,
    required this.receipt,
    required this.rating,
    this.submittedRating,
    this.submissionError,
  });

  final PassengerFareSnapshot fare;
  PassengerPaymentSnapshot payment;
  final PassengerPaymentReceiptSnapshot receipt;
  PassengerRatingSnapshot rating;
  final PassengerRatingSnapshot? submittedRating;
  final PassengerPaymentRatingException? submissionError;

  final List<PassengerRatingSubmission> submissions =
      <PassengerRatingSubmission>[];

  @override
  Future<PassengerFareSnapshot> fetchFare(String requestReference) async {
    return fare;
  }

  @override
  Future<PassengerPaymentSnapshot> fetchPayment(String requestReference) async {
    return payment;
  }

  @override
  Future<PassengerPaymentSnapshot> initiatePayment(
    String requestReference, {
    required String idempotencyKey,
  }) async {
    return payment;
  }

  @override
  Future<PassengerPaymentReceiptSnapshot> fetchReceipt(
    String requestReference,
  ) async {
    return receipt;
  }

  @override
  Future<PassengerRatingSnapshot> fetchRating(String requestReference) async {
    return rating;
  }

  @override
  Future<PassengerRatingSnapshot> submitRating(
    String requestReference,
    PassengerRatingSubmission submission,
  ) async {
    submissions.add(submission);

    final error = submissionError;

    if (error != null) {
      throw error;
    }

    final result = submittedRating ?? _submittedRating();
    rating = result;
    return result;
  }
}
