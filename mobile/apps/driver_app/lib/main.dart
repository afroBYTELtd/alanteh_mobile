import 'dart:async';

import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_app_config/asm_app_config.dart';
import 'package:asm_auth/asm_auth.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'driver_duty_trips.dart';
import 'driver_reload_signal.dart';
import 'network/driver_rating_gateway.dart';
import 'driver_shell.dart';
import 'foundation/driver_foundation_widgets.dart';
import 'network/driver_offer_response_gateway.dart';
import 'network/driver_offer_response_resilience.dart';
import 'network/driver_report_gateway.dart';
import 'network/driver_trip_action_gateway.dart';
import 'network/driver_trip_action_resilience.dart';
import 'network/ghana_network_resilience.dart';
import 'notifications/push_device_registration.dart';
import 'notifications/push_notification_runtime.dart';
import 'notifications/trip_offer_channel.dart';
import 'notifications/trip_offer_notifications_warning.dart';
import 'offers/driver_offer_card_wiring.dart';
import 'offers/driver_offer_coordinator.dart';
import 'offers/driver_offer_layer.dart';
import 'offers/driver_pending_offer_store.dart';
import 'offers/driver_pending_offers_panel.dart';
import 'readiness/driver_shift_check_submission.dart';
import 'safety/driver_trip_safety.dart';

export 'driver_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    await prepareAndroidPush(
      createOfferChannel: ensureTripOfferChannel,
      startFirebase: () async {
        await Firebase.initializeApp();
        FirebaseMessaging.onBackgroundMessage(
          firebaseMessagingBackgroundHandler,
        );
      },
    );
  }

  final configuration = AsmAppConfigLoader.fromCompileTimeEnvironment();
  final pushDeviceRegistrarFactory =
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android
      ? (AuthTokenStore tokenStore) =>
            FirebasePushDeviceRegistrar.withDefaultClient(
              tokenStore: tokenStore,
              baseUrl: AsmApiClient.defaultBaseUrl,
            )
      : null;
  runApp(
    buildDriverRoot(
      configuration: configuration,
      showLoginShell: true,
      showSplash: true,
      enableNetworkResilience: true,
      pushDeviceRegistrarFactory: pushDeviceRegistrarFactory,
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

  /// Refreshes in flight, by the refresh token they present: callers that
  /// would present the same token share one request (with rotation, the
  /// server refuses a second use of a token).
  final _inFlight = <String, Future<DriverTokenRefreshOutcome>>{};

  Future<DriverTokenRefreshOutcome> refresh() async {
    final storedRefreshToken = (await tokenStore.readRefreshToken())?.trim();

    if (storedRefreshToken == null || storedRefreshToken.isEmpty) {
      await tokenStore.clearTokens();
      return DriverTokenRefreshOutcome.sessionExpired;
    }

    return _inFlight[storedRefreshToken] ??= _refresh(storedRefreshToken)
        .whenComplete(() {
          // A block body: returning the removed future would make this wait
          // for itself.
          _inFlight.remove(storedRefreshToken);
        });
  }

  Future<DriverTokenRefreshOutcome> _refresh(String storedRefreshToken) async {
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
        // A 200 the app cannot use is not a refusal: keep the sign-in.
        return DriverTokenRefreshOutcome.temporarilyUnavailable;
      }

      // A sign-out or a newer sign-in while the request was out replaced
      // the session this refresh was for; leave the new one alone.
      final current = await _currentRefreshToken();
      if (current != storedRefreshToken) {
        return current == null
            ? DriverTokenRefreshOutcome.sessionExpired
            : DriverTokenRefreshOutcome.refreshed;
      }

      await tokenStore.saveTokens(
        AuthTokens(accessToken: accessToken, refreshToken: refreshToken),
      );
      return DriverTokenRefreshOutcome.refreshed;
    }

    // Only a 401 from the refresh endpoint means the token was refused.
    // Anything else (no network, a 5xx, a proxy's 403 or 404, a 429, a page
    // that is not JSON) keeps the sign-in.
    if (response.statusCode != 401) {
      return DriverTokenRefreshOutcome.temporarilyUnavailable;
    }

    // Refused - but if another refresh has already stored a newer token,
    // this 401 was for the old one.
    final current = await _currentRefreshToken();
    if (current != null && current != storedRefreshToken) {
      return DriverTokenRefreshOutcome.refreshed;
    }
    await tokenStore.clearTokens();
    return DriverTokenRefreshOutcome.sessionExpired;
  }

  Future<String?> _currentRefreshToken() async {
    final value = (await tokenStore.readRefreshToken())?.trim();
    return value == null || value.isEmpty ? null : value;
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
}

typedef DriverNormalAppBuilder = Widget Function();

