import 'dart:async';

import 'package:asm_api_client/asm_api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passenger_app/notifications/push_device_registration.dart';

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
