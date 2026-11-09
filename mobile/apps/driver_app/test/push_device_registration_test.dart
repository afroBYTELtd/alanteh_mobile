import 'dart:async';

import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_auth/asm_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:driver_app/notifications/push_device_registration.dart';

void main() {
  group('FirebasePushDeviceRegistrar', () {
    test(
      'registers initial token with exact backend contract on 200',
      () async {
        final tokens = _FakeTokenSource(initialToken: '  FCM-TOKEN-1  ');
        final gateway = _RecordingGateway(statusCode: 200);
        final registrar = FirebasePushDeviceRegistrar(
          tokenSource: tokens,
          apiGateway: gateway,
        );

        final result = await registrar.registerForAuthenticatedSession();

        expect(result, isTrue);
        expect(gateway.paths, <String>[pushDeviceRegistrationPath]);
        expect(gateway.bodies, <Map<String, Object?>>[
          <String, Object?>{
            'device_token': 'FCM-TOKEN-1',
            'platform': 'android',
          },
        ]);
        expect(gateway.bodies.single.containsKey('user_id'), isFalse);

        await registrar.dispose();
        await tokens.dispose();
      },
    );

    test('accepts successful registration response on 201', () async {
      final tokens = _FakeTokenSource(initialToken: 'FCM-TOKEN-201');
      final gateway = _RecordingGateway(statusCode: 201);
      final registrar = FirebasePushDeviceRegistrar(
        tokenSource: tokens,
        apiGateway: gateway,
      );

      expect(await registrar.registerForAuthenticatedSession(), isTrue);
      expect(gateway.bodies, hasLength(1));

      await registrar.dispose();
      await tokens.dispose();
    });

    test('forwards token refresh while authenticated', () async {
      final tokens = _FakeTokenSource(initialToken: 'FCM-INITIAL');
      final gateway = _RecordingGateway();
      final registrar = FirebasePushDeviceRegistrar(
        tokenSource: tokens,
        apiGateway: gateway,
      );

      expect(await registrar.registerForAuthenticatedSession(), isTrue);

      tokens.emitRefresh('FCM-REFRESHED');
      await gateway.waitForCallCount(2);

      expect(gateway.bodies.last, <String, Object?>{
        'device_token': 'FCM-REFRESHED',
        'platform': 'android',
      });

      await registrar.dispose();
      await tokens.dispose();
    });

    test('ignores token refresh after authenticated session ends', () async {
      final tokens = _FakeTokenSource(initialToken: 'FCM-INITIAL');
      final gateway = _RecordingGateway();
      final registrar = FirebasePushDeviceRegistrar(
        tokenSource: tokens,
        apiGateway: gateway,
      );

      expect(await registrar.registerForAuthenticatedSession(), isTrue);
      registrar.endAuthenticatedSession();

      tokens.emitRefresh('FCM-MUST-NOT-POST');
      await Future<void>.delayed(Duration.zero);

      expect(gateway.bodies, hasLength(1));

      await registrar.dispose();
      await tokens.dispose();
    });

    test('re-login obtains and registers the current token again', () async {
      final tokens = _FakeTokenSource(initialToken: 'FCM-FIRST');
      final gateway = _RecordingGateway();
      final registrar = FirebasePushDeviceRegistrar(
        tokenSource: tokens,
        apiGateway: gateway,
      );

      expect(await registrar.registerForAuthenticatedSession(), isTrue);
      registrar.endAuthenticatedSession();

      tokens.initialToken = 'FCM-SECOND';
      expect(await registrar.registerForAuthenticatedSession(), isTrue);

      expect(gateway.bodies, <Map<String, Object?>>[
        <String, Object?>{'device_token': 'FCM-FIRST', 'platform': 'android'},
        <String, Object?>{'device_token': 'FCM-SECOND', 'platform': 'android'},
      ]);

      await registrar.dispose();
      await tokens.dispose();
    });

    test('missing token is non-blocking and does not call backend', () async {
      final tokens = _FakeTokenSource(initialToken: '   ');
      final gateway = _RecordingGateway();
      final registrar = FirebasePushDeviceRegistrar(
        tokenSource: tokens,
        apiGateway: gateway,
      );

      expect(await registrar.registerForAuthenticatedSession(), isFalse);
      expect(gateway.bodies, isEmpty);

      await registrar.dispose();
      await tokens.dispose();
    });

    test('non-success status is non-blocking', () async {
      final tokens = _FakeTokenSource(initialToken: 'FCM-TOKEN');
      final gateway = _RecordingGateway(statusCode: 500);
      final registrar = FirebasePushDeviceRegistrar(
        tokenSource: tokens,
        apiGateway: gateway,
      );

      expect(await registrar.registerForAuthenticatedSession(), isFalse);
      expect(gateway.bodies, hasLength(1));

      await registrar.dispose();
      await tokens.dispose();
    });

    test('malformed success payload is rejected', () async {
      final tokens = _FakeTokenSource(initialToken: 'FCM-TOKEN');
      final gateway = _RecordingGateway(
        responseData: <String, Object?>{
          'device_token_registered': true,
          'platform': 'android',
          'active': false,
        },
      );
      final registrar = FirebasePushDeviceRegistrar(
        tokenSource: tokens,
        apiGateway: gateway,
      );

      expect(await registrar.registerForAuthenticatedSession(), isFalse);

      await registrar.dispose();
      await tokens.dispose();
    });

    test('permission result is forwarded without blocking', () async {
      final tokens = _FakeTokenSource(
        initialToken: 'FCM-TOKEN',
        permissionResult: true,
      );
      final registrar = FirebasePushDeviceRegistrar(
        tokenSource: tokens,
        apiGateway: _RecordingGateway(),
      );

      expect(await registrar.requestNotificationPermission(), isTrue);
      expect(tokens.permissionRequestCount, 1);

      await registrar.dispose();
      await tokens.dispose();
    });

    test('permission exception is converted to false', () async {
      final tokens = _FakeTokenSource(
        initialToken: 'FCM-TOKEN',
        throwOnPermission: true,
      );
      final registrar = FirebasePushDeviceRegistrar(
        tokenSource: tokens,
        apiGateway: _RecordingGateway(),
      );

      expect(await registrar.requestNotificationPermission(), isFalse);

      await registrar.dispose();
      await tokens.dispose();
    });
  });

  // Sign-in build A2: registration carries this install's id, so the server
  // can retire this phone's older rows; sign-out sends the token in use.
  group('installation id (A2)', () {
    test('registration and token refresh send the installation id', () async {
      final tokens = _FakeTokenSource(initialToken: ' FCM-1 ');
      final gateway = _RecordingGateway();
      final registrar = FirebasePushDeviceRegistrar(
        tokenSource: tokens,
        apiGateway: gateway,
        installationIdStore: MemoryInstallationIdStore('install-1'),
      );

      expect(await registrar.registerForAuthenticatedSession(), isTrue);
      tokens.emitRefresh('FCM-2');
      await gateway.waitForCallCount(2);

      expect(gateway.bodies, <Map<String, Object?>>[
        <String, Object?>{
          'device_token': 'FCM-1',
          'platform': 'android',
          'installation_id': 'install-1',
        },
        <String, Object?>{
          'device_token': 'FCM-2',
          'platform': 'android',
          'installation_id': 'install-1',
        },
      ]);

      await registrar.dispose();
      await tokens.dispose();
    });

    test('an id that cannot be read does not stop registration', () async {
      final tokens = _FakeTokenSource(initialToken: 'FCM-1');
      final gateway = _RecordingGateway();
      final registrar = FirebasePushDeviceRegistrar(
        tokenSource: tokens,
        apiGateway: gateway,
        installationIdStore: _FailingInstallationIdStore(),
      );

      expect(await registrar.registerForAuthenticatedSession(), isTrue);
      expect(gateway.bodies.single, <String, Object?>{
        'device_token': 'FCM-1',
        'platform': 'android',
      });

      await registrar.dispose();
      await tokens.dispose();
    });

    test('deviceToken is the token last sent, for sign-out', () async {
      final tokens = _FakeTokenSource(initialToken: ' FCM-1 ');
      final gateway = _RecordingGateway();
      final registrar = FirebasePushDeviceRegistrar(
        tokenSource: tokens,
        apiGateway: gateway,
      );

      final before = registrar.deviceToken;
      await registrar.registerForAuthenticatedSession();
      final afterRegistration = registrar.deviceToken;
      tokens.emitRefresh('FCM-2');
      await gateway.waitForCallCount(2);

      expect(before, isNull);
      expect(afterRegistration, 'FCM-1');
      expect(registrar.deviceToken, 'FCM-2');

      await registrar.dispose();
      await tokens.dispose();
    });

    // Lead, 7 Nov (3d): built the way production builds it (no id store
    // passed), with secure storage holding a known id: the request carries
    // that id. Only the token source and the gateway are swapped, because
    // the default ones need Firebase and the network.
    test('the default registrar sends the id kept in secure storage', () async {
      const knownId = '0123456789abcdef0123456789abcdef';
      FlutterSecureStorage.setMockInitialValues(<String, String>{
        SecureInstallationIdStore.key: knownId,
      });
      final tokens = _FakeTokenSource(initialToken: 'FCM-1');
      final gateway = _RecordingGateway();
      final registrar = FirebasePushDeviceRegistrar.withDefaultClient(
        tokenStore: MemoryAuthTokenStore(),
        baseUrl: 'https://push-test.alanteh.invalid',
        tokenSource: tokens,
        apiGateway: gateway,
      );

      expect(await registrar.registerForAuthenticatedSession(), isTrue);
      expect(gateway.bodies.single['installation_id'], knownId);

      await registrar.dispose();
      await tokens.dispose();
    });
  });
  // T2 (lead, 8 Nov): a 401 refreshes the session once and registers once
  // more; otherwise false, as before.
  group('T2 a 401 on registration', () {
    ApiResponse<Map<String, Object?>> unauthorized() =>
        ApiResponse<Map<String, Object?>>.apiFailure(
          const AsmApiException(
            type: AsmApiExceptionType.authentication,
            message: 'Unauthenticated.',
            statusCode: 401,
          ),
        );

    Future<(bool, int, int)> register(
      List<ApiResponse<Map<String, Object?>>> answers, {
      bool? refreshes,
      bool refreshThrows = false,
    }) async {
      final tokens = _FakeTokenSource(initialToken: 'FCM-T2');
      final gateway = _ScriptedGateway(answers);
      var refreshCalls = 0;
      final registrar = FirebasePushDeviceRegistrar(
        tokenSource: tokens,
        apiGateway: gateway,
        refreshSession: refreshes == null && !refreshThrows
            ? null
            : () async {
                refreshCalls += 1;
                if (refreshThrows) {
                  throw StateError('no network');
                }
                return refreshes!;
              },
      );
      final result = await registrar.registerForAuthenticatedSession();
      await registrar.dispose();
      await tokens.dispose();
      return (result, gateway.posts, refreshCalls);
    }

    test('then a refresh that works: registered, two posts', () async {
      expect(await register([unauthorized(), _registered()], refreshes: true), (
        true,
        2,
        1,
      ));
    });

    test('then a refused refresh: false after one post', () async {
      expect(
        await register([unauthorized(), _registered()], refreshes: false),
        (false, 1, 1),
      );
    });

    test('then a refresh that throws: false after one post', () async {
      expect(
        await register([unauthorized(), _registered()], refreshThrows: true),
        (false, 1, 1),
      );
    });

    test('T2d: a refresh that works, then 401 again: false, exactly two '
        'posts', () async {
      expect(
        await register([
          unauthorized(),
          unauthorized(),
          _registered(),
        ], refreshes: true),
        (false, 2, 1),
      );
    });

    test('with no refresh to ask: false after one post', () async {
      expect(await register([unauthorized(), _registered()]), (false, 1, 0));
    });
  });
}

