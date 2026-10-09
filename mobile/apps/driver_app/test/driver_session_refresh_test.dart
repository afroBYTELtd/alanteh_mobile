import 'dart:async';
import 'dart:typed_data';

import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_auth/asm_auth.dart';
import 'package:dio/dio.dart';
import 'package:driver_app/main.dart' as driver_main;
import 'package:driver_app/network/driver_trip_action_gateway.dart';
import 'package:driver_app/network/ghana_network_resilience.dart';
import 'package:flutter_test/flutter_test.dart';

// The driver's shared refresh: only a 401 from the refresh endpoint ends the
// session, refreshes at the same time share one request, and a 401 for a
// token another refresh has already replaced leaves the new sign-in alone.
void main() {
  Future<MemoryAuthTokenStore> storedSession() async {
    final store = MemoryAuthTokenStore();
    await store.saveTokens(
      AuthTokens(accessToken: 'access-one', refreshToken: 'refresh-one'),
    );
    return store;
  }

  driver_main.DriverSessionRefreshController controller(
    driver_main.DriverSessionRefreshApiGateway api,
    AuthTokenStore store,
  ) => driver_main.DriverSessionRefreshController(
    apiGateway: api,
    tokenStore: store,
    retryPolicy: GhanaRetryPolicy(delay: (_) async {}),
  );

  group('only a 401 ends the session', () {
    for (final status in <int>[400, 403, 404, 429]) {
      test('a $status from the refresh endpoint keeps the sign-in', () async {
        final store = await storedSession();
        final outcome = await controller(
          _Scripted([_status(status)]),
          store,
        ).refresh();

        expect(outcome, DriverTokenRefreshOutcome.temporarilyUnavailable);
        expect(await store.readRefreshToken(), 'refresh-one');
        expect(await store.readAccessToken(), 'access-one');
      });
    }

    test('a non-JSON 200 (a Wi-Fi login page), through the real client, '
        'keeps the sign-in', () async {
      final store = await storedSession();
      final dio = Dio()
        ..httpClientAdapter = _FixedAdapter(
          200,
          '<html>Sign in to the Wi-Fi</html>',
          'text/html',
        );
      final api = driver_main.AsmDriverSessionRefreshApiGateway(
        AsmApiClient(baseUrl: 'https://alanteh.test', dio: dio),
      );

      final outcome = await controller(api, store).refresh();

      expect(outcome, DriverTokenRefreshOutcome.temporarilyUnavailable);
      expect(await store.readRefreshToken(), 'refresh-one');
    });

    test('a 200 without an access token keeps the sign-in', () async {
      final store = await storedSession();
      final outcome = await controller(
        _Scripted([
          ApiResponse<Map<String, Object?>>.success(<String, Object?>{
            'detail': 'unexpected',
          }, statusCode: 200),
        ]),
        store,
      ).refresh();

      expect(outcome, DriverTokenRefreshOutcome.temporarilyUnavailable);
      expect(await store.readRefreshToken(), 'refresh-one');
    });

    test('a 401 for the stored token ends the session', () async {
      final store = await storedSession();
      final outcome = await controller(
        _Scripted([_status(401)]),
        store,
      ).refresh();

      expect(outcome, DriverTokenRefreshOutcome.sessionExpired);
      expect(await store.readRefreshToken(), isNull);
    });
  });

  group('refreshes at the same time', () {
    test('two at once, with a server that rotates and blacklists: one request, '
        'both refreshed', () async {
      final store = await storedSession();
      final server = _RotatingServer();
      final shared = controller(server, store);

      final a = shared.refresh();
      final b = shared.refresh();
      await pumpEventQueue();
      server.answerInReverseOrder();
      final outcomes = await Future.wait([a, b]);

      expect(server.received, ['refresh-one']);
      expect(outcomes, everyElement(DriverTokenRefreshOutcome.refreshed));
      expect(await store.readRefreshToken(), 'refresh-two');
    });

    test('a 401 for a token another refresh already replaced does not clear '
        'the new sign-in', () async {
      final store = await storedSession();
      final server = _RotatingServer(answerAtOnce: true);
      final gate = Completer<void>();
      final late = controller(server, _StaleReadStore(store, gate.future));
      final early = controller(server, store);

      final lateRefresh = late.refresh(); // reads refresh-one, then waits
      await pumpEventQueue();
      expect(await early.refresh(), DriverTokenRefreshOutcome.refreshed);
      gate.complete();
      final outcome = await lateRefresh;

      expect(server.received, ['refresh-one', 'refresh-one']);
      expect(outcome, DriverTokenRefreshOutcome.refreshed);
      expect(await store.readRefreshToken(), 'refresh-two');
    });
  });

  group('a lost answer, retried', () {
    test('today (no rotation): the retry succeeds', () async {
      final store = await storedSession();
      final outcome = await controller(
        _Scripted([
          _lost(),
          ApiResponse<Map<String, Object?>>.success(<String, Object?>{
            'access': 'access-two',
          }, statusCode: 200),
        ]),
        store,
      ).refresh();

      expect(outcome, DriverTokenRefreshOutcome.refreshed);
      expect(await store.readAccessToken(), 'access-two');
      expect(await store.readRefreshToken(), 'refresh-one');
    });

    test('with rotation and no reuse grace on the server, the retry is refused '
        'and the driver is signed out (the grace in the rotation design is '
        'what fixes this)', () async {
      final store = await storedSession();
      final server = _RotatingServer(answerAtOnce: true, loseFirstAnswer: true);

      final outcome = await controller(server, store).refresh();

      expect(server.received, ['refresh-one', 'refresh-one']);
      expect(outcome, DriverTokenRefreshOutcome.sessionExpired);
      expect(await store.readRefreshToken(), isNull);
    });
  });
}

