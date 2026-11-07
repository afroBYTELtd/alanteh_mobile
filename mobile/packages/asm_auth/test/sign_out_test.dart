import 'dart:async';
import 'dart:math';

import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_auth/asm_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

// Sign-in build A1: sign-out tells the server (5 s limit), clears the tokens
// either way, and keeps a pending sign-out when the server could not be told.
// Lead decision (b), 7 Nov: a pending record is sent at app start only while
// no one is signed in (kept until 200, dropped after 31 days); right after a
// new sign-in it is sent once and dropped whatever the answer.

final _now = DateTime.utc(2026, 11, 7, 12);

ApiResponse<Map<String, Object?>> _ok() => ApiResponse.success(
  const <String, Object?>{'detail': 'Signed out.'},
  statusCode: 200,
);

ApiResponse<Map<String, Object?>> _status(int code, [Object? body]) =>
    ApiResponse.apiFailure(
      AsmApiException(
        type: code >= 500
            ? AsmApiExceptionType.server
            : AsmApiExceptionType.badResponse,
        message: 'status $code',
        statusCode: code,
        cause: body,
      ),
    );

ApiResponse<Map<String, Object?>> _network() => ApiResponse.clientException(
  const AsmApiException(
    type: AsmApiExceptionType.network,
    message: 'no network',
  ),
);

ApiResponse<Map<String, Object?>> _activeTrip() => _status(409, {
  'detail': 'You have an active trip. Call dispatch before signing out.',
  'code': 'active_trip',
});

/// Every kind of answer a logout can get; null never answers.
final _everyAnswer = <String, ApiResponse<Map<String, Object?>>? Function()>{
  '200': _ok,
  '409 active_trip': _activeTrip,
  '429': () => _status(429),
  '500': () => _status(500),
  'network': _network,
  'no answer within the limit': () => null,
};

PendingSignOut _record(
  String refresh, {
  DateTime? at,
  String? deviceToken = 'fcm-1',
  String? installationId = 'install-1',
}) => PendingSignOut(
  refresh: refresh,
  createdAt: at ?? _now,
  deviceToken: deviceToken,
  installationId: installationId,
);

class _Call {
  _Call(this.path, this.body);

  final String path;
  final Map<String, Object?> body;
}

class _Gateway implements AuthApiGateway {
  final calls = <_Call>[];

  /// Logout answers in order; the last one repeats. A null answer never
  /// completes.
  final answers = <ApiResponse<Map<String, Object?>>?>[];

  /// The sign-in answer; a 200 with new tokens unless set.
  ApiResponse<Map<String, Object?>>? signInAnswer;

  /// Runs when a call arrives, before it is answered.
  void Function()? onCall;

  @override
  Future<ApiResponse<Map<String, Object?>>> post(
    String path, {
    required Map<String, Object?> body,
  }) {
    calls.add(_Call(path, Map.of(body)));
    onCall?.call();
    if (path == AuthService.tokenPath) {
      return Future.value(
        signInAnswer ??
            ApiResponse.success(<String, Object?>{
              'access': 'access-new',
              'refresh': 'refresh-new',
              'account_type': 'driver',
            }, statusCode: 200),
      );
    }
    final index = min(
      calls.where((c) => c.path == path).length - 1,
      answers.length - 1,
    );
    final answer = answers.isEmpty ? _ok() : answers[index];
    if (answer == null) {
      return Completer<ApiResponse<Map<String, Object?>>>().future;
    }
    return Future.value(answer);
  }

  List<_Call> get logouts =>
      calls.where((c) => c.path == AuthService.logoutPath).toList();
}

class _Harness {
  _Harness({Duration limit = const Duration(milliseconds: 50)}) {
    service = AuthService(
      apiGateway: gateway,
      tokenStore: tokens,
      pendingSignOutStore: pending,
      installationIdStore: installation,
      logoutTimeout: limit,
      now: () => clock,
    );
  }

