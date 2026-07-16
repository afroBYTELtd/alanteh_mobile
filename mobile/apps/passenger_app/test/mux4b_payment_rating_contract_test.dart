import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_auth/asm_auth.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passenger_app/payment_rating/passenger_payment_rating_contract.dart';
import 'package:passenger_app/payment_rating/passenger_payment_rating_page.dart';

void main() {
  group('Passenger payment and rating contract', () {
    test(
      'uses the six accepted endpoint paths and exact request payloads',
      () async {
        final tokenStore = MemoryAuthTokenStore();
        await tokenStore.saveTokens(
          AuthTokens(accessToken: 'access', refreshToken: 'refresh'),
        );

        final gateway = _RecordingPaymentRatingGateway(
          results: <_GatewayResult>[
            _GatewayResult.success(_fareJson()),
            _GatewayResult.success(_paymentJson()),
            _GatewayResult.success(_paymentJson(status: 'pending')),
            _GatewayResult.success(_receiptJson()),
            _GatewayResult.success(
              _ratingJson(
                status: 'rating_submitted',
                canRate: false,
                includeScores: true,
              ),
            ),
            _GatewayResult.success(
              _ratingJson(
                status: 'rating_submitted',
                canRate: false,
                includeScores: true,
              ),
            ),
          ],
        );

        final repository = ApiPassengerPaymentRatingRepository(
          gateway,
          tokenStore: tokenStore,
        );

        await repository.fetchFare(' RR/APP-1 ');
        await repository.initiatePayment(
          ' RR/APP-1 ',
          idempotencyKey: 'APP-PAY-SAME-KEY',
        );
        await repository.fetchPayment(' RR/APP-1 ');
        await repository.fetchReceipt(' RR/APP-1 ');
        await repository.submitRating(
          ' RR/APP-1 ',
          PassengerRatingSubmission(
            overallScore: 5,
            comfortScore: 4,
            conductScore: 5,
            cleanlinessScore: 4,
            feedbackNote: '  Quiet and comfortable.  ',
          ),
        );
        await repository.fetchRating(' RR/APP-1 ');

        expect(
          gateway.calls.map((call) => '${call.method} ${call.path}'),
          <String>[
            'GET /api/passenger/rides/RR%2FAPP-1/fare/',
            'POST /api/passenger/rides/RR%2FAPP-1/payment/',
            'GET /api/passenger/rides/RR%2FAPP-1/payment/',
            'GET /api/passenger/rides/RR%2FAPP-1/payment/receipt/',
            'POST /api/passenger/rides/RR%2FAPP-1/rating/',
            'GET /api/passenger/rides/RR%2FAPP-1/rating/',
          ],
        );

        expect(gateway.calls[1].headers, <String, String>{
          'Idempotency-Key': 'APP-PAY-SAME-KEY',
        });
        expect(gateway.calls[1].data, const <String, Object?>{});

        expect(gateway.calls[4].data, <String, Object?>{
          'overall_score': 5,
          'comfort_score': 4,
          'conduct_score': 5,
          'cleanliness_score': 4,
          'feedback_note': 'Quiet and comfortable.',
        });
      },
    );

    test('fare without backend amount never creates a display amount', () {
      final fare = PassengerFareSnapshot.fromJson(
        _fareJson(status: 'fare_not_ready', amount: null, canPay: false),
      );

      expect(fare.isNotReady, isTrue);
      expect(fare.hasAuthoritativeAmount, isFalse);
      expect(fare.formattedAmount, isNull);
      expect(fare.canPay, isFalse);
    });

    test('confirmed payment requires an accepted backend status', () {
      final confirmed = PassengerPaymentSnapshot.fromJson(
        _paymentJson(status: 'payment_confirmed'),
      );
      final pending = PassengerPaymentSnapshot.fromJson(
        _paymentJson(status: 'pending'),
      );
      final failed = PassengerPaymentSnapshot.fromJson(
        _paymentJson(status: 'failed'),
      );
      final unknown = PassengerPaymentSnapshot.fromJson(
        _paymentJson(status: 'not_started'),
      );

      expect(confirmed.isConfirmed, isTrue);
      expect(pending.isConfirmed, isFalse);
      expect(pending.isPending, isTrue);
      expect(failed.isConfirmed, isFalse);
      expect(failed.isFailed, isTrue);
      expect(unknown.isConfirmed, isFalse);
    });

    test('receipt unavailable response contains no generated receipt data', () {
      final receipt = PassengerPaymentReceiptSnapshot.fromJson(
        _receiptJson(
          status: 'receipt_not_available',
          amount: null,
          paymentReference: null,
        ),
      );

      expect(receipt.isAvailable, isFalse);
      expect(receipt.formattedAmount, isNull);
      expect(receipt.paymentReference, isNull);
    });

    test('rating submission accepts only scores from one through five', () {
      for (final invalidScore in <int>[0, 6]) {
        expect(
          () => PassengerRatingSubmission(
            overallScore: invalidScore,
            comfortScore: 5,
            conductScore: 5,
            cleanlinessScore: 5,
          ),
          throwsArgumentError,
        );
      }

      final submission = PassengerRatingSubmission(
        overallScore: 5,
        comfortScore: 4,
        conductScore: 3,
        cleanlinessScore: 2,
      );

      expect(submission.toJson(), <String, Object?>{
        'overall_score': 5,
        'comfort_score': 4,
        'conduct_score': 3,
        'cleanliness_score': 2,
      });
    });

    test('missing access token blocks every backend call', () async {
      final gateway = _RecordingPaymentRatingGateway(
        results: const <_GatewayResult>[],
      );
      final repository = ApiPassengerPaymentRatingRepository(
        gateway,
        tokenStore: MemoryAuthTokenStore(),
      );

      await expectLater(
        repository.fetchFare('RR-APP-1'),
        throwsA(
          isA<PassengerPaymentRatingException>()
              .having((error) => error.requiresSignIn, 'requiresSignIn', isTrue)
              .having(
                (error) => error.message,
                'message',
                PassengerPaymentRatingException.sessionExpiredMessage,
              ),
        ),
      );

      expect(gateway.calls, isEmpty);
    });

    test('first 401 refreshes once and retries the same request', () async {
      final tokenStore = MemoryAuthTokenStore();
      await tokenStore.saveTokens(
        AuthTokens(
          accessToken: 'expired-access',
          refreshToken: 'stored-refresh',
        ),
      );

      final gateway = _RecordingPaymentRatingGateway(
        results: <_GatewayResult>[
          _GatewayResult.failure(
            const AsmApiException(
              type: AsmApiExceptionType.authentication,
              message: 'Authentication failed.',
              statusCode: 401,
            ),
          ),
          _GatewayResult.success(_fareJson()),
        ],
      );

      final authGateway = _RecordingAuthGateway();
      final repository = ApiPassengerPaymentRatingRepository(
        gateway,
        tokenStore: tokenStore,
        authService: AuthService(
          apiGateway: authGateway,
          tokenStore: tokenStore,
        ),
      );

      final fare = await repository.fetchFare('RR-APP-1');

      expect(fare.requestReference, 'RR-APP-1');
      expect(gateway.calls, hasLength(2));
      expect(gateway.calls[0].path, gateway.calls[1].path);
      expect(authGateway.paths, <String>[AuthService.refreshPath]);
      expect(authGateway.bodies.single, <String, Object?>{
        'refresh': 'stored-refresh',
      });
      expect(await tokenStore.readAccessToken(), 'new-access');
      expect(await tokenStore.readRefreshToken(), 'stored-refresh');
    });
  });

  group('Passenger payment and rating page', () {
    testWidgets('fare-not-ready state disables payment safely', (tester) async {
      _useSurface(tester);

      final repository = _PageRepository(
        fare: PassengerFareSnapshot.fromJson(
          _fareJson(status: 'fare_not_ready', amount: null, canPay: false),
        ),
        payment: PassengerPaymentSnapshot.fromJson(
          _paymentJson(status: 'payment_not_available', canPay: false),
        ),
        rating: PassengerRatingSnapshot.fromJson(
          _ratingJson(status: 'rating_not_open', canRate: false),
        ),
      );

      await _pumpPage(tester, repository);

      expect(find.byKey(const Key('payment-rating-loaded')), findsOneWidget);
      expect(find.text('Not available'), findsOneWidget);
      expect(
        find.byKey(const Key('payment-not-available-state')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('rating-not-eligible-state')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('initiate-payment')), findsNothing);
      expect(find.byKey(const Key('payment-confirmed-state')), findsNothing);
      expect(find.byKey(const Key('payment-receipt-state')), findsNothing);
    });

    testWidgets('pending payment never displays confirmation or receipt', (
      tester,
    ) async {
      _useSurface(tester);

      final repository = _PageRepository(
        fare: PassengerFareSnapshot.fromJson(_fareJson()),
        payment: PassengerPaymentSnapshot.fromJson(
          _paymentJson(status: 'pending'),
        ),
        rating: PassengerRatingSnapshot.fromJson(
          _ratingJson(status: 'rating_not_open', canRate: false),
        ),
      );

      await _pumpPage(tester, repository);

      expect(find.byKey(const Key('payment-pending-state')), findsOneWidget);
      expect(find.byKey(const Key('refresh-payment-status')), findsOneWidget);
      expect(find.byKey(const Key('payment-confirmed-state')), findsNothing);
      expect(find.byKey(const Key('payment-receipt-state')), findsNothing);
      expect(repository.receiptCalls, 0);
    });

    testWidgets('confirmed response displays only returned receipt fields', (
      tester,
    ) async {
      _useSurface(tester);

      final repository = _PageRepository(
        fare: PassengerFareSnapshot.fromJson(
          _fareJson(amount: 42.5, canPay: false),
        ),
        payment: PassengerPaymentSnapshot.fromJson(
          _paymentJson(
            status: 'payment_confirmed',
            amount: 42.5,
            canPay: false,
          ),
        ),
        receipt: PassengerPaymentReceiptSnapshot.fromJson(
          _receiptJson(amount: 42.5, paymentReference: 'PAY-BACKEND-123'),
        ),
        rating: PassengerRatingSnapshot.fromJson(
          _ratingJson(
            status: 'rating_submitted',
            canRate: false,
            includeScores: true,
          ),
        ),
      );

      await _pumpPage(tester, repository);

      expect(find.byKey(const Key('payment-confirmed-state')), findsOneWidget);
      expect(find.byKey(const Key('payment-receipt-state')), findsOneWidget);
      expect(find.text('PAY-BACKEND-123'), findsOneWidget);
      expect(find.text('GHS 42.50'), findsNWidgets(2));
      expect(find.byKey(const Key('rating-submitted-state')), findsOneWidget);
      expect(repository.receiptCalls, 1);
    });

    testWidgets('confirmed response handles unavailable receipt safely', (
      tester,
    ) async {
      _useSurface(tester);

      final repository = _PageRepository(
        fare: PassengerFareSnapshot.fromJson(
          _fareJson(amount: 42, canPay: false),
        ),
        payment: PassengerPaymentSnapshot.fromJson(
          _paymentJson(status: 'payment_confirmed', amount: 42, canPay: false),
        ),
        receiptError: const PassengerPaymentRatingException.notFound(),
        rating: PassengerRatingSnapshot.fromJson(
          _ratingJson(status: 'rating_not_open', canRate: false),
        ),
      );

      await _pumpPage(tester, repository);

      expect(
        find.byKey(const Key('receipt-not-available-state')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('payment-receipt-state')), findsNothing);
      expect(find.textContaining('PAY-'), findsNothing);
    });

    testWidgets('open rating submits the exact accepted fields', (
      tester,
    ) async {
      _useSurface(tester);

      final repository = _PageRepository(
        fare: PassengerFareSnapshot.fromJson(
          _fareJson(status: 'fare_not_ready', amount: null, canPay: false),
        ),
        payment: PassengerPaymentSnapshot.fromJson(
          _paymentJson(status: 'payment_not_available', canPay: false),
        ),
        rating: PassengerRatingSnapshot.fromJson(
          _ratingJson(status: 'rating_open', canRate: true),
        ),
        submittedRating: PassengerRatingSnapshot.fromJson(
          _ratingJson(
            status: 'rating_submitted',
            canRate: false,
            includeScores: true,
          ),
        ),
      );

      await _pumpPage(tester, repository);

      await tester.tap(find.byKey(const Key('rating-overall-5')));
      await tester.tap(find.byKey(const Key('rating-comfort-4')));
      await tester.tap(find.byKey(const Key('rating-driver-conduct-5')));
      await tester.tap(find.byKey(const Key('rating-cleanliness-4')));

      await tester.enterText(
        find.byKey(const Key('rating-feedback-note')),
        '  Excellent ride.  ',
      );

      final submitFinder = find.byKey(const Key('submit-rating'));
      await tester.ensureVisible(submitFinder);
      await tester.tap(submitFinder);
      await tester.pumpAndSettle();

      expect(repository.submittedRatings, hasLength(1));
      expect(repository.submittedRatings.single.toJson(), <String, Object?>{
        'overall_score': 5,
        'comfort_score': 4,
        'conduct_score': 5,
        'cleanliness_score': 4,
        'feedback_note': 'Excellent ride.',
      });
      expect(find.byKey(const Key('rating-submitted-state')), findsOneWidget);
      expect(find.byKey(const Key('submit-rating')), findsNothing);
    });
  });
}

