import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_app_config/asm_app_config.dart';
import 'package:asm_auth/asm_auth.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';

import 'driver_duty_trips.dart';
import 'driver_shell.dart';
import 'foundation/driver_foundation_widgets.dart';
import 'network/driver_offer_response_gateway.dart';
import 'network/driver_offer_response_resilience.dart';
import 'network/driver_trip_action_gateway.dart';
import 'network/driver_trip_action_resilience.dart';
import 'network/ghana_network_resilience.dart';

export 'driver_shell.dart';

void main() {
  final configuration = AsmAppConfigLoader.fromCompileTimeEnvironment();
  runApp(
    DriverApp(
      configuration: configuration,
      showLoginShell: true,
      showSplash: true,
      enableNetworkResilience: true,
    ),
  );
}

Future<AuthState> driverLoginWithGhanaRetry({
  required Future<AuthState> Function() attempt,
  Future<void> Function(Duration duration)? delay,
}) async {
  final wait = delay ?? Future<void>.delayed;
  AuthState? lastState;

  for (
    var attemptIndex = 0;
    attemptIndex < GhanaRequestPolicy.maxAttempts;
    attemptIndex += 1
  ) {
    try {
      final state = await attempt();
      lastState = state;

      if (state.isAuthenticated || !_isTransientAuthFailure(state.error)) {
        return state;
      }
    } on AuthException catch (error) {
      if (!_isTransientAuthFailure(error)) {
        rethrow;
      }
      lastState = AuthState.unauthenticated(error);
    }

    if (attemptIndex >= GhanaRequestPolicy.retryBackoffs.length) {
      break;
    }

    await wait(GhanaRequestPolicy.retryBackoffs[attemptIndex]);
  }

  return lastState ??
      const AuthState.unauthenticated(
        AuthException(
          type: AuthExceptionType.apiFailure,
          message: 'Authentication request failed.',
        ),
      );
}

bool _isTransientAuthFailure(AuthException? error) {
  final cause = error?.cause;
  return cause is AsmApiException &&
      (cause.type == AsmApiExceptionType.network ||
          cause.type == AsmApiExceptionType.timeout);
}

abstract interface class DriverSessionRefreshApiGateway {
  Future<ApiResponse<T>> post<T>(
    String path, {
    required Map<String, Object?> body,
    JsonDecoder<T>? decoder,
  });
}

final class AsmDriverSessionRefreshApiGateway
    implements DriverSessionRefreshApiGateway {
  const AsmDriverSessionRefreshApiGateway(this.client);

  final AsmApiClient client;

  @override
  Future<ApiResponse<T>> post<T>(
    String path, {
    required Map<String, Object?> body,
    JsonDecoder<T>? decoder,
  }) {
    return client.post<T>(path, data: body, decoder: decoder);
  }
}

final class DriverSessionRefreshController {
  DriverSessionRefreshController({
    required this.apiGateway,
    required this.tokenStore,
    GhanaRetryPolicy? retryPolicy,
  }) : _retryPolicy = retryPolicy ?? GhanaRetryPolicy();

  final DriverSessionRefreshApiGateway apiGateway;
  final AuthTokenStore tokenStore;
  final GhanaRetryPolicy _retryPolicy;