Widget buildDriverRoot({
  AsmAppConfig configuration = AsmAppConfig.localGhana,
  bool showLoginShell = false,
  bool showSplash = false,
  bool enableNetworkResilience = false,
  AuthService? authService,
  AuthTokenStore? authTokenStore,
  DriverDutyGateway? driverDutyGateway,
  DriverTripActionControllerFactory? driverTripActionControllerFactory,
  DriverOfferResponseControllerFactory? driverOfferResponseControllerFactory,
  DriverShiftCheckSubmissionController? driverShiftCheckController,
  DriverReportGateway? driverReportGateway,
  ApiDriverRatingGateway? driverRatingGateway,
  PushDeviceRegistrarFactory? pushDeviceRegistrarFactory,
  DriverNormalAppBuilder? normalAppBuilder,
}) {
  Widget buildNormalApp() {
    final builder = normalAppBuilder;
    if (builder != null) {
      return builder();
    }

    return DriverApp(
      configuration: configuration,
      showLoginShell: showLoginShell,
      showSplash: showSplash,
      enableNetworkResilience: enableNetworkResilience,
      authService: authService,
      authTokenStore: authTokenStore,
      driverDutyGateway: driverDutyGateway,
      driverTripActionControllerFactory: driverTripActionControllerFactory,
      driverOfferResponseControllerFactory:
          driverOfferResponseControllerFactory,
      driverShiftCheckController: driverShiftCheckController,
      driverReportGateway: driverReportGateway,
      driverRatingGateway: driverRatingGateway,
      pushDeviceRegistrarFactory: pushDeviceRegistrarFactory,
    );
  }

  if (!driverOfferSubmissionTelemetryQaEnabled) {
    return buildNormalApp();
  }

  return DriverTelemetryInitializationRoot(normalAppBuilder: buildNormalApp);
}

class DriverTelemetryInitializationRoot extends StatefulWidget {
  const DriverTelemetryInitializationRoot({
    required this.normalAppBuilder,
    super.key,
  });

  final DriverNormalAppBuilder normalAppBuilder;

  @override
  State<DriverTelemetryInitializationRoot> createState() =>
      _DriverTelemetryInitializationRootState();
}

class _DriverTelemetryInitializationRootState
    extends State<DriverTelemetryInitializationRoot> {
  Widget? _normalApp;

  void _continueToDriverApp() {
    if (_normalApp != null) {
      return;
    }

    setState(() {
      _normalApp = widget.normalAppBuilder();
    });
  }

  @override
  Widget build(BuildContext context) {
    final normalApp = _normalApp;
    if (normalApp != null) {
      return normalApp;
    }

    return DriverOfferTelemetryInitializationGate(
      onContinue: _continueToDriverApp,
    );
  }
}