ApiResponse<Map<String, Object?>> _status(int status) =>
    ApiResponse<Map<String, Object?>>.apiFailure(
      AsmApiException(
        type: status == 401
            ? AsmApiExceptionType.authentication
            : status == 404
            ? AsmApiExceptionType.notFound
            : AsmApiExceptionType.badResponse,
        message: 'refused',
        statusCode: status,
      ),
    );

ApiResponse<Map<String, Object?>> _lost() =>
    ApiResponse<Map<String, Object?>>.clientException(
      const AsmApiException(
        type: AsmApiExceptionType.network,
        message: 'connection reset',
      ),
    );

final class _Scripted implements driver_main.DriverSessionRefreshApiGateway {
  _Scripted(this.script);

  final List<ApiResponse<Map<String, Object?>>> script;
  var calls = 0;

  @override
  Future<ApiResponse<T>> post<T>(
    String path, {
    required Map<String, Object?> body,
    JsonDecoder<T>? decoder,
  }) async {
    final next = script[calls < script.length ? calls : script.length - 1];
    calls += 1;
    return next as ApiResponse<T>;
  }
}

/// Rotation with blacklist-after-rotation: each refresh token works once.
final class _RotatingServer
    implements driver_main.DriverSessionRefreshApiGateway {
  _RotatingServer({this.answerAtOnce = false, this.loseFirstAnswer = false});

  final bool answerAtOnce;
  final bool loseFirstAnswer;
  final received = <String>[];
  final _pending = <Completer<ApiResponse<Map<String, Object?>>>>[];
  final _used = <String>{};
  var _issued = 1;

  static const _names = ['one', 'two', 'three', 'four'];

  ApiResponse<Map<String, Object?>> _answer(String token) {
    if (!_used.add(token)) {
      return _status(401);
    }
    _issued += 1;
    return ApiResponse<Map<String, Object?>>.success(<String, Object?>{
      'access': 'access-${_names[_issued - 1]}',
      'refresh': 'refresh-${_names[_issued - 1]}',
    }, statusCode: 200);
  }

  @override
  Future<ApiResponse<T>> post<T>(
    String path, {
    required Map<String, Object?> body,
    JsonDecoder<T>? decoder,
  }) async {
    final token = body['refresh']! as String;
    received.add(token);
    if (answerAtOnce) {
      final answer = _answer(token);
      // The server handled it, but the answer never reached the phone.
      if (loseFirstAnswer && received.length == 1) {
        return _lost() as ApiResponse<T>;
      }
      return answer as ApiResponse<T>;
    }
    final pending = Completer<ApiResponse<Map<String, Object?>>>();
    _pending.add(pending);
    return await pending.future as ApiResponse<T>;
  }

  void answerInReverseOrder() {
    final answers = [for (final token in received) _answer(token)];
    for (var i = _pending.length - 1; i >= 0; i -= 1) {
      _pending[i].complete(answers[i]);
    }
  }
}

final class _StaleReadStore implements AuthTokenStore {
  _StaleReadStore(this.inner, this.gate);

  final AuthTokenStore inner;
  final Future<void> gate;
  var _first = true;

  @override
  Future<String?> readRefreshToken() async {
    final value = await inner.readRefreshToken();
    if (_first) {
      _first = false;
      await gate;
    }
    return value;
  }

  @override
  Future<String?> readAccessToken() => inner.readAccessToken();

  @override
  Future<void> saveTokens(AuthTokens tokens) => inner.saveTokens(tokens);

  @override
  Future<void> clearTokens() => inner.clearTokens();
}

final class _FixedAdapter implements HttpClientAdapter {
  _FixedAdapter(this.status, this.body, this.contentType);

  final int status;
  final String body;
  final String contentType;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    body,
    status,
    headers: {
      Headers.contentTypeHeader: [contentType],
    },
  );

  @override
  void close({bool force = false}) {}
}