Map<String, Object?> _fareJson({
  String status = 'fare_ready',
  double? amount = 42,
  bool canPay = true,
}) {
  return <String, Object?>{
    'request_reference': 'RR-APP-1',
    'trip_reference': 'TRIP-1',
    'fare_status': status,
    'amount': amount,
    'currency': amount == null ? null : 'GHS',
    'can_pay': canPay,
    'status': 'available',
    'message': status == 'fare_not_ready'
        ? 'The final fare is not ready yet.'
        : 'Fare available.',
    'created_at': '2026-07-16T10:00:00Z',
    'updated_at': '2026-07-16T10:01:00Z',
  };
}

Map<String, Object?> _paymentJson({
  String status = 'payment_not_available',
  double? amount = 42,
  bool canPay = true,
  bool canRetry = false,
}) {
  return <String, Object?>{
    'request_reference': 'RR-APP-1',
    'trip_reference': 'TRIP-1',
    'fare_status': amount == null ? 'fare_not_ready' : 'fare_ready',
    'amount': amount,
    'currency': amount == null ? null : 'GHS',
    'can_pay': canPay,
    'payment_status': status,
    'payment_provider': 'backend-provider',
    'payment_method_label': 'MTN Mobile Money',
    'payment_reference': status == 'payment_confirmed'
        ? 'PAY-BACKEND-123'
        : null,
    'can_retry': canRetry,
    'status': status,
    'message': 'Backend payment update.',
    'created_at': '2026-07-16T10:00:00Z',
    'updated_at': '2026-07-16T10:02:00Z',
  };
}