class DriverOfferTelemetryInitializationGate extends StatelessWidget {
  const DriverOfferTelemetryInitializationGate({
    required this.onContinue,
    super.key,
  });

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final initialization = initializeDriverOfferSubmissionTelemetryHooks();
    assert(initialization.allHooksRegistered);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ALANTEH Driver',
      theme: AsmThemes.driver,
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: AsmSystemChrome.driver,
        child: child ?? const SizedBox.shrink(),
      ),
      home: Scaffold(
        key: const Key('driver-telemetry-initialization-gate'),
        backgroundColor: AsmColors.driverVisualSurface,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              22,
              AsmSpacing.space20,
              22,
              AsmSpacing.space24,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TELEMETRY_INIT_ONLY',
                  key: const Key('driver-telemetry-init-only-title'),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: AsmSpacing.space8),
                Text(
                  'ALL_7_HOOKS_REGISTERED',
                  key: const Key('driver-telemetry-all-hooks-registered'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AsmSpacing.space20),
                for (final hookCode in initialization.hookCodes) ...[
                  Text(
                    hookCode,
                    key: ValueKey<String>('driver-telemetry-hook-$hookCode'),
                  ),
                  const SizedBox(height: AsmSpacing.space8),
                ],
                const SizedBox(height: AsmSpacing.space12),
                const Text(
                  'Registration only — no request sent.',
                  key: Key('driver-telemetry-registration-only-message'),
                ),
                const SizedBox(height: AsmSpacing.space24),
                FilledButton(
                  key: const Key('driver-telemetry-continue'),
                  onPressed: onContinue,
                  child: const Text('Continue to Driver app'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
    this.driverShiftCheckController,
    this.driverReportGateway,
    this.driverRatingGateway,
    this.driverTrustedContactRepository,
    this.driverSafetyAlertRepository,
    this.pushDeviceRegistrarFactory,
    this.pushMessageSource,
    this.offerCoordinator,
    this.offerCardControllerFactory,
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
  final DriverShiftCheckSubmissionController? driverShiftCheckController;
  final DriverReportGateway? driverReportGateway;
  final ApiDriverRatingGateway? driverRatingGateway;
  final DriverTrustedContactRepository? driverTrustedContactRepository;
  final DriverSafetyAlertRepository? driverSafetyAlertRepository;
  final PushDeviceRegistrarFactory? pushDeviceRegistrarFactory;
  final DriverPushMessageSource? pushMessageSource;

  /// Tests only: the pending-offer coordinator and the card's Accept/Decline.
  final DriverOfferCoordinator? offerCoordinator;
  final DriverOfferResponseControllerFactory? offerCardControllerFactory;

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
    final sharedPersistentQueue = shouldCreateDefaultDutyGateway
        ? PersistentDriverTripActionQueue()
        : null;
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
                persistentQueue: sharedPersistentQueue,
              )
            : null);
    final offerResponseControllerFactory =
        driverOfferResponseControllerFactory ??
        (shouldCreateDefaultDutyGateway && dutyGateway != null
            ? driverOfferResponseControllerFactoryFor(
                baseUrl: apiBaseUrl,
                tokenStore: tokenStore,
                dutyGateway: dutyGateway,
                refreshAccessToken: sessionRefreshController?.refresh,
                persistentQueue: sharedPersistentQueue,
              )
            : null);
    final shiftCheckController =
        driverShiftCheckController ??
        (shouldCreateDefaultDutyGateway && sharedPersistentQueue != null
            ? _driverShiftCheckControllerFor(
                baseUrl: apiBaseUrl,
                tokenStore: tokenStore,
                persistentQueue: sharedPersistentQueue,
                refreshAccessToken: sessionRefreshController?.refresh,
              )
            : null);
    final reportGateway =
        driverReportGateway ??
        (shouldCreateDefaultDutyGateway
            ? _driverReportGatewayFor(
                baseUrl: apiBaseUrl,
                tokenStore: tokenStore,
                refreshAccessToken: sessionRefreshController?.refresh,
              )
            : null);

    final trustedContactRepository =
        driverTrustedContactRepository ??
        ApiDriverTrustedContactRepository.withDefaultClient(
          tokenStore: tokenStore,
          baseUrl: apiBaseUrl,
        );

    final safetyAlertRepository =
        driverSafetyAlertRepository ??
        ApiDriverSafetyAlertRepository.withDefaultClient(
          tokenStore: tokenStore,
          baseUrl: apiBaseUrl,
        );

    final ratingGateway =
        driverRatingGateway ??
        _driverRatingGatewayFor(baseUrl: apiBaseUrl, tokenStore: tokenStore);

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
            driverShiftCheckController: shiftCheckController,
            driverReportGateway: reportGateway,
            driverRatingGateway: ratingGateway,
            driverTrustedContactRepository: trustedContactRepository,
            driverSafetyAlertRepository: safetyAlertRepository,
            accessTokenRefresh: sessionRefreshController?.refresh,
            pushDeviceRegistrarFactory: pushDeviceRegistrarFactory,
            pushMessageSource: pushMessageSource,
            apiBaseUrl: apiBaseUrl,
            offerCoordinator: offerCoordinator,
            offerCardControllerFactory: offerCardControllerFactory,
          )
        : DriverShell(
            configuration: configuration,
            localQaEnabled: configuration.localQaEnabled,
            driverDutyGateway: dutyGateway,
            driverTripActionControllerFactory: actionControllerFactory,
            driverOfferResponseControllerFactory:
                offerResponseControllerFactory,
            driverShiftCheckController: shiftCheckController,
            driverReportGateway: reportGateway,
            driverRatingGateway: ratingGateway,
            driverTrustedContactRepository: trustedContactRepository,
            driverSafetyAlertRepository: safetyAlertRepository,
          );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ALANTEH Driver',
      theme: AsmThemes.driver,
      navigatorKey: driverNavigatorKey,
      navigatorObservers: [driverOfferRoutes],
      builder: (context, child) {
        final content = enableNetworkResilience
            ? GhanaNetworkStatusBanner(
                baseUrl: apiBaseUrl,
                offlineMessage:
                    'Poor or no connection. Driver data stays visible and safe retries remain bounded.',
                child: child ?? const SizedBox.shrink(),
              )
            : (child ?? const SizedBox.shrink());

        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: AsmSystemChrome.driver,
          child: DriverOfferLayer(
            navigatorKey: driverNavigatorKey,
            routeCounter: driverOfferRoutes,
            child: content,
          ),
        );
      },
      home: showSplash ? DriverSplashGate(child: home) : home,
    );
  }
}

/// The driver app's navigator, for the offer card that sits above it.
/// What the driver sees when the server refuses sign-out because of an
/// active trip and its answer carries no text of its own (S2's wording).
const driverSignOutActiveTripText =
    'You have an active trip. Call dispatch before signing out.';

final driverNavigatorKey = GlobalKey<NavigatorState>();

/// Where the offer card goes: over the tabs or over a pushed screen.
final driverOfferRoutes = DriverOfferRouteObserver();

