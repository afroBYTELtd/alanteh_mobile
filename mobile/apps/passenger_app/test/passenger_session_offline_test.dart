import 'dart:async';
import 'dart:io';

import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_app_config/asm_app_config.dart';
import 'package:asm_auth/asm_auth.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:asm_ride_domain/asm_ride_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passenger_app/booking/booking_draft.dart';
import 'package:passenger_app/booking/booking_submission.dart';
import 'package:passenger_app/booking/passenger_fare_estimate.dart';
import 'package:passenger_app/main.dart';
import 'package:passenger_app/network/ghana_network_resilience.dart';
import 'package:passenger_app/network/passenger_auth_service.dart';
import 'package:passenger_app/network/passenger_cancellation_gateway.dart';
import 'package:passenger_app/payment_rating/passenger_payment_rating_contract.dart';
import 'package:passenger_app/ride_requests/ride_request_history.dart';
import 'package:passenger_app/support/new_message_form.dart';

// Seen on the test phone: the app started while the phone was offline and
// signed the passenger out, because any failed token refresh deleted the
// stored sign-in. Only a definite rejection by the server may do that.
const _cannotReach =
    'Cannot reach the server. Check your connection and try again.';

void main() {
  group('start-up', () {
    testWidgets('offline: opens signed in and keeps the sign-in', (
      tester,
    ) async {
      final store = await _storedSession();
      await tester.pumpWidget(_app(store, _AuthGateway.unreachable()));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('passenger-home-full-screen-map-layout')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('passenger-sign-in')), findsNothing);
      expect(find.text('Please sign in again to continue.'), findsNothing);
      expect(await store.readAccessToken(), 'stored-access');
      expect(await store.readRefreshToken(), 'stored-refresh');
    });

    testWidgets('opens home without waiting for the refresh', (tester) async {
      final store = await _storedSession();
      final gateway = _AuthGateway.pending();
      await tester.pumpWidget(_app(store, gateway));
      for (var frame = 0; frame < 5; frame += 1) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(gateway.calls, 1);
      expect(
        find.byKey(const Key('passenger-home-full-screen-map-layout')),
        findsOneWidget,
      );

      gateway.answer(ApiResponse.success(const {'access': 'new-access'}));
      await tester.pumpAndSettle();
      expect(await store.readAccessToken(), 'new-access');
      expect(
        find.byKey(const Key('passenger-home-full-screen-map-layout')),
        findsOneWidget,
      );
    });

    testWidgets('a rejection arriving later signs out with the message', (
      tester,
    ) async {
      final store = await _storedSession();
      final gateway = _AuthGateway.pending();
      await tester.pumpWidget(_app(store, gateway));
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.byKey(const Key('passenger-home-full-screen-map-layout')),
        findsOneWidget,
      );

      gateway.answer(_rejected());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('passenger-sign-in')), findsOneWidget);
      expect(find.text('Please sign in again to continue.'), findsOneWidget);
      expect(await store.readRefreshToken(), isNull);
    });
  });

  testWidgets('a refresh that ends after signing out changes nothing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    final store = await _storedSession();
    final gateway = _AuthGateway.pending();
    await tester.pumpWidget(_app(store, gateway));
    await tester.pump(const Duration(milliseconds: 300));

    tester
        .widget<AsmBottomNavigationBar>(find.byType(AsmBottomNavigationBar))
        .onDestinationSelected!
        .call(2);
    await tester.pump(const Duration(milliseconds: 300));
    final signOut = find.byKey(const Key('passenger-account-sign-out'));
    await tester.ensureVisible(signOut);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(signOut);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('passenger-sign-in')), findsOneWidget);

    gateway.answer(_rejected());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('passenger-sign-in')), findsOneWidget);
    expect(find.text('Please sign in again to continue.'), findsNothing);
  });

  group('refresh retry', () {
    test('a refresh is retried on the Ghana schedule', () async {
      final waits = <Duration>[];
      final retry = ghanaAuthRefreshRetry(
        GhanaRetryPolicy(delay: (wait) async => waits.add(wait)),
      );
      var attempts = 0;

      final response = await retry(() async {
        attempts += 1;
        return attempts < 3 ? _unreachableResponse() : _refreshed();
      });

      expect(response.isSuccess, isTrue);
      expect(attempts, 3);
      expect(waits, GhanaRequestPolicy.retryBackoffs.take(2));
    });

    test('a rejection is not retried', () async {
      final retry = ghanaAuthRefreshRetry(
        GhanaRetryPolicy(delay: (_) async {}),
      );
      var attempts = 0;

      await retry(() async {
        attempts += 1;
        return _rejected();
      });

      expect(attempts, 1);
    });

    test('every passenger auth service is built with the retry', () {
      final builders = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .where(
            (file) =>
                file.readAsStringSync().contains('AuthService.withApiClient('),
          )
          .map((file) => file.path.replaceAll('\\', '/'))
          .toList();
      expect(builders, <String>['lib/network/passenger_auth_service.dart']);
      expect(
        File('lib/network/passenger_auth_service.dart').readAsStringSync(),
        contains('refreshRetry: ghanaAuthRefreshRetry('),
      );
    });
  });

  group('a refresh that cannot reach the server keeps the sign-in', () {
    test('ride history', () async {
      final store = await _storedSession();
      final repository = ApiPassengerRideRequestHistoryRepository(
        _UnauthorizedGateway(),
        tokenStore: store,
        authService: _unreachableAuth(store),
      );

      await expectLater(
        repository.fetchRequests(),
        throwsA(
          isA<PassengerRideRequestHistoryException>().having(
            (e) => e.requiresSignIn,
            'requiresSignIn',
            isFalse,
          ),
        ),
      );
      expect(await store.readRefreshToken(), 'stored-refresh');
    });

    test('fare estimate', () async {
      final store = await _storedSession();
      final repository = ApiPassengerFareEstimateRepository(
        _UnauthorizedGateway(),
        tokenStore: store,
        authService: _unreachableAuth(store),
      );

      await expectLater(
        repository.fetchEstimate(10),
        throwsA(
          isA<PassengerFareEstimateException>().having(
            (e) => e.requiresSignIn,
            'requiresSignIn',
            isFalse,
          ),
        ),
      );
      expect(await store.readRefreshToken(), 'stored-refresh');
    });

    test('payment and rating', () async {
      final store = await _storedSession();
      final repository = ApiPassengerPaymentRatingRepository(
        _UnauthorizedGateway(),
        tokenStore: store,
        authService: _unreachableAuth(store),
      );

      await expectLater(
        repository.fetchPayment('RR-APP-OFFLINE'),
        throwsA(
          isA<PassengerPaymentRatingException>().having(
            (e) => e.requiresSignIn,
            'requiresSignIn',
            isFalse,
          ),
        ),
      );
      expect(await store.readRefreshToken(), 'stored-refresh');
    });

    test('booking', () async {
      final store = await _storedSession();
      final submitter = ApiPassengerRideRequestSubmitter(
        _UnauthorizedClient(),
        tokenStore: store,
        authService: _unreachableAuth(store),
      );

      await expectLater(
        submitter.submit(
          BookingDraft(
            marketCode: MarketConfig.ghanaAccra.marketCode,
            serviceContext: RideServiceContextCode.otherApprovedRequest,
            pickupDescription: 'Osu',
            destinationDescription: 'Airport',
            passengerCount: 1,
          ),
          idempotencyKey: 'APP-offline',
        ),
        throwsA(
          isA<PassengerRideRequestSubmissionException>().having(
            (e) => e.message,
            'message',
            _cannotReach,
          ),
        ),
      );
      expect(await store.readRefreshToken(), 'stored-refresh');
    });

    test('cancellation', () async {
      final store = await _storedSession();
      final gateway = ApiPassengerCancellationGateway(
        _UnauthorizedClient(),
        tokenStore: store,
        authService: _unreachableAuth(store),
      );

      await expectLater(
        gateway.cancelRideRequest(
          requestReference: 'RR-APP-OFFLINE',
          reason: PassengerCancellationReason.noLongerNeeded,
          idempotencyKey: 'APP-cancel-offline',
        ),
        throwsA(
          isA<PassengerCancellationException>().having(
            (e) => e.message,
            'message',
            _cannotReach,
          ),
        ),
      );
      expect(await store.readRefreshToken(), 'stored-refresh');
    });

    test('support message', () async {
      final store = await _storedSession();
      final submitter = ApiPassengerSupportMessageSubmitter(
        _UnauthorizedClient(),
        tokenStore: store,
        authService: _unreachableAuth(store),
      );

      await expectLater(
        submitter.submit(
          category: 'other',
          tripReference: null,
          name: 'Ama Mensah',
          message: 'A message long enough to send.',
        ),
        throwsA(
          isA<PassengerSupportMessageException>().having(
            (e) => e.message,
            'message',
            _cannotReach,
          ),
        ),
      );
      expect(await store.readRefreshToken(), 'stored-refresh');
    });
  });
}