final class _FakeTokenSource implements PushMessagingTokenSource {
  _FakeTokenSource({
    this.initialToken,
    this.permissionResult = false,
    this.throwOnPermission = false,
  });

  String? initialToken;
  final bool permissionResult;
  final bool throwOnPermission;
  int permissionRequestCount = 0;

  final StreamController<String> _refreshController =
      StreamController<String>.broadcast(sync: true);

  @override
  Future<String?> getToken() async => initialToken;

  @override
  Stream<String> get onTokenRefresh => _refreshController.stream;

  @override
  Future<bool> requestNotificationPermission() async {
    permissionRequestCount += 1;
    if (throwOnPermission) {
      throw StateError('permission failure');
    }
    return permissionResult;
  }

  void emitRefresh(String token) {
    _refreshController.add(token);
  }

  Future<void> dispose() => _refreshController.close();
}

final class _RecordingGateway implements PushDeviceRegistrationApiGateway {
  _RecordingGateway({this.statusCode = 200, Map<String, Object?>? responseData})
    : responseData =
          responseData ??
          <String, Object?>{
            'device_token_registered': true,
            'platform': 'android',
            'active': true,
          };

  final int statusCode;
  final Map<String, Object?> responseData;

  final List<String> paths = <String>[];
  final List<Map<String, Object?>> bodies = <Map<String, Object?>>[];
  final List<Completer<void>> _waiters = <Completer<void>>[];