Map<String, Object?> _receiptJson({
  String status = 'receipt_available',
  double? amount = 42,
  String? paymentReference = 'PAY-BACKEND-123',
}) {
  return <String, Object?>{
    'request_reference': 'RR-APP-1',
    'trip_reference': 'TRIP-1',
    'receipt_status': status,
    'amount': amount,
    'currency': amount == null ? null : 'GHS',
    'payment_status': 'payment_confirmed',
    'payment_provider': 'backend-provider',
    'payment_method_label': 'MTN Mobile Money',
    'payment_reference': paymentReference,
    'status': status,
    'message': 'Receipt update.',
    'created_at': '2026-07-16T10:00:00Z',
    'updated_at': '2026-07-16T10:03:00Z',
  };
}

Map<String, Object?> _ratingJson({
  required String status,
  required bool canRate,
  bool includeScores = false,
}) {
  return <String, Object?>{
    'request_reference': 'RR-APP-1',
    'trip_reference': 'TRIP-1',
    'rating_status': status,
    'can_rate': canRate,
    'overall_score': includeScores ? 5 : null,
    'comfort_score': includeScores ? 4 : null,
    'conduct_score': includeScores ? 5 : null,
    'cleanliness_score': includeScores ? 4 : null,
    'feedback_note': includeScores ? 'Excellent ride.' : null,
    'status': status,
    'message': 'Backend rating update.',
    'created_at': '2026-07-16T10:00:00Z',
    'updated_at': '2026-07-16T10:04:00Z',
  };
}