Future<MemoryAuthTokenStore> _storedSession() async {
  final store = MemoryAuthTokenStore();
  await store.saveTokens(
    AuthTokens(accessToken: 'stored-access', refreshToken: 'stored-refresh'),
  );
  return store;
}

Widget _app(AuthTokenStore store, _AuthGateway gateway) {
  return PassengerApp(
    showLoginShell: true,
    authTokenStore: store,
    authService: AuthService(
      apiGateway: gateway,
      tokenStore: store,
      appContext: AuthAppContext.passenger,
    ),
  );
}

AuthService _unreachableAuth(AuthTokenStore store) {
  return AuthService(apiGateway: _AuthGateway.unreachable(), tokenStore: store);
}

ApiResponse<Map<String, Object?>> _unreachableResponse() {
  return ApiResponse.clientException(
    const AsmApiException(
      type: AsmApiExceptionType.network,
      message: 'The API request could not reach the network.',
    ),
  );
}

ApiResponse<Map<String, Object?>> _rejected() {
  return ApiResponse.apiFailure(
    const AsmApiException(
      type: AsmApiExceptionType.authentication,
      message: 'Token is invalid or expired',
      statusCode: 401,
    ),
  );
}

ApiResponse<Map<String, Object?>> _refreshed() {
  return ApiResponse.success(const <String, Object?>{'access': 'new-access'});
}