  Future<DriverTokenRefreshOutcome> refresh() async {
    final storedRefreshToken = (await tokenStore.readRefreshToken())?.trim();

    if (storedRefreshToken == null || storedRefreshToken.isEmpty) {
      await tokenStore.clearTokens();
      return DriverTokenRefreshOutcome.sessionExpired;
    }

    final response = await _retryPolicy.execute<Map<String, Object?>>(
      safeToRetry: true,
      operation: () => apiGateway.post<Map<String, Object?>>(
        AuthService.refreshPath,
        body: <String, Object?>{'refresh': storedRefreshToken},
        decoder: _decodeRefreshResponse,
      ),
    );

    if (response.isSuccess && response.data != null) {
      final accessToken = _firstToken(response.data!, const <String>[
        'access',
        'accessToken',
        'access_token',
      ]);
      final refreshToken =
          _firstToken(response.data!, const <String>[
            'refresh',
            'refreshToken',
            'refresh_token',
          ]) ??
          storedRefreshToken;

      if (accessToken == null || refreshToken.trim().isEmpty) {
        await tokenStore.clearTokens();
        return DriverTokenRefreshOutcome.sessionExpired;
      }

      await tokenStore.saveTokens(
        AuthTokens(accessToken: accessToken, refreshToken: refreshToken),
      );
      return DriverTokenRefreshOutcome.refreshed;
    }

    if (_isTransientRefreshResponse(response)) {
      return DriverTokenRefreshOutcome.temporarilyUnavailable;
    }

    await tokenStore.clearTokens();
    return DriverTokenRefreshOutcome.sessionExpired;
  }

  static Map<String, Object?> _decodeRefreshResponse(Object? json) {
    if (json is Map<String, Object?>) {
      return json;
    }

    if (json is Map) {
      return json.map((key, value) => MapEntry(key.toString(), value));
    }

    throw const FormatException(
      'Token refresh response was not a JSON object.',
    );
  }

  static String? _firstToken(Map<String, Object?> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return null;
  }

  static bool _isTransientRefreshResponse(
    ApiResponse<Map<String, Object?>> response,
  ) {
    final error = response.error;
    return error?.type == AsmApiExceptionType.network ||
        error?.type == AsmApiExceptionType.timeout ||
        error?.type == AsmApiExceptionType.server ||
        response.statusCode == 502 ||
        response.statusCode == 503 ||
        response.statusCode == 504;
  }
}

class DriverApp extends StatelessWidget {
  const DriverApp({
    this.configuration = AsmAppConfig.localGhana,
    this.showLoginShell = false,
    this.showSplash = false,
    this.enableNetworkResilience = false,
    this.authService,
    this.authTokenStore,
    this.driverDutyGateway,
    this.driverTripActionControllerFactory,
    this.driverOfferResponseControllerFactory,
    super.key,
  });

  final AsmAppConfig configuration;
  final bool showLoginShell;
  final bool showSplash;
  final bool enableNetworkResilience;
  final AuthService? authService;
  final AuthTokenStore? authTokenStore;
  final DriverDutyGateway? driverDutyGateway;
  final DriverTripActionControllerFactory? driverTripActionControllerFactory;
  final DriverOfferResponseControllerFactory?
  driverOfferResponseControllerFactory;

