import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_app_config/asm_app_config.dart';
import 'package:asm_auth/asm_auth.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';

import 'booking/booking_submission.dart';
import 'passenger_shell.dart';

void main() {
  final configuration = AsmAppConfigLoader.fromCompileTimeEnvironment();
  runApp(PassengerApp(configuration: configuration, showLoginShell: true));
}

class PassengerApp extends StatelessWidget {
  const PassengerApp({
    this.configuration = AsmAppConfig.localGhana,
    this.showLoginShell = false,
    this.rideRequestSubmitter,
    this.authService,
    this.authTokenStore,
    super.key,
  });

  final AsmAppConfig configuration;
  final bool showLoginShell;
  final PassengerRideRequestSubmitter? rideRequestSubmitter;
  final AuthService? authService;
  final AuthTokenStore? authTokenStore;

  @override
  Widget build(BuildContext context) {
    assert(AuthState.unauthenticated().status == AuthStatus.unauthenticated);
    final tokenStore = authTokenStore ?? SecureAuthTokenStore();
    const apiBaseUrl = AsmApiClient.defaultBaseUrl;
    final resolvedRideRequestSubmitter =
        rideRequestSubmitter ??
        ApiPassengerRideRequestSubmitter.withDefaultClient(
          tokenStore: tokenStore,
          baseUrl: apiBaseUrl,
        );
    final resolvedAuthService =
        authService ??
        _authServiceFor(
          baseUrl: apiBaseUrl,
          tokenStore: tokenStore,
          appContext: AuthAppContext.passenger,
        );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ALANTEH Passenger',
      theme: AsmThemes.passenger,
      home: showLoginShell
          ? PassengerLoginShell(
              configuration: configuration,
              authService: resolvedAuthService,
              authTokenStore: tokenStore,
              rideRequestSubmitter: resolvedRideRequestSubmitter,
              localQaEnabled: configuration.localQaEnabled,
            )
          : PassengerShell(
              configuration: configuration,
              rideRequestSubmitter: resolvedRideRequestSubmitter,
            ),
    );
  }
}

class PassengerLoginShell extends StatefulWidget {
  const PassengerLoginShell({
    this.configuration = AsmAppConfig.localGhana,
    this.authService,
    this.authTokenStore,
    this.rideRequestSubmitter,
    this.localQaEnabled = false,
    super.key,
  });

  final AsmAppConfig configuration;
  final AuthService? authService;
  final AuthTokenStore? authTokenStore;
  final PassengerRideRequestSubmitter? rideRequestSubmitter;
  final bool localQaEnabled;

  @override
  State<PassengerLoginShell> createState() => _PassengerLoginShellState();
}

