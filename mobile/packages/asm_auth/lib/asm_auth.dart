import 'dart:async';
import 'dart:convert';
import 'dart:math';

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

  /// For a refresh: the server could not be reached; the sign-in was kept.
  bool get isTemporarilyUnavailable =>
      error?.type == AuthExceptionType.temporarilyUnavailable;

  AuthRefreshOutcome get refreshOutcome {
    if (isAuthenticated) {
      return AuthRefreshOutcome.refreshed;
    }
    return isTemporarilyUnavailable
        ? AuthRefreshOutcome.temporarilyUnavailable
        : AuthRefreshOutcome.rejected;
  }
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
  const AuthSession({required this.tokens, this.accountType, this.account});

  final AuthTokens tokens;
  final AuthAccountType? accountType;
  final Map<String, Object?>? account;

  bool get isAuthenticated => tokens.isValid;
}

enum AuthExceptionType {
  validation,
  apiFailure,
  accountType,
  missingRefreshToken,
  storage,

  /// A refresh could not reach the server (no network, timeout, server
  /// error). The stored sign-in is kept.
  temporarilyUnavailable,
}

/// What a refresh came to. Only [rejected] ends the session.
enum AuthRefreshOutcome { refreshed, temporarilyUnavailable, rejected }

/// Wraps the refresh request, for example to retry it on a weak network.
typedef AuthRefreshRetry =
    Future<ApiResponse<Map<String, Object?>>> Function(
      Future<ApiResponse<Map<String, Object?>>> Function() attempt,
    );

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

/// Optional Passenger session metadata storage used alongside auth tokens.
abstract interface class PassengerDisplayNameStore {
  Future<void> savePassengerDisplayName(String displayName);

  Future<String?> readPassengerDisplayName();

  Future<void> clearPassengerDisplayName();
}

/// Optional Passenger phone metadata storage used alongside auth tokens.
abstract interface class PassengerPhoneNumberStore {
  Future<void> savePassengerPhoneNumber(String phoneNumber);

  Future<String?> readPassengerPhoneNumber();

  Future<void> clearPassengerPhoneNumber();
}

/// Secure token storage foundation backed by flutter_secure_storage.
class SecureAuthTokenStore
    implements
        AuthTokenStore,
        PassengerDisplayNameStore,
        PassengerPhoneNumberStore {
  SecureAuthTokenStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const accessTokenKey = 'asm.auth.access_token';
  static const refreshTokenKey = 'asm.auth.refresh_token';
  static const passengerDisplayNameKey = 'passenger_display_name';
  static const passengerPhoneNumberKey = 'passenger_phone_number';

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
  Future<void> savePassengerDisplayName(String displayName) {
    return _storage.write(
      key: passengerDisplayNameKey,
      value: displayName.trim(),
    );
  }

  @override
  Future<String?> readPassengerDisplayName() {
    return _storage.read(key: passengerDisplayNameKey);
  }

  @override
  Future<void> clearPassengerDisplayName() {
    return _storage.delete(key: passengerDisplayNameKey);
  }

  @override
  Future<void> savePassengerPhoneNumber(String phoneNumber) {
    return _storage.write(
      key: passengerPhoneNumberKey,
      value: phoneNumber.trim(),
    );
  }

  @override
  Future<String?> readPassengerPhoneNumber() {
    return _storage.read(key: passengerPhoneNumberKey);
  }

  @override
  Future<void> clearPassengerPhoneNumber() {
    return _storage.delete(key: passengerPhoneNumberKey);
  }

  @override
  Future<void> clearTokens() async {
    await _storage.delete(key: accessTokenKey);
    await _storage.delete(key: refreshTokenKey);
    await clearPassengerDisplayName();
    await clearPassengerPhoneNumber();
  }
}

