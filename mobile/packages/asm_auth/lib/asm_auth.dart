import 'package:asm_api_client/asm_api_client.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Required disabled handoff message for future CC4A mobile auth.
const cc4aMobileAuthDisabledMessage =
    'CC4A Mobile auth API is disabled pending Control Center handoff';

/// CC4A mobile auth remains unavailable until Control Center handoff.
bool get mobileAuthAvailable => false;

/// Exception thrown when code tries to require disabled CC4A mobile auth.
class MobileAuthDisabledException implements Exception {
  const MobileAuthDisabledException([
    this.message = cc4aMobileAuthDisabledMessage,
  ]);

  final String message;

  @override
  String toString() => message;
}

/// Guardrail for future CC4A mobile auth access.
void requireMobileAuth() {
  throw const MobileAuthDisabledException();
}

/// Minimum authentication states needed by the Passenger and Driver apps.
enum AuthStatus { loading, authenticated, unauthenticated }

/// User authentication state for future controlled app login flows.
class AuthState {
  const AuthState._({required this.status, this.session, this.error});

  const AuthState.loading() : this._(status: AuthStatus.loading);

  factory AuthState.authenticated(AuthSession session) {
    if (!session.isAuthenticated) {
      throw ArgumentError.value(
        session,
        'session',
        'must include non-empty access and refresh tokens',
      );
    }

    return AuthState._(status: AuthStatus.authenticated, session: session);
  }

  const AuthState.unauthenticated([AuthException? error])
    : this._(status: AuthStatus.unauthenticated, error: error);

  final AuthStatus status;
  final AuthSession? session;
  final AuthException? error;

  bool get isLoading => status == AuthStatus.loading;
  bool get isAuthenticated => status == AuthStatus.authenticated;
  bool get isUnauthenticated => status == AuthStatus.unauthenticated;
}

/// Access and refresh token pair returned by future ASM auth endpoints.
class AuthTokens {
  AuthTokens({required String accessToken, required String refreshToken})
    : accessToken = _validateToken(accessToken, 'accessToken'),
      refreshToken = _validateToken(refreshToken, 'refreshToken');

  final String accessToken;
  final String refreshToken;

  bool get isValid => accessToken.isNotEmpty && refreshToken.isNotEmpty;

  static String _validateToken(String token, String fieldName) {
    final trimmed = token.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(token, fieldName, 'must not be empty');
    }
    return trimmed;
  }
}

/// Authenticated session value used by future app auth state.
class AuthSession {
  const AuthSession({required this.tokens});

  final AuthTokens tokens;

  bool get isAuthenticated => tokens.isValid;
}

enum AuthExceptionType { validation, apiFailure, missingRefreshToken, storage }

/// Clear authentication exception for validation, API, and storage failures.
class AuthException implements Exception {
  const AuthException({required this.type, required this.message, this.cause});

  final AuthExceptionType type;
  final String message;
  final Object? cause;

  @override
  String toString() {
    return 'AuthException(type=$type, message=$message)';
  }
}

/// Token storage contract used by [AuthService].
abstract interface class AuthTokenStore {
  Future<void> saveTokens(AuthTokens tokens);

  Future<String?> readAccessToken();

  Future<String?> readRefreshToken();

  Future<void> clearTokens();
}

/// Secure token storage foundation backed by flutter_secure_storage.
class SecureAuthTokenStore implements AuthTokenStore {
  SecureAuthTokenStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const accessTokenKey = 'asm.auth.access_token';
  static const refreshTokenKey = 'asm.auth.refresh_token';

  final FlutterSecureStorage _storage;

  @override
  Future<void> saveTokens(AuthTokens tokens) async {
    await _storage.write(key: accessTokenKey, value: tokens.accessToken);
    await _storage.write(key: refreshTokenKey, value: tokens.refreshToken);
  }

  @override
  Future<String?> readAccessToken() {
    return _storage.read(key: accessTokenKey);
  }

  @override
  Future<String?> readRefreshToken() {
    return _storage.read(key: refreshTokenKey);
  }

  @override
  Future<void> clearTokens() async {
    await _storage.delete(key: accessTokenKey);
    await _storage.delete(key: refreshTokenKey);
  }
}

/// In-memory token storage for tests and local non-platform checks only.
class MemoryAuthTokenStore implements AuthTokenStore {
  String? _accessToken;
  String? _refreshToken;

  @override
  Future<void> saveTokens(AuthTokens tokens) async {
    _accessToken = tokens.accessToken;
    _refreshToken = tokens.refreshToken;
  }

  @override
  Future<String?> readAccessToken() async => _accessToken;

  @override
  Future<String?> readRefreshToken() async => _refreshToken;

  @override
  Future<void> clearTokens() async {
    _accessToken = null;
    _refreshToken = null;
  }
}

/// Minimal API gateway so auth tests can use mocked responses only.
abstract interface class AuthApiGateway {
  Future<ApiResponse<Map<String, Object?>>> post(
    String path, {
    required Map<String, Object?> body,
  });
}

/// Adapter that defines the future Control Center auth endpoint calls.
class AsmAuthApiGateway implements AuthApiGateway {
  const AsmAuthApiGateway(this.client);

  final AsmApiClient client;

  @override
  Future<ApiResponse<Map<String, Object?>>> post(
    String path, {
    required Map<String, Object?> body,
  }) {
    return client.post<Map<String, Object?>>(
      path,
      data: body,
      decoder: _decodeJsonMap,
    );
  }