class DriverLoginShell extends StatefulWidget {
  const DriverLoginShell({
    required this.authService,
    required this.authTokenStore,
    this.configuration = AsmAppConfig.localGhana,
    this.localQaEnabled = false,
    this.driverDutyGateway,
    this.driverTripActionControllerFactory,
    this.driverOfferResponseControllerFactory,
    this.driverShiftCheckController,
    this.driverReportGateway,
    this.driverRatingGateway,
    this.driverTrustedContactRepository,
    this.driverSafetyAlertRepository,
    this.accessTokenRefresh,
    this.pushDeviceRegistrarFactory,
    this.pushMessageSource,
    this.apiBaseUrl,
    this.offerCoordinator,
    this.offerCardControllerFactory,
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
  final DriverShiftCheckSubmissionController? driverShiftCheckController;
  final DriverReportGateway? driverReportGateway;
  final ApiDriverRatingGateway? driverRatingGateway;
  final DriverTrustedContactRepository? driverTrustedContactRepository;
  final DriverSafetyAlertRepository? driverSafetyAlertRepository;
  final DriverAccessTokenRefresh? accessTokenRefresh;
  final PushDeviceRegistrarFactory? pushDeviceRegistrarFactory;
  final DriverPushMessageSource? pushMessageSource;
  final String? apiBaseUrl;

  /// Tests only; built from [apiBaseUrl] otherwise.
  final DriverOfferCoordinator? offerCoordinator;
  final DriverOfferResponseControllerFactory? offerCardControllerFactory;

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
  bool _restoringSession = true;
  String? _loginError;
  DriverOfferResponseControllerFactory?
  _sessionAwareOfferResponseControllerFactory;
  late final PushDeviceRegistrar? _pushDeviceRegistrar;

  /// The duty gateway, remembering the driver reference for offers.
  DriverDutyGateway? _dutyGateway;

  /// Pending offers: null when the app has no API address (then a push tap
  /// opens the trip detail, as before).
  DriverOfferCoordinator? _offers;
  DriverOfferResponseControllerFactory? _offerCardFactory;
  DriverOfferPickupTimeLookupFn? _offerPickupTimeLookup;
  AppLifecycleListener? _lifecycle;
  bool _offerScreenOpen = false;

  /// Pinged when the driver's trips may have changed: the pending offers
  /// changed, or a trip push arrived in front. The shell reloads on it.
  final _tripsChanged = DriverReloadSignal();

  /// What a "Session expired" panel's Sign in does: end the session and
  /// show this sign-in screen.
  Future<void> _signInAgain() =>
      _handleOfferSessionExpired(driverSessionExpiredMessage);

  @override
  void initState() {
    super.initState();
    DriverSessionEnd.signIn = _signInAgain;
    _pushDeviceRegistrar = widget.pushDeviceRegistrarFactory?.call(
      widget.authTokenStore,
    );
    _configureSessionAwareOfferResponseFactory();
    _configureOffers();
    _restoreStoredSession();
  }

  void _configureOffers() {
    final duty = widget.driverDutyGateway;
    final identity = duty == null
        ? null
        : duty is DriverIdentityCachingDutyGateway
        ? duty
        : DriverIdentityCachingDutyGateway(duty);
    _dutyGateway = identity ?? duty;

    final offers =
        widget.offerCoordinator ??
        driverOfferCoordinatorFor(
          baseUrl: widget.apiBaseUrl,
          tokenStore: widget.authTokenStore,
          identity: identity,
          refreshAccessToken: widget.accessTokenRefresh,
          onSessionExpired: () =>
              _handleOfferSessionExpired(driverSessionExpiredMessage),
        );
    final baseUrl = widget.apiBaseUrl;
    final factory =
        widget.offerCardControllerFactory ??
        (offers != null && identity != null && baseUrl != null
            ? driverOfferCardControllerFactoryFor(
                baseUrl: baseUrl,
                tokenStore: widget.authTokenStore,
                identity: identity,
                refreshAccessToken: widget.accessTokenRefresh,
              )
            : null);
    if (offers == null || factory == null) {
      return;
    }
    _offers = offers;
    offers.offerSetChanged.addListener(_tripsChanged.ping);
    _offerCardFactory =
        (tripReference, {assignedAt, unknownOffer = false}) async {
          final controller = await factory(
            tripReference,
            assignedAt: assignedAt,
            unknownOffer: unknownOffer,
          );
          controller.attachSessionExpiredHandler(_handleOfferSessionExpired);
          return controller;
        };
    _offerPickupTimeLookup = identity == null
        ? null
        : driverOfferPickupTimeLookupFor(identity);
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) =>
          offers.setForeground(state == AppLifecycleState.resumed),
    );
  }

  /// Sign-out, session end or another driver: no offer, cached driver or
  /// queued tap survives into the next session.
  void _forgetOffers() {
    _offers
      ?..setOnDuty(false)
      ..clear();
  }