  final gateway = _Gateway();
  final tokens = MemoryAuthTokenStore();
  final pending = MemoryPendingSignOutStore();
  final installation = MemoryInstallationIdStore('install-1');
  DateTime clock = _now;
  late final AuthService service;

  Future<void> signedIn([String refresh = 'refresh-1']) => tokens.saveTokens(
    AuthTokens(accessToken: 'access-1', refreshToken: refresh),
  );
}

void main() {
  group('signOut', () {
    test(
      'tells the server first, with refresh, device token and installation id',
      () async {
        final h = _Harness();
        await h.signedIn();
        String? refreshWhenCalled;
        h.gateway.onCall = () async {
          refreshWhenCalled = await h.tokens.readRefreshToken();
        };

        final result = await h.service.signOut(deviceToken: 'fcm-1');

        expect(result.outcome, SignOutOutcome.signedOut);
        expect(h.gateway.logouts.single.body, {
          'refresh': 'refresh-1',
          'device_token': 'fcm-1',
          'installation_id': 'install-1',
        });
        expect(refreshWhenCalled, 'refresh-1');
        expect(await h.tokens.readRefreshToken(), isNull);
        expect(await h.tokens.readAccessToken(), isNull);
        expect(await h.pending.read(), isEmpty);
      },
    );

    test('leaves out a device token it does not have', () async {
      final h = _Harness();
      await h.signedIn();

      await h.service.signOut();

      expect(h.gateway.logouts.single.body, {
        'refresh': 'refresh-1',
        'installation_id': 'install-1',
      });
    });

    test(
      'a pending record is written before the call (a kill mid-call keeps it)',
      () async {
        final h = _Harness();
        await h.signedIn();
        List<PendingSignOut>? pendingDuringCall;
        h.gateway.answers.add(null); // never answers
        h.gateway.onCall = () async {
          pendingDuringCall = await h.pending.read();
        };

        await h.service.signOut(deviceToken: 'fcm-1');

        expect(pendingDuringCall, hasLength(1));
        expect(pendingDuringCall!.single.refresh, 'refresh-1');
      },
    );

    for (final failure
        in <String, ApiResponse<Map<String, Object?>>? Function()>{
          'network': _network,
          '429': () => _status(429),
          '500': () => _status(500),
          '503': () => _status(503),
          'no answer within the limit': () => null,
        }.entries) {
      test(
        '${failure.key}: signed out on the phone, sign-out kept pending',
        () async {
          final h = _Harness();
          await h.signedIn();
          h.gateway.answers.add(failure.value());

          final result = await h.service.signOut(deviceToken: 'fcm-1');

          expect(result.outcome, SignOutOutcome.signedOutPending);
          expect(await h.tokens.readRefreshToken(), isNull);
          final kept = await h.pending.read();
          expect(kept.single.toBody(), {
            'refresh': 'refresh-1',
            'device_token': 'fcm-1',
            'installation_id': 'install-1',
          });
          expect(kept.single.createdAt, _now);
        },
      );
    }

    test('the limit is the 5 s design value by default', () {
      expect(AuthService.defaultLogoutTimeout, const Duration(seconds: 5));
    });

    test(
      '409 active_trip: stays signed in, nothing pending, server message shown',
      () async {
        final h = _Harness();
        await h.signedIn();
        h.gateway.answers.add(_activeTrip());

        final result = await h.service.signOut(deviceToken: 'fcm-1');

        expect(result.outcome, SignOutOutcome.activeTrip);
        expect(
          result.message,
          'You have an active trip. Call dispatch before signing out.',
        );
        expect(await h.tokens.readRefreshToken(), 'refresh-1');
        expect(await h.tokens.readAccessToken(), 'access-1');
        expect(await h.pending.read(), isEmpty);
      },
    );

    test('a 409 without the active_trip code is not the trip answer', () async {
      final h = _Harness();
      await h.signedIn();
      h.gateway.answers.add(_status(409, {'code': 'something_else'}));

      final result = await h.service.signOut();

      expect(result.outcome, SignOutOutcome.signedOutPending);
      expect(await h.tokens.readRefreshToken(), isNull);
    });

    test('nothing stored: no call, nothing pending', () async {
      final h = _Harness();

      final result = await h.service.signOut(deviceToken: 'fcm-1');

      expect(result.outcome, SignOutOutcome.signedOut);
      expect(h.gateway.logouts, isEmpty);
      expect(await h.pending.read(), isEmpty);
    });

    test('a second failed sign-out keeps both records', () async {
      final h = _Harness();
      h.gateway.answers.add(_network());
      await h.signedIn('refresh-1');
      await h.service.signOut(deviceToken: 'fcm-1');
      await h.signedIn('refresh-2');
      await h.service.signOut(deviceToken: 'fcm-1');

      final kept = await h.pending.read();

      expect(kept.map((r) => r.refresh), ['refresh-1', 'refresh-2']);
    });

    test(
      'at most ${AuthService.maxPendingSignOuts} records; the oldest goes',
      () async {
        final h = _Harness();
        h.gateway.answers.add(_network());
        for (var i = 1; i <= AuthService.maxPendingSignOuts + 1; i++) {
          await h.signedIn('refresh-$i');
          await h.service.signOut();
        }

        final kept = await h.pending.read();

        expect(kept, hasLength(AuthService.maxPendingSignOuts));
        expect(kept.first.refresh, 'refresh-2');
      },
    );
  });

  group('sendPendingSignOuts (app start, no one signed in)', () {
    Future<_Harness> withPending(List<PendingSignOut> records) async {
      final h = _Harness();
      await h.pending.write(records);
      return h;
    }

    final record = _record('refresh-old');

    test('200: sent once with the stored fields, then dropped', () async {
      final h = await withPending([record]);

      final left = await h.service.sendPendingSignOuts();
      await h.service.sendPendingSignOuts();

      expect(left, 0);
      expect(h.gateway.logouts.single.body, record.toBody());
      expect(await h.pending.read(), isEmpty);
    });

    for (final failure
        in <String, ApiResponse<Map<String, Object?>>? Function()>{
          'network': _network,
          '429': () => _status(429),
          '500': () => _status(500),
          'a 409': _activeTrip,
          'a 400': () => _status(400),
          'no answer within the limit': () => null,
        }.entries) {
      test('${failure.key}: kept for the next start', () async {
        final h = await withPending([record]);
        h.gateway.answers.add(failure.value());

        final left = await h.service.sendPendingSignOuts();

        expect(left, 1);
        expect((await h.pending.read()).single.toJson(), record.toJson());
      });
    }

    test(
      'each record stands alone: only the answered one is dropped',
      () async {
        final h = await withPending([record, _record('refresh-older')]);
        h.gateway.answers
          ..add(_ok())
          ..add(_network());

        final left = await h.service.sendPendingSignOuts();

        expect(left, 1);
        expect((await h.pending.read()).single.refresh, 'refresh-older');
      },
    );

    test('never sent while someone is signed in; kept', () async {
      final h = await withPending([record]);
      await h.signedIn('refresh-now');

      final left = await h.service.sendPendingSignOuts();

      expect(h.gateway.logouts, isEmpty);
      expect(left, 1);
      expect(await h.tokens.readRefreshToken(), 'refresh-now');
    });

    test('older than 31 days: dropped without sending', () async {
      final h = await withPending([
        _record(
          'refresh-expired',
          at: _now.subtract(const Duration(days: 31, minutes: 1)),
        ),
        _record('refresh-30-days', at: _now.subtract(const Duration(days: 30))),
      ]);

      final left = await h.service.sendPendingSignOuts();

      expect(left, 0);
      expect(h.gateway.logouts.map((c) => c.body['refresh']), [
        'refresh-30-days',
      ]);
      expect(await h.pending.read(), isEmpty);
    });

    test('an expired record goes even when the network is down', () async {
      final h = await withPending([
        _record('refresh-expired', at: _now.subtract(const Duration(days: 40))),
      ]);
      h.gateway.answers.add(_network());

      final left = await h.service.sendPendingSignOuts();

      expect(left, 0);
      expect(await h.pending.read(), isEmpty);
    });

    test('the age limit is 31 days', () {
      expect(AuthService.pendingSignOutMaxAge, const Duration(days: 31));
    });

    test('two starts at once send one request', () async {
      final h = await withPending([record]);

      await Future.wait([
        h.service.sendPendingSignOuts(),
        h.service.sendPendingSignOuts(),
      ]);

      expect(h.gateway.logouts, hasLength(1));
    });
  });

  group('right after a new sign-in', () {
    for (final answer in _everyAnswer.entries) {
      test(
        '${answer.key}: each record sent once (refresh only), then gone',
        () async {
          final h = _Harness();
          await h.pending.write([
            _record('refresh-old'),
            _record('refresh-older', deviceToken: null),
          ]);
          h.gateway.answers.add(answer.value());

          final state = await h.service.login('+233000000001', '1234');
          final atStartLater = await h.service.sendPendingSignOuts();

          expect(state.status, AuthStatus.authenticated);
          expect(h.gateway.logouts.map((c) => c.body), [
            {'refresh': 'refresh-old'},
            {'refresh': 'refresh-older'},
          ]);
          expect(await h.pending.read(), isEmpty);
          expect(atStartLater, 0);
          expect(await h.tokens.readRefreshToken(), 'refresh-new');
        },
      );
    }

    test('sign-in finishes only after the sends (before duty loads)', () async {
      final h = _Harness(limit: const Duration(seconds: 5));
      await h.pending.write([_record('refresh-old')]);
      final logoutAnswer = Completer<ApiResponse<Map<String, Object?>>>();
      final gateway = _ControlledGateway(h.gateway, logoutAnswer.future);
      final service = AuthService(
        apiGateway: gateway,
        tokenStore: h.tokens,
        pendingSignOutStore: h.pending,
        installationIdStore: h.installation,
        now: () => h.clock,
      );
      var signedIn = false;

      final signingIn = service
          .login('+233000000001', '1234')
          .then((_) => signedIn = true);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final beforeAnswer = signedIn;
      logoutAnswer.complete(_ok());
      await signingIn;

      expect(h.gateway.calls.map((c) => c.path), [
        AuthService.tokenPath,
        AuthService.logoutPath,
      ]);
      expect(beforeAnswer, isFalse);
      expect(signedIn, isTrue);
    });

    test(
      'the sends run side by side: sign-in waits at most about one limit',
      () async {
        final h = _Harness(limit: const Duration(milliseconds: 200));
        await h.pending.write([
          _record('refresh-a'),
          _record('refresh-b'),
          _record('refresh-c'),
        ]);
        h.gateway.answers.add(null); // never answers
        final watch = Stopwatch()..start();

        await h.service.login('+233000000001', '1234');

        expect(h.gateway.logouts, hasLength(3));
        expect(watch.elapsedMilliseconds, lessThan(450));
        expect(await h.pending.read(), isEmpty);
      },
    );

    test('nothing pending: no logout call at sign-in', () async {
      final h = _Harness();

      await h.service.login('+233000000001', '1234');

      expect(h.gateway.logouts, isEmpty);
    });

    test('a refused sign-in leaves the records as they were', () async {
      final h = _Harness();
      final records = [_record('refresh-old')];
      await h.pending.write(records);
      h.gateway.signInAnswer = _status(401, {'detail': 'Invalid credentials'});

      final state = await h.service.login('+233000000001', '1234');

      expect(state.status, AuthStatus.unauthenticated);
      expect(h.gateway.logouts, isEmpty);
      expect(
        (await h.pending.read()).map((r) => r.toJson()),
        records.map((r) => r.toJson()),
      );
    });

    test(
      'a sign-in whose tokens cannot be saved leaves the records as they were',
      () async {
        final h = _Harness();
        final records = [_record('refresh-old')];
        await h.pending.write(records);
        final service = AuthService(
          apiGateway: h.gateway,
          tokenStore: _FailingSaveTokenStore(),
          pendingSignOutStore: h.pending,
          now: () => h.clock,
        );

        final state = await service.login('+233000000001', '1234');

        expect(state.status, AuthStatus.unauthenticated);
        expect(h.gateway.logouts, isEmpty);
        expect(
          (await h.pending.read()).map((r) => r.toJson()),
          records.map((r) => r.toJson()),
        );
      },
    );

    test('an invalid sign-in form leaves the records as they were', () async {
      final h = _Harness();
      final records = [_record('refresh-old')];
      await h.pending.write(records);

      await expectLater(
        h.service.login('not-a-phone', '1234'),
        throwsA(isA<AuthException>()),
      );

      expect(h.gateway.logouts, isEmpty);
      expect(
        (await h.pending.read()).map((r) => r.toJson()),
        records.map((r) => r.toJson()),
      );
    });
  });

  group('installation id', () {
    test(
      'made once, random, at most 64 characters, kept across sign-outs',
      () async {
        FlutterSecureStorage.setMockInitialValues(<String, String>{});
        final store = SecureInstallationIdStore();

        final first = await store.readOrCreate();
        final second = await SecureInstallationIdStore().readOrCreate();
        await SecureAuthTokenStore().clearTokens();
        final third = await store.readOrCreate();
        FlutterSecureStorage.setMockInitialValues(<String, String>{});
        final otherPhone = await SecureInstallationIdStore().readOrCreate();

        expect(first, matches(RegExp(r'^[0-9a-f]{32}$')));
        expect(second, first);
        expect(third, first);
        expect(otherPhone, isNot(first));
      },
    );

    test('a stored value that is not an id is replaced', () async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{
        SecureInstallationIdStore.key: 'x' * 65,
      });

      final id = await SecureInstallationIdStore().readOrCreate();

      expect(id, matches(RegExp(r'^[0-9a-f]{32}$')));
    });
  });

  group('secure pending store', () {
    test(
      'round trip with the date; a damaged value reads as nothing pending',
      () async {
        FlutterSecureStorage.setMockInitialValues(<String, String>{});
        const storage = FlutterSecureStorage();
        final store = SecurePendingSignOutStore();
        final records = [
          _record('r1', deviceToken: 'd1', installationId: 'i1'),
          _record(
            'r2',
            at: _now.subtract(const Duration(days: 3)),
            deviceToken: null,
            installationId: null,
          ),
        ];

        await store.write(records);
        final back = await store.read();
        await storage.write(
          key: SecurePendingSignOutStore.key,
          value: '{not json',
        );
        final damaged = await store.read();
        await store.write(const []);

        expect(back.map((r) => r.toJson()), records.map((r) => r.toJson()));
        expect(back.last.createdAt, _now.subtract(const Duration(days: 3)));
        expect(damaged, isEmpty);
        expect(await store.read(), isEmpty);
      },
    );

    test('a stored record without a date is not kept', () async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{
        SecurePendingSignOutStore.key: '[{"refresh": "r1"}]',
      });

      expect(await SecurePendingSignOutStore().read(), isEmpty);
    });

    test('kept across clearTokens', () async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{});
      await SecurePendingSignOutStore().write([_record('r1')]);

      await SecureAuthTokenStore().clearTokens();

      expect(await SecurePendingSignOutStore().read(), hasLength(1));
    });
  });
}

/// Passes sign-in to [inner]; holds every logout until [answer] completes.
class _ControlledGateway implements AuthApiGateway {
  _ControlledGateway(this.inner, this.answer);

  final _Gateway inner;
  final Future<ApiResponse<Map<String, Object?>>> answer;

  @override
  Future<ApiResponse<Map<String, Object?>>> post(
    String path, {
    required Map<String, Object?> body,
  }) {
    if (path == AuthService.logoutPath) {
      inner.calls.add(_Call(path, Map.of(body)));
      return answer;
    }
    return inner.post(path, body: body);
  }
}

class _FailingSaveTokenStore extends MemoryAuthTokenStore {
  @override
  Future<void> saveTokens(AuthTokens tokens) =>
      Future.error(StateError('storage unavailable'));
}
