import 'dart:io';

import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_auth/asm_auth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CC4A accepted mobile auth guard', () {
    test('mobile auth availability is true', () {
      expect(mobileAuthAvailable, isTrue);
    });

    test('requiring mobile auth returns normally after handoff', () {
      expect(requireMobileAuth, returnsNormally);
    });

    test('availability guard exposes no endpoint URLs, tokens, or secrets', () {
      final exposedText = <String>[
        mobileAuthAvailable.toString(),
        cc4aMobileAuthDisabledMessage,
        const MobileAuthDisabledException().toString(),
      ].join(' ');

      expect(exposedText, isNot(contains('http')));
      expect(exposedText, isNot(contains('api/auth')));
      expect(exposedText, isNot(contains('token')));
      expect(exposedText, isNot(contains('refresh')));
      expect(exposedText, isNot(contains('secret')));
      expect(exposedText, isNot(contains('credential')));
    });

    test('no duplicate CC4A credential submission method is added', () {
      final source = File('lib/asm_auth.dart').readAsStringSync();

      expect(source, isNot(contains('submitCc4aCredentials')));
      expect(source, isNot(contains('sendCc4aCredentials')));
      expect(source, isNot(contains('writeCc4aToken')));
    });
  });

  group('CC4A phone and PIN validation helpers', () {
    test('supports Ghana +233 phone and exact 4 digit PIN only', () {
      expect(isValidGhanaPhoneNumber('+233000000000'), isTrue);
      expect(isValidGhanaPhoneNumber('+233000000001'), isTrue);
      expect(isValidGhanaPhoneNumber('0200000000'), isFalse);
      expect(isValidGhanaPhoneNumber('+23355000006'), isFalse);
      expect(isValidGhanaPhoneNumber('+2330000000000'), isFalse);
      expect(isValidGhanaPhoneNumber('+23355abc4567'), isFalse);
      expect(isValidGhanaPhoneNumber('+23300 0000000'), isFalse);
      expect(isValidGhanaPhoneNumber(' +233000000000 '), isFalse);

      expect(isValidPin('0000'), isTrue);
      expect(isValidPin('9876'), isTrue);
      expect(isValidPin('123'), isFalse);
      expect(isValidPin('00000'), isFalse);
      expect(isValidPin('12a4'), isFalse);
      expect(isValidPin('12 4'), isFalse);
      expect(isValidPin(' 0000 '), isFalse);
    });

    test('returns exact user-facing validation messages', () {
      expect(validateGhanaPhoneNumberForLogin(''), loginPhoneRequiredMessage);
      expect(
        validateGhanaPhoneNumberForLogin('   '),
        loginPhoneRequiredMessage,
      );
      expect(
        validateGhanaPhoneNumberForLogin('0550000000'),
        loginPhoneFormatMessage,
      );
      expect(
        validateGhanaPhoneNumberForLogin('+23300 0000000'),
        loginPhoneFormatMessage,
      );
      expect(validateGhanaPhoneNumberForLogin('+233000000000'), isNull);

      expect(validatePinForLogin(''), loginPinRequiredMessage);
      expect(validatePinForLogin('   '), loginPinRequiredMessage);
      expect(validatePinForLogin('123'), loginPinFormatMessage);
      expect(validatePinForLogin('00000'), loginPinFormatMessage);
      expect(validatePinForLogin('12a4'), loginPinFormatMessage);
      expect(validatePinForLogin(' 0000 '), loginPinFormatMessage);
      expect(validatePinForLogin('0000'), isNull);
    });
  });

  group('Auth account type parsing and app context validation', () {
    test('parses finalized CC4A account_type values', () {
      expect(AuthAccountType.tryParse('passenger'), AuthAccountType.passenger);
      expect(AuthAccountType.tryParse('driver'), AuthAccountType.driver);
      expect(AuthAccountType.tryParse('staff'), AuthAccountType.staff);

      expect(AuthAccountType.passenger.backendCode, 'passenger');
      expect(AuthAccountType.driver.backendCode, 'driver');
      expect(AuthAccountType.staff.backendCode, 'staff');
    });

    test('Passenger context accepts only passenger account_type', () {
      expect(
        AuthAppContext.passenger.allowsAccountType(AuthAccountType.passenger),
        isTrue,
      );
      expect(
        AuthAppContext.passenger.allowsAccountType(AuthAccountType.driver),
        isFalse,
      );
      expect(
        AuthAppContext.passenger.allowsAccountType(AuthAccountType.staff),
        isFalse,
      );
    });

    test('Driver context accepts only driver account_type', () {
      expect(
        AuthAppContext.driver.allowsAccountType(AuthAccountType.driver),
        isTrue,
      );
      expect(
        AuthAppContext.driver.allowsAccountType(AuthAccountType.passenger),
        isFalse,
      );
      expect(
        AuthAppContext.driver.allowsAccountType(AuthAccountType.staff),
        isFalse,
      );
    });

    test('missing and unknown account_type fail safely', () {
      expect(
        () => AuthAccountType.parse(null),
        throwsA(
          isA<AuthException>().having(
            (error) => error.message,
            'message',
            authAppContextErrorMessage,
          ),
        ),
      );
      expect(
        () => AuthAccountType.parse('unknown'),
        throwsA(
          isA<AuthException>().having(
            (error) => error.message,
            'message',
            authAppContextErrorMessage,
          ),
        ),
      );
    });
  });

  group('AuthService', () {
    test('login validates phone and PIN against the CC4A contract', () async {
      final api = _MockAuthApiGateway(responseData: _successLoginResponse());
      final service = AuthService(
        apiGateway: api,
        tokenStore: MemoryAuthTokenStore(),
      );

      await expectLater(
        service.login('', '0000'),
        throwsA(
          isA<AuthException>().having(
            (error) => error.message,
            'message',
            loginPhoneRequiredMessage,
          ),
        ),
      );
      await expectLater(
        service.login('0200000000', '0000'),
        throwsA(
          isA<AuthException>().having(
            (error) => error.message,
            'message',
            loginPhoneFormatMessage,
          ),
        ),
      );
      await expectLater(
        service.login('+233000000000', ''),
        throwsA(
          isA<AuthException>().having(
            (error) => error.message,
            'message',
            loginPinRequiredMessage,
          ),
        ),
      );
      await expectLater(
        service.login('+233000000000', 'bad-pin'),
        throwsA(
          isA<AuthException>().having(
            (error) => error.message,
            'message',
            loginPinFormatMessage,
          ),
        ),
      );
      await expectLater(
        service.login('+233000000000', '0000 '),
        throwsA(
          isA<AuthException>().having(
            (error) => error.message,
            'message',
            loginPinFormatMessage,
          ),
        ),
      );
      expect(api.paths, isEmpty);
    });

    test(
      'login request body uses phone and pin exactly and keeps PIN as string',
      () async {
        final store = MemoryAuthTokenStore();
        final api = _MockAuthApiGateway(responseData: _successLoginResponse());
        final service = AuthService(apiGateway: api, tokenStore: store);

        final state = await service.login('+233000000000', '0000');

        expect(state.status, AuthStatus.authenticated);
        expect(state.session?.accountType, AuthAccountType.passenger);
        expect(state.session?.account, <String, Object?>{
          'id': 'passenger-test-account',
          'display_name': 'Test Passenger',
        });
        expect(api.paths, <String>[AuthService.tokenPath]);
        expect(api.bodies.single, <String, Object?>{
          'phone': '+233000000000',
          'pin': '0000',
        });
        expect(api.bodies.single.keys, isNot(contains('email')));
        expect(api.bodies.single.keys, isNot(contains('password')));
        expect(api.bodies.single['pin'], isA<String>());
      },
    );

    test('M3A locks auth service to accepted token endpoints only', () {
      final source = File('lib/asm_auth.dart').readAsStringSync();

      expect(AuthService.tokenPath, '/api/auth/token/');
      expect(AuthService.refreshPath, '/api/auth/token/refresh/');
      expect(source, contains("static const tokenPath = '/api/auth/token/';"));
      expect(
        source,
        contains("static const refreshPath = '/api/auth/token/refresh/';"),
      );
      expect(source, isNot(contains('/api/logout')));
      expect(source, isNot(contains('session/validate')));
      expect(source, isNot(contains('/api/profile')));
      expect(source, isNot(contains('/api/account')));
      expect(source, isNot(contains('/api/wallet')));
      expect(source, isNot(contains('/api/payment')));
      expect(source, isNot(contains('/api/payments')));
      expect(source, isNot(contains('/api/payout')));
      expect(source, isNot(contains('/api/payouts')));
      expect(source, isNot(contains('/api/earnings')));
      expect(source, isNot(contains('/api/support')));
      expect(source, isNot(contains('/api/documents')));
      expect(source, isNot(contains('/api/verification')));
      expect(source, isNot(contains('/api/vehicles')));
      expect(source, isNot(contains(['fake', 'token'].join(' '))));
      expect(source, isNot(contains(['fake', 'Token'].join())));
    });

    test('Passenger app context accepts passenger account_type', () async {
      final service = AuthService(
        apiGateway: _MockAuthApiGateway(
          responseData: _successLoginResponse(accountType: 'passenger'),
        ),
        tokenStore: MemoryAuthTokenStore(),
        appContext: AuthAppContext.passenger,
      );

      final state = await service.login('+233000000000', '0000');

      expect(state.status, AuthStatus.authenticated);
      expect(state.session?.accountType, AuthAccountType.passenger);
    });

    test('Driver app context accepts driver account_type', () async {
      final service = AuthService(
        apiGateway: _MockAuthApiGateway(
          responseData: _successLoginResponse(accountType: 'driver'),
        ),
        tokenStore: MemoryAuthTokenStore(),
        appContext: AuthAppContext.driver,
      );

      final state = await service.login('+233000000001', '9876');

      expect(state.status, AuthStatus.authenticated);
      expect(state.session?.accountType, AuthAccountType.driver);
    });

    test(
      'Passenger context rejects driver, staff, missing, and unknown',
      () async {
        for (final accountType in <Object?>[
          'driver',
          'staff',
          null,
          'unknown',
        ]) {
          final store = MemoryAuthTokenStore();
          final service = AuthService(
            apiGateway: _MockAuthApiGateway(
              responseData: _successLoginResponse(accountType: accountType),
            ),
            tokenStore: store,
            appContext: AuthAppContext.passenger,
          );

          final state = await service.login('+233000000000', '0000');

          expect(state.status, AuthStatus.unauthenticated);
          expect(state.error?.message, authAppContextErrorMessage);
          expect(await store.readAccessToken(), isNull);
          expect(await store.readRefreshToken(), isNull);
        }
      },
    );

    test(
      'Driver context rejects passenger, staff, missing, and unknown',
      () async {
        for (final accountType in <Object?>[
          'passenger',
          'staff',
          null,
          'unknown',
        ]) {
          final store = MemoryAuthTokenStore();
          final service = AuthService(
            apiGateway: _MockAuthApiGateway(
              responseData: _successLoginResponse(accountType: accountType),
            ),
            tokenStore: store,
            appContext: AuthAppContext.driver,
          );

          final state = await service.login('+233000000001', '9876');

          expect(state.status, AuthStatus.unauthenticated);
          expect(state.error?.message, authAppContextErrorMessage);
          expect(await store.readAccessToken(), isNull);
          expect(await store.readRefreshToken(), isNull);
        }
      },
    );

    test(
      'currentSession returns authenticated when stored tokens exist',
      () async {
        final store = MemoryAuthTokenStore();
        await store.saveTokens(
          AuthTokens(
            accessToken: 'stored-access',
            refreshToken: 'stored-refresh',
          ),
        );
        final service = AuthService(
          apiGateway: _MockAuthApiGateway(
            responseData: _successLoginResponse(),
          ),
          tokenStore: store,
        );

        final state = await service.currentSession();

        expect(state.status, AuthStatus.authenticated);
        expect(state.session?.tokens.accessToken, 'stored-access');
      },
    );

    test(
      'currentSession returns unauthenticated when tokens are missing',
      () async {
        final service = _serviceWithResponse(_successLoginResponse());

        final state = await service.currentSession();

        expect(state.status, AuthStatus.unauthenticated);
        expect(state.session, isNull);
      },
    );

    test('refresh uses stored refresh token', () async {
      final store = MemoryAuthTokenStore();
      await store.saveTokens(
        AuthTokens(accessToken: 'old-access', refreshToken: 'refresh-one'),
      );
      final api = _MockAuthApiGateway(
        responseData: <String, Object?>{'access': 'new-access'},
      );
      final service = AuthService(apiGateway: api, tokenStore: store);

      final state = await service.refresh();

      expect(state.status, AuthStatus.authenticated);
      expect(api.paths, <String>[AuthService.refreshPath]);
      expect(api.bodies.single, <String, Object?>{'refresh': 'refresh-one'});
    });

    test('refresh updates access token from mocked response', () async {
      final store = MemoryAuthTokenStore();
      await store.saveTokens(
        AuthTokens(accessToken: 'old-access', refreshToken: 'refresh-one'),
      );
      final service = AuthService(
        apiGateway: _MockAuthApiGateway(
          responseData: <String, Object?>{'access': 'new-access'},
        ),
        tokenStore: store,
      );

      final state = await service.refresh();

      expect(state.session?.tokens.accessToken, 'new-access');
      expect(state.session?.tokens.refreshToken, 'refresh-one');
      expect(await store.readAccessToken(), 'new-access');
      expect(await store.readRefreshToken(), 'refresh-one');
    });

    test('logout clears tokens', () async {
      final store = MemoryAuthTokenStore();
      await store.saveTokens(
        AuthTokens(accessToken: 'access-one', refreshToken: 'refresh-one'),
      );
      final service = AuthService(
        apiGateway: _MockAuthApiGateway(responseData: _successLoginResponse()),
        tokenStore: store,
      );

      final state = await service.logout();

      expect(state.status, AuthStatus.unauthenticated);
      expect(await store.readAccessToken(), isNull);
      expect(await store.readRefreshToken(), isNull);
    });

    test('failed login does not store tokens', () async {
      final store = MemoryAuthTokenStore();
      final service = AuthService(
        apiGateway: _MockAuthApiGateway(statusCode: 401),
        tokenStore: store,
      );

      final state = await service.login('+233000000000', '0000');

      expect(state.status, AuthStatus.unauthenticated);
      expect(await store.readAccessToken(), isNull);
      expect(await store.readRefreshToken(), isNull);
    });

    test('failed refresh does not silently authenticate', () async {
      final store = MemoryAuthTokenStore();
      await store.saveTokens(
        AuthTokens(accessToken: 'old-access', refreshToken: 'refresh-one'),
      );
      final service = AuthService(
        apiGateway: _MockAuthApiGateway(statusCode: 401),
        tokenStore: store,
      );

      final state = await service.refresh();

      expect(state.status, AuthStatus.unauthenticated);
      expect(state.session, isNull);
      expect(await store.readAccessToken(), isNull);
      expect(await store.readRefreshToken(), isNull);
    });

    test('SharedPreferences is not used', () {
      final source = File('lib/asm_auth.dart').readAsStringSync();

      expect(source, contains('flutter_secure_storage'));
      expect(source, isNot(contains('SharedPreferences')));
    });
  });

  group('AuthTokens', () {
    test('empty tokens are not treated as authenticated', () {
      expect(
        () => AuthTokens(accessToken: '', refreshToken: 'refresh-one'),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => AuthTokens(accessToken: 'access-one', refreshToken: ''),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}

AuthService _serviceWithResponse(Map<String, Object?> responseData) {
  return AuthService(
    apiGateway: _MockAuthApiGateway(responseData: responseData),
    tokenStore: MemoryAuthTokenStore(),
  );
}

Map<String, Object?> _successLoginResponse({
  Object? accountType = 'passenger',
  Object? account = const <String, Object?>{
    'id': 'passenger-test-account',
    'display_name': 'Test Passenger',
  },
}) {
  return <String, Object?>{
    'access': 'access-one',
    'refresh': 'refresh-one',
    if (accountType != null) 'account_type': accountType,
    if (account != null) 'account': account,
  };
}

class _MockAuthApiGateway implements AuthApiGateway {
  _MockAuthApiGateway({this.responseData, this.statusCode = 200});

  final Map<String, Object?>? responseData;
  final int statusCode;
  final List<String> paths = <String>[];
  final List<Map<String, Object?>> bodies = <Map<String, Object?>>[];

  @override
  Future<ApiResponse<Map<String, Object?>>> post(
    String path, {
    required Map<String, Object?> body,
  }) async {
    paths.add(path);
    bodies.add(body);

    if (statusCode < 200 || statusCode >= 300) {
      return ApiResponse.apiFailure(
        AsmApiException(
          type: AsmApiExceptionType.authentication,
          message: 'Mock authentication failed.',
          statusCode: statusCode,
        ),
      );
    }

    return ApiResponse.success(responseData ?? <String, Object?>{});
  }
}
