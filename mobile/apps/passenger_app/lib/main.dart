import 'dart:async';

import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_app_config/asm_app_config.dart';
import 'package:asm_auth/asm_auth.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';

import 'auth/passenger_otp_verification_screen.dart';
import 'booking/booking_submission.dart';
import 'booking/passenger_fare_estimate.dart';
import 'network/ghana_network_resilience.dart';
import 'passenger_shell.dart';
import 'payment_rating/passenger_payment_rating_contract.dart';
import 'ride_requests/ride_request_history.dart';

void main() {
  final configuration = AsmAppConfigLoader.fromCompileTimeEnvironment();
  runApp(
    PassengerApp(
      configuration: configuration,
      showLoginShell: true,
      showSplash: true,
      enableNetworkResilience: true,
    ),
  );
}

class PassengerApp extends StatelessWidget {
  const PassengerApp({
    this.configuration = AsmAppConfig.localGhana,
    this.showLoginShell = false,
    this.showSplash = false,
    this.enableNetworkResilience = false,
    this.rideRequestSubmitter,
    this.authService,
    this.authTokenStore,
    this.paymentRatingRepository,
    this.fareEstimateRepository,
    super.key,
  });

  final AsmAppConfig configuration;
  final bool showLoginShell;
  final bool showSplash;
  final bool enableNetworkResilience;
  final PassengerRideRequestSubmitter? rideRequestSubmitter;
  final AuthService? authService;
  final AuthTokenStore? authTokenStore;
  final PassengerPaymentRatingRepository? paymentRatingRepository;
  final PassengerFareEstimateRepository? fareEstimateRepository;

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
    final resolvedRideRequestHistoryRepository =
        ApiPassengerRideRequestHistoryRepository.withDefaultClient(
          tokenStore: tokenStore,
          baseUrl: apiBaseUrl,
        );
    final resolvedPaymentRatingRepository =
        paymentRatingRepository ??
        ApiPassengerPaymentRatingRepository.withDefaultClient(
          tokenStore: tokenStore,
          baseUrl: apiBaseUrl,
        );
    final resolvedFareEstimateRepository =
        fareEstimateRepository ??
        ApiPassengerFareEstimateRepository.withDefaultClient(
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

    final home = showLoginShell
        ? PassengerLoginShell(
            configuration: configuration,
            authService: resolvedAuthService,
            authTokenStore: tokenStore,
            rideRequestSubmitter: resolvedRideRequestSubmitter,
            rideRequestHistoryRepository: resolvedRideRequestHistoryRepository,
            paymentRatingRepository: resolvedPaymentRatingRepository,
            fareEstimateRepository: resolvedFareEstimateRepository,
            localQaEnabled: configuration.localQaEnabled,
          )
        : PassengerShell(
            configuration: configuration,
            localQaEnabled: configuration.localQaEnabled,
            rideRequestSubmitter: resolvedRideRequestSubmitter,
            rideRequestHistoryRepository: resolvedRideRequestHistoryRepository,
            paymentRatingRepository: resolvedPaymentRatingRepository,
            fareEstimateRepository: resolvedFareEstimateRepository,
          );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ALANTEH Passenger',
      theme: AsmThemes.passenger,
      builder: enableNetworkResilience
          ? (context, child) => GhanaNetworkStatusBanner(
              baseUrl: apiBaseUrl,
              offlineMessage:
                  'Poor or no connection. Your screen stays ready while ALANTEH retries safely.',
              child: child ?? const SizedBox.shrink(),
            )
          : null,
      home: showSplash ? PassengerSplashGate(child: home) : home,
    );
  }
}

class PassengerSplashGate extends StatefulWidget {
  const PassengerSplashGate({
    required this.child,
    this.duration = const Duration(milliseconds: 900),
    super.key,
  });

  final Widget child;
  final Duration duration;

  @override
  State<PassengerSplashGate> createState() => _PassengerSplashGateState();
}

class _PassengerSplashGateState extends State<PassengerSplashGate> {
  Timer? _timer;
  bool _complete = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.duration, () {
      if (!mounted) {
        return;
      }

      setState(() => _complete = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _complete ? widget.child : const PassengerSplashScreen();
  }
}

class PassengerSplashScreen extends StatelessWidget {
  const PassengerSplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('passenger-splash-screen'),
      backgroundColor: AsmColors.brandDeepGreen,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AsmSpacing.space24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/brand/alanteh_header_white.png',
                  key: const Key('passenger-splash-logo'),
                  width: 220,
                  fit: BoxFit.contain,
                  semanticLabel: 'ALANTEH passenger logo',
                ),
                const SizedBox(height: AsmSpacing.space24),
                const Text(
                  "Ghana's first solar electric ride service",
                  key: Key('passenger-splash-tagline'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    height: 1.4,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
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
    required this.rideRequestHistoryRepository,
    required this.paymentRatingRepository,
    this.fareEstimateRepository,
    this.localQaEnabled = false,
    super.key,
  });