  static Map<String, Object?> _decodeJsonMap(Object? json) {
    if (json is Map<String, Object?>) {
      return json;
    }
    if (json is Map) {
      return json.map((key, value) => MapEntry('$key', value));
    }
    throw const AuthException(
      type: AuthExceptionType.apiFailure,
      message: 'Authentication response was not a JSON object.',
    );
  }
}

/// Mock-testable authentication service foundation.
class AuthService {
  AuthService({
    required AuthApiGateway apiGateway,
    required AuthTokenStore tokenStore,
  }) : _apiGateway = apiGateway,
       _tokenStore = tokenStore;

  factory AuthService.withApiClient({
    required AsmApiClient client,
    AuthTokenStore? tokenStore,
  }) {
    return AuthService(
      apiGateway: AsmAuthApiGateway(client),
      tokenStore: tokenStore ?? SecureAuthTokenStore(),
    );
  }

  static const tokenPath = '/api/auth/token/';
  static const refreshPath = '/api/auth/token/refresh/';

  final AuthApiGateway _apiGateway;
  final AuthTokenStore _tokenStore;

  Future<AuthState> login(String phone, String pin) async {
    final cleanPhone = phone.trim();
    final cleanPin = pin.trim();

    if (cleanPhone.isEmpty) {
      throw const AuthException(
        type: AuthExceptionType.validation,
        message: 'Phone must not be empty.',
      );
    }
    if (cleanPin.isEmpty) {
      throw const AuthException(
        type: AuthExceptionType.validation,
        message: 'PIN must not be empty.',
      );
    }

    final response = await _apiGateway.post(
      tokenPath,
      body: <String, Object?>{'phone': cleanPhone, 'pin': cleanPin},
    );

    if (!response.isSuccess || response.data == null) {
      await _tokenStore.clearTokens();
      return AuthState.unauthenticated(_authError(response));
    }

    try {
      final tokens = _tokensFromResponse(response.data!);
      await _tokenStore.saveTokens(tokens);
      return AuthState.authenticated(AuthSession(tokens: tokens));
    } on Object catch (error) {
      await _tokenStore.clearTokens();
      return AuthState.unauthenticated(_parseError(error));
    }
  }

  Future<AuthState> refresh() async {
    final storedRefreshToken = (await _tokenStore.readRefreshToken())?.trim();
    if (storedRefreshToken == null || storedRefreshToken.isEmpty) {
      return const AuthState.unauthenticated(
        AuthException(
          type: AuthExceptionType.missingRefreshToken,
          message: 'No refresh token is stored.',
        ),
      );
    }

    final response = await _apiGateway.post(
      refreshPath,
      body: <String, Object?>{'refresh': storedRefreshToken},
    );

    if (!response.isSuccess || response.data == null) {
      await _tokenStore.clearTokens();
      return AuthState.unauthenticated(_authError(response));
    }

    try {
      final tokens = _tokensFromResponse(
        response.data!,
        fallbackRefreshToken: storedRefreshToken,
      );
      await _tokenStore.saveTokens(tokens);
      return AuthState.authenticated(AuthSession(tokens: tokens));
    } on Object catch (error) {
      await _tokenStore.clearTokens();
      return AuthState.unauthenticated(_parseError(error));
    }
  }

  Future<AuthState> logout() async {
    await _tokenStore.clearTokens();
    return const AuthState.unauthenticated();
  }

  Future<AuthState> currentSession() async {
    final accessToken = (await _tokenStore.readAccessToken())?.trim();
    final refreshToken = (await _tokenStore.readRefreshToken())?.trim();

    if (accessToken == null || accessToken.isEmpty) {
      return const AuthState.unauthenticated();
    }
    if (refreshToken == null || refreshToken.isEmpty) {
      return const AuthState.unauthenticated();
    }

    final tokens = AuthTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
    );
    return AuthState.authenticated(AuthSession(tokens: tokens));
  }

  AuthTokens _tokensFromResponse(
    Map<String, Object?> json, {
    String? fallbackRefreshToken,
  }) {
    final accessToken =
        _stringField(json, 'access') ??
        _stringField(json, 'accessToken') ??
        _stringField(json, 'access_token');
    final refreshToken =
        _stringField(json, 'refresh') ??
        _stringField(json, 'refreshToken') ??
        _stringField(json, 'refresh_token') ??
        fallbackRefreshToken;

    if (accessToken == null || refreshToken == null) {
      throw const AuthException(
        type: AuthExceptionType.apiFailure,
        message: 'Authentication response did not include required tokens.',
      );
    }

    return AuthTokens(accessToken: accessToken, refreshToken: refreshToken);
  }

  String? _stringField(Map<String, Object?> json, String key) {
    final value = json[key];
    return value is String ? value : null;
  }

  AuthException _authError(ApiResponse<dynamic> response) {
    final apiError = response.error;
    return AuthException(
      type: AuthExceptionType.apiFailure,
      message: apiError?.message ?? 'Authentication request failed.',
      cause: apiError,
    );
  }

  AuthException _parseError(Object error) {
    if (error is AuthException) {
      return error;
    }
    if (error is ArgumentError) {
      return AuthException(
        type: AuthExceptionType.apiFailure,
        message: 'Authentication response included invalid tokens.',
        cause: error,
      );
    }
    return AuthException(
      type: AuthExceptionType.apiFailure,
      message: 'Authentication response could not be processed.',
      cause: error,
    );
  }
}