class _GatewayCall {
  const _GatewayCall({
    required this.method,
    required this.path,
    this.data,
    this.headers,
  });

  final String method;
  final String path;
  final Object? data;
  final Map<String, String>? headers;
}

class _GatewayResult {
  const _GatewayResult._({this.payload, this.error, this.statusCode = 200});

  factory _GatewayResult.success(Object? payload, {int statusCode = 200}) {
    return _GatewayResult._(payload: payload, statusCode: statusCode);
  }

  factory _GatewayResult.failure(AsmApiException error) {
    return _GatewayResult._(error: error, statusCode: error.statusCode ?? 0);
  }

  final Object? payload;
  final AsmApiException? error;
  final int statusCode;
}

class _RecordingPaymentRatingGateway
    implements PassengerPaymentRatingApiGateway {
  _RecordingPaymentRatingGateway({required List<_GatewayResult> results})
    : _results = List<_GatewayResult>.of(results);

  final List<_GatewayResult> _results;
  final List<_GatewayCall> calls = <_GatewayCall>[];

  @override
  Future<ApiResponse<T>> get<T>(String path, {JsonDecoder<T>? decoder}) {
    calls.add(_GatewayCall(method: 'GET', path: path));
    return _next(decoder);
  }

  @override
  Future<ApiResponse<T>> post<T>(
    String path, {
    Object? data,
    Map<String, String>? headers,
    JsonDecoder<T>? decoder,
  }) {
    calls.add(
      _GatewayCall(method: 'POST', path: path, data: data, headers: headers),
    );
    return _next(decoder);
  }

  Future<ApiResponse<T>> _next<T>(JsonDecoder<T>? decoder) async {
    if (_results.isEmpty) {
      throw StateError('No gateway result configured.');
    }

    final result = _results.removeAt(0);
    final error = result.error;

    if (error != null) {
      return ApiResponse<T>.apiFailure(error);
    }

    if (decoder == null) {
      throw StateError('Decoder was required.');
    }

    return ApiResponse<T>.success(
      decoder(result.payload),
      statusCode: result.statusCode,
    );
  }
}