class _PassengerLoginShellState extends State<PassengerLoginShell> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _pinController = TextEditingController();

  late final AuthTokenStore _tokenStore;
  late final AuthService _authService;
  late final PassengerRideRequestSubmitter _rideRequestSubmitter;

  bool _localQaOpened = false;
  bool _signedIn = false;
  bool _isSigningIn = false;
  String? _loginErrorMessage;

  @override
  void initState() {
    super.initState();
    _tokenStore = widget.authTokenStore ?? SecureAuthTokenStore();
    const apiBaseUrl = AsmApiClient.defaultBaseUrl;
    _authService =
        widget.authService ??
        _authServiceFor(
          baseUrl: apiBaseUrl,
          tokenStore: _tokenStore,
          appContext: AuthAppContext.passenger,
        );
    _rideRequestSubmitter =
        widget.rideRequestSubmitter ??
        ApiPassengerRideRequestSubmitter.withDefaultClient(
          tokenStore: _tokenStore,
          baseUrl: apiBaseUrl,
        );
    _restoreStoredSession();
  }

  Future<void> _restoreStoredSession() async {
    final accessToken = (await _tokenStore.readAccessToken())?.trim();
    if (!mounted || _localQaOpened || _signedIn) {
      return;
    }

    if (accessToken == null || accessToken.isEmpty) {
      setState(() {
        _signedIn = false;
        _isSigningIn = false;
      });
      return;
    }

    setState(() {
      _signedIn = true;
      _isSigningIn = false;
      _loginErrorMessage = null;
    });
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate() || _isSigningIn) {
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _isSigningIn = true;
      _loginErrorMessage = null;
    });

    try {
      final state = await _authService.login(
        _phoneController.text,
        _pinController.text,
      );

      if (!mounted) {
        return;
      }

      if (state.isAuthenticated &&
          state.session?.accountType == AuthAccountType.passenger) {
        _phoneController.clear();
        _pinController.clear();
        setState(() {
          _signedIn = true;
          _isSigningIn = false;
          _loginErrorMessage = null;
        });
        return;
      }

      _pinController.clear();
      setState(() {
        _isSigningIn = false;
        _loginErrorMessage = _passengerLoginErrorMessage(state.error);
      });
    } on AuthException catch (error) {
      if (!mounted) {
        return;
      }

      _pinController.clear();
      setState(() {
        _isSigningIn = false;
        _loginErrorMessage = _passengerLoginErrorMessage(error);
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      _pinController.clear();
      setState(() {
        _isSigningIn = false;
        _loginErrorMessage = _unknownApiErrorMessage;
      });
    }
  }

  void _clearForm() {
    FocusManager.instance.primaryFocus?.unfocus();
    _phoneController.clear();
    _pinController.clear();
    _formKey.currentState?.reset();
    setState(() {
      _loginErrorMessage = null;
    });
  }

  Future<void> _continueLocalQa() async {
    await _tokenStore.clearTokens();
    if (!mounted || _isSigningIn) {
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _localQaOpened = true;
      _signedIn = false;
      _loginErrorMessage = null;
    });
  }

  Future<void> _returnToSignIn() async {
    await _tokenStore.clearTokens();
    if (!mounted) {
      return;
    }

    setState(() {
      _localQaOpened = false;
      _signedIn = false;
      _isSigningIn = false;
      _loginErrorMessage =
          PassengerRideRequestSubmissionException.signInRequiredMessage;
    });
  }

  Future<void> _signOut() async {
    await _tokenStore.clearTokens();
    if (!mounted) {
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    _phoneController.clear();
    _pinController.clear();
    _formKey.currentState?.reset();
    setState(() {
      _localQaOpened = false;
      _signedIn = false;
      _isSigningIn = false;
      _loginErrorMessage = null;
    });
  }

  static const _signInFailedMessage =
      'Sign in failed. Check your phone and PIN.';
  static const _networkErrorMessage =
      'Cannot reach the server. Check your connection and try again.';
  static const _serverUnavailableMessage =
      'Service is temporarily unavailable. Please try again later.';
  static const _unknownApiErrorMessage =
      'Something went wrong. Please try again.';

  String _passengerLoginErrorMessage(AuthException? error) {
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

  @override
  Widget build(BuildContext context) {
    if (_localQaOpened || _signedIn) {
      return PassengerShell(
        configuration: widget.configuration,
        rideRequestSubmitter: _rideRequestSubmitter,
        onSignInRequired: _returnToSignIn,
        onSignOut: _signOut,
      );
    }

    return Scaffold(
      body: AsmScreenSurface(
        scrollable: true,
        padding: const EdgeInsets.fromLTRB(
          AsmSpacing.space16,
          AsmSpacing.space20,
          AsmSpacing.space16,
          AsmSpacing.space24,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AsmScreenHeader(
                leading: const AsmAppBrandMark(),
                title: 'ALANTEH',
                subtitle: 'Passenger access',
              ),
              const SizedBox(height: AsmSpacing.space20),
              const Text(
                'Sign in to ride',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: AsmSpacing.space8),
              const Text('Enter your phone number and PIN to continue.'),
              const SizedBox(height: AsmSpacing.space20),
              TextFormField(
                key: const Key('passenger-phone-field'),
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
                key: const Key('passenger-pin-field'),
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
              if (_loginErrorMessage != null) ...[
                const SizedBox(height: AsmSpacing.space12),
                _LoginErrorPanel(message: _loginErrorMessage!),
              ],
              const SizedBox(height: AsmSpacing.space20),
              AsmPrimaryActionButton(
                key: const Key('passenger-sign-in'),
                onPressed: _isSigningIn ? null : _signIn,
                icon: Icons.login_outlined,
                label: _isSigningIn ? 'Signing in...' : 'Sign in',
              ),
              const SizedBox(height: AsmSpacing.space8),
              AsmPrimaryActionButton(
                key: const Key('passenger-clear-form'),
                onPressed: _isSigningIn ? null : _clearForm,
                variant: AsmActionButtonVariant.text,
                icon: Icons.clear_outlined,
                label: 'Clear form',
                minimumHeight: 48,
              ),
              if (widget.localQaEnabled) ...[
                const SizedBox(height: AsmSpacing.space8),
                AsmPrimaryActionButton(
                  key: const Key('passenger-continue-local-qa'),
                  onPressed: _isSigningIn ? null : _continueLocalQa,
                  variant: AsmActionButtonVariant.text,
                  icon: Icons.play_arrow_outlined,
                  label: 'Continue without signing in',
                  minimumHeight: 48,
                ),
              ],
              const SizedBox(height: AsmSpacing.space20),
              const AsmPilotNoticeBanner(
                message: 'Use your passenger phone and PIN to sign in.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoginErrorPanel extends StatelessWidget {
  const _LoginErrorPanel({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    const backgroundColor = Color(0xFFFFF3E0);
    const foregroundColor = Color(0xFF8A4B00);

    return Container(
      key: const Key('passenger-login-error'),
      width: double.infinity,
      padding: const EdgeInsets.all(AsmSpacing.space12),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(AsmRadii.radius8),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: foregroundColor,
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
    client: AsmApiClient(baseUrl: baseUrl!),
    tokenStore: tokenStore,
    appContext: appContext,
  );
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
