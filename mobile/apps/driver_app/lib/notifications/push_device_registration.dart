// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_auth/asm_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

const String pushDeviceRegistrationPath = '/api/push/devices/';

abstract interface class PushMessagingTokenSource {
  Future<String?> getToken();

  Stream<String> get onTokenRefresh;

  Future<bool> requestNotificationPermission();
}

final class FirebasePushMessagingTokenSource
    implements PushMessagingTokenSource {
  FirebasePushMessagingTokenSource({FirebaseMessaging? messaging})
    : _messaging = messaging ?? FirebaseMessaging.instance;

  final FirebaseMessaging _messaging;

  @override
  Future<String?> getToken() => _messaging.getToken();

  @override
  Stream<String> get onTokenRefresh => _messaging.onTokenRefresh;

  @override
  Future<bool> requestNotificationPermission() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }
}

abstract interface class PushDeviceRegistrationApiGateway {
  Future<ApiResponse<Map<String, Object?>>> post(
    String path, {
    required Map<String, Object?> data,
  });
}

final class AsmPushDeviceRegistrationApiGateway
    implements PushDeviceRegistrationApiGateway {
  const AsmPushDeviceRegistrationApiGateway(this.client);

  final AsmApiClient client;

  @override
  Future<ApiResponse<Map<String, Object?>>> post(
    String path, {
    required Map<String, Object?> data,
  }) {
    return client.post<Map<String, Object?>>(
      path,
      data: data,
      decoder: _decodeObjectMap,
    );
  }
}

typedef PushDeviceRegistrarFactory =
    PushDeviceRegistrar Function(AuthTokenStore tokenStore);

abstract interface class PushDeviceRegistrar {
  Future<bool> registerForAuthenticatedSession();

  Future<bool> requestNotificationPermission();

  void endAuthenticatedSession();

  Future<void> dispose();
}

final class FirebasePushDeviceRegistrar implements PushDeviceRegistrar {
  FirebasePushDeviceRegistrar({
    required PushMessagingTokenSource tokenSource,
    required PushDeviceRegistrationApiGateway apiGateway,
  }) : _tokenSource = tokenSource,
       _apiGateway = apiGateway;

  factory FirebasePushDeviceRegistrar.withDefaultClient({
    required AuthTokenStore tokenStore,
    required String baseUrl,
  }) {
    return FirebasePushDeviceRegistrar(
      tokenSource: FirebasePushMessagingTokenSource(),
      apiGateway: AsmPushDeviceRegistrationApiGateway(
        AsmApiClient(
          baseUrl: baseUrl,
          tokenProvider: _PushDeviceTokenProvider(tokenStore),
        ),
      ),
    );
  }

  final PushMessagingTokenSource _tokenSource;
  final PushDeviceRegistrationApiGateway _apiGateway;

  StreamSubscription<String>? _tokenRefreshSubscription;
  bool _authenticated = false;
  bool _disposed = false;

  @override
  Future<bool> registerForAuthenticatedSession() async {
    if (_disposed) {
      return false;
    }

    _authenticated = true;
    _tokenRefreshSubscription ??= _tokenSource.onTokenRefresh.listen((token) {
      if (_authenticated && !_disposed) {
        unawaited(_registerTokenSafely(token));
      }
    });

    try {
      final token = await _tokenSource.getToken();
      return _registerTokenSafely(token);
    } on Object {
      return false;
    }
  }

  @override
  Future<bool> requestNotificationPermission() async {
    if (_disposed) {
      return false;
    }

    try {
      return await _tokenSource.requestNotificationPermission();
    } on Object {
      return false;
    }
  }

  @override
  void endAuthenticatedSession() {
    _authenticated = false;
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _authenticated = false;
    await _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = null;
  }

  Future<bool> _registerTokenSafely(String? rawToken) async {
    if (!_authenticated || _disposed) {
      return false;
    }

    final token = rawToken?.trim();
    if (token == null || token.isEmpty) {
      return false;
    }

    try {
      final response = await _apiGateway.post(
        pushDeviceRegistrationPath,
        data: <String, Object?>{'device_token': token, 'platform': 'android'},
      );

      if (response.statusCode != 200 && response.statusCode != 201) {
        return false;
      }

      final data = response.data;
      return response.isSuccess &&
          data?['device_token_registered'] == true &&
          data?['platform'] == 'android' &&
          data?['active'] == true;
    } on Object {
      return false;
    }
  }
}

final class _PushDeviceTokenProvider implements TokenProvider {
  const _PushDeviceTokenProvider(this.tokenStore);

  final AuthTokenStore tokenStore;

  @override
  Future<String?> getAccessToken() => tokenStore.readAccessToken();
}

Map<String, Object?> _decodeObjectMap(Object? json) {
  if (json is Map<String, Object?>) {
    return json;
  }

  if (json is Map) {
    return json.map((key, value) => MapEntry(key.toString(), value));
  }

  throw const FormatException(
    'Push device registration response was not a JSON object.',
  );
}