  Future<void> _openOfferScreen(String tripReference) async {
    final offers = _offers;
    final factory = _offerCardFactory;
    if (offers == null || factory == null || _offerScreenOpen || !mounted) {
      return;
    }
    _offerScreenOpen = true;
    _offerLayer?.offerScreenOpen = true;
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => DriverPendingOfferScreen(
            tripReference: tripReference,
            coordinator: offers,
            controllerFactory: factory,
            pickupTimeLookup: _offerPickupTimeLookup,
            onAccepted: (screenContext, reference) =>
                Navigator.of(screenContext).pushReplacement<void, void>(
                  MaterialPageRoute<void>(
                    builder: (_) => _tripDetailScreen(reference),
                  ),
                ),
          ),
        ),
      );
    } finally {
      _offerScreenOpen = false;
      _offerLayer?.offerScreenOpen = false;
    }
  }

  Widget _tripDetailScreen(String tripReference) {
    return DriverTripDetailScreen(
      gateway: _dutyGateway!,
      tripReference: tripReference,
      actionControllerFactory: widget.driverTripActionControllerFactory,
      offerResponseControllerFactory:
          _sessionAwareOfferResponseControllerFactory,
      ratingGateway: widget.driverRatingGateway,
      driverTrustedContactRepository: widget.driverTrustedContactRepository,
      driverSafetyAlertRepository: widget.driverSafetyAlertRepository,
    );
  }

  void _openTripDetail(String tripReference) {
    if (!mounted || _dutyGateway == null) {
      return;
    }
    unawaited(
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => _tripDetailScreen(tripReference),
        ),
      ),
    );
  }

  /// A push tap that arrived before sign-in opens its card only while the
  /// offer is still pending, and only within about two minutes.
  Future<void> _openQueuedOfferTap(DriverQueuedOfferTap? tap) async {
    final offers = _offers;
    if (tap == null || offers == null) {
      return;
    }
    final listed = await offers.fetchThenCanOpen(tap.tripReference);
    if (!mounted || !_signedIn) {
      return;
    }
    if (listed) {
      await _openOfferScreen(tap.tripReference);
    }
  }

  /// The tap that launched the app. Wherever the session restore has got
  /// to, the same rule applies: queued while restoring, opened only while
  /// the offer is still pending, dropped if the restore failed.
  Future<void> _handleLaunchTap(DriverPushNavigationIntent intent) async {
    final offers = _offers;
    if (offers == null ||
        _localDemoOpened ||
        intent.eventType != 'driver_assigned') {
      return;
    }
    if (_restoringSession && !_signedIn) {
      offers.queueTap(intent.tripReference);
      return;
    }
    if (!_signedIn) {
      return;
    }
    offers.queueTap(intent.tripReference);
    await _openQueuedOfferTap(offers.takeTap());
  }

  Future<bool> _handleForegroundOffer(DriverPushNavigationIntent intent) async {
    final offers = _offers;
    if (offers == null || intent.eventType != 'driver_assigned') {
      return false;
    }
    if (!_signedIn) {
      return true;
    }
    final listed = await offers.fetchThenCanOpen(
      intent.tripReference,
      reason: DriverOfferFetchReason.pushAssigned,
    );
    if (!mounted || !_signedIn) {
      return true;
    }
    if (_offerScreenOpen) {
      return true;
    }
    if (!listed) {
      return false;
    }
    unawaited(_openOfferScreen(intent.tripReference));
    return true;
  }

  @override
  void didUpdateWidget(covariant DriverLoginShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.driverOfferResponseControllerFactory !=
        widget.driverOfferResponseControllerFactory) {
      _configureSessionAwareOfferResponseFactory();
    }
  }

  void _configureSessionAwareOfferResponseFactory() {
    final factory = widget.driverOfferResponseControllerFactory;
    _sessionAwareOfferResponseControllerFactory = factory == null
        ? null
        : (tripReference, {assignedAt, unknownOffer = false}) async {
            final controller = await factory(
              tripReference,
              assignedAt: assignedAt,
              unknownOffer: unknownOffer,
            );
            controller.attachSessionExpiredHandler(_handleOfferSessionExpired);
            return controller;
          };
  }

  Future<void> _handleOfferSessionExpired(String message) async {
    _forgetOffers();
    _pushDeviceRegistrar?.endAuthenticatedSession();
    widget.driverReportGateway?.clearSessionCache();
    try {
      await widget.authTokenStore.clearTokens();
    } on Object {
      // Login transition must remain available after storage failure.
    }

    if (!mounted) {
      return;
    }

    Navigator.of(context).popUntil((route) => route.isFirst);
    setState(() {
      _localDemoOpened = false;
      _signedIn = false;
      _isSigningIn = false;
      _loginError = message;
    });
  }

  Future<void> _restoreStoredSession() async {
    // A sign-out the server has not heard of yet: sent now if no one is
    // signed in (A1 checks; it never fires during a session).
    unawaited(_sendPendingSignOuts());
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
      _forgetOffers();
      if (hadStoredSession) {
        await widget.authTokenStore.clearTokens();
      }

      if (!mounted || _localDemoOpened || _signedIn) {
        return;
      }

      setState(() {
        _signedIn = false;
        _isSigningIn = false;
        _restoringSession = false;
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
            _restoringSession = false;
            _loginError = null;
          });
          unawaited(_pushDeviceRegistrar?.registerForAuthenticatedSession());
          unawaited(_openQueuedOfferTap(_offers?.takeTap()));
          return;
        case DriverTokenRefreshOutcome.temporarilyUnavailable:
          _forgetOffers();
          setState(() {
            _signedIn = false;
            _isSigningIn = false;
            _restoringSession = false;
            _loginError =
                'Cannot refresh your session right now. '
                'Your stored sign-in was kept. Check your connection and retry.';
          });
          return;
        case DriverTokenRefreshOutcome.sessionExpired:
          _forgetOffers();
          _pushDeviceRegistrar?.endAuthenticatedSession();
          await widget.authTokenStore.clearTokens();
          if (!mounted) {
            return;
          }
          setState(() {
            _signedIn = false;
            _isSigningIn = false;
            _restoringSession = false;
            _loginError = 'Please sign in again to continue.';
          });
          return;
      }
    }

    AuthState state;
    try {
      state = await widget.authService.refresh();
    } on Object {
      _forgetOffers();
      await widget.authTokenStore.clearTokens();
      if (!mounted || _localDemoOpened) {
        return;
      }

      setState(() {
        _signedIn = false;
        _isSigningIn = false;
        _restoringSession = false;
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
        _restoringSession = false;
        _loginError = null;
      });
      unawaited(_pushDeviceRegistrar?.registerForAuthenticatedSession());
      unawaited(_openQueuedOfferTap(_offers?.takeTap()));
      return;
    }

    _forgetOffers();
    _pushDeviceRegistrar?.endAuthenticatedSession();
    await widget.authTokenStore.clearTokens();
    if (!mounted) {
      return;
    }

    setState(() {
      _signedIn = false;
      _isSigningIn = false;
      _restoringSession = false;
      _loginError = 'Please sign in again to continue.';
    });
  }

  @override
  void dispose() {
    final pushDeviceRegistrar = _pushDeviceRegistrar;
    if (pushDeviceRegistrar != null) {
      unawaited(pushDeviceRegistrar.dispose());
    }
    _lifecycle?.dispose();
    _offers?.offerSetChanged.removeListener(_tripsChanged.ping);
    _offers?.dispose();
    _tripsChanged.dispose();
    final layer = _offerLayer;
    if (layer != null && _layerSource != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (layer.mounted) {
          layer.source = null;
        }
      });
    }
    // Tear-offs of the same method on the same object are equal.
    if (DriverSessionEnd.signIn == _signInAgain) {
      DriverSessionEnd.signIn = null;
    }
    _phoneController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _continueLocalDemo() async {
    _forgetOffers();
    _pushDeviceRegistrar?.endAuthenticatedSession();
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
        // A new session, perhaps another driver: start with nothing from
        // the last one except a push tap made on this sign-in screen.
        final tap = _offers?.takeTap();
        _forgetOffers();
        setState(() {
          _isSigningIn = false;
          _signedIn = true;
        });
        unawaited(_pushDeviceRegistrar?.registerForAuthenticatedSession());
        unawaited(_openQueuedOfferTap(tap));
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

  Future<void> _handlePushNavigationIntent(
    DriverPushNavigationIntent intent,
  ) async {
    if (_localDemoOpened || !mounted || intent.eventType != 'driver_assigned') {
      return;
    }

    final offers = _offers;
    if (offers != null) {
      if (!_signedIn) {
        offers.queueTap(intent.tripReference);
        return;
      }
      unawaited(offers.offerPushed());
      await _openOfferScreen(intent.tripReference);
      return;
    }

    if (!_signedIn) {
      return;
    }

    final gateway = widget.driverDutyGateway;
    if (gateway == null) {
      return;
    }

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => DriverTripDetailScreen(
          gateway: gateway,
          tripReference: intent.tripReference,
          actionControllerFactory: widget.driverTripActionControllerFactory,
          offerResponseControllerFactory:
              _sessionAwareOfferResponseControllerFactory,
          ratingGateway: widget.driverRatingGateway,
          driverTrustedContactRepository: widget.driverTrustedContactRepository,
          driverSafetyAlertRepository: widget.driverSafetyAlertRepository,
        ),
      ),
    );
  }

  /// A trip push with the app in front: the offers (a cancel ends an open
  /// card at once) and the trips reload.
  void _tripPushed(String eventType) {
    _offers?.tripPushed(eventType);
    _tripsChanged.ping();
  }

  void _clearForm() {
    FocusManager.instance.primaryFocus?.unfocus();
    _phoneController.clear();
    _pinController.clear();
    _formKey.currentState?.reset();
    setState(() => _loginError = null);
  }

  Future<void> _sendPendingSignOuts() async {
    try {
      await widget.authService.sendPendingSignOuts();
    } on Object {
      // Kept for the next start.
    }
  }

  bool _signingOut = false;

  /// Sign-out (A1/A3): the server is told first, within 5 s, under a
  /// "Signing out…" dialog. On 409 active_trip the driver stays signed in
  /// and sees the server's words; Work reloads. Otherwise the session ends
  /// on the phone (a sign-out the server did not get is kept pending).
  Future<void> _signOut() async {
    if (_signingOut) {
      return;
    }
    _signingOut = true;
    SignOutResult? result;
    try {
      result = await _whileSigningOut(
        widget.authService.signOut(
          deviceToken: _pushDeviceRegistrar?.deviceToken,
        ),
      );
    } on Object {
      // Storage failed: end the session on the phone anyway.
      result = null;
    } finally {
      _signingOut = false;
    }
    if (!mounted) {
      return;
    }
    if (result?.outcome == SignOutOutcome.activeTrip) {
      await _showSignOutRefused(result?.message ?? driverSignOutActiveTripText);
      _tripsChanged.ping();
      return;
    }
    await _endSessionOnPhone();
  }

  Future<T> _whileSigningOut<T>(Future<T> work) async {
    final navigator = Navigator.of(context);
    var showing = true;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const PopScope(
          canPop: false,
          child: AlertDialog(
            key: Key('driver-signing-out'),
            content: Row(
              children: [
                SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: AsmSpacing.space16),
                Text('Signing out…'),
              ],
            ),
          ),
        ),
      ).whenComplete(() => showing = false),
    );
    try {
      return await work;
    } finally {
      if (showing && navigator.mounted) {
        navigator.pop();
      }
    }
  }

  Future<void> _showSignOutRefused(String message) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('driver-sign-out-refused'),
        title: const Text('Still signed in'),
        content: Text(message),
        actions: [
          TextButton(
            key: const Key('driver-sign-out-refused-ok'),
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _endSessionOnPhone() async {
    _forgetOffers();
    _pushDeviceRegistrar?.endAuthenticatedSession();
    widget.driverReportGateway?.clearSessionCache();
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
    _syncOfferLayer();
    final content = _buildContent(context);
    final listens =
        _pushDeviceRegistrar != null || widget.pushMessageSource != null;
    if (_offers == null || !listens) {
      return content;
    }
    // With offers, the listener runs from app start, so a tap that opened
    // the app is seen (and queued) while the session is still restoring.
    return FirebaseForegroundPushListener(
      onNavigationIntent: _handlePushNavigationIntent,
      onInitialIntent: _handleLaunchTap,
      onForegroundIntent: _handleForegroundOffer,
      onTripPush: _tripPushed,
      foregroundEnabled: _signedIn,
      messageSource: widget.pushMessageSource,
      child: content,
    );
  }

  /// Work's offers area. The card itself is the app-wide one
  /// ([DriverOfferLayer]); Work says "Waiting for offers" while there is
  /// none.
  Widget? _pendingOffersPanel(Widget waitingPanel) {
    final offers = _offers;
    final factory = _offerCardFactory;
    if (offers == null || factory == null || !_signedIn) {
      return null;
    }
    return Column(
      children: [
        const TripOfferNotificationsWarning(),
        ListenableBuilder(
          listenable: offers.store,
          builder: (context, _) => offers.store.firstOffer == null
              ? waitingPanel
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  /// Kept from [didChangeDependencies]: dispose may not look it up.
  DriverOfferLayerState? _offerLayer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _offerLayer = DriverOfferLayer.maybeOf(context);
  }

  /// What the app-wide card shows: this driver's offers while signed in.
  DriverOfferLayerSource? _layerSource;

  void _syncOfferLayer() {
    final offers = _offers;
    final factory = _offerCardFactory;
    final wanted = offers == null || factory == null || !_signedIn
        ? null
        : DriverOfferLayerSource(
            coordinator: offers,
            controllerFactory: factory,
            pickupTimeLookup: _offerPickupTimeLookup,
            onAccepted: _openTripDetail,
          );
    final changed = (wanted == null) != (_layerSource == null);
    if (!changed) {
      return;
    }
    _layerSource = wanted;
    // Not during this build: the layer is above it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _offerLayer?.source = _layerSource;
      }
    });
  }

  Widget _buildContent(BuildContext context) {
    if (_localDemoOpened || _signedIn) {
      final shell = DriverShell(
        configuration: widget.configuration,
        localQaEnabled: widget.localQaEnabled,
        onSignOut: _signOut,
        requestNotificationPermission: _signedIn
            ? _pushDeviceRegistrar?.requestNotificationPermission
            : null,
        driverDutyGateway: _dutyGateway,
        driverTripActionControllerFactory:
            widget.driverTripActionControllerFactory,
        driverOfferResponseControllerFactory:
            _sessionAwareOfferResponseControllerFactory,
        signInTimeLeft: _signedIn
            ? () async => authTokenTimeLeft(
                await widget.authTokenStore.readRefreshToken(),
              )
            : null,
        pendingOffersPanelBuilder: _offers == null
            ? null
            : (waitingPanel) =>
                  _pendingOffersPanel(waitingPanel) ?? waitingPanel,
        onDutyChanged: _offers?.setOnDuty,
        reloadSignal: _tripsChanged,
        driverShiftCheckController: widget.driverShiftCheckController,
        driverReportGateway: widget.driverReportGateway,
        driverRatingGateway: widget.driverRatingGateway,
        driverTrustedContactRepository: widget.driverTrustedContactRepository,
        driverSafetyAlertRepository: widget.driverSafetyAlertRepository,
      );
      return _offers == null &&
              _signedIn &&
              (_pushDeviceRegistrar != null || widget.pushMessageSource != null)
          ? FirebaseForegroundPushListener(
              onNavigationIntent: _handlePushNavigationIntent,
              onTripPush: _tripPushed,
              messageSource: widget.pushMessageSource,
              child: shell,
            )
          : shell;
    }

    if (_restoringSession) {
      return const Scaffold(
        key: Key('driver-session-restoring'),
        backgroundColor: AsmColors.driverVisualSurface,
        body: Center(
          child: CircularProgressIndicator(color: AsmColors.driverMintAction),
        ),
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
              Container(
                width: 176,
                height: 56,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: AsmColors.brandWhite,
                  borderRadius: BorderRadius.circular(AsmRadii.radius16),
                ),
                child: Image.asset(
                  'assets/brand/alanteh-master-logo.png',
                  key: const Key('driver-login-brand-logo'),
                  width: 176,
                  height: 48,
                  fit: BoxFit.contain,
                  alignment: Alignment.centerLeft,
                  semanticLabel: 'ALANTEH driver logo',
                ),
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
    tokenStore: tokenStore,
    refreshAccessToken: refreshAccessToken,
  );
}

ApiDriverRatingGateway? _driverRatingGatewayFor({
  required String? baseUrl,
  required AuthTokenStore tokenStore,
}) {
  if (!AsmApiBaseUrl.isUsable(baseUrl)) {
    return null;
  }

  return ApiDriverRatingGateway(
    apiGateway: AsmDriverRatingApiGateway(
      GhanaResilientApiClient(
        baseUrl: baseUrl!,
        tokenProvider: _StoredAccessTokenProvider(tokenStore),
      ),
    ),
  );
}

DriverTripActionControllerFactory? _driverTripActionControllerFactoryFor({
  required String? baseUrl,
  required AuthTokenStore tokenStore,
  required DriverDutyGateway dutyGateway,
  DriverAccessTokenRefresh? refreshAccessToken,
  DriverTripActionPersistentQueue? persistentQueue,
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
  final resolvedQueue = persistentQueue ?? PersistentDriverTripActionQueue();

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
      queue: resolvedQueue,
      gateway: liveGateway,
      tripReference: tripReference,
      driverId: driverReference,
      readCurrentTripStatus: () async {
        final currentTrip = await dutyGateway.fetchTripDetail(tripReference);
        return currentTrip.status;
      },
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

DriverOfferResponseControllerFactory? driverOfferResponseControllerFactoryFor({
  required String? baseUrl,
  required AuthTokenStore tokenStore,
  required DriverDutyGateway dutyGateway,
  DriverAccessTokenRefresh? refreshAccessToken,
  DriverTripActionPersistentQueue? persistentQueue,
  DriverOfferResponseGateway? offerGateway,
}) {
  if (!AsmApiBaseUrl.isUsable(baseUrl)) {
    return null;
  }

  final resolvedGateway =
      offerGateway ??
      ApiDriverOfferResponseGateway(
        apiGateway: AsmDriverOfferResponseApiGateway(
          GhanaResilientApiClient(baseUrl: baseUrl!),
        ),
        tokenStore: tokenStore,
        refreshAccessToken: refreshAccessToken,
      );
  final resolvedQueue = persistentQueue ?? PersistentDriverTripActionQueue();

  return (tripReference, {assignedAt, unknownOffer = false}) async {
    DriverDutySummary duty;

    try {
      duty = await dutyGateway.fetchDuty();
    } on Object {
      throw const DriverOfferPreparationException(
        DriverOfferPreparationFailureCode.driverDutyFetchFailed,
      );
    }

    final driverReference = duty.driverReference?.trim();
    if (driverReference == null || driverReference.isEmpty) {
      throw const DriverOfferPreparationException(
        DriverOfferPreparationFailureCode.driverReferenceMissing,
      );
    }

    return DriverOfferResponseResilienceController(
      queue: resolvedQueue,
      gateway: resolvedGateway,
      tripReference: tripReference,
      driverId: driverReference,
      assignedAt: assignedAt,
      unknownOffer: unknownOffer,
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

DriverReportGateway? _driverReportGatewayFor({
  required String? baseUrl,
  required AuthTokenStore tokenStore,
  DriverAccessTokenRefresh? refreshAccessToken,
}) {
  if (!AsmApiBaseUrl.isUsable(baseUrl)) {
    return null;
  }

  return ApiDriverReportGateway(
    apiGateway: AsmDriverReportApiGateway(
      GhanaResilientApiClient(baseUrl: baseUrl!),
    ),
    tokenStore: tokenStore,
    refreshAccessToken: refreshAccessToken,
  );
}

DriverShiftCheckSubmissionController? _driverShiftCheckControllerFor({
  required String? baseUrl,
  required AuthTokenStore tokenStore,
  required DriverTripActionPersistentQueue persistentQueue,
  required DriverAccessTokenRefresh? refreshAccessToken,
}) {
  if (!AsmApiBaseUrl.isUsable(baseUrl)) {
    return null;
  }

  final reachability = GhanaApiReachability(baseUrl: baseUrl);

  return DriverShiftCheckSubmissionController(
    queue: persistentQueue,
    gateway: ApiDriverShiftCheckGateway(
      client: GhanaResilientApiClient(baseUrl: baseUrl!),
      tokenStore: tokenStore,
      refreshAccessToken: refreshAccessToken,
    ),
    isOnline: () => reachability.isOnline,
    connectivitySource: const PluginGhanaConnectivitySource(),
  );
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