  final AsmAppConfig configuration;
  final AuthService? authService;
  final AuthTokenStore? authTokenStore;
  final PassengerRideRequestSubmitter? rideRequestSubmitter;
  final PassengerRideRequestHistoryRepository rideRequestHistoryRepository;
  final PassengerPaymentRatingRepository paymentRatingRepository;
  final PassengerFareEstimateRepository? fareEstimateRepository;
  final bool localQaEnabled;

  @override
  State<PassengerLoginShell> createState() => _PassengerLoginShellState();
}

class _PassengerLoginShellState extends State<PassengerLoginShell> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _pinController = TextEditingController();

  late final AuthTokenStore _tokenStore;
  String? _passengerPhoneNumber;
  late final AuthService _authService;
  late final PassengerRideRequestSubmitter _rideRequestSubmitter;

  bool _localQaOpened = false;
  bool _signedIn = false;
  bool _otpRequired = false;
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
    final rawAccessToken = await _tokenStore.readAccessToken();
    final rawRefreshToken = await _tokenStore.readRefreshToken();
    final accessToken = rawAccessToken?.trim();
    final refreshToken = rawRefreshToken?.trim();
    final hadStoredSession = rawAccessToken != null || rawRefreshToken != null;

    if (!mounted || _localQaOpened || _signedIn) {
      return;
    }

    if (accessToken == null ||
        accessToken.isEmpty ||
        refreshToken == null ||
        refreshToken.isEmpty) {
      if (hadStoredSession) {
        await _tokenStore.clearTokens();
      }
      if (!mounted || _localQaOpened || _signedIn) {
        return;
      }

      setState(() {
        _signedIn = false;
        _passengerPhoneNumber = null;
        _isSigningIn = false;
        _loginErrorMessage = hadStoredSession
            ? 'Please sign in again to continue.'
            : null;
      });
      return;
    }

    AuthState state;
    try {
      state = await _authService.refresh();
    } on Object {
      await _tokenStore.clearTokens();
      if (!mounted || _localQaOpened) {
        return;
      }

      setState(() {
        _signedIn = false;
        _passengerPhoneNumber = null;
        _isSigningIn = false;
        _loginErrorMessage = 'Please sign in again to continue.';
      });
      return;
    }

    if (!mounted || _localQaOpened) {
      return;
    }

    final accountType = state.session?.accountType;
    if (state.isAuthenticated &&
        (accountType == null || accountType == AuthAccountType.passenger)) {
      setState(() {
        _signedIn = true;
        _otpRequired = false;
        _isSigningIn = false;
        _loginErrorMessage = null;
      });
      return;
    }

    await _tokenStore.clearTokens();
    if (!mounted) {
      return;
    }

    setState(() {
      _signedIn = false;
      _passengerPhoneNumber = null;
      _isSigningIn = false;
      _loginErrorMessage = 'Please sign in again to continue.';
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
      final state = await _loginWithNetworkRetry(
        _phoneController.text,
        _pinController.text,
      );

      if (!mounted) {
        return;
      }

      if (state.isAuthenticated &&
          state.session?.accountType == AuthAccountType.passenger) {
        final enteredPhoneNumber = _phoneController.text.trim();
        final sessionPhoneNumber =
            _phoneNumberFromSession(state.session) ?? enteredPhoneNumber;
        _pinController.clear();
        setState(() {
          _passengerPhoneNumber = sessionPhoneNumber.isEmpty
              ? null
              : sessionPhoneNumber;
          _signedIn = true;
          _otpRequired = false;
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

  Future<AuthState> _loginWithNetworkRetry(String phone, String pin) async {
    for (
      var attempt = 0;
      attempt < GhanaRequestPolicy.maxAttempts;
      attempt += 1
    ) {
      final state = await _authService.login(phone, pin);
      final retryable = _isRetryableLoginFailure(state.error);
      final retriesExhausted =
          attempt >= GhanaRequestPolicy.retryBackoffs.length;

      if (!retryable || retriesExhausted) {
        return state;
      }

      await Future<void>.delayed(GhanaRequestPolicy.retryBackoffs[attempt]);
    }

    return const AuthState.unauthenticated();
  }

  bool _isRetryableLoginFailure(AuthException? error) {
    final cause = error?.cause;
    return cause is AsmApiException &&
        (cause.type == AsmApiExceptionType.network ||
            cause.type == AsmApiExceptionType.timeout);
  }

  void _completeOtpVerification() {
    if (!_otpRequired) {
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    _phoneController.clear();
    _pinController.clear();

    setState(() {
      _otpRequired = false;
      _signedIn = true;
      _isSigningIn = false;
      _loginErrorMessage = null;
    });
  }

  Future<void> _useAnotherPhoneNumber() async {
    await _tokenStore.clearTokens();

    if (!mounted) {
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    _pinController.clear();

    setState(() {
      _otpRequired = false;
      _signedIn = false;
      _isSigningIn = false;
      _loginErrorMessage = null;
    });
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
      _otpRequired = false;
      _passengerPhoneNumber = null;
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
      _otpRequired = false;
      _passengerPhoneNumber = null;
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
      _otpRequired = false;
      _passengerPhoneNumber = null;
      _isSigningIn = false;
      _loginErrorMessage = null;
    });
  }

  static const _incorrectPhoneOrPinMessage = 'Incorrect phone number or PIN';
  static const _passengerAccountMismatchMessage =
      'This account cannot be used in the passenger app';
  static const _networkErrorMessage =
      'Cannot reach the server. Check your connection and try again.';
  static const _serverUnavailableMessage =
      'Service is temporarily unavailable. Please try again later.';
  static const _unknownApiErrorMessage =
      'Something went wrong. Please try again.';

  String _passengerLoginErrorMessage(AuthException? error) {
    if (error == null) {
      return _incorrectPhoneOrPinMessage;
    }

    if (error.message == authAppContextErrorMessage) {
      return _passengerAccountMismatchMessage;
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

      if (cause.statusCode == 403) {
        return _passengerAccountMismatchMessage;
      }

      if (cause.statusCode == 401 || cause.statusCode == 400) {
        return _incorrectPhoneOrPinMessage;
      }
    }

    if (error.type == AuthExceptionType.accountType) {
      return _passengerAccountMismatchMessage;
    }

    if (error.type == AuthExceptionType.validation) {
      return _incorrectPhoneOrPinMessage;
    }

    if (error.type == AuthExceptionType.apiFailure) {
      return _unknownApiErrorMessage;
    }

    return _incorrectPhoneOrPinMessage;
  }

  String? _phoneNumberFromSession(AuthSession? session) {
    final account = session?.account;
    if (account == null) {
      return null;
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

  @override
  Widget build(BuildContext context) {
    if (_otpRequired) {
      return PassengerOtpVerificationScreen(
        phoneNumber: _passengerPhoneNumber ?? _phoneController.text.trim(),
        onVerified: _completeOtpVerification,
        onUseAnotherNumber: _useAnotherPhoneNumber,
      );
    }

    if (_localQaOpened || _signedIn) {
      return PassengerShell(
        configuration: widget.configuration,
        localQaEnabled: widget.configuration.localQaEnabled,
        rideRequestSubmitter: _rideRequestSubmitter,
        rideRequestHistoryRepository: widget.rideRequestHistoryRepository,
        paymentRatingRepository: widget.paymentRatingRepository,
        fareEstimateRepository: widget.fareEstimateRepository,
        phoneNumber: _passengerPhoneNumber,
        onSignInRequired: _returnToSignIn,
        onSignOut: _signOut,
      );
    }

    return Scaffold(
      backgroundColor: AsmColors.passengerSurface,
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
              Image.asset(
                'assets/brand/alanteh_header_dark.png',
                key: const Key('passenger-login-brand-logo'),
                width: 176,
                height: 56,
                fit: BoxFit.contain,
                alignment: Alignment.centerLeft,
                semanticLabel: 'ALANTEH passenger logo',
              ),
              const SizedBox(height: AsmSpacing.space16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AsmSpacing.space20),
                decoration: BoxDecoration(
                  color: AsmColors.passengerCard,
                  borderRadius: BorderRadius.circular(AsmRadii.radius28),
                  border: Border.all(color: AsmColors.passengerLine),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x16000000),
                      blurRadius: 28,
                      offset: Offset(0, 14),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Passenger access',
                      style: TextStyle(
                        color: AsmColors.brandGreen,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: AsmSpacing.space16),
                    const Text(
                      'Sign in to ride',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        height: 1.08,
                      ),
                    ),
                    const SizedBox(height: AsmSpacing.space8),
                    Text(
                      'Enter your phone number and PIN to continue.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        height: 1.45,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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
                  ],
                ),
              ),
              const SizedBox(height: AsmSpacing.space16),
              const _PassengerLoginAccentCard(),
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

class _PassengerLoginAccentCard extends StatelessWidget {
  const _PassengerLoginAccentCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('passenger-login-clean-energy-card'),
      width: double.infinity,
      padding: const EdgeInsets.all(AsmSpacing.space16),
      decoration: BoxDecoration(
        color: AsmColors.passengerMintSurface,
        borderRadius: BorderRadius.circular(AsmRadii.radius20),
        border: Border.all(color: const Color(0xFFBFE3CF)),
      ),
      child: const Row(
        children: [
          Icon(Icons.bolt_outlined, color: AsmColors.solarYellow),
          SizedBox(width: AsmSpacing.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Ghana's first solar electric ride service. Clean, quiet, and reliable.",
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                SizedBox(height: AsmSpacing.space4),
              ],
            ),
          ),
        ],
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
    client: GhanaResilientApiClient(baseUrl: baseUrl!),
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