class _RecordingAuthGateway implements AuthApiGateway {
  final List<String> paths = <String>[];
  final List<Map<String, Object?>> bodies = <Map<String, Object?>>[];

  @override
  Future<ApiResponse<Map<String, Object?>>> post(
    String path, {
    required Map<String, Object?> body,
  }) async {
    paths.add(path);
    bodies.add(Map<String, Object?>.of(body));

    return ApiResponse<Map<String, Object?>>.success(<String, Object?>{
      'access': 'new-access',
    }, statusCode: 200);
  }
}

class _PageRepository implements PassengerPaymentRatingRepository {
  _PageRepository({
    required this.fare,
    required this.payment,
    required this.rating,
    this.receipt,
    this.receiptError,
    this.submittedRating,
  });

  final PassengerFareSnapshot fare;
  PassengerPaymentSnapshot payment;
  PassengerRatingSnapshot rating;
  final PassengerPaymentReceiptSnapshot? receipt;
  final PassengerPaymentRatingException? receiptError;
  final PassengerRatingSnapshot? submittedRating;

  int receiptCalls = 0;
  final List<PassengerRatingSubmission> submittedRatings =
      <PassengerRatingSubmission>[];

  @override
  Future<PassengerFareSnapshot> fetchFare(String requestReference) async {
    return fare;
  }

  @override
  Future<PassengerPaymentSnapshot> initiatePayment(
    String requestReference, {
    required String idempotencyKey,
  }) async {
    return payment;
  }

  @override
  Future<PassengerPaymentSnapshot> fetchPayment(String requestReference) async {
    return payment;
  }

  @override
  Future<PassengerPaymentReceiptSnapshot> fetchReceipt(
    String requestReference,
  ) async {
    receiptCalls += 1;

    final error = receiptError;
    if (error != null) {
      throw error;
    }

    final value = receipt;
    if (value == null) {
      throw const PassengerPaymentRatingException.notFound();
    }

    return value;
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
    submittedRatings.add(submission);
    final value = submittedRating ?? rating;
    rating = value;
    return value;
  }
}

Future<void> _pumpPage(
  WidgetTester tester,
  PassengerPaymentRatingRepository repository,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AsmThemes.passenger,
      home: PassengerPaymentRatingPage(
        repository: repository,
        requestReference: 'RR-APP-1',
      ),
    ),
  );

  await tester.pump();
  await tester.pumpAndSettle();
}

void _useSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(430, 1000);
  tester.view.devicePixelRatio = 1;

  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
