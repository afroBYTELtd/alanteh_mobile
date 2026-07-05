import 'package:asm_api_client/asm_api_client.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Required handoff message for accepted CC4A mobile auth.
const cc4aMobileAuthDisabledMessage =
    'CC4A Mobile auth API is available after accepted Control Center handoff';

/// CC4A mobile auth is available after accepted Control Center handoff.
bool get mobileAuthAvailable => true;

/// Exception thrown when code tries to require disabled CC4A mobile auth.
class MobileAuthDisabledException implements Exception {
  const MobileAuthDisabledException([
    this.message = cc4aMobileAuthDisabledMessage,
  ]);

  final String message;

  @override
  String toString() => message;
}

/// Guardrail for accepted CC4A mobile auth access.
void requireMobileAuth() {}

/// Minimum authentication states needed by the Passenger and Driver apps.
enum AuthStatus { loading, authenticated, unauthenticated }

/// Clear error message for account type/app-context mismatches.
const authAppContextErrorMessage =
    'This account is not allowed to sign in to this app.';

/// User-facing login validation message for a missing Ghana pilot phone.
const loginPhoneRequiredMessage = 'Enter a Ghana phone number.';

/// User-facing login validation message for an invalid Ghana pilot phone.
const loginPhoneFormatMessage = 'Use format +233XXXXXXXXX.';

/// User-facing login validation message for a missing PIN.
const loginPinRequiredMessage = 'Enter your 4-digit PIN.';

/// User-facing login validation message for an invalid PIN.
const loginPinFormatMessage = 'PIN must be 4 digits.';

/// Ghana pilot phone validation for CC4A phone/PIN auth.
bool isValidGhanaPhoneNumber(String phone) {
  return RegExp(r'^\+233\d{9}$').hasMatch(phone);
}

/// Ghana pilot PIN validation for CC4A phone/PIN auth.
bool isValidPin(String pin) {
  return RegExp(r'^\d{4}$').hasMatch(pin);
}

/// Returns the exact user-facing phone validation message, or null when valid.
String? validateGhanaPhoneNumberForLogin(String phone) {
  if (phone.trim().isEmpty) {
    return loginPhoneRequiredMessage;
  }
  if (!isValidGhanaPhoneNumber(phone)) {
    return loginPhoneFormatMessage;
  }
  return null;
}

/// Returns the exact user-facing PIN validation message, or null when valid.
String? validatePinForLogin(String pin) {
  if (pin.trim().isEmpty) {
    return loginPinRequiredMessage;
  }
  if (!isValidPin(pin)) {
    return loginPinFormatMessage;
  }
  return null;
}

/// Account types returned by the finalized CC4A auth response.
enum AuthAccountType {
  passenger,
  driver,
  staff;

  String get backendCode {
    return switch (this) {
      AuthAccountType.passenger => 'passenger',
      AuthAccountType.driver => 'driver',
      AuthAccountType.staff => 'staff',
    };
  }

  static AuthAccountType? tryParse(Object? value) {
    if (value is! String) {
      return null;
    }

    return switch (value.trim()) {
      'passenger' => AuthAccountType.passenger,
      'driver' => AuthAccountType.driver,
      'staff' => AuthAccountType.staff,
      _ => null,
    };
  }

  static AuthAccountType parse(Object? value) {
    final accountType = tryParse(value);
    if (accountType == null) {
      throw const AuthException(
        type: AuthExceptionType.accountType,
        message: authAppContextErrorMessage,
      );
    }

    return accountType;
  }
}

/// App context expected by Passenger and Driver app login flows.
enum AuthAppContext {
  passenger,
  driver;

  AuthAccountType get expectedAccountType {
    return switch (this) {
      AuthAppContext.passenger => AuthAccountType.passenger,
      AuthAppContext.driver => AuthAccountType.driver,
    };
  }

  bool allowsAccountType(AuthAccountType accountType) {
    return accountType == expectedAccountType;
  }

  void validateAccountType(AuthAccountType accountType) {
    if (!allowsAccountType(accountType)) {
      throw const AuthException(
        type: AuthExceptionType.accountType,
        message: authAppContextErrorMessage,
      );
    }
  }
}

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
  const AuthSession({required this.tokens, this.accountType});

  final AuthTokens tokens;
  final AuthAccountType? accountType;

  bool get isAuthenticated => tokens.isValid;
}

enum AuthExceptionType {
  validation,
  apiFailure,
  accountType,
  missingRefreshToken,
  storage,
}

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
    AuthAppContext? appContext,
  }) : _apiGateway = apiGateway,
       _tokenStore = tokenStore,
       _appContext = appContext;

  factory AuthService.withApiClient({
    required AsmApiClient client,
    AuthTokenStore? tokenStore,
    AuthAppContext? appContext,
  }) {
    return AuthService(
      apiGateway: AsmAuthApiGateway(client),
      tokenStore: tokenStore ?? SecureAuthTokenStore(),
      appContext: appContext,
    );
  }

  static const tokenPath = '/api/auth/token/';
  static const refreshPath = '/api/auth/token/refresh/';

  final AuthApiGateway _apiGateway;
  final AuthTokenStore _tokenStore;
  final AuthAppContext? _appContext;

  Future<AuthState> login(String phone, String pin) async {
    final cleanPhone = phone.trim();
    final cleanPin = pin.trim();
    final phoneValidationMessage = validateGhanaPhoneNumberForLogin(phone);
    final pinValidationMessage = validatePinForLogin(pin);

    if (phoneValidationMessage != null) {
      throw AuthException(
        type: AuthExceptionType.validation,
        message: phoneValidationMessage,
      );
    }
    if (pinValidationMessage != null) {
      throw AuthException(
        type: AuthExceptionType.validation,
        message: pinValidationMessage,
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
      final session = _sessionFromLoginResponse(response.data!);
      await _tokenStore.saveTokens(session.tokens);
      return AuthState.authenticated(session);
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

  AuthSession _sessionFromLoginResponse(Map<String, Object?> json) {
    final tokens = _tokensFromResponse(json);
    final accountType = AuthAccountType.parse(json['account_type']);
    _appContext?.validateAccountType(accountType);

    return AuthSession(tokens: tokens, accountType: accountType);
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