/// In-memory token storage for tests and local non-platform checks only.
class MemoryAuthTokenStore
    implements
        AuthTokenStore,
        PassengerDisplayNameStore,
        PassengerPhoneNumberStore {
  String? _accessToken;
  String? _refreshToken;
  String? _passengerDisplayName;
  String? _passengerPhoneNumber;

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
  Future<void> savePassengerDisplayName(String displayName) async {
    _passengerDisplayName = displayName.trim();
  }

  @override
  Future<String?> readPassengerDisplayName() async => _passengerDisplayName;

  @override
  Future<void> clearPassengerDisplayName() async {
    _passengerDisplayName = null;
  }

  @override
  Future<void> savePassengerPhoneNumber(String phoneNumber) async {
    _passengerPhoneNumber = phoneNumber.trim();
  }

  @override
  Future<String?> readPassengerPhoneNumber() async => _passengerPhoneNumber;

  @override
  Future<void> clearPassengerPhoneNumber() async {
    _passengerPhoneNumber = null;
  }

  @override
  Future<void> clearTokens() async {
    _accessToken = null;
    _refreshToken = null;
    _passengerDisplayName = null;
    _passengerPhoneNumber = null;
  }
}

/// A random id for this app install, sent at push registration and
/// sign-out so the server can retire this phone's push rows (sign-in build
/// A1/A2). It is not a secret and survives sign-out; it is lost only when
/// the app's data is (reinstall).
abstract interface class InstallationIdStore {
  Future<String> readOrCreate();
}

final RegExp _installationIdPattern = RegExp(r'^[0-9a-f]{32}$');

