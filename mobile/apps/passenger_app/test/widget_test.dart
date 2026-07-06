import 'dart:async';
import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_app_config/asm_app_config.dart';
import 'package:asm_auth/asm_auth.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passenger_app/main.dart';
import 'package:passenger_app/passenger_shell.dart';

void main() {
  test('Passenger auth endpoint contract paths remain stable', () {
    expect(AuthService.tokenPath, '/api/auth/token/');
    expect(AuthService.refreshPath, '/api/auth/token/refresh/');
  });

  test('Passenger ALANTEH in-app logo asset is bundled', () async {
    final logo = await rootBundle.load('assets/brand/alanteh_header_dark.png');
    expect(logo.lengthInBytes, greaterThan(0));
  });

  testWidgets('Passenger phone PIN login stores tokens and opens home', (
    tester,
  ) async {
    _useSurface(tester, const Size(430, 900));
    final store = MemoryAuthTokenStore();
    final api = _FakeAuthApiGateway(responseData: _loginResponse());
    await tester.pumpWidget(_loginTestApp(api: api, store: store));

    expect(find.byKey(const Key('passenger-login-brand-logo')), findsOneWidget);
    final passengerLoginLogo = tester.widget<Image>(
      find.byKey(const Key('passenger-login-brand-logo')),
    );
    expect(passengerLoginLogo.width, greaterThanOrEqualTo(160));
    expect(passengerLoginLogo.width, lessThanOrEqualTo(190));
    expect(passengerLoginLogo.fit, BoxFit.contain);
    expect(find.text('Passenger access'), findsOneWidget);
    expect(find.text('Sign in to ride'), findsOneWidget);
    expect(find.byKey(const Key('passenger-phone-field')), findsOneWidget);
    expect(find.text('Phone number'), findsOneWidget);
    expect(find.byKey(const Key('passenger-pin-field')), findsOneWidget);
    expect(find.text('PIN'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Clear form'), findsOneWidget);
    expect(find.text('Continue'), findsNothing);
    expect(find.text('Pilot access'), findsNothing);
    expect(find.text('LOCAL DEMO'), findsNothing);
    expect(find.text('Create account'), findsNothing);
    expect(find.text('Open public account'), findsNothing);
    expect(find.text('Email'), findsNothing);
    expect(find.text('email'), findsNothing);
    expect(find.text('Password'), findsNothing);
    expect(find.text('password'), findsNothing);

    await tester.tap(find.byKey(const Key('passenger-sign-in')));
    await tester.pumpAndSettle();
    expect(find.text(loginPhoneRequiredMessage), findsOneWidget);
    expect(find.text(loginPinRequiredMessage), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('passenger-phone-field')),
      '0550000000',
    );
    await tester.enterText(find.byKey(const Key('passenger-pin-field')), '12');
    await tester.tap(find.byKey(const Key('passenger-sign-in')));
    await tester.pumpAndSettle();
    expect(find.text(loginPhoneFormatMessage), findsOneWidget);
    expect(find.text(loginPinFormatMessage), findsOneWidget);

    await tester.tap(find.byKey(const Key('passenger-clear-form')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('passenger-phone-field')))
          .controller
          ?.text,
      isEmpty,
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('passenger-pin-field')))
          .controller
          ?.text,
      isEmpty,
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

    expect(api.paths, <String>[AuthService.tokenPath]);
    expect(api.bodies.single, <String, Object?>{
      'phone': '+233000000000',
      'pin': '0000',
    });
    expect(api.bodies.single.keys, isNot(contains('password')));
    expect(api.bodies.single.keys, isNot(contains('email')));
    expect(await store.readAccessToken(), 'passenger-access-token');
    expect(await store.readRefreshToken(), 'passenger-refresh-token');
    expect(await store.readAccessToken(), isNot('0000'));
    expect(await store.readRefreshToken(), isNot('0000'));

    expect(find.text('Book a ride'), findsOneWidget);
    expect(
      find.text(
        'The Control Center will review your request and confirm pickup details.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('open-live-request')), findsOneWidget);
    expect(find.text('Local QA route preview'), findsNothing);
    expect(find.text('Map preview unavailable.'), findsNothing);
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

  testWidgets('Passenger login shows local QA entry only when enabled', (
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

    expect(find.text('Continue without signing in'), findsOneWidget);
    expect(
      find.byKey(const Key('passenger-continue-local-qa')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('passenger-continue-local-qa')));
    await tester.pumpAndSettle();

    expect(api.paths, isEmpty);
    expect(await store.readAccessToken(), isNull);
    expect(await store.readRefreshToken(), isNull);
    expect(find.text('Local QA route preview'), findsOneWidget);
    expect(find.text('Map preview unavailable.'), findsOneWidget);
    expect(find.text('Book a ride'), findsOneWidget);
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

  testWidgets('navigates the simplified passenger shell', (tester) async {
    _useSurface(tester, const Size(430, 900));
    await tester.pumpWidget(const PassengerApp());
    await _openPassengerAccess(tester);

    expect(find.byKey(const Key('passenger-home-brand-logo')), findsOneWidget);
    final passengerHomeLogo = tester.widget<Image>(
      find.byKey(const Key('passenger-home-brand-logo')),
    );
    expect(passengerHomeLogo.width, greaterThanOrEqualTo(160));
    expect(passengerHomeLogo.width, lessThanOrEqualTo(190));
    expect(passengerHomeLogo.fit, BoxFit.contain);
    expect(find.text('Book a ride'), findsOneWidget);
    expect(
      find.text(
        'The Control Center will review your request and confirm pickup details.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('open-live-request')), findsOneWidget);
    expect(find.text('Local QA route preview'), findsNothing);
    expect(find.text('Map preview unavailable.'), findsNothing);
    expect(find.byKey(const Key('choose-pickup')), findsNothing);
    expect(find.byKey(const Key('continue-local-draft')), findsNothing);
    expect(find.text('GHANA PILOT'), findsNothing);

    await tester.tap(find.byKey(const Key('open-live-request')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('booking-pickup')), findsOneWidget);
    expect(find.byKey(const Key('booking-destination')), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Trips'));
    await tester.pumpAndSettle();
    expect(find.text('No trips connected'), findsOneWidget);
    expect(find.text('LOCAL DEMO'), findsNothing);

    await tester.tap(find.text('Support'));
    await tester.pumpAndSettle();
    expect(find.text('Support not connected'), findsOneWidget);
    expect(find.text('Support is not available yet.'), findsOneWidget);

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.text('Map preview unavailable.'), findsNothing);
  });

  testWidgets(
    'local QA route preview remains reachable on a small scaled screen',
    (tester) async {
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

      expect(find.text('LOCAL DEMO'), findsNothing);
      expect(find.text('Local QA route preview'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('choose-pickup')));
      expect(find.byKey(const Key('choose-pickup')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('continue-local-draft')));
      expect(find.byKey(const Key('continue-local-draft')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

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

  testWidgets('Passenger live home hides local route preview by default', (
    tester,
  ) async {
    _useSurface(tester, const Size(430, 900));

    await tester.pumpWidget(
      MaterialApp(theme: AsmThemes.passenger, home: const PassengerShell()),
    );

    expect(find.text('Book a ride'), findsOneWidget);
    expect(
      find.text(
        'The Control Center will review your request and confirm pickup details.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('open-live-request')), findsOneWidget);
    expect(find.text('Local QA route preview'), findsNothing);
    expect(find.byKey(const Key('local-map-preview')), findsNothing);
    expect(find.byKey(const Key('choose-pickup')), findsNothing);
    expect(find.byKey(const Key('choose-destination')), findsNothing);
    expect(find.byKey(const Key('continue-local-draft')), findsNothing);
    expect(find.textContaining('ETA'), findsNothing);
    expect(find.textContaining('fare'), findsNothing);
    expect(find.textContaining('estimate'), findsNothing);
    expect(find.textContaining('driver assignment'), findsNothing);
  });

  testWidgets('Passenger local QA route preview is gated and local only', (
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
    expect(find.text('Local QA route preview'), findsOneWidget);
    expect(find.byKey(const Key('local-map-preview')), findsOneWidget);
    expect(find.byKey(const Key('choose-pickup')), findsOneWidget);
    expect(find.byKey(const Key('choose-destination')), findsOneWidget);
    expect(find.byKey(const Key('continue-local-draft')), findsOneWidget);
    expect(await store.readAccessToken(), isNull);
    expect(await store.readRefreshToken(), isNull);
    expect(find.textContaining('/api/routes'), findsNothing);
    expect(find.textContaining('/api/estimate'), findsNothing);
    expect(find.textContaining('/api/fares'), findsNothing);
    expect(find.textContaining('/api/driver'), findsNothing);
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

  testWidgets('Passenger startup with stored tokens opens home', (
    tester,
  ) async {
    _useSurface(tester, const Size(430, 900));
    final store = _AccessOnlyAuthTokenStore('stored-passenger-access');
    final api = _FakeAuthApiGateway(responseData: _loginResponse());

    await tester.pumpWidget(_loginTestApp(api: api, store: store));
    await tester.pumpAndSettle();

    expect(find.text('Book a ride'), findsOneWidget);
    expect(
      find.text(
        'The Control Center will review your request and confirm pickup details.',
      ),
      findsOneWidget,
    );
    expect(find.text('Map preview unavailable.'), findsNothing);
    expect(find.byKey(const Key('passenger-sign-out')), findsOneWidget);
    expect(find.byKey(const Key('passenger-sign-in')), findsNothing);
    expect(api.paths, isEmpty);
  });

  testWidgets('Passenger restored driver and staff sessions clear safely', (
    tester,
  ) async {
    for (final accountType in <String>['driver', 'staff']) {
      _useSurface(tester, const Size(430, 900));
      final store = MemoryAuthTokenStore();
      await store.saveTokens(
        AuthTokens(
          accessToken: 'stored-cross-app-access-$accountType',
          refreshToken: 'stored-cross-app-refresh-$accountType',
        ),
      );
      final api = _FakeAuthApiGateway(
        responseData: _loginResponse(accountType: accountType),
      );

      await tester.pumpWidget(_loginTestApp(api: api, store: store));
      await tester.pumpAndSettle();

      expect(api.paths, <String>[AuthService.refreshPath]);
      expect(api.bodies.single, <String, Object?>{
        'refresh': 'stored-cross-app-refresh-$accountType',
      });
      expect(find.byKey(const Key('passenger-sign-in')), findsOneWidget);
      expect(find.text('Book a ride'), findsNothing);
      expect(await store.readAccessToken(), isNull);
      expect(await store.readRefreshToken(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('Passenger sign out after restored startup clears next startup', (
    tester,
  ) async {
    _useSurface(tester, const Size(430, 900));
    final store = _AccessOnlyAuthTokenStore('stored-passenger-access');
    final api = _FakeAuthApiGateway(responseData: _loginResponse());

    await tester.pumpWidget(_loginTestApp(api: api, store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('passenger-sign-out')));
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

  testWidgets('Passenger local shell does not create stored tokens', (
    tester,
  ) async {
    _useSurface(tester, const Size(430, 900));
    final store = MemoryAuthTokenStore();

    await tester.pumpWidget(PassengerApp(authTokenStore: store));
    await tester.pumpAndSettle();

    expect(find.text('Book a ride'), findsOneWidget);
    expect(find.text('Map preview unavailable.'), findsNothing);
    expect(find.byKey(const Key('open-live-request')), findsOneWidget);
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
    expect(find.byKey(const Key('passenger-sign-out')), findsOneWidget);

    await tester.tap(find.byKey(const Key('passenger-sign-out')));
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

Map<String, Object?> _loginResponse({Object? accountType = 'passenger'}) {
  final response = <String, Object?>{
    'access': 'passenger-access-token',
    'refresh': 'passenger-refresh-token',
    'account': <String, Object?>{},
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
];

const _noLiveFeatureTexts = [
  'request_reference',
  'Paystack',
  'GPS',
  'GoogleMap',
  'WebSocket',
];

Future<void> _openPassengerAccess(WidgetTester tester) async {
  if (find.byKey(const Key('passenger-phone-field')).evaluate().isEmpty) {
    return;
  }

  await tester.enterText(
    find.byKey(const Key('passenger-phone-field')),
    '+233000000000',
  );
  await tester.enterText(find.byKey(const Key('passenger-pin-field')), '0000');
  await tester.tap(find.byKey(const Key('passenger-sign-in')));
  await tester.pumpAndSettle();
}

void _useSurface(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
