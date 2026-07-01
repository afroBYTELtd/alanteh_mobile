import 'dart:io';

import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_auth/asm_auth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CC4A disabled mobile auth guard', () {
    test('mobile auth availability is false', () {
      expect(mobileAuthAvailable, isFalse);
    });

    test('requiring mobile auth throws the disabled handoff message', () {
      expect(
        requireMobileAuth,
        throwsA(
          isA<MobileAuthDisabledException>().having(
            (error) => error.message,
            'message',
            cc4aMobileAuthDisabledMessage,
          ),
        ),
      );
    });

    test('disabled guard exposes no live auth surface', () {
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

    test('no CC4A credential submission method is added', () {
      final source = File('lib/asm_auth.dart').readAsStringSync();

      expect(source, isNot(contains('submitCc4aCredentials')));
      expect(source, isNot(contains('sendCc4aCredentials')));
      expect(source, isNot(contains('writeCc4aToken')));
    });
  });

  group('AuthService', () {
    test('login validates phone and PIN', () async {
      final service = _serviceWithResponse(_successTokens());

      await expectLater(
        service.login('', '1234'),
        throwsA(isA<AuthException>()),
      );
      await expectLater(
        service.login('0200000000', ''),
        throwsA(isA<AuthException>()),
      );
    });

    test(
      'login stores access and refresh tokens from mocked response',
      () async {
        final store = MemoryAuthTokenStore();
        final api = _MockAuthApiGateway(responseData: _successTokens());
        final service = AuthService(apiGateway: api, tokenStore: store);

        final state = await service.login(' 0200000000 ', ' 1234 ');

        expect(state.status, AuthStatus.authenticated);
        expect(state.session?.tokens.accessToken, 'access-one');
        expect(await store.readAccessToken(), 'access-one');
        expect(await store.readRefreshToken(), 'refresh-one');
        expect(api.paths, <String>[AuthService.tokenPath]);
        expect(api.bodies.single, <String, Object?>{
          'phone': '0200000000',
          'pin': '1234',
        });
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
          apiGateway: _MockAuthApiGateway(responseData: _successTokens()),
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
        final service = _serviceWithResponse(_successTokens());

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
        apiGateway: _MockAuthApiGateway(responseData: _successTokens()),
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

      final state = await service.login('0200000000', 'bad-pin');

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

Map<String, Object?> _successTokens() {
  return <String, Object?>{'access': 'access-one', 'refresh': 'refresh-one'};
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
