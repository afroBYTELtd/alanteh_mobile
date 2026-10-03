import 'dart:async';

import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_auth/asm_auth.dart';
import 'package:flutter_test/flutter_test.dart';

// A refresh has three outcomes. Only a definite rejection by the server
// ends the session; failing to reach the server keeps the stored sign-in.
// Seen on the passenger test phone: starting the app offline signed the
// passenger out because any failed refresh deleted the tokens.
void main() {
  Future<MemoryAuthTokenStore> storedSession() async {
    final store = MemoryAuthTokenStore();
    await store.saveTokens(
      AuthTokens(accessToken: 'old-access', refreshToken: 'refresh-one'),
    );
    return store;
  }

  final unreachable = <String, ApiResponse<Map<String, Object?>>>{
    'no network': ApiResponse.clientException(
      const AsmApiException(
        type: AsmApiExceptionType.network,
        message: 'offline',
      ),
    ),
    'timeout': ApiResponse.clientException(
      const AsmApiException(type: AsmApiExceptionType.timeout, message: 'slow'),
    ),
    'server error 500': ApiResponse.apiFailure(
      const AsmApiException(
        type: AsmApiExceptionType.server,
        message: 'boom',
        statusCode: 500,
      ),
    ),
    for (final status in <int>[502, 503, 504])
      'gateway $status': ApiResponse.apiFailure(
        AsmApiException(
          type: AsmApiExceptionType.badResponse,
          message: 'gateway',
          statusCode: status,
        ),
      ),
  };

  for (final entry in unreachable.entries) {
    test('${entry.key}: temporarily unavailable, sign-in kept', () async {
      final store = await storedSession();
      final service = AuthService(
        apiGateway: _ScriptedGateway(<Object>[entry.value]),
        tokenStore: store,
      );

      final state = await service.refresh();

      expect(state.refreshOutcome, AuthRefreshOutcome.temporarilyUnavailable);
      expect(state.isTemporarilyUnavailable, isTrue);
      expect(state.isAuthenticated, isFalse);
      expect(await store.readAccessToken(), 'old-access');
      expect(await store.readRefreshToken(), 'refresh-one');
    });
  }

  test('a request that throws: temporarily unavailable, kept', () async {
    final store = await storedSession();
    final service = AuthService(
      apiGateway: _ScriptedGateway(<Object>[StateError('socket closed')]),
      tokenStore: store,
    );

    final state = await service.refresh();

    expect(state.refreshOutcome, AuthRefreshOutcome.temporarilyUnavailable);
    expect(await store.readRefreshToken(), 'refresh-one');
  });

  for (final status in <int>[400, 401, 403]) {
    test('server rejects with $status: rejected, sign-in cleared', () async {
      final store = await storedSession();
      final service = AuthService(
        apiGateway: _ScriptedGateway(<Object>[
          ApiResponse<Map<String, Object?>>.apiFailure(
            AsmApiException(
              type: AsmApiExceptionType.authentication,
              message: 'Token is invalid or expired',
              statusCode: status,
            ),
          ),
        ]),
        tokenStore: store,
      );

      final state = await service.refresh();

      expect(state.refreshOutcome, AuthRefreshOutcome.rejected);
      expect(state.isTemporarilyUnavailable, isFalse);
      expect(await store.readAccessToken(), isNull);
      expect(await store.readRefreshToken(), isNull);
    });
  }

  test('success: refreshed', () async {
    final store = await storedSession();
    final service = AuthService(
      apiGateway: _ScriptedGateway(<Object>[
        ApiResponse<Map<String, Object?>>.success(const <String, Object?>{
          'access': 'new-access',
        }),
      ]),
      tokenStore: store,
    );

    final state = await service.refresh();

    expect(state.refreshOutcome, AuthRefreshOutcome.refreshed);
    expect(await store.readAccessToken(), 'new-access');
  });

  test('no stored refresh token: rejected', () async {
    final service = AuthService(
      apiGateway: _ScriptedGateway(const <Object>[]),
      tokenStore: MemoryAuthTokenStore(),
    );

    expect(
      (await service.refresh()).refreshOutcome,
      AuthRefreshOutcome.rejected,
    );
  });

  // A sign-out or a new sign-in while the refresh request is out replaces
  // the session it was for; its answer must not touch the new one.
  group('a session replaced during the refresh', () {
    Future<(AuthService, _PendingGateway, MemoryAuthTokenStore)>
    pendingRefresh() async {
      final store = await storedSession();
      final gateway = _PendingGateway();
      return (
        AuthService(apiGateway: gateway, tokenStore: store),
        gateway,
        store,
      );
    }

    test('a new sign-in is not cleared by the old rejection', () async {
      final (service, gateway, store) = await pendingRefresh();
      final refreshing = service.refresh();
      await store.saveTokens(
        AuthTokens(accessToken: 'new-access', refreshToken: 'new-refresh'),
      );

      gateway.answer(
        ApiResponse.apiFailure(
          const AsmApiException(
            type: AsmApiExceptionType.authentication,
            message: 'Token is invalid or expired',
            statusCode: 401,
          ),
        ),
      );
      final state = await refreshing;

      expect(await store.readAccessToken(), 'new-access');
      expect(await store.readRefreshToken(), 'new-refresh');
      expect(state.isAuthenticated, isTrue);
      expect(state.session!.tokens.refreshToken, 'new-refresh');
    });

    test('a new sign-in is not overwritten by the old success', () async {
      final (service, gateway, store) = await pendingRefresh();
      final refreshing = service.refresh();
      await store.saveTokens(
        AuthTokens(accessToken: 'new-access', refreshToken: 'new-refresh'),
      );

      gateway.answer(
        ApiResponse.success(const <String, Object?>{'access': 'old-access-2'}),
      );
      await refreshing;

      expect(await store.readAccessToken(), 'new-access');
      expect(await store.readRefreshToken(), 'new-refresh');
    });

    test('a sign-out is not undone by the old success', () async {
      final (service, gateway, store) = await pendingRefresh();
      final refreshing = service.refresh();
      await store.clearTokens();

      gateway.answer(
        ApiResponse.success(const <String, Object?>{'access': 'old-access-2'}),
      );
      final state = await refreshing;

      expect(await store.readAccessToken(), isNull);
      expect(await store.readRefreshToken(), isNull);
      expect(state.isAuthenticated, isFalse);
    });
  });

  test('a refresh retry hook decides how often to try', () async {
    final store = await storedSession();
    final gateway = _ScriptedGateway(<Object>[
      ApiResponse<Map<String, Object?>>.clientException(
        const AsmApiException(
          type: AsmApiExceptionType.network,
          message: 'offline',
        ),
      ),
      ApiResponse<Map<String, Object?>>.success(const <String, Object?>{
        'access': 'new-access',
      }),
    ]);
    var hookCalls = 0;
    final service = AuthService(
      apiGateway: gateway,
      tokenStore: store,
      refreshRetry: (attempt) async {
        hookCalls += 1;
        final first = await attempt();
        return first.isSuccess ? first : attempt();
      },
    );

    final state = await service.refresh();

    expect(hookCalls, 1);
    expect(gateway.calls, 2);
    expect(state.refreshOutcome, AuthRefreshOutcome.refreshed);
    expect(await store.readAccessToken(), 'new-access');
  });
}

/// Holds the refresh request open until [answer] is called.
class _PendingGateway implements AuthApiGateway {
  final _response = Completer<ApiResponse<Map<String, Object?>>>();

  void answer(ApiResponse<Map<String, Object?>> response) =>
      _response.complete(response);

  @override
  Future<ApiResponse<Map<String, Object?>>> post(
    String path, {
    required Map<String, Object?> body,
  }) => _response.future;
}

/// Answers each post with the next scripted response, or throws it.
class _ScriptedGateway implements AuthApiGateway {
  _ScriptedGateway(this.script);

  final List<Object> script;
  int calls = 0;

  @override
  Future<ApiResponse<Map<String, Object?>>> post(
    String path, {
    required Map<String, Object?> body,
  }) async {
    final next = script[calls];
    calls += 1;
    if (next is ApiResponse<Map<String, Object?>>) {
      return next;
    }
    throw next;
  }
}