ApiResponse<T> _unauthorized<T>() {
  return ApiResponse<T>.apiFailure(
    const AsmApiException(
      type: AsmApiExceptionType.authentication,
      message: 'Authentication credentials were not provided.',
      statusCode: 401,
    ),
  );
}

class _AuthGateway implements AuthApiGateway {
  _AuthGateway.unreachable() : _pending = null;

  _AuthGateway.pending()
    : _pending = Completer<ApiResponse<Map<String, Object?>>>();

  final Completer<ApiResponse<Map<String, Object?>>>? _pending;
  int calls = 0;

  void answer(ApiResponse<Map<String, Object?>> response) =>
      _pending!.complete(response);

  @override
  Future<ApiResponse<Map<String, Object?>>> post(
    String path, {
    required Map<String, Object?> body,
  }) async {
    calls += 1;
    final pending = _pending;
    return pending == null ? _unreachableResponse() : pending.future;
  }
}

/// Every API request is refused as unauthorised (an expired access token).
class _UnauthorizedGateway
    implements
        PassengerRideRequestHistoryApiGateway,
        PassengerFareEstimateApiGateway,
        PassengerPaymentRatingApiGateway {
  @override
  Future<ApiResponse<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    JsonDecoder<T>? decoder,
  }) async => _unauthorized<T>();

  @override
  Future<ApiResponse<T>> post<T>(
    String path, {
    Object? data,
    Map<String, String>? headers,
    JsonDecoder<T>? decoder,
  }) async => _unauthorized<T>();
}

class _UnauthorizedClient extends AsmApiClient {
  _UnauthorizedClient() : super(baseUrl: 'https://control.example/api/');

  @override
  Future<ApiResponse<T>> request<T>({
    required String method,
    required String path,
    Object? data,
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
    JsonDecoder<T>? decoder,
  }) async => _unauthorized<T>();
}
