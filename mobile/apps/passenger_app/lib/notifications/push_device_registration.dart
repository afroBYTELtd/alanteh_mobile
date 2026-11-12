// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_auth/asm_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

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

/// Refreshes the app session once; true when it was refreshed (T2).
typedef PushSessionRefresh = Future<bool> Function();

typedef PushDeviceRegistrarFactory =
    PushDeviceRegistrar Function(
      AuthTokenStore tokenStore, {
      PushSessionRefresh? refreshSession,
    });

abstract interface class PushDeviceRegistrar {
  Future<bool> registerForAuthenticatedSession();

  /// The push token last sent for this session, for sign-out (A1).
  String? get deviceToken;

  Future<bool> requestNotificationPermission();

  void endAuthenticatedSession();

  Future<void> dispose();
}

final class FirebasePushDeviceRegistrar implements PushDeviceRegistrar {
  FirebasePushDeviceRegistrar({
    required PushMessagingTokenSource tokenSource,
    required PushDeviceRegistrationApiGateway apiGateway,
    InstallationIdStore? installationIdStore,
    PushSessionRefresh? refreshSession,
  }) : _tokenSource = tokenSource,
       _apiGateway = apiGateway,
       _installationIdStore = installationIdStore,
       _refreshSession = refreshSession;

  /// What the apps use. [tokenSource] and [apiGateway] are for tests only
  /// (the defaults need Firebase and the network); the installation id
  /// store is always the secure one.
  factory FirebasePushDeviceRegistrar.withDefaultClient({
    required AuthTokenStore tokenStore,
    required String baseUrl,
    PushSessionRefresh? refreshSession,
    @visibleForTesting PushMessagingTokenSource? tokenSource,
    @visibleForTesting PushDeviceRegistrationApiGateway? apiGateway,
    @visibleForTesting
    AsmApiClient Function(TokenProvider tokenProvider)? clientFor,
  }) {
    final tokenProvider = _PushDeviceTokenProvider(tokenStore);
    return FirebasePushDeviceRegistrar(
      tokenSource: tokenSource ?? FirebasePushMessagingTokenSource(),
      apiGateway:
          apiGateway ??
          AsmPushDeviceRegistrationApiGateway(
            clientFor?.call(tokenProvider) ??
                AsmApiClient(baseUrl: baseUrl, tokenProvider: tokenProvider),
          ),
      installationIdStore: SecureInstallationIdStore(),
      refreshSession: refreshSession,
    );
  }

  final PushMessagingTokenSource _tokenSource;
  final PushDeviceRegistrationApiGateway _apiGateway;
  final InstallationIdStore? _installationIdStore;
  final PushSessionRefresh? _refreshSession;
  String? _deviceToken;

  @override
  String? get deviceToken => _deviceToken;

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

  /// This install's id (A2), or null when it cannot be read: registration
  /// then goes ahead without it, as older builds do.
  Future<String?> _installationId() async {
    try {
      return await _installationIdStore?.readOrCreate();
    } on Object {
      return null;
    }
  }

  Future<bool> _registerTokenSafely(String? rawToken) async {
    if (!_authenticated || _disposed) {
      return false;
    }

    final token = rawToken?.trim();
    if (token == null || token.isEmpty) {
      return false;
    }

    _deviceToken = token;
    final installationId = await _installationId();
    try {
      var response = await _post(token, installationId);
      if (_unauthorized(response)) {
        // T2: refresh the session once and ask once more; the API client
        // reads the new access token from the store. T2c: a session that
        // ended while the post was out is not refreshed.
        final refresh = _refreshSession;
        if (refresh == null ||
            !_authenticated ||
            _disposed ||
            !await _refreshed(refresh) ||
            !_authenticated ||
            _disposed) {
          return false;
        }
        response = await _post(token, installationId);
      }

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

  Future<ApiResponse<Map<String, Object?>>> _post(
    String token,
    String? installationId,
  ) {
    return _apiGateway.post(
      pushDeviceRegistrationPath,
      data: <String, Object?>{
        'device_token': token,
        'platform': 'android',
        'installation_id': ?installationId,
      },
    );
  }

  static bool _unauthorized(ApiResponse<Map<String, Object?>> response) =>
      response.statusCode == 401 ||
      response.error?.type == AsmApiExceptionType.authentication;

  static Future<bool> _refreshed(PushSessionRefresh refresh) async {
    try {
      return await refresh();
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
