import 'dart:async';
import 'dart:io';
import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_app_config/asm_app_config.dart';
import 'package:asm_auth/asm_auth.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passenger_app/account/passenger_account_screen.dart';
import 'package:passenger_app/main.dart';
import 'package:passenger_app/map/passenger_map.dart';
import 'package:passenger_app/passenger_shell.dart';
import 'package:passenger_app/ride_requests/ride_request_history.dart';

void main() {
  test('Passenger auth endpoint contract paths remain stable', () {
    expect(AuthService.tokenPath, '/api/auth/token/');
    expect(AuthService.refreshPath, '/api/auth/token/refresh/');
  });

  test('M3A keeps Passenger runtime free of unaccepted backend endpoints', () {
    final source = _readM3aDartSources('lib');

    expect(source, contains('PassengerAccountScreen'));
    expect(source, contains('AsmPassengerMap'));
    expect(source, isNot(contains('/api/mobile/passenger/ride-requests/')));
    expect(source, isNot(contains('/api/trips')));
    expect(source, isNot(contains('/api/rides/status')));
    expect(source, isNot(contains('/api/driver')));
    expect(source, isNot(contains('/api/dispatch')));
    expect(source, isNot(contains('/api/assignments')));
    expect(source, isNot(contains('/api/routes')));
    expect(source, isNot(contains('/api/estimate')));
    expect(source, isNot(contains('/api/fares')));
    expect(source, isNot(contains('/api/profile')));
    expect(source, isNot(contains('/api/account')));
    expect(source, isNot(contains('/api/wallet')));
    expect(source, isNot(contains('/api/payment')));
    expect(source, isNot(contains('/api/payments')));
    expect(source, isNot(contains('/api/payout')));
    expect(source, isNot(contains('/api/payouts')));
    expect(source, isNot(contains('/api/earnings')));
    expect(source, isNot(contains('/api/support')));
    expect(source, isNot(contains('/api/documents')));
    expect(source, isNot(contains('/api/verification')));
    expect(source, isNot(contains('/api/vehicles')));
    expect(source, isNot(contains('/api/logout')));
    expect(source, isNot(contains('session/validate')));
    expect(source, isNot(contains('GoogleMap')));
    expect(source, isNot(contains('geolocator')));
    for (final credential in _m3aDevelopmentCredentials) {
      expect(source, isNot(contains(credential)));
    }
    expect(source, isNot(contains(['fake', 'token'].join(' '))));
    expect(source, isNot(contains(['fake', 'Token'].join())));
  });

  test('Passenger ALANTEH in-app logo asset is bundled', () async {
    final logo = await rootBundle.load('assets/brand/alanteh_header_dark.png');
    expect(logo.lengthInBytes, greaterThan(0));
  });

  testWidgets(
    'PassengerAccountScreen masks phone and exposes account actions',
    (tester) async {
      var openedTrips = false;
      var signedOut = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: AsmThemes.passenger,
          home: PassengerAccountScreen(
            phoneNumber: '+233559991234',
            onOpenTrips: () => openedTrips = true,
            onSignOut: () => signedOut = true,
          ),
        ),
      );

      expect(find.byType(PassengerAccountScreen), findsOneWidget);
      expect(find.text('+233 55 ****234'), findsOneWidget);
      expect(find.text('Riding clean with ALANTEH.'), findsOneWidget);
      expect(find.text('+233559991234'), findsNothing);
      expect(
        find.byKey(const Key('passenger-account-my-trips')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('passenger-account-help')), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
      expect(
        find.byKey(const Key('passenger-account-sign-out')),
        findsOneWidget,
      );
      expect(find.textContaining('Control Center'), findsNothing);
      expect(find.textContaining('profile endpoint'), findsNothing);
      expect(find.textContaining('account endpoint'), findsNothing);

      await tester.tap(find.byKey(const Key('passenger-account-my-trips')));
      expect(openedTrips, isTrue);

      await tester.tap(find.byKey(const Key('passenger-account-help')));
      await tester.pumpAndSettle();
      expect(find.text('Contact us at contact@alanteh.io'), findsOneWidget);

      await tester.tap(find.byKey(const Key('passenger-account-help-close')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('passenger-account-sign-out')));
      expect(signedOut, isTrue);
    },
  );

  testWidgets('PassengerAccountScreen shows safe phone fallback', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: PassengerAccountScreen(
          phoneNumber: null,
          onOpenTrips: () {},
          onSignOut: () {},
        ),
      ),
    );

    expect(find.text('Phone number unavailable'), findsOneWidget);
    expect(find.textContaining('Control Center'), findsNothing);
  });

  testWidgets('AsmPassengerMap uses Accra center and renders without marker', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AsmPassengerMap())),
    );

    expect(find.byType(AsmPassengerMap), findsOneWidget);
    expect(find.byType(FlutterMap), findsOneWidget);
    final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
    expect(map.options.initialCenter.latitude, accraHomeCenter.latitude);
    expect(map.options.initialCenter.longitude, accraHomeCenter.longitude);
    expect(map.options.initialZoom, initialZoom);
    expect(find.byKey(const Key('passenger-map-pickup-marker')), findsNothing);
  });

  testWidgets('AsmPassengerMap renders pickup marker when description exists', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AsmPassengerMap(pickup: accraPickup)),
      ),
    );

    expect(find.byType(FlutterMap), findsOneWidget);
    expect(
      find.byKey(const Key('passenger-map-pickup-marker')),
      findsOneWidget,
    );
  });

  testWidgets('Passenger phone PIN login opens M-UX3 home', (tester) async {
    _useSurface(tester, const Size(430, 900));
    final store = MemoryAuthTokenStore();
    final api = _FakeAuthApiGateway(responseData: _loginResponse());

    await tester.pumpWidget(_loginTestApp(api: api, store: store));

    expect(find.byKey(const Key('passenger-login-brand-logo')), findsOneWidget);
    expect(find.text('Sign in to ride'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('passenger-phone-field')),
      '+233000000000',
    );
    await tester.enterText(
      find.byKey(const Key('passenger-pin-field')),
      '0000',
    );
    await tester.tap(find.byKey(const Key('passenger-sign-in')));
    await tester.pumpAndSettle();

    expect(api.paths, <String>[AuthService.tokenPath]);
    expect(api.bodies.single.keys, isNot(contains('password')));
    expect(api.bodies.single.keys, isNot(contains('email')));
    expect(await store.readAccessToken(), 'passenger-access-token');
    expect(await store.readRefreshToken(), 'passenger-refresh-token');

    expect(
      find.byKey(const Key('passenger-home-full-screen-map-layout')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('passenger-home-floating-logo')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('passenger-home-solar-banner')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('passenger-home-bottom-sheet')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('open-live-request')), findsOneWidget);
    expect(find.byKey(const Key('open-ride-request-history')), findsOneWidget);
    expect(find.byKey(const Key('passenger-map')), findsOneWidget);
    expect(find.text('Request ride'), findsOneWidget);
    expect(find.text('My Ride Requests'), findsOneWidget);
    expect(
      find.text(
        "Ghana's first solar electric ride service. Clean, quiet, and reliable.",
      ),
      findsOneWidget,
    );
    expect(find.text('Route preview'), findsNothing);
    expect(find.byKey(const Key('choose-pickup')), findsNothing);
    expect(find.byKey(const Key('continue-local-draft')), findsNothing);
    expect(find.text('LOCAL DEMO'), findsNothing);
  });

  testWidgets('Passenger invalid login input is blocked before network', (
    tester,
  ) async {
    _useSurface(tester, const Size(430, 900));
    final store = MemoryAuthTokenStore();
    final api = _FakeAuthApiGateway(responseData: _loginResponse());

    await tester.pumpWidget(_loginTestApp(api: api, store: store));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('passenger-sign-in')));
    await tester.pumpAndSettle();

    expect(find.text(loginPhoneRequiredMessage), findsOneWidget);
    expect(find.text(loginPinRequiredMessage), findsOneWidget);
    expect(api.paths, isEmpty);
    expect(await store.readAccessToken(), isNull);
    expect(await store.readRefreshToken(), isNull);

    await tester.enterText(
      find.byKey(const Key('passenger-phone-field')),
      '0550000000',
    );
    await tester.enterText(find.byKey(const Key('passenger-pin-field')), '123');
    await tester.tap(find.byKey(const Key('passenger-sign-in')));
    await tester.pumpAndSettle();

    expect(find.text(loginPhoneFormatMessage), findsOneWidget);
    expect(find.text(loginPinFormatMessage), findsOneWidget);
    expect(api.paths, isEmpty);

    await tester.enterText(
      find.byKey(const Key('passenger-phone-field')),
      '+23300 0000000',
    );
    await tester.enterText(
      find.byKey(const Key('passenger-pin-field')),
      '12a4',
    );
    await tester.tap(find.byKey(const Key('passenger-sign-in')));
    await tester.pumpAndSettle();

    expect(find.text(loginPhoneFormatMessage), findsOneWidget);
    expect(find.text(loginPinFormatMessage), findsOneWidget);
    expect(api.paths, isEmpty);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('passenger-phone-field')))
          .controller
          ?.text,
      '+23300 0000000',
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('passenger-pin-field')))
          .controller
          ?.text,
      '12a4',
    );
    expect(await store.readAccessToken(), isNull);
    expect(await store.readRefreshToken(), isNull);
  });

  testWidgets('Passenger local QA opens the same M-UX3 home', (tester) async {
    _useSurface(tester, const Size(430, 900));
    final store = MemoryAuthTokenStore();
    final api = _FakeAuthApiGateway(responseData: _loginResponse());

    await tester.pumpWidget(
      _loginTestApp(
        api: api,
        store: store,
        configuration: _localQaEnabledConfig,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('passenger-continue-local-qa')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('passenger-continue-local-qa')));
    await tester.pumpAndSettle();

    expect(api.paths, isEmpty);
    expect(await store.readAccessToken(), isNull);
    expect(await store.readRefreshToken(), isNull);
    expect(
      find.byKey(const Key('passenger-home-full-screen-map-layout')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('passenger-home-solar-banner')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('open-live-request')), findsOneWidget);
    expect(find.text('Request ride'), findsOneWidget);
    expect(find.text('Route preview'), findsNothing);
    expect(find.byKey(const Key('choose-pickup')), findsNothing);
    expect(find.byKey(const Key('continue-local-draft')), findsNothing);
  });

  testWidgets('Passenger login rejects non-passenger account types', (
    tester,
  ) async {
    for (final accountType in <Object?>['driver', 'staff', 'unknown', null]) {
      _useSurface(tester, const Size(430, 900));
      final store = MemoryAuthTokenStore();
      final api = _FakeAuthApiGateway(
        responseData: _loginResponse(accountType: accountType),
      );
      await tester.pumpWidget(_loginTestApp(api: api, store: store));

      await tester.enterText(
        find.byKey(const Key('passenger-phone-field')),
        '+233000000000',
      );
      await tester.enterText(
        find.byKey(const Key('passenger-pin-field')),
        '0000',
      );
      await tester.tap(find.byKey(const Key('passenger-sign-in')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('passenger-login-error')), findsOneWidget);
      expect(find.text(authAppContextErrorMessage), findsOneWidget);
      expect(find.text('Map preview unavailable.'), findsNothing);
      expect(await store.readAccessToken(), isNull);
      expect(await store.readRefreshToken(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('failed Passenger login shows clear error and stores no token', (
    tester,
  ) async {
    _useSurface(tester, const Size(430, 900));
    final store = MemoryAuthTokenStore();
    final api = _FakeAuthApiGateway(statusCode: 401);
    await tester.pumpWidget(_loginTestApp(api: api, store: store));

    await tester.enterText(
      find.byKey(const Key('passenger-phone-field')),
      '+233000000000',
    );
    await tester.enterText(
      find.byKey(const Key('passenger-pin-field')),
      '0000',
    );
    await tester.tap(find.byKey(const Key('passenger-sign-in')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('passenger-login-error')), findsOneWidget);
    expect(
      find.text('Sign in failed. Check your phone and PIN.'),
      findsOneWidget,
    );
    expect(find.text('Map preview unavailable.'), findsNothing);
    expect(await store.readAccessToken(), isNull);
    expect(await store.readRefreshToken(), isNull);
  });

  testWidgets(
    'Passenger sign-in shows loading state and prevents duplicate submit while loading',
    (tester) async {
      _useSurface(tester, const Size(430, 900));
      final store = MemoryAuthTokenStore();
      final pending = Completer<ApiResponse<Map<String, Object?>>>();
      final api = _FakeAuthApiGateway(pendingResponse: pending);

      await tester.pumpWidget(
        PassengerApp(
          showLoginShell: true,
          authTokenStore: store,
          authService: AuthService(
            apiGateway: api,
            tokenStore: store,
            appContext: AuthAppContext.passenger,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('passenger-phone-field')),
        '+233000000000',
      );
      await tester.enterText(
        find.byKey(const Key('passenger-pin-field')),
        '0000',
      );
      await tester.tap(find.byKey(const Key('passenger-sign-in')));
      await tester.pump();

      expect(find.text('Signing in...'), findsOneWidget);
      expect(api.paths, <String>[AuthService.tokenPath]);

      await tester.tap(find.byKey(const Key('passenger-sign-in')));
      await tester.pump();

      expect(api.paths, <String>[AuthService.tokenPath]);

      pending.complete(ApiResponse.success(_loginResponse(), statusCode: 200));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('passenger-login-error')), findsNothing);
      expect(await store.readAccessToken(), isNotNull);
    },
  );

  testWidgets('Passenger sign-in invalid credentials shows safe message', (
    tester,
  ) async {
    _useSurface(tester, const Size(430, 900));
    final store = MemoryAuthTokenStore();
    final api = _FakeAuthApiGateway(statusCode: 401);

    await tester.pumpWidget(
      PassengerApp(
        showLoginShell: true,
        authTokenStore: store,
        authService: AuthService(
          apiGateway: api,
          tokenStore: store,
          appContext: AuthAppContext.passenger,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('passenger-phone-field')),
      '+233000000000',
    );
    await tester.enterText(
      find.byKey(const Key('passenger-pin-field')),
      '0000',
    );
    await tester.tap(find.byKey(const Key('passenger-sign-in')));
    await tester.pumpAndSettle();

    expect(
      find.text('Sign in failed. Check your phone and PIN.'),
      findsOneWidget,
    );
    expect(find.textContaining('Authentication failed'), findsNothing);
    expect(await store.readAccessToken(), isNull);
  });

  testWidgets('Passenger sign-in network failure shows safe message', (
    tester,
  ) async {
    _useSurface(tester, const Size(430, 900));
    final store = MemoryAuthTokenStore();
    final api = _FakeAuthApiGateway(exceptionType: AsmApiExceptionType.network);

    await tester.pumpWidget(
      PassengerApp(
        showLoginShell: true,
        authTokenStore: store,
        authService: AuthService(
          apiGateway: api,
          tokenStore: store,
          appContext: AuthAppContext.passenger,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('passenger-phone-field')),
      '+233000000000',
    );
    await tester.enterText(
      find.byKey(const Key('passenger-pin-field')),
      '0000',
    );
    await tester.tap(find.byKey(const Key('passenger-sign-in')));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Cannot reach the server. Check your connection and try again.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Raw technical'), findsNothing);
    expect(await store.readAccessToken(), isNull);
  });

  testWidgets(
    'Passenger sign-in timeout shows safe message and stores no token',
    (tester) async {
      _useSurface(tester, const Size(430, 900));
      final store = MemoryAuthTokenStore();
      final api = _FakeAuthApiGateway(
        exceptionType: AsmApiExceptionType.timeout,
      );

      await tester.pumpWidget(
        PassengerApp(
          showLoginShell: true,
          authTokenStore: store,
          authService: AuthService(
            apiGateway: api,
            tokenStore: store,
            appContext: AuthAppContext.passenger,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('passenger-phone-field')),
        '+233000000000',
      );
      await tester.enterText(
        find.byKey(const Key('passenger-pin-field')),
        '0000',
      );
      await tester.tap(find.byKey(const Key('passenger-sign-in')));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Cannot reach the server. Check your connection and try again.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('TimeoutException'), findsNothing);
      expect(find.textContaining('Raw technical'), findsNothing);
      expect(find.byKey(const Key('passenger-phone-field')), findsOneWidget);
      expect(await store.readAccessToken(), isNull);
      expect(await store.readRefreshToken(), isNull);
    },
  );

  testWidgets('Passenger sign-in 503 shows service unavailable message', (
    tester,
  ) async {
    _useSurface(tester, const Size(430, 900));
    final store = MemoryAuthTokenStore();
    final api = _FakeAuthApiGateway(statusCode: 503);

    await tester.pumpWidget(
      PassengerApp(
        showLoginShell: true,
        authTokenStore: store,
        authService: AuthService(
          apiGateway: api,
          tokenStore: store,
          appContext: AuthAppContext.passenger,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('passenger-phone-field')),
      '+233000000000',
    );
    await tester.enterText(
      find.byKey(const Key('passenger-pin-field')),
      '0000',
    );
    await tester.tap(find.byKey(const Key('passenger-sign-in')));
    await tester.pumpAndSettle();

    expect(
      find.text('Service is temporarily unavailable. Please try again later.'),
      findsOneWidget,
    );
    expect(await store.readAccessToken(), isNull);
  });

  testWidgets('Passenger sign-in non-passenger account shows app mismatch', (
    tester,
  ) async {
    _useSurface(tester, const Size(430, 900));
    final store = MemoryAuthTokenStore();
    final api = _FakeAuthApiGateway(
      responseData: const <String, Object?>{
        'access': 'driver-access',
        'refresh': 'driver-refresh',
        'account_type': 'driver',
      },
    );

    await tester.pumpWidget(
      PassengerApp(
        showLoginShell: true,
        authTokenStore: store,
        authService: AuthService(
          apiGateway: api,
          tokenStore: store,
          appContext: AuthAppContext.passenger,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('passenger-phone-field')),
      '+233000000000',
    );
    await tester.enterText(
      find.byKey(const Key('passenger-pin-field')),
      '0000',
    );
    await tester.tap(find.byKey(const Key('passenger-sign-in')));
    await tester.pumpAndSettle();

    expect(find.text(authAppContextErrorMessage), findsOneWidget);
    expect(await store.readAccessToken(), isNull);
  });

  testWidgets(
    'Passenger app accepts production API base URL dart-define without live HTTP',
    (tester) async {
      const productionBaseUrl = 'https://control.alanteh.io';
      const configuredBaseUrl = String.fromEnvironment('ASM_API_BASE_URL');

      if (configuredBaseUrl != productionBaseUrl) {
        expect(AsmApiClient.defaultBaseUrl, configuredBaseUrl);
        return;
      }

      await tester.pumpWidget(const PassengerApp());
      await tester.pump();

      expect(AsmApiClient.defaultBaseUrl, productionBaseUrl);
      expect(AsmApiBaseUrl.isUsable(AsmApiClient.defaultBaseUrl), isTrue);
      expect(AuthService.tokenPath, '/api/auth/token/');
      expect(AuthService.refreshPath, '/api/auth/token/refresh/');
      expect(find.byType(PassengerApp), findsOneWidget);
    },
  );

  testWidgets(
    'real sign-in without API base URL shows connection configuration error',
    (tester) async {
      if (AsmApiClient.defaultBaseUrl.trim().isNotEmpty) {
        return;
      }

      _useSurface(tester, const Size(430, 900));
      final store = MemoryAuthTokenStore();

      await tester.pumpWidget(
        PassengerApp(showLoginShell: true, authTokenStore: store),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('passenger-phone-field')),
        '+233000000000',
      );
      await tester.enterText(
        find.byKey(const Key('passenger-pin-field')),
        '0000',
      );
      await tester.tap(find.byKey(const Key('passenger-sign-in')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('passenger-login-error')), findsOneWidget);
      expect(
        find.text(AsmApiClient.connectionNotConfiguredMessage),
        findsOneWidget,
      );
      expect(await store.readAccessToken(), isNull);
      expect(await store.readRefreshToken(), isNull);
      expect(find.text('Map preview unavailable.'), findsNothing);
    },
  );

  testWidgets('navigates the M-UX3 passenger shell', (tester) async {
    _useSurface(tester, const Size(430, 900));

    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: const PassengerShell(
          rideRequestHistoryRepository:
              EmptyPassengerRideRequestHistoryRepository(),
        ),
      ),
    );

    expect(
      find.byKey(const Key('passenger-home-full-screen-map-layout')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('passenger-home-floating-logo')),
      findsOneWidget,
    );

    final passengerHomeLogo = tester.widget<Image>(
      find.descendant(
        of: find.byKey(const Key('passenger-home-floating-logo')),
        matching: find.byType(Image),
      ),
    );

    expect(passengerHomeLogo.width, 132);
    expect(passengerHomeLogo.fit, BoxFit.contain);
    expect(passengerHomeLogo.semanticLabel, contains('ALANTEH'));

    expect(find.text('Request ride'), findsOneWidget);
    expect(find.text('My Ride Requests'), findsOneWidget);
    expect(find.byKey(const Key('passenger-map')), findsOneWidget);
    expect(find.text('Route preview'), findsNothing);
    expect(find.byKey(const Key('choose-pickup')), findsNothing);
    expect(find.byKey(const Key('continue-local-draft')), findsNothing);

    await tester.tap(find.byKey(const Key('open-live-request')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('booking-pickup')), findsOneWidget);
    expect(find.byKey(const Key('booking-destination')), findsOneWidget);

    await tester.pageBack();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    AsmBottomNavigationBar navigationBar() => tester
        .widget<AsmBottomNavigationBar>(find.byType(AsmBottomNavigationBar));

    navigationBar().onDestinationSelected!.call(1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('No trips yet.'), findsOneWidget);
    expect(find.text('Your ride history will appear here.'), findsOneWidget);

    navigationBar().onDestinationSelected!.call(0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.byKey(const Key('passenger-home-full-screen-map-layout')),
      findsOneWidget,
    );

    navigationBar().onDestinationSelected!.call(2);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('passenger-account-screen')), findsOneWidget);
    expect(find.text('Phone number unavailable'), findsOneWidget);
    expect(find.byKey(const Key('passenger-account-sign-out')), findsOneWidget);
    expect(find.textContaining('wallet'), findsNothing);
    expect(find.textContaining('payment method'), findsNothing);
    expect(find.textContaining('ride statistics'), findsNothing);
  });

  testWidgets('M-UX3 home remains usable on a small scaled screen', (
    tester,
  ) async {
    _useSurface(tester, const Size(320, 568));

    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: const PassengerShell(localQaEnabled: true),
      ),
    );

    expect(
      find.byKey(const Key('passenger-home-full-screen-map-layout')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('passenger-home-floating-logo')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('passenger-home-solar-banner')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('passenger-home-bottom-sheet')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('open-live-request')), findsOneWidget);
    expect(find.byKey(const Key('open-ride-request-history')), findsOneWidget);
    expect(find.text('Route preview'), findsNothing);
    expect(find.byKey(const Key('choose-pickup')), findsNothing);
    expect(find.byKey(const Key('continue-local-draft')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('passenger shell hides internal and no live feature wording', (
    tester,
  ) async {
    _useSurface(tester, const Size(430, 900));
    await tester.pumpWidget(const PassengerApp());

    for (final removedText in _removedPassengerTexts) {
      expect(find.text(removedText), findsNothing);
    }

    for (final forbiddenText in _noLiveFeatureTexts) {
      expect(find.textContaining(forbiddenText), findsNothing);
    }
  });

  testWidgets('Passenger live home shows the M-UX3 full-screen map layout', (
    tester,
  ) async {
    _useSurface(tester, const Size(430, 900));

    await tester.pumpWidget(
      MaterialApp(theme: AsmThemes.passenger, home: const PassengerShell()),
    );

    expect(
      find.byKey(const Key('passenger-home-full-screen-map-layout')),
      findsOneWidget,
    );
    expect(find.byType(AsmPassengerMap), findsOneWidget);
    expect(find.byKey(const Key('passenger-map')), findsOneWidget);
    expect(
      find.byKey(const Key('passenger-home-floating-logo')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('passenger-home-solar-banner')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('passenger-home-bottom-sheet')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('open-live-request')), findsOneWidget);
    expect(find.byKey(const Key('open-ride-request-history')), findsOneWidget);
    expect(find.text('Request ride'), findsOneWidget);
    expect(find.text('My Ride Requests'), findsOneWidget);
    expect(find.text('Route preview'), findsNothing);
    expect(find.byKey(const Key('choose-pickup')), findsNothing);
    expect(find.byKey(const Key('choose-destination')), findsNothing);
    expect(find.byKey(const Key('continue-local-draft')), findsNothing);
    expect(find.textContaining('driver assignment'), findsNothing);
    expect(find.textContaining('active trip'), findsNothing);
  });

  testWidgets('Passenger local QA does not restore the old route planner', (
    tester,
  ) async {
    _useSurface(tester, const Size(430, 900));
    final store = MemoryAuthTokenStore();
    final api = _FakeAuthApiGateway(responseData: _loginResponse());

    await tester.pumpWidget(
      _loginTestApp(
        api: api,
        store: store,
        configuration: _localQaEnabledConfig,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('passenger-continue-local-qa')));
    await tester.pumpAndSettle();

    expect(api.paths, isEmpty);
    expect(await store.readAccessToken(), isNull);
    expect(await store.readRefreshToken(), isNull);
    expect(
      find.byKey(const Key('passenger-home-full-screen-map-layout')),
      findsOneWidget,
    );
    expect(find.byType(AsmPassengerMap), findsOneWidget);
    expect(find.byKey(const Key('passenger-map')), findsOneWidget);
    expect(find.byKey(const Key('open-live-request')), findsOneWidget);
    expect(find.text('Route preview'), findsNothing);
    expect(find.byKey(const Key('choose-pickup')), findsNothing);
    expect(find.byKey(const Key('choose-destination')), findsNothing);
    expect(find.byKey(const Key('continue-local-draft')), findsNothing);
    expect(find.textContaining('/api/routes'), findsNothing);
    expect(find.textContaining('/api/estimate'), findsNothing);
    expect(find.textContaining('/api/fares'), findsNothing);
    expect(find.textContaining('GoogleMap'), findsNothing);
    expect(find.textContaining('geolocator'), findsNothing);
  });

  testWidgets('Passenger startup without stored tokens opens login', (
    tester,
  ) async {
    _useSurface(tester, const Size(430, 900));
    final store = MemoryAuthTokenStore();
    final api = _FakeAuthApiGateway(responseData: _loginResponse());

    await tester.pumpWidget(_loginTestApp(api: api, store: store));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('passenger-sign-in')), findsOneWidget);
    expect(find.byKey(const Key('passenger-sign-out')), findsNothing);
    expect(find.text('Passenger access'), findsOneWidget);
    expect(api.paths, isEmpty);
  });

  testWidgets(
    'Passenger access-only restored session clears tokens and asks sign in again',
    (tester) async {
      _useSurface(tester, const Size(430, 900));
      final store = _AccessOnlyAuthTokenStore('stored-passenger-access');
      final api = _FakeAuthApiGateway(responseData: _loginResponse());

      await tester.pumpWidget(_loginTestApp(api: api, store: store));
      await tester.pumpAndSettle();

      expect(api.paths, isEmpty);
      expect(find.byKey(const Key('passenger-sign-in')), findsOneWidget);
      expect(find.text('Passenger access'), findsOneWidget);
      expect(find.text('Please sign in again to continue.'), findsOneWidget);
      expect(find.text('Book a ride'), findsNothing);
      expect(await store.readAccessToken(), isNull);
      expect(await store.readRefreshToken(), isNull);
    },
  );

  testWidgets(
    'Passenger rejected restored session clears tokens and asks sign in again',
    (tester) async {
      _useSurface(tester, const Size(430, 900));
      final store = MemoryAuthTokenStore();
      await store.saveTokens(
        AuthTokens(
          accessToken: 'expired-passenger-access',
          refreshToken: 'expired-passenger-refresh',
        ),
      );
      final api = _FakeAuthApiGateway(statusCode: 401);

      await tester.pumpWidget(_loginTestApp(api: api, store: store));
      await tester.pumpAndSettle();

      expect(api.paths, <String>[AuthService.refreshPath]);
      expect(api.bodies.single, <String, Object?>{
        'refresh': 'expired-passenger-refresh',
      });
      expect(find.byKey(const Key('passenger-sign-in')), findsOneWidget);
      expect(find.text('Passenger access'), findsOneWidget);
      expect(find.text('Please sign in again to continue.'), findsOneWidget);
      expect(find.text('Book a ride'), findsNothing);
      expect(await store.readAccessToken(), isNull);
      expect(await store.readRefreshToken(), isNull);
    },
  );

  testWidgets('Passenger refreshed session opens M-UX3 home', (tester) async {
    _useSurface(tester, const Size(430, 900));
    final store = MemoryAuthTokenStore();

    await store.saveTokens(
      AuthTokens(
        accessToken: 'stored-passenger-access',
        refreshToken: 'stored-passenger-refresh',
      ),
    );

    final api = _FakeAuthApiGateway(
      responseData: const <String, Object?>{
        'access': 'restored-passenger-access',
      },
    );

    await tester.pumpWidget(_loginTestApp(api: api, store: store));
    await tester.pumpAndSettle();

    expect(api.paths, <String>[AuthService.refreshPath]);
    expect(api.bodies.single, <String, Object?>{
      'refresh': 'stored-passenger-refresh',
    });
    expect(await store.readAccessToken(), 'restored-passenger-access');
    expect(await store.readRefreshToken(), 'stored-passenger-refresh');

    expect(
      find.byKey(const Key('passenger-home-full-screen-map-layout')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('passenger-home-solar-banner')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('open-live-request')), findsOneWidget);
    expect(find.byKey(const Key('open-ride-request-history')), findsOneWidget);
    expect(find.byKey(const Key('passenger-map')), findsOneWidget);
    expect(find.text('Request ride'), findsOneWidget);
    expect(find.text('Route preview'), findsNothing);
    expect(find.text('Please sign in again to continue.'), findsNothing);
  });

  testWidgets('Passenger sign out after restored startup clears next startup', (
    tester,
  ) async {
    _useSurface(tester, const Size(430, 900));
    final store = MemoryAuthTokenStore();
    await store.saveTokens(
      AuthTokens(
        accessToken: 'stored-passenger-access',
        refreshToken: 'stored-passenger-refresh',
      ),
    );
    final api = _FakeAuthApiGateway(responseData: _loginResponse());

    await tester.pumpWidget(_loginTestApp(api: api, store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Account'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('passenger-account-sign-out')));
    await tester.pumpAndSettle();

    expect(await store.readAccessToken(), isNull);
    expect(await store.readRefreshToken(), isNull);
    expect(find.byKey(const Key('passenger-sign-in')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(_loginTestApp(api: api, store: store));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('passenger-sign-in')), findsOneWidget);
    expect(find.byKey(const Key('passenger-sign-out')), findsNothing);
  });

  testWidgets('Passenger local shell opens M-UX3 home without tokens', (
    tester,
  ) async {
    _useSurface(tester, const Size(430, 900));
    final store = MemoryAuthTokenStore();

    await tester.pumpWidget(PassengerApp(authTokenStore: store));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('passenger-home-full-screen-map-layout')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('passenger-home-solar-banner')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('open-live-request')), findsOneWidget);
    expect(find.byKey(const Key('open-ride-request-history')), findsOneWidget);
    expect(find.byKey(const Key('passenger-map')), findsOneWidget);
    expect(find.text('Request ride'), findsOneWidget);
    expect(find.text('Route preview'), findsNothing);
    expect(await store.readAccessToken(), isNull);
    expect(await store.readRefreshToken(), isNull);
  });

  testWidgets('passenger sign out clears tokens and returns to login', (
    tester,
  ) async {
    _useSurface(tester, const Size(430, 1000));
    final store = MemoryAuthTokenStore();
    final api = _FakeAuthApiGateway(responseData: _loginResponse());
    await tester.pumpWidget(
      PassengerApp(
        showLoginShell: true,
        authService: AuthService(
          apiGateway: api,
          tokenStore: store,
          appContext: AuthAppContext.passenger,
        ),
        authTokenStore: store,
      ),
    );

    await tester.enterText(
      find.byKey(const Key('passenger-phone-field')),
      '+233000000000',
    );
    await tester.enterText(
      find.byKey(const Key('passenger-pin-field')),
      '0000',
    );
    await tester.tap(find.byKey(const Key('passenger-sign-in')));
    await tester.pumpAndSettle();

    expect(await store.readAccessToken(), 'passenger-access-token');
    expect(await store.readRefreshToken(), 'passenger-refresh-token');
    expect(find.byKey(const Key('passenger-sign-out')), findsNothing);

    await tester.tap(find.text('Account'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('passenger-account-screen')), findsOneWidget);
    expect(find.text('+233 55 ****234'), findsOneWidget);
    expect(find.text('+233559991234'), findsNothing);
    expect(find.text('Sign out'), findsOneWidget);
    expect(find.byKey(const Key('passenger-account-sign-out')), findsOneWidget);

    await tester.tap(find.byKey(const Key('passenger-account-sign-out')));
    await tester.pumpAndSettle();

    expect(await store.readAccessToken(), isNull);
    expect(await store.readRefreshToken(), isNull);
    expect(find.byKey(const Key('passenger-sign-in')), findsOneWidget);
    expect(find.byKey(const Key('passenger-sign-out')), findsNothing);
    expect(find.text('Sign in'), findsOneWidget);
  });
}

Widget _loginTestApp({
  required _FakeAuthApiGateway api,
  required AuthTokenStore store,
  AsmAppConfig configuration = AsmAppConfig.localGhana,
}) {
  return PassengerApp(
    configuration: configuration,
    showLoginShell: true,
    authTokenStore: store,
    authService: AuthService(
      apiGateway: api,
      tokenStore: store,
      appContext: AuthAppContext.passenger,
    ),
  );
}

Map<String, Object?> _loginResponse({
  Object? accountType = 'passenger',
  String? phoneNumber = '+233559991234',
}) {
  final account = <String, Object?>{};
  if (phoneNumber != null) {
    account['phone'] = phoneNumber;
  }

  final response = <String, Object?>{
    'access': 'passenger-access-token',
    'refresh': 'passenger-refresh-token',
    'account': account,
  };

  if (accountType != null) {
    response['account_type'] = accountType;
  }

  return response;
}

class _AccessOnlyAuthTokenStore implements AuthTokenStore {
  _AccessOnlyAuthTokenStore(this._accessToken);

  String? _accessToken;

  @override
  Future<void> saveTokens(AuthTokens tokens) async {
    _accessToken = tokens.accessToken;
  }

  @override
  Future<String?> readAccessToken() async => _accessToken;

  @override
  Future<String?> readRefreshToken() async => null;

  @override
  Future<void> clearTokens() async {
    _accessToken = null;
  }
}

class _FakeAuthApiGateway implements AuthApiGateway {
  _FakeAuthApiGateway({
    this.responseData,
    this.statusCode = 200,
    this.exceptionType,
    this.pendingResponse,
  });

  final Map<String, Object?>? responseData;
  final int statusCode;
  final AsmApiExceptionType? exceptionType;
  final Completer<ApiResponse<Map<String, Object?>>>? pendingResponse;

  final paths = <String>[];
  final bodies = <Map<String, Object?>>[];

  @override
  Future<ApiResponse<Map<String, Object?>>> post(
    String path, {
    required Map<String, Object?> body,
  }) async {
    paths.add(path);
    bodies.add(body);

    final pending = pendingResponse;
    if (pending != null) {
      return pending.future;
    }

    final type = exceptionType;
    if (type != null) {
      return ApiResponse.clientException(
        AsmApiException(
          type: type,
          message: 'Raw technical auth failure must not be shown.',
          statusCode: statusCode == 200 ? null : statusCode,
        ),
      );
    }

    if (statusCode >= 200 && statusCode < 300 && responseData != null) {
      return ApiResponse.success(responseData!, statusCode: statusCode);
    }

    return ApiResponse.apiFailure(
      AsmApiException(
        type: statusCode == 401
            ? AsmApiExceptionType.authentication
            : statusCode >= 500
            ? AsmApiExceptionType.server
            : AsmApiExceptionType.badResponse,
        message: 'Authentication failed.',
        statusCode: statusCode,
        cause: const <String, Object?>{'detail': 'Invalid credentials.'},
      ),
    );
  }
}

const _localQaEnabledConfig = AsmAppConfig(
  environment: RuntimeEnvironment.local,
  market: MarketConfig.ghanaAccra,
  capabilities: CapabilityConfig(),
  localQaEnabled: true,
);

const _removedPassengerTexts = [
  'ASM PASSENGER',
  'ASM DRIVER',
  'Africa Solar Mobility',
  'Approved service context',
  'LOCAL DEMO',
  'Local QA',
  'Plan a demo ride',
  'Local draft',
  'local draft',
  'controlled pilot',
  'gh-accra',
  'This stays on this device',
  'No ride request has been sent',
  'Operating market',
  'Service context',
  'Close draft',
  'GHANA PILOT',
  'No ride service is connected',
  'Local description only. No map search is connected.',
  'No map search is connected',
  'Plan a demo ride',
  'Review local draft',
  'Close draft',
  'No trips connected',
  'No trips to show yet.',
  'Support not connected',
  'Live support is unavailable',
];

const _noLiveFeatureTexts = [
  'request_reference',
  'Paystack',
  'GPS',
  'GoogleMap',
  'WebSocket',
];

void _useSurface(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

String _readM3aDartSources(String rootPath) {
  final buffer = StringBuffer();
  for (final entity in Directory(rootPath).listSync(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) {
      buffer.writeln(entity.readAsStringSync());
    }
  }
  return buffer.toString();
}

List<String> get _m3aDevelopmentCredentials => <String>[
  ['+23355', '123', '4567'].join(),
  ['+23324', '123', '4567'].join(),
  ['12', '34'].join(),
  ['43', '21'].join(),
];