/// 32 lowercase hex characters from a secure random source (the server
/// takes up to 64).
String newInstallationId([Random? random]) {
  final source = random ?? Random.secure();
  final buffer = StringBuffer();
  for (var i = 0; i < 16; i++) {
    buffer.write(source.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

class SecureInstallationIdStore implements InstallationIdStore {
  SecureInstallationIdStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const key = 'asm.auth.installation_id';

  final FlutterSecureStorage _storage;
  Future<String>? _reading;

  @override
  Future<String> readOrCreate() =>
      _reading ??= _readOrCreate().whenComplete(() => _reading = null);

  Future<String> _readOrCreate() async {
    final stored = (await _storage.read(key: key))?.trim();
    if (stored != null && _installationIdPattern.hasMatch(stored)) {
      return stored;
    }
    final id = newInstallationId();
    await _storage.write(key: key, value: id);
    return id;
  }
}

/// In-memory installation id for tests.
class MemoryInstallationIdStore implements InstallationIdStore {
  MemoryInstallationIdStore([String? id]) : _id = id;

  String? _id;

  @override
  Future<String> readOrCreate() async => _id ??= newInstallationId();
}

/// A sign-out the server has not confirmed yet: sent again at the next app
/// start until the server answers 200.
class PendingSignOut {
  const PendingSignOut({
    required this.refresh,
    this.deviceToken,
    this.installationId,
  });

  final String refresh;
  final String? deviceToken;
  final String? installationId;

  /// The same sign-out without this phone's push details. After a new
  /// sign-in on this phone they would retire the new session's push rows.
  PendingSignOut refreshOnly() => PendingSignOut(refresh: refresh);

  /// The logout request body; absent fields are left out.
  Map<String, Object?> toJson() => <String, Object?>{
    'refresh': refresh,
    if (deviceToken != null) 'device_token': deviceToken,
    if (installationId != null) 'installation_id': installationId,
  };

  static PendingSignOut? tryParse(Object? json) {
    if (json is! Map) {
      return null;
    }
    final refresh = json['refresh'];
    if (refresh is! String || refresh.trim().isEmpty) {
      return null;
    }
    String? text(Object? value) =>
        value is String && value.trim().isNotEmpty ? value : null;
    return PendingSignOut(
      refresh: refresh,
      deviceToken: text(json['device_token']),
      installationId: text(json['installation_id']),
    );
  }
}

/// Where pending sign-outs wait. Kept apart from the tokens: clearing the
/// tokens must not drop them.
abstract interface class PendingSignOutStore {
  Future<List<PendingSignOut>> read();

  Future<void> write(List<PendingSignOut> records);
}

class SecurePendingSignOutStore implements PendingSignOutStore {
  SecurePendingSignOutStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const key = 'asm.auth.pending_sign_outs';

  final FlutterSecureStorage _storage;

  @override
  Future<List<PendingSignOut>> read() async {
    final raw = await _storage.read(key: key);
    if (raw == null || raw.isEmpty) {
      return const <PendingSignOut>[];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const <PendingSignOut>[];
      }
      return decoded
          .map(PendingSignOut.tryParse)
          .whereType<PendingSignOut>()
          .toList(growable: false);
    } on FormatException {
      return const <PendingSignOut>[];
    }
  }

  @override
  Future<void> write(List<PendingSignOut> records) async {
    if (records.isEmpty) {
      await _storage.delete(key: key);
      return;
    }
    await _storage.write(
      key: key,
      value: jsonEncode(records.map((record) => record.toJson()).toList()),
    );
  }
}

/// In-memory pending sign-outs for tests.
class MemoryPendingSignOutStore implements PendingSignOutStore {
  List<PendingSignOut> _records = const <PendingSignOut>[];

  @override
  Future<List<PendingSignOut>> read() async => _records;

  @override
  Future<void> write(List<PendingSignOut> records) async {
    _records = List<PendingSignOut>.unmodifiable(records);
  }
}

enum SignOutOutcome {
  /// The server confirmed the sign-out (or there was nothing to sign out).
  signedOut,

  /// Signed out on the phone; the server is told at a later app start.
  signedOutPending,

  /// The server refused: the driver holds an active trip. Still signed in.
  activeTrip,
}

class SignOutResult {
  const SignOutResult(this.outcome, {this.message});

  final SignOutOutcome outcome;

  /// The server's own words for [SignOutOutcome.activeTrip].
  final String? message;
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

/// Refreshes in flight, by the refresh token they present. Callers that
/// would present the same token share one request, even from different
/// [AuthService] objects: with rotation, the server refuses a second use of
/// a token.
final Map<String, Future<ApiResponse<Map<String, Object?>>>>
_refreshesInFlight = <String, Future<ApiResponse<Map<String, Object?>>>>{};

/// Mock-testable authentication service foundation.
class AuthService {
  AuthService({
    required AuthApiGateway apiGateway,
    required AuthTokenStore tokenStore,
    AuthAppContext? appContext,
    AuthRefreshRetry? refreshRetry,
    PendingSignOutStore? pendingSignOutStore,
    InstallationIdStore? installationIdStore,
    Duration logoutTimeout = defaultLogoutTimeout,
  }) : _apiGateway = apiGateway,
       _tokenStore = tokenStore,
       _appContext = appContext,
       _refreshRetry = refreshRetry,
       _pendingSignOutStore = pendingSignOutStore,
       _installationIdStore = installationIdStore,
       _logoutTimeout = logoutTimeout;

  factory AuthService.withApiClient({
    required AsmApiClient client,
    AuthTokenStore? tokenStore,
    AuthAppContext? appContext,
    AuthRefreshRetry? refreshRetry,
  }) {
    return AuthService(
      apiGateway: AsmAuthApiGateway(client),
      tokenStore: tokenStore ?? SecureAuthTokenStore(),
      appContext: appContext,
      refreshRetry: refreshRetry,
    );
  }

  static const tokenPath = '/api/auth/token/';
  static const refreshPath = '/api/auth/token/refresh/';
  static const logoutPath = '/api/auth/logout/';
  static const defaultLogoutTimeout = Duration(seconds: 5);
  static const maxPendingSignOuts = 5;

  final AuthApiGateway _apiGateway;
  final AuthTokenStore _tokenStore;
  final AuthAppContext? _appContext;
  final AuthRefreshRetry? _refreshRetry;
  final PendingSignOutStore? _pendingSignOutStore;
  final InstallationIdStore? _installationIdStore;
  final Duration _logoutTimeout;
  Future<int>? _sendingPending;

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
      await _keepOnlyRefreshInPendingSignOuts();
      await _persistPassengerDisplayName(session);
      await _persistPassengerPhoneNumber(session);
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

    Future<ApiResponse<Map<String, Object?>>> attempt() {
      return _apiGateway.post(
        refreshPath,
        body: <String, Object?>{'refresh': storedRefreshToken},
      );
    }

    final ApiResponse<Map<String, Object?>> response;
    try {
      final retry = _refreshRetry;
      response = await (_refreshesInFlight[storedRefreshToken] ??=
          (retry == null ? attempt() : retry(attempt)).whenComplete(() {
            // A block body: returning the removed future would make this
            // wait for itself.
            _refreshesInFlight.remove(storedRefreshToken);
          }));
    } on Object catch (error) {
      // Nothing came back from the server, so nothing was rejected.
      return AuthState.unauthenticated(_temporarilyUnavailable(error));
    }

    // A sign-out or a new sign-in while the request was out replaced the
    // session this refresh was for; its answer must not touch the new one.
    final currentRefreshToken = (await _tokenStore.readRefreshToken())?.trim();
    if (currentRefreshToken != storedRefreshToken) {
      return currentSession();
    }

    if (!response.isSuccess || response.data == null) {
      // Only a 401 from the refresh endpoint means the token was refused.
      // Anything else (no network, a 5xx, a proxy's 403 or 404, a 429, a
      // page that is not JSON) leaves the sign-in as it was.
      if (response.statusCode != 401) {
        return AuthState.unauthenticated(
          _temporarilyUnavailable(response.error),
        );
      }
      await _tokenStore.clearTokens();
      return AuthState.unauthenticated(_authError(response));
    }

    final AuthTokens tokens;
    try {
      tokens = _tokensFromResponse(
        response.data!,
        fallbackRefreshToken: storedRefreshToken,
      );
    } on Object catch (error) {
      // A 200 the app cannot read is not a refusal either.
      return AuthState.unauthenticated(_temporarilyUnavailable(error));
    }

    try {
      await _tokenStore.saveTokens(tokens);
      final passengerDisplayName = await _readPassengerDisplayName();
      final passengerPhoneNumber = await _readPassengerPhoneNumber();
      final account = <String, Object?>{
        if (passengerDisplayName != null) 'display_name': passengerDisplayName,
        if (passengerPhoneNumber != null) 'phone': passengerPhoneNumber,
      };
      return AuthState.authenticated(
        AuthSession(tokens: tokens, account: account.isEmpty ? null : account),
      );
    } on Object catch (error) {
      await _tokenStore.clearTokens();
      return AuthState.unauthenticated(_parseError(error));
    }
  }

  /// Signs out on the server (at most [defaultLogoutTimeout]) and on the
  /// phone. The tokens are cleared whatever the server says, except for a
  /// 409 active_trip: then the driver stays signed in. If the server could
  /// not be told, the sign-out is kept and sent by [sendPendingSignOuts].
  ///
  /// The pending record is written before the request, so an app killed
  /// mid-request still tells the server later.
  Future<SignOutResult> signOut({String? deviceToken}) async {
    final refresh = (await _tokenStore.readRefreshToken())?.trim();
    if (refresh == null || refresh.isEmpty) {
      await _tokenStore.clearTokens();
      return const SignOutResult(SignOutOutcome.signedOut);
    }
    final cleanDeviceToken = deviceToken?.trim();
    final record = PendingSignOut(
      refresh: refresh,
      deviceToken: cleanDeviceToken == null || cleanDeviceToken.isEmpty
          ? null
          : cleanDeviceToken,
      installationId: await _installationIdStore?.readOrCreate(),
    );
    await _addPendingSignOut(record);

    final response = await _postLogout(record);
    if (_confirmed(response)) {
      await _removePendingSignOut(record);
      await _tokenStore.clearTokens();
      return const SignOutResult(SignOutOutcome.signedOut);
    }
    if (_isActiveTrip(response)) {
      await _removePendingSignOut(record);
      return SignOutResult(
        SignOutOutcome.activeTrip,
        message: _detail(response),
      );
    }
    await _tokenStore.clearTokens();
    return const SignOutResult(SignOutOutcome.signedOutPending);
  }

  /// Sends each pending sign-out once (call at app start, with network).
  /// A record is dropped only on a 200; anything else keeps it for the
  /// next start. Returns how many are still pending.
  Future<int> sendPendingSignOuts() {
    return _sendingPending ??= _sendPendingSignOuts().whenComplete(() {
      _sendingPending = null;
    });
  }

  Future<int> _sendPendingSignOuts() async {
    final store = _pendingSignOutStore;
    if (store == null) {
      return 0;
    }
    for (final record in await store.read()) {
      if (_confirmed(await _postLogout(record))) {
        await _removePendingSignOut(record);
      }
    }
    return (await store.read()).length;
  }

  Future<ApiResponse<Map<String, Object?>>?> _postLogout(
    PendingSignOut record,
  ) async {
    try {
      return await _apiGateway
          .post(logoutPath, body: record.toJson())
          .timeout(_logoutTimeout);
    } on Object {
      // No answer in time, or no network: the server was not told.
      return null;
    }
  }

  static bool _confirmed(ApiResponse<Map<String, Object?>>? response) =>
      response != null && response.isSuccess && response.statusCode == 200;

  static bool _isActiveTrip(ApiResponse<Map<String, Object?>>? response) {
    final body = response?.error?.cause;
    return response?.statusCode == 409 &&
        body is Map &&
        body['code'] == 'active_trip';
  }

  static String? _detail(ApiResponse<Map<String, Object?>>? response) {
    final body = response?.error?.cause;
    final detail = body is Map ? body['detail'] : null;
    return detail is String && detail.trim().isNotEmpty ? detail : null;
  }

  Future<void> _addPendingSignOut(PendingSignOut record) async {
    final store = _pendingSignOutStore;
    if (store == null) {
      return;
    }
    final records = [...await store.read(), record];
    await store.write(
      records.sublist(max(0, records.length - maxPendingSignOuts)),
    );
  }

  Future<void> _removePendingSignOut(PendingSignOut record) async {
    final store = _pendingSignOutStore;
    if (store == null) {
      return;
    }
    final records = [...await store.read()];
    records.removeWhere((kept) => kept.refresh == record.refresh);
    await store.write(records);
  }

  Future<void> _keepOnlyRefreshInPendingSignOuts() async {
    final store = _pendingSignOutStore;
    if (store == null) {
      return;
    }
    final records = await store.read();
    if (records.isEmpty) {
      return;
    }
    await store.write(records.map((record) => record.refreshOnly()).toList());
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
    final passengerDisplayName = await _readPassengerDisplayName();
    final passengerPhoneNumber = await _readPassengerPhoneNumber();
    final account = <String, Object?>{
      if (passengerDisplayName != null) 'display_name': passengerDisplayName,
      if (passengerPhoneNumber != null) 'phone': passengerPhoneNumber,
    };
    return AuthState.authenticated(
      AuthSession(tokens: tokens, account: account.isEmpty ? null : account),
    );
  }

  Future<void> _persistPassengerDisplayName(AuthSession session) async {
    if (_appContext != AuthAppContext.passenger) {
      return;
    }

    final store = _tokenStore;
    if (store is! PassengerDisplayNameStore) {
      return;
    }
    final displayNameStore = store as PassengerDisplayNameStore;

    final value = _passengerDisplayNameFromAccount(session.account);
    if (value != null) {
      await displayNameStore.savePassengerDisplayName(value);
    } else {
      await displayNameStore.clearPassengerDisplayName();
    }
  }

  Future<void> _persistPassengerPhoneNumber(AuthSession session) async {
    if (_appContext != AuthAppContext.passenger) {
      return;
    }

    final store = _tokenStore;
    if (store is! PassengerPhoneNumberStore) {
      return;
    }
    final phoneStore = store as PassengerPhoneNumberStore;

    final value = _passengerPhoneNumberFromAccount(session.account);
    if (value != null) {
      await phoneStore.savePassengerPhoneNumber(value);
    } else {
      await phoneStore.clearPassengerPhoneNumber();
    }
  }

  String? _passengerPhoneNumberFromAccount(Map<String, Object?>? account) {
    if (account == null) {
      return null;
    }

    final passengerProfile = _mapField(account, 'passenger_profile');
    final nestedPhoneNumber = passengerProfile?['phone_number'];
    if (nestedPhoneNumber is String && nestedPhoneNumber.trim().isNotEmpty) {
      return nestedPhoneNumber.trim();
    }

    for (final key in const [
      'phone',
      'phone_number',
      'phoneNumber',
      'mobile',
      'mobile_number',
      'mobileNumber',
    ]) {
      final value = account[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }

    return null;
  }

  String? _passengerDisplayNameFromAccount(Map<String, Object?>? account) {
    if (account == null) {
      return null;
    }

    for (final key in const [
      'display_name',
      'displayName',
      'full_name',
      'fullName',
      'name',
    ]) {
      final value = account[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }

    final passengerProfile = _mapField(account, 'passenger_profile');
    final nestedDisplayName = passengerProfile?['display_name'];
    if (nestedDisplayName is String && nestedDisplayName.trim().isNotEmpty) {
      return nestedDisplayName.trim();
    }

    return null;
  }

  Future<String?> _readPassengerDisplayName() async {
    if (_appContext != AuthAppContext.passenger) {
      return null;
    }

    final store = _tokenStore;
    if (store is! PassengerDisplayNameStore) {
      return null;
    }
    final displayNameStore = store as PassengerDisplayNameStore;

    final value = (await displayNameStore.readPassengerDisplayName())?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  Future<String?> _readPassengerPhoneNumber() async {
    if (_appContext != AuthAppContext.passenger) {
      return null;
    }

    final store = _tokenStore;
    if (store is! PassengerPhoneNumberStore) {
      return null;
    }
    final phoneStore = store as PassengerPhoneNumberStore;

    final value = (await phoneStore.readPassengerPhoneNumber())?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  AuthSession _sessionFromLoginResponse(Map<String, Object?> json) {
    final tokens = _tokensFromResponse(json);
    final accountType = AuthAccountType.parse(json['account_type']);
    final account = _mapField(json, 'account');
    _appContext?.validateAccountType(accountType);

    return AuthSession(
      tokens: tokens,
      accountType: accountType,
      account: account,
    );
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

  Map<String, Object?>? _mapField(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is Map<String, Object?>) {
      return Map<String, Object?>.unmodifiable(value);
    }
    if (value is Map) {
      return Map<String, Object?>.unmodifiable(
        value.map((key, value) => MapEntry(key.toString(), value)),
      );
    }
    return null;
  }

  static AuthException _temporarilyUnavailable(Object? cause) {
    return AuthException(
      type: AuthExceptionType.temporarilyUnavailable,
      message: 'Cannot reach ALANTEH right now. Your sign-in was kept.',
      cause: cause,
    );
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

/// Asked before a shift check or a booking when the sign-in ends soon.
const authSignInEndsSoonMessage =
    "Your sign-in ends soon. Sign in again now so it doesn't stop you "
    'mid-trip.';

/// Time left before [token] (a JWT) expires, read from its own `exp` claim.
/// Null when there is no token or its expiry cannot be read. Zero once it
/// has expired.
Duration? authTokenTimeLeft(String? token, {DateTime? now}) {
  final parts = token?.trim().split('.');
  if (parts == null || parts.length != 3) {
    return null;
  }
  final Object? payload;
  try {
    payload = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    );
  } on Object {
    return null;
  }
  final exp = payload is Map ? payload['exp'] : null;
  if (exp is! num || !exp.isFinite) {
    return null;
  }
  final expiresAt = DateTime.fromMillisecondsSinceEpoch(
    (exp * 1000).round(),
    isUtc: true,
  );
  final left = expiresAt.difference((now ?? DateTime.now()).toUtc());
  return left.isNegative ? Duration.zero : left;
}