  @override
  Future<ApiResponse<Map<String, Object?>>> post(
    String path, {
    required Map<String, Object?> data,
  }) async {
    paths.add(path);
    bodies.add(Map<String, Object?>.of(data));

    for (final waiter in List<Completer<void>>.of(_waiters)) {
      if (!waiter.isCompleted) {
        waiter.complete();
      }
    }
    _waiters.clear();

    return ApiResponse<Map<String, Object?>>.success(
      Map<String, Object?>.of(responseData),
      statusCode: statusCode,
    );
  }

  Future<void> waitForCallCount(int expected) async {
    while (bodies.length < expected) {
      final waiter = Completer<void>();
      _waiters.add(waiter);
      await waiter.future;
    }
  }
}

final class _FailingInstallationIdStore implements InstallationIdStore {
  @override
  Future<String> readOrCreate() => Future.error(StateError('no storage'));
}

ApiResponse<Map<String, Object?>> _registered() =>
    ApiResponse<Map<String, Object?>>.success(<String, Object?>{
      'device_token_registered': true,
      'platform': 'android',
      'active': true,
    }, statusCode: 201);

/// Answers each registration with the next scripted reply.
final class _ScriptedGateway implements PushDeviceRegistrationApiGateway {
  _ScriptedGateway(this.answers);

  final List<ApiResponse<Map<String, Object?>>> answers;
  var posts = 0;

  @override
  Future<ApiResponse<Map<String, Object?>>> post(
    String path, {
    required Map<String, Object?> data,
  }) async => answers[posts++];
}