  @override
  Widget build(BuildContext context) {
    assert(AuthState.unauthenticated().status == AuthStatus.unauthenticated);

    final tokenStore = authTokenStore ?? SecureAuthTokenStore();
    const apiBaseUrl = AsmApiClient.defaultBaseUrl;
    final service =
        authService ??
        _authServiceFor(
          baseUrl: apiBaseUrl,
          tokenStore: tokenStore,
          appContext: AuthAppContext.driver,
        );
    final sessionRefreshController = authService == null
        ? _driverSessionRefreshControllerFor(
            baseUrl: apiBaseUrl,
            tokenStore: tokenStore,
          )
        : null;
    final shouldCreateDefaultDutyGateway =
        showLoginShell && authService == null && authTokenStore == null;
    final dutyGateway =
        driverDutyGateway ??
        (shouldCreateDefaultDutyGateway
            ? _driverDutyGatewayFor(
                baseUrl: apiBaseUrl,
                tokenStore: tokenStore,
                refreshAccessToken: sessionRefreshController?.refresh,
              )
            : null);
    final actionControllerFactory =
        driverTripActionControllerFactory ??
        (shouldCreateDefaultDutyGateway && dutyGateway != null
            ? _driverTripActionControllerFactoryFor(
                baseUrl: apiBaseUrl,
                tokenStore: tokenStore,
                dutyGateway: dutyGateway,
                refreshAccessToken: sessionRefreshController?.refresh,
              )
            : null);
    final offerResponseControllerFactory =
        driverOfferResponseControllerFactory ??
        (shouldCreateDefaultDutyGateway && dutyGateway != null
            ? _driverOfferResponseControllerFactoryFor(
                baseUrl: apiBaseUrl,
                tokenStore: tokenStore,
                dutyGateway: dutyGateway,
                refreshAccessToken: sessionRefreshController?.refresh,
              )
            : null);

    final home = showLoginShell
        ? DriverLoginShell(
            configuration: configuration,
            authService: service,
            authTokenStore: tokenStore,
            localQaEnabled: configuration.localQaEnabled,
            driverDutyGateway: dutyGateway,
            driverTripActionControllerFactory: actionControllerFactory,
            driverOfferResponseControllerFactory:
                offerResponseControllerFactory,
            accessTokenRefresh: sessionRefreshController?.refresh,
          )
        : DriverShell(
            configuration: configuration,
            localQaEnabled: configuration.localQaEnabled,
            driverDutyGateway: dutyGateway,
            driverTripActionControllerFactory: actionControllerFactory,
            driverOfferResponseControllerFactory:
                offerResponseControllerFactory,
          );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ALANTEH Driver',
      theme: AsmThemes.driver,
      builder: enableNetworkResilience
          ? (context, child) => GhanaNetworkStatusBanner(
              baseUrl: apiBaseUrl,
              offlineMessage:
                  'Poor or no connection. Driver data stays visible and safe retries remain bounded.',
              child: child ?? const SizedBox.shrink(),
            )
          : null,
      home: showSplash ? DriverSplashGate(child: home) : home,
    );
  }
}

class DriverLoginShell extends StatefulWidget {
  const DriverLoginShell({
    required this.authService,
    required this.authTokenStore,
    this.configuration = AsmAppConfig.localGhana,
    this.localQaEnabled = false,
    this.driverDutyGateway,
    this.driverTripActionControllerFactory,
    this.driverOfferResponseControllerFactory,
    this.accessTokenRefresh,
    super.key,
  });

  final AsmAppConfig configuration;
  final AuthService authService;
  final AuthTokenStore authTokenStore;
  final bool localQaEnabled;
  final DriverDutyGateway? driverDutyGateway;
  final DriverTripActionControllerFactory? driverTripActionControllerFactory;
  final DriverOfferResponseControllerFactory?
  driverOfferResponseControllerFactory;
  final DriverAccessTokenRefresh? accessTokenRefresh;

  @override
  State<DriverLoginShell> createState() => _DriverLoginShellState();
}

class _DriverLoginShellState extends State<DriverLoginShell> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _pinController = TextEditingController();

  bool _localDemoOpened = false;
  bool _signedIn = false;
  bool _isSigningIn = false;
  String? _loginError;

  @override
  void initState() {
    super.initState();
    _restoreStoredSession();
  }

  Future<void> _restoreStoredSession() async {
    final rawAccessToken = await widget.authTokenStore.readAccessToken();
    final rawRefreshToken = await widget.authTokenStore.readRefreshToken();
    final accessToken = rawAccessToken?.trim();
    final refreshToken = rawRefreshToken?.trim();
    final hadStoredSession = rawAccessToken != null || rawRefreshToken != null;

    if (!mounted || _localDemoOpened || _signedIn) {
      return;
    }

    if (accessToken == null ||
        accessToken.isEmpty ||
        refreshToken == null ||
        refreshToken.isEmpty) {
      if (hadStoredSession) {
        await widget.authTokenStore.clearTokens();
      }

      if (!mounted || _localDemoOpened || _signedIn) {
        return;
      }

      setState(() {
        _signedIn = false;
        _isSigningIn = false;
        _loginError = hadStoredSession
            ? 'Please sign in again to continue.'
            : null;
      });
      return;
    }

    final controlledRefresh = widget.accessTokenRefresh;
    if (controlledRefresh != null) {
      final outcome = await controlledRefresh();

      if (!mounted || _localDemoOpened) {
        return;
      }

      switch (outcome) {
        case DriverTokenRefreshOutcome.refreshed:
          setState(() {
            _signedIn = true;
            _isSigningIn = false;
            _loginError = null;
          });
          return;
        case DriverTokenRefreshOutcome.temporarilyUnavailable:
          setState(() {
            _signedIn = false;
            _isSigningIn = false;
            _loginError =
                'Cannot refresh your session right now. '
                'Your stored sign-in was kept. Check your connection and retry.';
          });
          return;
        case DriverTokenRefreshOutcome.sessionExpired:
          await widget.authTokenStore.clearTokens();
          if (!mounted) {
            return;
          }
          setState(() {
            _signedIn = false;
            _isSigningIn = false;
            _loginError = 'Please sign in again to continue.';
          });
          return;
      }
    }

    AuthState state;
    try {
      state = await widget.authService.refresh();
    } on Object {
      await widget.authTokenStore.clearTokens();
      if (!mounted || _localDemoOpened) {
        return;
      }

      setState(() {
        _signedIn = false;
        _isSigningIn = false;
        _loginError = 'Please sign in again to continue.';
      });
      return;
    }

    if (!mounted || _localDemoOpened) {
      return;
    }

    final accountType = state.session?.accountType;
    if (state.isAuthenticated &&
        (accountType == null || accountType == AuthAccountType.driver)) {
      setState(() {
        _signedIn = true;
        _isSigningIn = false;
        _loginError = null;
      });
      return;
    }

    await widget.authTokenStore.clearTokens();
    if (!mounted) {
      return;
    }

    setState(() {
      _signedIn = false;
      _isSigningIn = false;
      _loginError = 'Please sign in again to continue.';
    });
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _continueLocalDemo() async {
    FocusManager.instance.primaryFocus?.unfocus();
    _phoneController.clear();
    _pinController.clear();
    _formKey.currentState?.reset();

    await widget.authTokenStore.clearTokens();
    if (!mounted) {
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _loginError = null;
      _localDemoOpened = true;
      _signedIn = false;
    });
  }

  Future<void> _signIn() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate() || _isSigningIn) {
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _loginError = null;
      _isSigningIn = true;
    });

    try {
      final state = await driverLoginWithGhanaRetry(
        attempt: () => widget.authService.login(
          _phoneController.text,
          _pinController.text,
        ),
      );

      if (!mounted) {
        return;
      }

      _pinController.clear();

      if (state.isAuthenticated &&
          state.session?.accountType == AuthAccountType.driver) {
        setState(() {
          _isSigningIn = false;
          _signedIn = true;
        });
        return;
      }

      setState(() {
        _isSigningIn = false;
        _loginError = _driverLoginErrorMessage(state.error);
      });
    } on AuthException catch (error) {
      if (!mounted) {
        return;
      }
      _pinController.clear();
      setState(() {
        _isSigningIn = false;
        _loginError = _driverLoginErrorMessage(error);
      });
    } on Object {
      if (!mounted) {
        return;
      }
      _pinController.clear();
      setState(() {
        _isSigningIn = false;
        _loginError = _unknownApiErrorMessage;
      });
    }
  }

  void _clearForm() {
    FocusManager.instance.primaryFocus?.unfocus();
    _phoneController.clear();
    _pinController.clear();
    _formKey.currentState?.reset();
    setState(() => _loginError = null);
  }

  Future<void> _signOut() async {
    await widget.authTokenStore.clearTokens();
    if (!mounted) {
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    _phoneController.clear();
    _pinController.clear();
    _formKey.currentState?.reset();
    setState(() {
      _localDemoOpened = false;
      _signedIn = false;
      _isSigningIn = false;
      _loginError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_localDemoOpened || _signedIn) {
      return DriverShell(
        configuration: widget.configuration,
        localQaEnabled: widget.localQaEnabled,
        onSignOut: _signOut,
        driverDutyGateway: widget.driverDutyGateway,
        driverTripActionControllerFactory:
            widget.driverTripActionControllerFactory,
        driverOfferResponseControllerFactory:
            widget.driverOfferResponseControllerFactory,
      );
    }

    return Scaffold(
      backgroundColor: AsmColors.driverVisualSurface,
      body: AsmScreenSurface(
        scrollable: true,
        expandToViewport: true,
        padding: const EdgeInsets.fromLTRB(
          22,
          AsmSpacing.space20,
          22,
          AsmSpacing.space24,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Image.asset(
                'assets/brand/alanteh_header_white.png',
                key: const Key('driver-login-brand-logo'),
                width: 176,
                height: 56,
                fit: BoxFit.contain,
                alignment: Alignment.centerLeft,
                semanticLabel: 'ALANTEH driver logo',
              ),
              const SizedBox(height: AsmSpacing.space16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AsmSpacing.space20),
                decoration: BoxDecoration(
                  color: AsmColors.driverCard,
                  borderRadius: BorderRadius.circular(AsmRadii.radius28),
                  border: Border.all(color: AsmColors.driverLine),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Driver',
                      style: TextStyle(
                        color: AsmColors.driverMintAction,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AsmSpacing.space20),
                    const Icon(
                      Icons.verified_user_outlined,
                      color: AsmColors.driverMintAction,
                      size: 44,
                    ),
                    const SizedBox(height: AsmSpacing.space20),
                    const Text(
                      'Driver sign in',
                      key: Key('driver-sign-in-title'),
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                        height: 1.05,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Enter your phone number and PIN to start your shift.',
                      style: TextStyle(
                        color: AsmColors.driverTextSecondary,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: AsmSpacing.space20),
                    TextFormField(
                      key: const Key('driver-phone-field'),
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Phone number',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) =>
                          validateGhanaPhoneNumberForLogin(value ?? ''),
                    ),
                    const SizedBox(height: AsmSpacing.space12),
                    TextFormField(
                      key: const Key('driver-pin-field'),
                      controller: _pinController,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _signIn(),
                      decoration: const InputDecoration(
                        labelText: 'PIN',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) => validatePinForLogin(value ?? ''),
                    ),
                    if (_loginError != null) ...[
                      const SizedBox(height: AsmSpacing.space16),
                      _DriverLoginErrorPanel(message: _loginError!),
                    ],
                    const SizedBox(height: AsmSpacing.space20),
                    AsmPrimaryActionButton(
                      key: const Key('driver-sign-in'),
                      onPressed: _isSigningIn ? null : _signIn,
                      icon: Icons.login_outlined,
                      label: _isSigningIn ? 'Signing in...' : 'Sign in',
                    ),
                    const SizedBox(height: AsmSpacing.space8),
                    Align(
                      alignment: Alignment.center,
                      child: TextButton(
                        key: const Key('driver-forgot-pin'),
                        onPressed: _isSigningIn
                            ? null
                            : () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Contact ALANTEH operations to reset your PIN.',
                                    ),
                                  ),
                                );
                              },
                        child: const Text('Forgot your PIN?'),
                      ),
                    ),
                    if (widget.localQaEnabled) ...[
                      AsmPrimaryActionButton(
                        key: const Key('driver-continue-local-demo'),
                        onPressed: _isSigningIn ? null : _continueLocalDemo,
                        variant: AsmActionButtonVariant.text,
                        icon: Icons.play_arrow_outlined,
                        label: 'Continue without signing in',
                        minimumHeight: 48,
                      ),
                      const SizedBox(height: AsmSpacing.space8),
                    ],
                    AsmPrimaryActionButton(
                      key: const Key('driver-clear-form'),
                      onPressed: _isSigningIn ? null : _clearForm,
                      variant: AsmActionButtonVariant.text,
                      icon: Icons.clear_outlined,
                      label: 'Clear form',
                      minimumHeight: 48,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static const _signInFailedMessage =
      'Sign in failed. Check your phone and PIN.';
  static const _networkErrorMessage =
      'Cannot reach the server. Check your connection and try again.';
  static const _serverUnavailableMessage =
      'Service is temporarily unavailable. Please try again later.';
  static const _unknownApiErrorMessage =
      'Something went wrong. Please try again.';

  String _driverLoginErrorMessage(AuthException? error) {
    if (error == null) {
      return _signInFailedMessage;
    }

    if (error.message == authAppContextErrorMessage) {
      return authAppContextErrorMessage;
    }

    if (error.message == AsmApiClient.connectionNotConfiguredMessage) {
      return AsmApiClient.connectionNotConfiguredMessage;
    }

    final cause = error.cause;
    if (cause is AsmApiException) {
      if (cause.type == AsmApiExceptionType.network ||
          cause.type == AsmApiExceptionType.timeout) {
        return _networkErrorMessage;
      }

      if (cause.statusCode == 503 || cause.type == AsmApiExceptionType.server) {
        return _serverUnavailableMessage;
      }

      if (cause.statusCode == 401 || cause.statusCode == 400) {
        return _signInFailedMessage;
      }
    }

    if (error.type == AuthExceptionType.accountType) {
      return authAppContextErrorMessage;
    }

    if (error.type == AuthExceptionType.validation) {
      return _signInFailedMessage;
    }

    if (error.type == AuthExceptionType.apiFailure) {
      return _unknownApiErrorMessage;
    }

    return _signInFailedMessage;
  }
}

class _DriverLoginErrorPanel extends StatelessWidget {
  const _DriverLoginErrorPanel({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('driver-login-error'),
      width: double.infinity,
      padding: const EdgeInsets.all(AsmSpacing.space12),
      decoration: BoxDecoration(
        color: AsmColors.driverScaffold,
        borderRadius: BorderRadius.circular(AsmRadii.radius8),
        border: Border.all(color: AsmColors.driverWarningSurface),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: AsmColors.driverWarningSurface,
          fontWeight: FontWeight.w700,
          height: 1.35,
        ),
      ),
    );
  }
}

AuthService _authServiceFor({
  required String? baseUrl,
  required AuthTokenStore tokenStore,
  required AuthAppContext appContext,
}) {
  if (!AsmApiBaseUrl.isUsable(baseUrl)) {
    return AuthService(
      apiGateway: const _UnconfiguredAuthApiGateway(),
      tokenStore: tokenStore,
      appContext: appContext,
    );
  }

  return AuthService.withApiClient(
    client: GhanaResilientApiClient(baseUrl: baseUrl!),
    tokenStore: tokenStore,
    appContext: appContext,
  );
}

DriverSessionRefreshController? _driverSessionRefreshControllerFor({
  required String? baseUrl,
  required AuthTokenStore tokenStore,
}) {
  if (!AsmApiBaseUrl.isUsable(baseUrl)) {
    return null;
  }

  return DriverSessionRefreshController(
    apiGateway: AsmDriverSessionRefreshApiGateway(
      GhanaResilientApiClient(baseUrl: baseUrl!),
    ),
    tokenStore: tokenStore,
  );
}

DriverDutyGateway? _driverDutyGatewayFor({
  required String? baseUrl,
  required AuthTokenStore tokenStore,
  DriverAccessTokenRefresh? refreshAccessToken,
}) {
  if (!AsmApiBaseUrl.isUsable(baseUrl)) {
    return null;
  }

  return AsmDriverDutyGateway(
    GhanaResilientApiClient(
      baseUrl: baseUrl!,
      tokenProvider: _StoredAccessTokenProvider(tokenStore),
    ),
    refreshAccessToken: refreshAccessToken,
  );
}

DriverTripActionControllerFactory? _driverTripActionControllerFactoryFor({
  required String? baseUrl,
  required AuthTokenStore tokenStore,
  required DriverDutyGateway dutyGateway,
  DriverAccessTokenRefresh? refreshAccessToken,
}) {
  if (!AsmApiBaseUrl.isUsable(baseUrl)) {
    return null;
  }

  final liveGateway = ApiDriverTripActionGateway(
    apiGateway: AsmDriverTripActionApiGateway(
      GhanaResilientApiClient(baseUrl: baseUrl!),
    ),
    tokenStore: tokenStore,
    refreshAccessToken: refreshAccessToken,
  );
  final persistentQueue = PersistentDriverTripActionQueue();

  return (tripReference) async {
    final duty = await dutyGateway.fetchDuty();
    final driverReference = duty.driverReference?.trim();
    if (driverReference == null || driverReference.isEmpty) {
      throw const DriverDutyApiException(
        DriverDutyApiFailureType.badResponse,
        'Driver identity could not be confirmed safely.',
      );
    }

    return DriverTripActionResilienceController(
      queue: persistentQueue,
      gateway: liveGateway,
      tripReference: tripReference,
      driverId: driverReference,
      verifyServerState: (action, receipt) async {
        final refreshedTrip = await dutyGateway.fetchTripDetail(
          receipt.tripReference,
        );
        return refreshedTrip.reference == receipt.tripReference &&
            refreshedTrip.status?.trim() == action.expectedStatus;
      },
    );
  };
}

DriverOfferResponseControllerFactory? _driverOfferResponseControllerFactoryFor({
  required String? baseUrl,
  required AuthTokenStore tokenStore,
  required DriverDutyGateway dutyGateway,
  DriverAccessTokenRefresh? refreshAccessToken,
}) {
  if (!AsmApiBaseUrl.isUsable(baseUrl)) {
    return null;
  }

  final liveGateway = ApiDriverOfferResponseGateway(
    apiGateway: AsmDriverOfferResponseApiGateway(
      GhanaResilientApiClient(baseUrl: baseUrl!),
    ),
    tokenStore: tokenStore,
    refreshAccessToken: refreshAccessToken,
  );
  final persistentQueue = PersistentDriverTripActionQueue();

  return (tripReference) async {
    final duty = await dutyGateway.fetchDuty();
    final driverReference = duty.driverReference?.trim();
    if (driverReference == null || driverReference.isEmpty) {
      throw const DriverDutyApiException(
        DriverDutyApiFailureType.badResponse,
        'Driver identity could not be confirmed safely.',
      );
    }

    return DriverOfferResponseResilienceController(
      queue: persistentQueue,
      gateway: liveGateway,
      tripReference: tripReference,
      driverId: driverReference,
      verifyServerState: (receipt) async {
        final refreshedTrip = await dutyGateway.fetchTripDetail(
          receipt.tripReference ?? tripReference,
        );
        return DriverOfferVerifiedTrip(
          tripReference: refreshedTrip.reference,
          status: refreshedTrip.status?.trim() ?? '',
          source: refreshedTrip,
        );
      },
    );
  };
}

final class _StoredAccessTokenProvider implements TokenProvider {
  const _StoredAccessTokenProvider(this.tokenStore);

  final AuthTokenStore tokenStore;

  @override
  Future<String?> getAccessToken() {
    return tokenStore.readAccessToken();
  }
}

class _UnconfiguredAuthApiGateway implements AuthApiGateway {
  const _UnconfiguredAuthApiGateway();

  @override
  Future<ApiResponse<Map<String, Object?>>> post(
    String path, {
    required Map<String, Object?> body,
  }) async {
    return ApiResponse.apiFailure(
      const AsmApiException(
        type: AsmApiExceptionType.badResponse,
        message: AsmApiClient.connectionNotConfiguredMessage,
      ),
    );
  }
}
