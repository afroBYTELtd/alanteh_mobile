import 'dart:async';
import 'dart:io';
import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_app_config/asm_app_config.dart';
import 'package:asm_auth/asm_auth.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:driver_app/concern/driver_concern_page.dart';
import 'package:driver_app/driver_duty_trips.dart';
import 'package:driver_app/main.dart';
import 'package:driver_app/readiness/driver_readiness_check.dart';
import 'package:driver_app/ride_offer/driver_ride_offer_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Driver auth endpoint contract paths remain stable', () {
    expect(AuthService.tokenPath, '/api/auth/token/');
    expect(AuthService.refreshPath, '/api/auth/token/refresh/');
  });

  test('M4D uses only accepted Driver read endpoints', () {
    final source = _readM3aDartSources('lib');

    expect(source, contains('Driver duty summary'));
    expect(source, contains(driverDutyPath));
    expect(source, contains(driverTripsPath));
    expect(source, isNot(contains('/api/mobile/passenger/ride-requests/')));
    expect(source, isNot(contains('/api/mobile/driver')));
    expect(source, isNot(contains('/api/dispatch')));
    expect(source, isNot(contains('/api/assignments')));
    expect(source, isNot(contains('/api/driver/.*/accept')));
    expect(source, isNot(contains('/api/driver/.*/reject')));
    expect(source, isNot(contains('/api/driver/.*/start')));
    expect(source, isNot(contains('/api/driver/.*/complete')));
    expect(source, isNot(contains('/api/routes')));
    expect(source, isNot(contains('/api/estimate')));
    expect(source, isNot(contains('/api/fares')));
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
    expect(source, isNot(contains(['fake', 'token'].join(' '))));
    expect(source, isNot(contains(['fake', 'Token'].join())));
  });

  test('Driver ALANTEH in-app logo asset is bundled', () async {
    final logo = await rootBundle.load('assets/brand/alanteh_header_white.png');
    expect(logo.lengthInBytes, greaterThan(0));
  });

  group('DriverReadinessCheck', () {
    test('starts empty and exposes an unmodifiable set', () {
      final check = DriverReadinessCheck.empty();

      expect(check.completedItems, isEmpty);
      expect(check.completedCount, 0);
      expect(check.isComplete, isFalse);
      expect(
        () =>
            check.completedItems.add(DriverReadinessItem.approvedShiftDetails),
        throwsUnsupportedError,
      );
    });

    test('toggle returns a new value and repeated toggle removes an item', () {
      final original = DriverReadinessCheck.empty();
      final selected = original.toggle(
        DriverReadinessItem.approvedShiftDetails,
      );
      final removed = selected.toggle(DriverReadinessItem.approvedShiftDetails);

      expect(original.completedItems, isEmpty);
      expect(selected.completedCount, 1);
      expect(removed.completedItems, isEmpty);
      expect(identical(original, selected), isFalse);
    });

    test('completion requires all four items and reset is immutable', () {
      final original = DriverReadinessCheck.empty();
      var complete = original;
      for (final item in DriverReadinessItem.values) {
        complete = complete.toggle(item);
      }
      final reset = complete.reset();

      expect(complete.completedCount, 4);
      expect(complete.isComplete, isTrue);
      expect(reset.completedItems, isEmpty);
      expect(reset.isComplete, isFalse);
      expect(complete.completedCount, 4);
      expect(original.completedItems, isEmpty);
    });
  });

  testWidgets('renders and validates the Driver access shell', (tester) async {
    _useSurface(tester, const Size(430, 1000));
    final store = MemoryAuthTokenStore();
    final authApi = _RecordingDriverAuthApiGateway();
    await tester.pumpWidget(
      DriverApp(
        showLoginShell: true,
        authService: AuthService(
          apiGateway: authApi,
          tokenStore: store,
          appContext: AuthAppContext.driver,
        ),
        authTokenStore: store,
      ),
    );

    expect(find.byKey(const Key('driver-login-brand-logo')), findsOneWidget);
    final driverLoginLogo = tester.widget<Image>(
      find.byKey(const Key('driver-login-brand-logo')),
    );
    expect(driverLoginLogo.width, greaterThanOrEqualTo(160));
    expect(driverLoginLogo.width, lessThanOrEqualTo(190));
    expect(driverLoginLogo.fit, BoxFit.contain);
    expect(find.text('Driver'), findsOneWidget);
    expect(find.byKey(const Key('driver-phone-field')), findsOneWidget);
    expect(find.text('Phone number'), findsOneWidget);
    expect(find.byKey(const Key('driver-pin-field')), findsOneWidget);
    expect(find.text('PIN'), findsOneWidget);
    expect(find.text('Driver sign in'), findsOneWidget);
    expect(
      find.text('Enter your phone number and PIN to start your shift.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('driver-sign-in')), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Continue without signing in'), findsNothing);
    expect(find.text('Clear form'), findsOneWidget);
    expect(find.text('Create account'), findsNothing);
    expect(find.text('Open public account'), findsNothing);
    expect(find.text('Email'), findsNothing);
    expect(find.text('email'), findsNothing);
    expect(find.text('Password'), findsNothing);
    expect(find.text('password'), findsNothing);

    await tester.tap(find.byKey(const Key('driver-sign-in')));
    await tester.pumpAndSettle();
    expect(find.text(loginPhoneRequiredMessage), findsOneWidget);
    expect(find.text(loginPinRequiredMessage), findsOneWidget);
    expect(authApi.paths, isEmpty);

    await tester.enterText(
      find.byKey(const Key('driver-phone-field')),
      '+233000000001',
    );
    await tester.enterText(find.byKey(const Key('driver-pin-field')), '0000');
    await tester.tap(find.byKey(const Key('driver-clear-form')));
    await tester.pumpAndSettle();
    expect(find.text('0550000000'), findsNothing);
    expect(find.text('0000'), findsNothing);
    expect(find.text(loginPhoneRequiredMessage), findsNothing);
    expect(find.text(loginPinRequiredMessage), findsNothing);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('driver-phone-field')))
          .controller
          ?.text,
      isEmpty,
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('driver-pin-field')))
          .controller
          ?.text,
      isEmpty,
    );
  });

  testWidgets('driver invalid login input is blocked before network', (
    tester,
  ) async {
    _useSurface(tester, const Size(430, 1000));
    final store = MemoryAuthTokenStore();
    final authApi = _RecordingDriverAuthApiGateway();

    await tester.pumpWidget(
      DriverApp(
        showLoginShell: true,
        authService: AuthService(
          apiGateway: authApi,
          tokenStore: store,
          appContext: AuthAppContext.driver,
        ),
        authTokenStore: store,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('driver-sign-in')));
    await tester.pumpAndSettle();

    expect(find.text(loginPhoneRequiredMessage), findsOneWidget);
    expect(find.text(loginPinRequiredMessage), findsOneWidget);
    expect(authApi.paths, isEmpty);
    expect(await store.readAccessToken(), isNull);
    expect(await store.readRefreshToken(), isNull);

    await tester.enterText(
      find.byKey(const Key('driver-phone-field')),
      '0550000000',
    );
    await tester.enterText(find.byKey(const Key('driver-pin-field')), '123');
    await tester.tap(find.byKey(const Key('driver-sign-in')));
    await tester.pumpAndSettle();

    expect(find.text(loginPhoneFormatMessage), findsOneWidget);
    expect(find.text(loginPinFormatMessage), findsOneWidget);
    expect(authApi.paths, isEmpty);

    await tester.enterText(
      find.byKey(const Key('driver-phone-field')),
      '+23300 0000001',
    );
    await tester.enterText(find.byKey(const Key('driver-pin-field')), '43a1');
    await tester.tap(find.byKey(const Key('driver-sign-in')));
    await tester.pumpAndSettle();

    expect(find.text(loginPhoneFormatMessage), findsOneWidget);
    expect(find.text(loginPinFormatMessage), findsOneWidget);
    expect(authApi.paths, isEmpty);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('driver-phone-field')))
          .controller
          ?.text,
      '+23300 0000001',
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('driver-pin-field')))
          .controller
          ?.text,
      '43a1',
    );
    expect(await store.readAccessToken(), isNull);
    expect(await store.readRefreshToken(), isNull);
  });

  testWidgets('driver login shows local QA entry only when enabled', (
    tester,
  ) async {
    _useSurface(tester, const Size(430, 1000));
    final store = MemoryAuthTokenStore();
    final authApi = _RecordingDriverAuthApiGateway();

    await tester.pumpWidget(
      DriverApp(
        configuration: _localQaEnabledConfig,
        showLoginShell: true,
        authService: AuthService(
          apiGateway: authApi,
          tokenStore: store,
          appContext: AuthAppContext.driver,
        ),
        authTokenStore: store,
      ),
    );

    expect(find.text('Continue without signing in'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('driver-phone-field')),
      '+233000000001',
    );
    await tester.enterText(find.byKey(const Key('driver-pin-field')), '9876');
    await tester.tap(find.byKey(const Key('driver-continue-local-demo')));
    await tester.pumpAndSettle();

    expect(authApi.paths, isEmpty);
    expect(await store.readAccessToken(), isNull);
    expect(await store.readRefreshToken(), isNull);
    expect(find.text('Driver app ready'), findsOneWidget);
    expect(find.text('Local QA: Off shift'), findsNothing);
    expect(find.text('Preview incoming offer'), findsOneWidget);
    expect(find.byKey(const Key('open-ride-offer-preview')), findsOneWidget);
  });

  testWidgets(
    'driver live signed-in home hides local trip preview by default',
    (tester) async {
      _useSurface(tester, const Size(430, 1000));
      final store = MemoryAuthTokenStore();
      final authApi = _RecordingDriverAuthApiGateway();

      await tester.pumpWidget(
        DriverApp(
          showLoginShell: true,
          authService: AuthService(
            apiGateway: authApi,
            tokenStore: store,
            appContext: AuthAppContext.driver,
          ),
          authTokenStore: store,
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('driver-phone-field')),
        '+233000000001',
      );
      await tester.enterText(find.byKey(const Key('driver-pin-field')), '9876');
      await tester.tap(find.byKey(const Key('driver-sign-in')));
      await tester.pumpAndSettle();

      expect(authApi.paths, <String>[AuthService.tokenPath]);
      expect(find.text('Driver app ready'), findsOneWidget);
      expect(find.text('Local QA: Off shift'), findsNothing);
      expect(find.text('Local QA: On shift'), findsNothing);
      expect(find.byKey(const Key('open-readiness')), findsNothing);
      expect(find.text('Local QA readiness preview'), findsNothing);
      expect(find.text("I'm ready"), findsNothing);
      expect(find.text('Driver app ready'), findsOneWidget);
      expect(find.text('Driver app ready'), findsWidgets);
      expect(find.text('New ride offer'), findsNothing);
      expect(find.text('Preview incoming offer'), findsNothing);
      expect(find.text('Accept'), findsNothing);
      expect(find.byKey(const Key('open-ride-offer-preview')), findsNothing);
      expect(await store.readAccessToken(), 'driver-access-token');
    },
  );

  testWidgets(
    'driver phone PIN sign in calls token endpoint and stores tokens',
    (tester) async {
      if (AsmApiClient.defaultBaseUrl.trim().isNotEmpty) {
        return;
      }

      _useSurface(tester, const Size(430, 1000));
      final store = MemoryAuthTokenStore();
      final authApi = _RecordingDriverAuthApiGateway();
      await tester.pumpWidget(
        DriverApp(
          showLoginShell: true,
          authService: AuthService(
            apiGateway: authApi,
            tokenStore: store,
            appContext: AuthAppContext.driver,
          ),
          authTokenStore: store,
        ),
      );

      await tester.enterText(
        find.byKey(const Key('driver-phone-field')),
        '+233000000001',
      );
      await tester.enterText(find.byKey(const Key('driver-pin-field')), '9876');
      await tester.tap(find.byKey(const Key('driver-sign-in')));
      await tester.pumpAndSettle();

      expect(authApi.paths, <String>[AuthService.tokenPath]);
      expect(authApi.bodies.single, <String, Object?>{
        'phone': '+233000000001',
        'pin': '9876',
      });
      expect(authApi.bodies.single.keys, isNot(contains('email')));
      expect(authApi.bodies.single.keys, isNot(contains('password')));
      expect(authApi.bodies.single['pin'], isA<String>());
      expect(await store.readAccessToken(), 'driver-access-token');
      expect(await store.readRefreshToken(), 'driver-refresh-token');
      expect(find.text('Driver app ready'), findsOneWidget);
      expect(find.text('Driver app ready'), findsOneWidget);
      expect(find.text('Local QA: Off shift'), findsNothing);
      expect(find.text('Local QA: On shift'), findsNothing);
      expect(find.byKey(const Key('open-readiness')), findsNothing);
      expect(find.text('Local QA readiness preview'), findsNothing);
      expect(find.text('Driver app ready'), findsOneWidget);
      expect(find.text('Driver app ready'), findsWidgets);
      expect(find.text('New ride offer'), findsNothing);
      expect(find.text('Accept'), findsNothing);
      expect(find.byKey(const Key('open-ride-offer-preview')), findsNothing);
      expect(find.text('9876'), findsNothing);
    },
  );

  testWidgets('driver app rejects non-driver account types', (tester) async {
    _useSurface(tester, const Size(430, 1000));

    for (final accountType in <Object?>[
      'passenger',
      'staff',
      'unknown',
      null,
    ]) {
      final store = MemoryAuthTokenStore();
      final authApi = _RecordingDriverAuthApiGateway(
        responseData: _driverLoginResponse(accountType: accountType),
      );
      await tester.pumpWidget(
        DriverApp(
          showLoginShell: true,
          authService: AuthService(
            apiGateway: authApi,
            tokenStore: store,
            appContext: AuthAppContext.driver,
          ),
          authTokenStore: store,
        ),
      );

      await tester.enterText(
        find.byKey(const Key('driver-phone-field')),
        '+233000000001',
      );
      await tester.enterText(find.byKey(const Key('driver-pin-field')), '9876');
      await tester.tap(find.byKey(const Key('driver-sign-in')));
      await tester.pumpAndSettle();

      expect(
        find.text(authAppContextErrorMessage),
        findsOneWidget,
        reason: 'account_type=$accountType',
      );
      expect(find.text('Driver app ready'), findsNothing);
      expect(await store.readAccessToken(), isNull);
      expect(await store.readRefreshToken(), isNull);
      expect(find.text('9876'), findsNothing);
    }
  });

  testWidgets('failed driver login shows clear error and stores no tokens', (
    tester,
  ) async {
    _useSurface(tester, const Size(430, 1000));
    final store = MemoryAuthTokenStore();
    final authApi = _RecordingDriverAuthApiGateway(statusCode: 401);
    await tester.pumpWidget(
      DriverApp(
        showLoginShell: true,
        authService: AuthService(
          apiGateway: authApi,
          tokenStore: store,
          appContext: AuthAppContext.driver,
        ),
        authTokenStore: store,
      ),
    );

    await tester.enterText(
      find.byKey(const Key('driver-phone-field')),
      '+233000000001',
    );
    await tester.enterText(find.byKey(const Key('driver-pin-field')), '9876');
    await tester.tap(find.byKey(const Key('driver-sign-in')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('driver-login-error')), findsOneWidget);
    expect(
      find.text('Sign in failed. Check your phone and PIN.'),
      findsOneWidget,
    );
    expect(find.text('Driver app ready'), findsNothing);
    expect(await store.readAccessToken(), isNull);
    expect(await store.readRefreshToken(), isNull);
    expect(find.text('9876'), findsNothing);
  });

  testWidgets(
    'Driver sign-in shows loading state and prevents duplicate submit while loading',
    (tester) async {
      _useSurface(tester, const Size(430, 1000));
      final store = MemoryAuthTokenStore();
      final pending = Completer<ApiResponse<Map<String, Object?>>>();
      final api = _RecordingDriverAuthApiGateway(pendingResponse: pending);

      await tester.pumpWidget(
        DriverApp(
          showLoginShell: true,
          authTokenStore: store,
          authService: AuthService(
            apiGateway: api,
            tokenStore: store,
            appContext: AuthAppContext.driver,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('driver-phone-field')),
        '+233000000001',
      );
      await tester.enterText(find.byKey(const Key('driver-pin-field')), '9876');
      await tester.tap(find.byKey(const Key('driver-sign-in')));
      await tester.pump();

      expect(find.text('Signing in...'), findsOneWidget);
      expect(api.paths, <String>[AuthService.tokenPath]);

      await tester.tap(find.byKey(const Key('driver-sign-in')));
      await tester.pump();

      expect(api.paths, <String>[AuthService.tokenPath]);

      pending.complete(
        ApiResponse.success(_driverLoginResponse(), statusCode: 200),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('driver-login-error')), findsNothing);
      expect(await store.readAccessToken(), isNotNull);
    },
  );

  testWidgets('Driver sign-in invalid credentials shows safe message', (
    tester,
  ) async {
    _useSurface(tester, const Size(430, 1000));
    final store = MemoryAuthTokenStore();
    final api = _RecordingDriverAuthApiGateway(statusCode: 401);

    await tester.pumpWidget(
      DriverApp(
        showLoginShell: true,
        authTokenStore: store,
        authService: AuthService(
          apiGateway: api,
          tokenStore: store,
          appContext: AuthAppContext.driver,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('driver-phone-field')),
      '+233000000001',
    );
    await tester.enterText(find.byKey(const Key('driver-pin-field')), '9876');
    await tester.tap(find.byKey(const Key('driver-sign-in')));
    await tester.pumpAndSettle();

    expect(
      find.text('Sign in failed. Check your phone and PIN.'),
      findsOneWidget,
    );
    expect(find.textContaining('Authentication failed'), findsNothing);
    expect(await store.readAccessToken(), isNull);
  });

  testWidgets('Driver sign-in network failure shows safe message', (
    tester,
  ) async {
    _useSurface(tester, const Size(430, 1000));
    final store = MemoryAuthTokenStore();
    final api = _RecordingDriverAuthApiGateway(
      exceptionType: AsmApiExceptionType.network,
    );

    await tester.pumpWidget(
      DriverApp(
        showLoginShell: true,
        authTokenStore: store,
        authService: AuthService(
          apiGateway: api,
          tokenStore: store,
          appContext: AuthAppContext.driver,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('driver-phone-field')),
      '+233000000001',
    );
    await tester.enterText(find.byKey(const Key('driver-pin-field')), '9876');
    await tester.tap(find.byKey(const Key('driver-sign-in')));
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
    'Driver sign-in timeout shows safe message and stores no tokens',
    (tester) async {
      _useSurface(tester, const Size(430, 1000));
      final store = MemoryAuthTokenStore();
      final api = _RecordingDriverAuthApiGateway(
        exceptionType: AsmApiExceptionType.timeout,
      );

      await tester.pumpWidget(
        DriverApp(
          showLoginShell: true,
          authTokenStore: store,
          authService: AuthService(
            apiGateway: api,
            tokenStore: store,
            appContext: AuthAppContext.driver,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('driver-phone-field')),
        '+233000000001',
      );
      await tester.enterText(find.byKey(const Key('driver-pin-field')), '9876');
      await tester.tap(find.byKey(const Key('driver-sign-in')));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Cannot reach the server. Check your connection and try again.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('TimeoutException'), findsNothing);
      expect(find.textContaining('Raw technical'), findsNothing);
      expect(find.byKey(const Key('driver-phone-field')), findsOneWidget);
      expect(await store.readAccessToken(), isNull);
      expect(await store.readRefreshToken(), isNull);
    },
  );

  testWidgets('Driver sign-in 503 shows service unavailable message', (
    tester,
  ) async {
    _useSurface(tester, const Size(430, 1000));
    final store = MemoryAuthTokenStore();
    final api = _RecordingDriverAuthApiGateway(statusCode: 503);

    await tester.pumpWidget(
      DriverApp(
        showLoginShell: true,
        authTokenStore: store,
        authService: AuthService(
          apiGateway: api,
          tokenStore: store,
          appContext: AuthAppContext.driver,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('driver-phone-field')),
      '+233000000001',
    );
    await tester.enterText(find.byKey(const Key('driver-pin-field')), '9876');
    await tester.tap(find.byKey(const Key('driver-sign-in')));
    await tester.pumpAndSettle();

    expect(
      find.text('Service is temporarily unavailable. Please try again later.'),
      findsOneWidget,
    );
    expect(await store.readAccessToken(), isNull);
  });

  testWidgets('Driver sign-in non-driver account shows app mismatch', (
    tester,
  ) async {
    _useSurface(tester, const Size(430, 1000));
    final store = MemoryAuthTokenStore();
    final api = _RecordingDriverAuthApiGateway(
      responseData: const <String, Object?>{
        'access': 'passenger-access',
        'refresh': 'passenger-refresh',
        'account_type': 'passenger',
      },
    );

    await tester.pumpWidget(
      DriverApp(
        showLoginShell: true,
        authTokenStore: store,
        authService: AuthService(
          apiGateway: api,
          tokenStore: store,
          appContext: AuthAppContext.driver,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('driver-phone-field')),
      '+233000000001',
    );
    await tester.enterText(find.byKey(const Key('driver-pin-field')), '9876');
    await tester.tap(find.byKey(const Key('driver-sign-in')));
    await tester.pumpAndSettle();

    expect(find.text(authAppContextErrorMessage), findsOneWidget);
    expect(await store.readAccessToken(), isNull);
  });

  testWidgets(
    'driver real sign-in without API base URL shows connection configuration error',
    (tester) async {
      if (AsmApiClient.defaultBaseUrl.trim().isNotEmpty) {
        return;
      }

      _useSurface(tester, const Size(430, 1000));
      final store = MemoryAuthTokenStore();

      await tester.pumpWidget(
        DriverApp(showLoginShell: true, authTokenStore: store),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('driver-phone-field')),
        '+233000000001',
      );
      await tester.enterText(find.byKey(const Key('driver-pin-field')), '9876');
      await tester.tap(find.byKey(const Key('driver-sign-in')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('driver-login-error')), findsOneWidget);
      expect(
        find.text(AsmApiClient.connectionNotConfiguredMessage),
        findsOneWidget,
      );
      expect(await store.readAccessToken(), isNull);
      expect(await store.readRefreshToken(), isNull);
      expect(find.text('Driver app ready'), findsNothing);
    },
  );

  testWidgets(
    'continue without signing in remains separate local QA readiness path',
    (tester) async {
      _useSurface(tester, const Size(430, 1000));
      final store = MemoryAuthTokenStore();
      final authApi = _RecordingDriverAuthApiGateway();
      await tester.pumpWidget(
        DriverApp(
          configuration: _localQaEnabledConfig,
          showLoginShell: true,
          authService: AuthService(
            apiGateway: authApi,
            tokenStore: store,
            appContext: AuthAppContext.driver,
          ),
          authTokenStore: store,
        ),
      );

      await tester.enterText(
        find.byKey(const Key('driver-phone-field')),
        '+233000000001',
      );
      await tester.enterText(find.byKey(const Key('driver-pin-field')), '9876');
      await tester.tap(find.byKey(const Key('driver-continue-local-demo')));
      await tester.pumpAndSettle();

      expect(authApi.paths, isEmpty);
      expect(await store.readAccessToken(), isNull);
      expect(await store.readRefreshToken(), isNull);
      expect(find.text('Driver app ready'), findsOneWidget);
      expect(find.text('Local QA: Off shift'), findsNothing);
    },
  );

  testWidgets('navigates the configured approved-driver local QA field shell', (
    tester,
  ) async {
    await tester.pumpWidget(
      const DriverApp(configuration: _localQaEnabledConfig),
    );
    await _openDriverLocalDemo(tester);

    expect(find.byKey(const Key('driver-home-brand-logo')), findsOneWidget);
    final driverHomeLogo = tester.widget<Image>(
      find.byKey(const Key('driver-home-brand-logo')),
    );
    expect(driverHomeLogo.width, greaterThanOrEqualTo(160));
    expect(driverHomeLogo.width, lessThanOrEqualTo(190));
    expect(driverHomeLogo.fit, BoxFit.contain);
    expect(find.text('Field workspace'), findsNothing);
    expect(find.text('Driver app ready'), findsOneWidget);
    expect(find.text('Local QA: Off shift'), findsNothing);
    expect(find.text('Driver app ready'), findsOneWidget);
    expect(find.text('Driver app ready'), findsOneWidget);
    expect(find.text('Driver app ready'), findsWidgets);
    expect(find.text('Local QA readiness preview'), findsOneWidget);
    expect(find.text('Report an issue'), findsOneWidget);
    expect(find.text('Preview incoming offer'), findsOneWidget);
    expect(find.byKey(const Key('open-ride-offer-preview')), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      0,
    );

    await tester.tap(find.text('Trips'));
    await tester.pumpAndSettle();
    expect(find.text('No assigned trips yet.'), findsOneWidget);
    expect(
      find.text('When the Control Center assigns a trip, it will appear here.'),
      findsOneWidget,
    );
    expect(find.textContaining('fake assigned trip'), findsNothing);
    expect(find.textContaining('assigned trip card'), findsNothing);
    expect(find.textContaining('fake active trip'), findsNothing);
    expect(find.textContaining('active trip'), findsNothing);
    expect(find.textContaining('fake completed trip'), findsNothing);
    expect(find.textContaining('completed trip'), findsNothing);
    expect(find.textContaining('fake passenger details'), findsNothing);
    expect(find.textContaining('passenger details'), findsNothing);
    expect(find.textContaining('fake ETA'), findsNothing);
    expect(find.textContaining('ETA'), findsNothing);
    expect(find.textContaining('fake fare'), findsNothing);
    expect(find.textContaining('fare'), findsNothing);
    expect(find.textContaining('fake earnings'), findsNothing);
    expect(find.textContaining('earnings'), findsNothing);
    expect(find.text('Accept trip'), findsNothing);
    expect(find.text('Start trip'), findsNothing);
    expect(find.text('Complete trip'), findsNothing);

    await tester.tap(find.text('Account'));
    await tester.pumpAndSettle();
    expect(find.text('Driver account'), findsOneWidget);
    expect(find.text('Signed in to ALANTEH Driver.'), findsOneWidget);
    expect(find.text('Sign out'), findsNothing);
    expect(find.textContaining('fake driver name'), findsNothing);
    expect(find.textContaining('driver phone'), findsNothing);
    expect(find.textContaining('fake phone number'), findsNothing);
    expect(find.textContaining('vehicle assignment'), findsNothing);
    expect(find.textContaining('fake earnings'), findsNothing);
    expect(find.textContaining('earnings'), findsNothing);
    expect(find.textContaining('wallet'), findsNothing);
    expect(find.textContaining('payout'), findsNothing);
    expect(find.textContaining('rating'), findsNothing);
    expect(find.textContaining('license'), findsNothing);
    expect(find.textContaining('document'), findsNothing);
    expect(find.textContaining('support ticket'), findsNothing);
    expect(find.textContaining('verification'), findsNothing);

    await tester.tap(find.text('Work'));
    await tester.pumpAndSettle();
    expect(find.text('Driver app ready'), findsOneWidget);
    expect(find.text('Driver app ready'), findsOneWidget);
    expect(find.text('Driver app ready'), findsWidgets);
  });

  testWidgets(
    'Driver shell exposes local QA readiness and existing field areas',
    (tester) async {
      _useSurface(tester, const Size(430, 1000));
      await tester.pumpWidget(
        const DriverApp(configuration: _localQaEnabledConfig),
      );
      await _openDriverLocalDemo(tester);

      expect(find.byKey(const Key('open-readiness')), findsOneWidget);
      expect(find.byKey(const Key('open-concern')), findsOneWidget);
      expect(find.text('Preview incoming offer'), findsOneWidget);
      expect(find.byKey(const Key('open-ride-offer-preview')), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('open-readiness')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-readiness')));
      await tester.pumpAndSettle();
      expect(find.text('Shift check'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('open-concern')));
      await tester.pumpAndSettle();
      expect(find.text('Report an issue'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await _openRideOfferPreview(tester);
      await tester.pumpAndSettle();
      expect(find.text('New ride offer'), findsWidgets);
      _expectNoOperationalActions();
    },
  );

  testWidgets('completes, resets, closes, and reopens the shift check', (
    tester,
  ) async {
    _useSurface(tester, const Size(430, 1000));
    await tester.pumpWidget(
      const DriverApp(configuration: _localQaEnabledConfig),
    );
    await _openDriverLocalDemo(tester);

    await tester.ensureVisible(find.byKey(const Key('open-readiness')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-readiness')));
    await tester.pumpAndSettle();

    expect(find.text('Shift check'), findsOneWidget);
    expect(find.text('Ghana'), findsOneWidget);
    expect(find.text('Complete these checks before driving.'), findsOneWidget);
    for (final item in DriverReadinessItem.values) {
      expect(find.text(item.label), findsOneWidget);
    }
    expect(find.text('0 of 4 checks complete'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('readiness-ready')))
          .onPressed,
      isNull,
    );

    await tester.tap(find.byKey(const Key('readiness-approvedShiftDetails')));
    await tester.tap(find.byKey(const Key('readiness-vehicleExterior')));
    await tester.pumpAndSettle();
    expect(find.text('2 of 4 checks complete'), findsOneWidget);

    await tester.tap(find.byKey(const Key('readiness-cabinSafety')));
    await tester.tap(find.byKey(const Key('readiness-batteryStatus')));
    await tester.pumpAndSettle();
    expect(find.text('4 of 4 checks complete'), findsOneWidget);
    expect(find.text('You’re ready to go online'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('readiness-ready')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('readiness-ready')))
          .onPressed,
      isNotNull,
    );
    expect(
      find.text('Review your vehicle and route before starting work.'),
      findsOneWidget,
    );
    _expectNoOperationalActions();

    await tester.ensureVisible(find.byKey(const Key('reset-readiness')));
    await tester.tap(find.byKey(const Key('reset-readiness')));
    await tester.pumpAndSettle();
    expect(find.text('0 of 4 checks complete'), findsOneWidget);
    expect(find.text('You’re ready to go online'), findsNothing);

    await tester.tap(find.byKey(const Key('readiness-approvedShiftDetails')));
    await tester.pumpAndSettle();
    expect(find.text('1 of 4 checks complete'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Driver app ready'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('open-readiness')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-readiness')));
    await tester.pumpAndSettle();
    expect(find.text('0 of 4 checks complete'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('readiness-open-concern')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('readiness-open-concern')), findsOneWidget);
    expect(find.text('Report an issue'), findsOneWidget);
  });

  testWidgets(
    'local QA ready button returns home and marks the preview on shift',
    (tester) async {
      _useSurface(tester, const Size(430, 1000));
      await tester.pumpWidget(
        const DriverApp(configuration: _localQaEnabledConfig),
      );
      await _openDriverLocalDemo(tester);

      expect(find.text('Local QA: Off shift'), findsNothing);
      expect(find.text('Local QA: On shift'), findsNothing);

      await tester.ensureVisible(find.byKey(const Key('open-readiness')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-readiness')));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('readiness-ready')))
            .onPressed,
        isNull,
      );

      for (final item in DriverReadinessItem.values) {
        await tester.tap(find.byKey(ValueKey('readiness-${item.name}')));
      }
      await tester.pumpAndSettle();

      expect(find.text('4 of 4 checks complete'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('readiness-ready')),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('readiness-ready')))
            .onPressed,
        isNotNull,
      );

      await tester.scrollUntilVisible(
        find.byKey(const Key('readiness-ready')),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('readiness-ready')));
      await tester.pumpAndSettle();

      expect(find.text('Driver app ready'), findsOneWidget);
      expect(find.text('Local QA: On shift'), findsNothing);
      expect(find.text('Local QA: Off shift'), findsNothing);
    },
  );

  testWidgets('validates, reviews, edits, closes, and resets a concern draft', (
    tester,
  ) async {
    _useSurface(tester, const Size(430, 1000));
    await tester.pumpWidget(const DriverApp());
    await _openDriverLocalDemo(tester);

    await tester.tap(find.byKey(const Key('open-concern')));
    await tester.pumpAndSettle();
    expect(find.text('Report an issue'), findsOneWidget);
    expect(find.text('Ghana'), findsOneWidget);
    expect(
      find.text(
        'This report is not sent from the app yet. For emergencies, follow approved local safety procedures.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'If there is immediate danger, do not drive and follow approved local safety procedures.',
      ),
      findsOneWidget,
    );

    await _scrollToConcernReview(tester);
    await tester.tap(find.byKey(const Key('review-concern')));
    await tester.pumpAndSettle();
    expect(find.text('Choose what the issue is.'), findsOneWidget);
    expect(find.text('Choose how urgent this is.'), findsOneWidget);
    expect(find.text('Describe the issue.'), findsOneWidget);

    await _completeConcernForm(tester, description: '  Loose mirror  ');
    expect(find.text('No issue report has been sent.'), findsOneWidget);
    expect(find.text('Service area'), findsOneWidget);
    expect(find.byKey(const Key('concern-market')), findsOneWidget);
    expect(find.text('Vehicle'), findsOneWidget);
    expect(find.text('Urgent'), findsOneWidget);
    expect(find.text('Loose mirror'), findsOneWidget);
    _expectNoOperationalActions();

    await tester.tap(find.byKey(const Key('edit-concern')));
    await tester.pumpAndSettle();
    final descriptionField = tester.widget<TextFormField>(
      find.byKey(const Key('concern-description')),
    );
    expect(descriptionField.controller!.text, '  Loose mirror  ');

    await _scrollToConcernReview(tester);
    await tester.tap(find.byKey(const Key('review-concern')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('close-concern')));
    await tester.pumpAndSettle();
    expect(find.text('Driver app ready'), findsOneWidget);

    await tester.tap(find.byKey(const Key('open-concern')));
    await tester.pumpAndSettle();
    final reopenedField = tester.widget<TextFormField>(
      find.byKey(const Key('concern-description')),
    );
    expect(reopenedField.controller!.text, isEmpty);
    expect(find.text('No issue report has been sent.'), findsNothing);
    await tester.enterText(
      find.byKey(const Key('concern-description')),
      'x' * 241,
    );
    expect(reopenedField.controller!.text.length, 240);
  });

  testWidgets('concern flow preserves readiness without completing it', (
    tester,
  ) async {
    _useSurface(tester, const Size(430, 1000));
    await tester.pumpWidget(
      const DriverApp(configuration: _localQaEnabledConfig),
    );
    await _openDriverLocalDemo(tester);

    await tester.ensureVisible(find.byKey(const Key('open-readiness')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-readiness')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('readiness-approvedShiftDetails')));
    await tester.pumpAndSettle();
    expect(find.text('1 of 4 checks complete'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('readiness-open-concern')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const Key('readiness-open-concern')));
    await tester.pumpAndSettle();
    await _completeConcernForm(tester, description: 'Battery warning noted');
    await tester.tap(find.byKey(const Key('close-concern')));
    await tester.pumpAndSettle();

    expect(find.text('Shift check'), findsOneWidget);
    expect(find.text('1 of 4 checks complete'), findsOneWidget);
    expect(find.text('You’re ready to go online'), findsNothing);
    expect(find.text('Report an issue'), findsOneWidget);
  });

  testWidgets(
    'accepts a ride-offer detail decision, closes, and reopens pending',
    (tester) async {
      _useSurface(tester, const Size(430, 1000));
      await tester.pumpWidget(
        const DriverApp(configuration: _localQaEnabledConfig),
      );
      await _openDriverLocalDemo(tester);

      expect(find.byKey(const Key('open-ride-offer-preview')), findsOneWidget);
      await _openRideOfferPreview(tester);
      await tester.pumpAndSettle();

      _expectPendingRideOffer();
      await tester.tap(find.byKey(const Key('view-ride-offer-details')));
      await tester.pumpAndSettle();
      _expectRideOfferDetails();

      await tester.tap(find.byKey(const Key('accept-ride-offer-preview')));
      await tester.pumpAndSettle();

      expect(find.text('Ride accepted'), findsOneWidget);
      expect(
        find.text('Head to Accra Mall to pick up your passenger.'),
        findsOneWidget,
      );
      expect(find.text('Accept'), findsNothing);
      expect(find.text('Decline'), findsNothing);
      _expectNoRideOfferLiveContent();

      await tester.tap(find.byKey(const Key('close-ride-offer-preview')));
      await tester.pumpAndSettle();
      expect(find.text('Driver app ready'), findsOneWidget);

      await _openRideOfferPreview(tester);
      await tester.pumpAndSettle();
      _expectPendingRideOffer();
      expect(find.text('Ride accepted'), findsNothing);
      final previewContext = tester.element(
        find.byKey(const Key('driver-ride-offer-page')),
      );
      Navigator.of(previewContext).pop();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Trips'));
      await tester.pumpAndSettle();
      expect(find.text('No assigned trips yet.'), findsOneWidget);
      expect(
        find.text(
          'When the Control Center assigns a trip, it will appear here.',
        ),
        findsOneWidget,
      );
      expect(find.text('Accept trip'), findsNothing);
      expect(find.text('Start trip'), findsNothing);
      expect(find.text('Complete trip'), findsNothing);
    },
  );

  testWidgets(
    'declines a ride-offer detail decision and returns to Driver Home',
    (tester) async {
      _useSurface(tester, const Size(430, 1000));
      await tester.pumpWidget(
        const DriverApp(configuration: _localQaEnabledConfig),
      );
      await _openDriverLocalDemo(tester);

      await _openRideOfferPreview(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('view-ride-offer-details')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('decline-ride-offer-preview')));
      await tester.pumpAndSettle();

      expect(find.text('Offer declined'), findsOneWidget);
      expect(
        find.text("You'll continue receiving new ride offers while online."),
        findsOneWidget,
      );
      expect(find.text('Back to home'), findsOneWidget);
      _expectNoRideOfferLiveContent();

      await tester.tap(find.byKey(const Key('close-ride-offer-preview')));
      await tester.pumpAndSettle();

      expect(find.text('Driver app ready'), findsOneWidget);
      expect(find.byKey(const Key('open-readiness')), findsOneWidget);
      expect(find.byKey(const Key('open-concern')), findsOneWidget);
    },
  );

  testWidgets('driver screens hide old brand and internal marker wording', (
    tester,
  ) async {
    _useSurface(tester, const Size(430, 1000));
    await tester.pumpWidget(
      const DriverApp(
        configuration: _localQaEnabledConfig,
        showLoginShell: true,
      ),
    );

    for (final removedText in _removedDriverTexts) {
      expect(find.text(removedText), findsNothing);
    }

    await _openDriverLocalDemo(tester);
    for (final removedText in _removedDriverTexts) {
      expect(find.text(removedText), findsNothing);
    }
  });

  testWidgets('ride screen remains reachable on a small scaled screen', (
    tester,
  ) async {
    _useSurface(tester, const Size(320, 568));
    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.driver,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: const DriverRideOfferPage(market: MarketConfig.ghanaAccra),
      ),
    );

    expect(find.text('New ride offer'), findsOneWidget);

    final previewScrollable = find.descendant(
      of: find.byKey(const Key('driver-ride-offer-page')),
      matching: find.byType(Scrollable),
    );

    expect(previewScrollable, findsOneWidget);

    await tester.dragUntilVisible(
      find.byKey(const Key('view-ride-offer-details')),
      previewScrollable,
      const Offset(0, -220),
    );
    await tester.pump();

    expect(find.byKey(const Key('view-ride-offer-details')), findsOneWidget);

    await tester.tap(find.byKey(const Key('view-ride-offer-details')));
    await tester.pump();

    expect(find.byKey(const Key('ride-offer-detail-state')), findsOneWidget);

    final detailScrollable = find.descendant(
      of: find.byKey(const Key('driver-ride-offer-page')),
      matching: find.byType(Scrollable),
    );

    expect(detailScrollable, findsOneWidget);

    await tester.dragUntilVisible(
      find.byKey(const Key('decline-ride-offer-preview')),
      detailScrollable,
      const Offset(0, -220),
    );
    await tester.pump();

    expect(find.byKey(const Key('decline-ride-offer-preview')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('issue form remains reachable on a small scaled screen', (
    tester,
  ) async {
    _useSurface(tester, const Size(320, 568));
    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.driver,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: const DriverConcernPage(market: MarketConfig.ghanaAccra),
      ),
    );

    expect(find.text('Report an issue'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('review-concern')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('review-concern')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('readiness remains reachable on a small scaled screen', (
    tester,
  ) async {
    _useSurface(tester, const Size(320, 568));
    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.driver,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: const DriverShell(localQaEnabled: true),
      ),
    );

    await tester.ensureVisible(find.byKey(const Key('open-readiness')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('open-readiness')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('open-readiness')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-readiness')));
    await tester.pumpAndSettle();
    expect(find.text('Shift check'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('readiness-batteryStatus')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.byKey(const Key('readiness-batteryStatus')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('reset-readiness')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.byKey(const Key('reset-readiness')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('driver startup without stored tokens opens login', (
    tester,
  ) async {
    _useSurface(tester, const Size(430, 1000));
    final store = MemoryAuthTokenStore();
    final authApi = _RecordingDriverAuthApiGateway();

    await tester.pumpWidget(
      DriverApp(
        showLoginShell: true,
        authService: AuthService(
          apiGateway: authApi,
          tokenStore: store,
          appContext: AuthAppContext.driver,
        ),
        authTokenStore: store,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('driver-sign-in')), findsOneWidget);
    expect(find.byKey(const Key('driver-sign-out')), findsNothing);
    expect(find.text('Driver sign in'), findsOneWidget);
    expect(authApi.paths, isEmpty);
  });

  testWidgets(
    'driver access-only restored session clears tokens and asks sign in again',
    (tester) async {
      _useSurface(tester, const Size(430, 1000));
      final store = _AccessOnlyAuthTokenStore('stored-driver-access');
      final authApi = _RecordingDriverAuthApiGateway();

      await tester.pumpWidget(
        DriverApp(
          showLoginShell: true,
          authService: AuthService(
            apiGateway: authApi,
            tokenStore: store,
            appContext: AuthAppContext.driver,
          ),
          authTokenStore: store,
        ),
      );
      await tester.pumpAndSettle();

      expect(authApi.paths, isEmpty);
      expect(find.byKey(const Key('driver-sign-in')), findsOneWidget);
      expect(find.text('Driver sign in'), findsOneWidget);
      expect(find.text('Please sign in again to continue.'), findsOneWidget);
      expect(find.text('No trip assigned yet.'), findsNothing);
      expect(await store.readAccessToken(), isNull);
      expect(await store.readRefreshToken(), isNull);
    },
  );

  testWidgets(
    'driver rejected restored session clears tokens and asks sign in again',
    (tester) async {
      _useSurface(tester, const Size(430, 1000));
      final store = MemoryAuthTokenStore();
      await store.saveTokens(
        AuthTokens(
          accessToken: 'expired-driver-access',
          refreshToken: 'expired-driver-refresh',
        ),
      );
      final authApi = _RecordingDriverAuthApiGateway(statusCode: 401);

      await tester.pumpWidget(
        DriverApp(
          showLoginShell: true,
          authService: AuthService(
            apiGateway: authApi,
            tokenStore: store,
            appContext: AuthAppContext.driver,
          ),
          authTokenStore: store,
        ),
      );
      await tester.pumpAndSettle();

      expect(authApi.paths, <String>[AuthService.refreshPath]);
      expect(authApi.bodies.single, <String, Object?>{
        'refresh': 'expired-driver-refresh',
      });
      expect(find.byKey(const Key('driver-sign-in')), findsOneWidget);
      expect(find.text('Driver sign in'), findsOneWidget);
      expect(find.text('Please sign in again to continue.'), findsOneWidget);
      expect(find.text('No trip assigned yet.'), findsNothing);
      expect(await store.readAccessToken(), isNull);
      expect(await store.readRefreshToken(), isNull);
    },
  );

  testWidgets(
    'driver startup with refreshable stored tokens opens live-safe home',
    (tester) async {
      _useSurface(tester, const Size(430, 1000));
      final store = MemoryAuthTokenStore();
      await store.saveTokens(
        AuthTokens(
          accessToken: 'stored-driver-access',
          refreshToken: 'stored-driver-refresh',
        ),
      );
      final authApi = _RecordingDriverAuthApiGateway(
        responseData: const <String, Object?>{
          'access': 'restored-driver-access',
        },
      );

      await tester.pumpWidget(
        DriverApp(
          showLoginShell: true,
          authService: AuthService(
            apiGateway: authApi,
            tokenStore: store,
            appContext: AuthAppContext.driver,
          ),
          authTokenStore: store,
        ),
      );
      await tester.pumpAndSettle();

      expect(authApi.paths, <String>[AuthService.refreshPath]);
      expect(authApi.bodies.single, <String, Object?>{
        'refresh': 'stored-driver-refresh',
      });
      expect(await store.readAccessToken(), 'restored-driver-access');
      expect(await store.readRefreshToken(), 'stored-driver-refresh');
      expect(find.text('Driver app ready'), findsOneWidget);
      expect(find.text('Driver app ready'), findsOneWidget);
      expect(find.text('Driver app ready'), findsOneWidget);
      expect(find.text('Driver app ready'), findsWidgets);
      expect(find.text('Preview incoming offer'), findsNothing);
      expect(find.text('Please sign in again to continue.'), findsNothing);
    },
  );

  testWidgets('driver sign out after restored startup clears next startup', (
    tester,
  ) async {
    _useSurface(tester, const Size(430, 1000));
    final store = MemoryAuthTokenStore();
    await store.saveTokens(
      AuthTokens(
        accessToken: 'stored-driver-access',
        refreshToken: 'stored-driver-refresh',
      ),
    );
    final authApi = _RecordingDriverAuthApiGateway();

    Widget app() => DriverApp(
      showLoginShell: true,
      authService: AuthService(
        apiGateway: authApi,
        tokenStore: store,
        appContext: AuthAppContext.driver,
      ),
      authTokenStore: store,
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Account'));
    await tester.pumpAndSettle();
    expect(find.text('Driver account'), findsOneWidget);
    expect(find.text('Signed in to ALANTEH Driver.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('driver-account-sign-out')));
    await tester.pumpAndSettle();

    expect(await store.readAccessToken(), isNull);
    expect(await store.readRefreshToken(), isNull);
    expect(find.byKey(const Key('driver-sign-in')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('driver-sign-in')), findsOneWidget);
    expect(find.byKey(const Key('driver-sign-out')), findsNothing);
  });

  testWidgets(
    'driver sign out clears tokens, returns login, and resets local QA shift',
    (tester) async {
      _useSurface(tester, const Size(430, 1000));
      final store = MemoryAuthTokenStore();
      final authApi = _RecordingDriverAuthApiGateway();
      await tester.pumpWidget(
        DriverApp(
          configuration: _localQaEnabledConfig,
          showLoginShell: true,
          authService: AuthService(
            apiGateway: authApi,
            tokenStore: store,
            appContext: AuthAppContext.driver,
          ),
          authTokenStore: store,
        ),
      );

      await tester.enterText(
        find.byKey(const Key('driver-phone-field')),
        '+233000000001',
      );
      await tester.enterText(find.byKey(const Key('driver-pin-field')), '9876');
      await tester.tap(find.byKey(const Key('driver-sign-in')));
      await tester.pumpAndSettle();

      expect(await store.readAccessToken(), 'driver-access-token');
      expect(await store.readRefreshToken(), 'driver-refresh-token');
      expect(find.byKey(const Key('driver-sign-out')), findsOneWidget);
      expect(find.text('Local QA: Off shift'), findsNothing);

      await tester.ensureVisible(find.byKey(const Key('open-readiness')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-readiness')));
      await tester.pumpAndSettle();
      for (final item in DriverReadinessItem.values) {
        await tester.tap(find.byKey(ValueKey('readiness-${item.name}')));
      }
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('readiness-ready')),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('readiness-ready')));
      await tester.pumpAndSettle();

      expect(find.text('Local QA: On shift'), findsNothing);

      await tester.ensureVisible(find.byKey(const Key('driver-sign-out')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('driver-sign-out')));
      await tester.pumpAndSettle();

      expect(await store.readAccessToken(), isNull);
      expect(await store.readRefreshToken(), isNull);
      expect(find.byKey(const Key('driver-sign-in')), findsOneWidget);
      expect(find.byKey(const Key('driver-sign-out')), findsNothing);
      expect(find.text('Sign in'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('driver-phone-field')),
        '+233000000001',
      );
      await tester.enterText(find.byKey(const Key('driver-pin-field')), '9876');
      await tester.tap(find.byKey(const Key('driver-continue-local-demo')));
      await tester.pumpAndSettle();

      expect(await store.readAccessToken(), isNull);
      expect(await store.readRefreshToken(), isNull);
      expect(find.text('Local QA: Off shift'), findsNothing);
      expect(find.text('Local QA: On shift'), findsNothing);
      expect(find.text('Preview incoming offer'), findsOneWidget);
    },
  );

  testWidgets('Driver home uses safe M3C copy without fake live status', (
    tester,
  ) async {
    _useSurface(tester, const Size(430, 1000));
    final store = MemoryAuthTokenStore();
    final authApi = _RecordingDriverAuthApiGateway();

    await tester.pumpWidget(
      DriverApp(
        showLoginShell: true,
        authService: AuthService(
          apiGateway: authApi,
          tokenStore: store,
          appContext: AuthAppContext.driver,
        ),
        authTokenStore: store,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('driver-phone-field')),
      '+233000000001',
    );
    await tester.enterText(find.byKey(const Key('driver-pin-field')), '9876');
    await tester.tap(find.byKey(const Key('driver-sign-in')));
    await tester.pumpAndSettle();

    expect(find.text('Field workspace'), findsNothing);
    expect(find.text('Approved drivers only'), findsNothing);
    expect(
      find.text('This workspace is reserved for approved ALANTEH drivers.'),
      findsNothing,
    );
    expect(find.text('Driver app foundation'), findsNothing);

    expect(find.text('Driver app ready'), findsOneWidget);
    expect(find.text('Driver app ready'), findsOneWidget);
    expect(find.text('Driver app ready'), findsOneWidget);
    expect(find.text('Driver app ready'), findsWidgets);

    expect(find.textContaining('On shift'), findsNothing);
    expect(find.textContaining('Off shift'), findsNothing);
    expect(find.textContaining('Waiting for trip'), findsNothing);
    expect(find.textContaining('Trip assigned'), findsNothing);
    expect(find.textContaining('Dispatcher confirmed'), findsNothing);
    expect(find.textContaining('Trip completed'), findsNothing);
    expect(find.textContaining('No trip waiting'), findsNothing);
    expect(
      find.textContaining('Shift status is managed by the dispatcher.'),
      findsNothing,
    );
    expect(
      find.textContaining('Control Center will confirm your duty status.'),
      findsNothing,
    );
    expect(
      find.textContaining('Stay ready for the Control Center.'),
      findsNothing,
    );

    expect(find.textContaining('fake assigned trip'), findsNothing);
    expect(find.textContaining('fake active trip'), findsNothing);
    expect(find.textContaining('fake passenger details'), findsNothing);
    expect(find.textContaining('fake earnings'), findsNothing);
    expect(find.textContaining('fake route'), findsNothing);
    expect(find.textContaining('fake ETA'), findsNothing);
    expect(find.textContaining('fake fare'), findsNothing);
    expect(find.textContaining('passenger details'), findsNothing);
    expect(find.textContaining('earnings'), findsNothing);
    expect(find.textContaining('ETA'), findsNothing);
    expect(find.textContaining('fare'), findsNothing);
    expect(find.text('Accept trip'), findsNothing);
    expect(find.text('Start trip'), findsNothing);
    expect(find.text('Complete trip'), findsNothing);

    expect(find.text('Preview incoming offer'), findsNothing);
    expect(find.text('Local QA readiness preview'), findsNothing);
  });
  testWidgets(
    'Driver app accepts production API base URL dart-define without live HTTP',
    (tester) async {
      const productionBaseUrl = 'https://control.alanteh.io';
      const configuredBaseUrl = String.fromEnvironment('ASM_API_BASE_URL');

      if (configuredBaseUrl != productionBaseUrl) {
        expect(AsmApiClient.defaultBaseUrl, configuredBaseUrl);
        return;
      }

      await tester.pumpWidget(const DriverApp());
      await tester.pump();

      expect(AsmApiClient.defaultBaseUrl, productionBaseUrl);
      expect(AsmApiBaseUrl.isUsable(AsmApiClient.defaultBaseUrl), isTrue);
      expect(AuthService.tokenPath, '/api/auth/token/');
      expect(AuthService.refreshPath, '/api/auth/token/refresh/');
      expect(find.byType(DriverApp), findsOneWidget);
    },
  );

  group('M4D Driver duty and assigned trips', () {
    testWidgets('Driver duty loading state is visible', (tester) async {
      _useSurface(tester, const Size(430, 3000));
      final completer = Completer<DriverDutySummary>();

      await tester.pumpWidget(
        MaterialApp(
          theme: AsmThemes.driver,
          home: AsmScreenSurface(
            child: DriverDutySummaryPanel(
              gateway: _FakeDriverDutyGateway(duty: completer.future),
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('driver-duty-loading')), findsOneWidget);
      expect(find.text('Loading driver duty...'), findsOneWidget);

      completer.complete(_sampleDuty());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('driver-duty-loaded')), findsOneWidget);
    });

    testWidgets('Driver duty loaded state shows safe fields only', (
      tester,
    ) async {
      _useSurface(tester, const Size(430, 3000));

      await tester.pumpWidget(
        MaterialApp(
          theme: AsmThemes.driver,
          home: AsmScreenSurface(
            child: DriverDutySummaryPanel(
              gateway: _FakeDriverDutyGateway(
                duty: Future.value(_sampleDuty()),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Driver duty summary'), findsOneWidget);
      expect(find.text('Driver One'), findsOneWidget);
      expect(find.text('DRV-001'), findsOneWidget);
      expect(find.text('+233 20 ****001'), findsOneWidget);
      expect(find.text('VEH-009'), findsOneWidget);
      expect(find.text('Yes'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('+233200000001'), findsNothing);
    });

    testWidgets('Assigned trips loading state is visible', (tester) async {
      _useSurface(tester, const Size(430, 1000));
      final completer = Completer<List<DriverAssignedTrip>>();

      await tester.pumpWidget(
        MaterialApp(
          theme: AsmThemes.driver,
          home: DriverAssignedTripsScreen(
            gateway: _FakeDriverDutyGateway(trips: completer.future),
          ),
        ),
      );

      expect(find.byKey(const Key('driver-trips-loading')), findsOneWidget);
      expect(find.text('Loading assigned trips...'), findsOneWidget);

      completer.complete(const <DriverAssignedTrip>[]);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('driver-trips-empty')), findsOneWidget);
    });

    testWidgets('Assigned trips loaded state displays trip cards', (
      tester,
    ) async {
      _useSurface(tester, const Size(430, 1200));

      await tester.pumpWidget(
        MaterialApp(
          theme: AsmThemes.driver,
          home: DriverAssignedTripsScreen(
            gateway: _FakeDriverDutyGateway(
              trips: Future.value(<DriverAssignedTrip>[_sampleTrip()]),
              detail: Future.value(_sampleTrip(reference: 'TRIP-001')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('My Assigned Trips'), findsOneWidget);
      expect(find.byKey(const Key('driver-trip-TRIP-001')), findsOneWidget);
      expect(find.text('TRIP-001'), findsOneWidget);
      expect(find.text('Assigned'), findsOneWidget);
      expect(find.text('Accra Mall'), findsOneWidget);
      expect(find.text('Osu'), findsOneWidget);
      expect(find.text('VEH-009'), findsOneWidget);
      expect(find.text('Meet at the main entrance.'), findsOneWidget);
    });

    testWidgets('Assigned trips empty state uses production-safe wording', (
      tester,
    ) async {
      _useSurface(tester, const Size(430, 1000));

      await tester.pumpWidget(
        MaterialApp(
          theme: AsmThemes.driver,
          home: DriverAssignedTripsScreen(
            gateway: _FakeDriverDutyGateway(
              trips: Future.value(const <DriverAssignedTrip>[]),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('driver-trips-empty')), findsOneWidget);
      expect(find.text(driverTripsEmptyTitle), findsOneWidget);
      expect(find.text(driverTripsEmptyMessage), findsOneWidget);
      expect(find.textContaining('fake assigned trip'), findsNothing);
    });

    testWidgets('Assigned trips error state is safe and refreshable', (
      tester,
    ) async {
      _useSurface(tester, const Size(430, 1000));

      await tester.pumpWidget(
        MaterialApp(
          theme: AsmThemes.driver,
          home: DriverAssignedTripsScreen(
            gateway: _FakeDriverDutyGateway(
              trips: _futureTripListError(
                const DriverDutyApiException(
                  DriverDutyApiFailureType.unavailable,
                  'temporary',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('driver-trips-error')), findsOneWidget);
      expect(find.text('Assigned trips could not be loaded.'), findsOneWidget);
      expect(find.text('Refresh'), findsOneWidget);
    });

    testWidgets('Unauthorized Driver trips state asks for sign in again', (
      tester,
    ) async {
      _useSurface(tester, const Size(430, 1000));

      await tester.pumpWidget(
        MaterialApp(
          theme: AsmThemes.driver,
          home: DriverAssignedTripsScreen(
            gateway: _FakeDriverDutyGateway(
              trips: _futureTripListError(
                const DriverDutyApiException(
                  DriverDutyApiFailureType.sessionExpired,
                  driverSessionExpiredMessage,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('driver-trips-session-expired')),
        findsOneWidget,
      );
      expect(find.text(driverSessionExpiredMessage), findsOneWidget);
    });

    testWidgets('Trip detail displays safe assigned trip fields', (
      tester,
    ) async {
      _useSurface(tester, const Size(430, 1200));

      await tester.pumpWidget(
        MaterialApp(
          theme: AsmThemes.driver,
          home: DriverTripDetailScreen(
            gateway: _FakeDriverDutyGateway(
              detail: Future.value(_sampleTrip(reference: 'TRIP-DETAIL')),
            ),
            tripReference: 'TRIP-DETAIL',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('driver-trip-detail-loaded')),
        findsOneWidget,
      );
      expect(find.text('Assigned trip detail'), findsWidgets);
      expect(find.text('TRIP-DETAIL'), findsOneWidget);
      expect(find.text('Assigned'), findsOneWidget);
      expect(find.text('Accra Mall'), findsOneWidget);
      expect(find.text('Osu'), findsOneWidget);
      expect(find.text('2026-07-13T09:00:00Z'), findsOneWidget);
      expect(find.text('2026-07-13T09:30:00Z'), findsOneWidget);
      expect(find.text('VEH-009'), findsOneWidget);
      expect(find.text('Meet at the main entrance.'), findsOneWidget);
    });

    testWidgets('Driver duty and trips do not render sensitive fields', (
      tester,
    ) async {
      _useSurface(tester, const Size(430, 1200));
      const sensitiveStrings = <String>[
        'PIN',
        'access token',
        'refresh token',
        'Authorization',
        'private phone',
        'private email',
        'Idempotency-Key',
        'raw payload',
        'password',
      ];

      await tester.pumpWidget(
        MaterialApp(
          theme: AsmThemes.driver,
          home: DriverAssignedTripsScreen(
            gateway: _FakeDriverDutyGateway(
              trips: Future.value(<DriverAssignedTrip>[_sampleTrip()]),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (final forbidden in sensitiveStrings) {
        expect(find.textContaining(forbidden), findsNothing);
      }
      expect(find.textContaining('+233200000001'), findsNothing);
      expect(find.textContaining('@'), findsNothing);
    });

    testWidgets('Driver Home opens My Assigned Trips from work tab', (
      tester,
    ) async {
      _useSurface(tester, const Size(430, 1200));

      await tester.pumpWidget(
        MaterialApp(
          theme: AsmThemes.driver,
          home: DriverShell(
            driverDutyGateway: _FakeDriverDutyGateway(
              duty: Future.value(_sampleDuty()),
              trips: Future.value(<DriverAssignedTrip>[_sampleTrip()]),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('driver-duty-loaded')), findsOneWidget);
      await tester.tap(find.byKey(const Key('open-assigned-trips')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('driver-assigned-trips-screen')),
        findsOneWidget,
      );
      expect(find.text('TRIP-001'), findsOneWidget);
    });
  });
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

class _RecordingDriverAuthApiGateway implements AuthApiGateway {
  _RecordingDriverAuthApiGateway({
    Map<String, Object?>? responseData,
    this.statusCode = 200,
    this.exceptionType,
    this.pendingResponse,
  }) : responseData = responseData ?? _driverLoginResponse();

  final Map<String, Object?> responseData;
  final int statusCode;
  final AsmApiExceptionType? exceptionType;
  final Completer<ApiResponse<Map<String, Object?>>>? pendingResponse;
  final List<String> paths = <String>[];
  final List<Map<String, Object?>> bodies = <Map<String, Object?>>[];

  @override
  Future<ApiResponse<Map<String, Object?>>> post(
    String path, {
    required Map<String, Object?> body,
  }) async {
    paths.add(path);
    bodies.add(Map<String, Object?>.of(body));

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

    if (statusCode < 200 || statusCode >= 300) {
      return ApiResponse.apiFailure(
        AsmApiException(
          type: statusCode == 401
              ? AsmApiExceptionType.authentication
              : statusCode >= 500
              ? AsmApiExceptionType.server
              : AsmApiExceptionType.badResponse,
          message: 'Authentication failed.',
          statusCode: statusCode,
        ),
      );
    }

    return ApiResponse.success(responseData, statusCode: statusCode);
  }
}

Map<String, Object?> _driverLoginResponse({Object? accountType = 'driver'}) {
  final response = <String, Object?>{
    'access': 'driver-access-token',
    'refresh': 'driver-refresh-token',
    'account': <String, Object?>{},
  };
  if (accountType != null) {
    response['account_type'] = accountType;
  }
  return response;
}

const _localQaEnabledConfig = AsmAppConfig(
  environment: RuntimeEnvironment.local,
  market: MarketConfig.ghanaAccra,
  capabilities: CapabilityConfig(),
  localQaEnabled: true,
);

const _removedDriverTexts = [
  'ASM DRIVER',
  'ASM PASSENGER',
  'Africa Solar Mobility',
  'LOCAL DEMO',
  'local demo',
  'ASM_DRIVER_APP_AUTOMATION_ACTIVE',
  'No live trips engineering warning',
  'No real offer',
  'demo preview',
  'Pre-shift readiness check',
  'Submit readiness',
  'Incoming ride offer',
  'Accept offer',
  'Report a vehicle concern',
  'Attention level',
  'Submit concern',
];

void _expectNoOperationalActions() {
  for (final label in [
    'Start Shift',
    'Go Online',
    'Accept Trip',
    'Submit',
    'Earnings',
    'Pay',
    'Send',
    'Notify operations',
    'Call support',
    'Upload',
  ]) {
    expect(find.text(label), findsNothing);
  }
}

void _expectPendingRideOffer() {
  expect(find.text('14s'), findsOneWidget);
  expect(find.text('New ride offer'), findsOneWidget);
  expect(find.text('Accra Mall → Accra Market'), findsOneWidget);
  expect(find.text('Distance'), findsOneWidget);
  expect(find.text('9.5 km'), findsOneWidget);
  expect(find.text('Pickup'), findsOneWidget);
  expect(find.text('1.2 km away'), findsOneWidget);
  expect(find.text('View details'), findsOneWidget);
  expect(find.text('Accept'), findsNothing);
  expect(find.text('Decline'), findsNothing);
  _expectNoRideOfferLiveContent();
}

void _expectRideOfferDetails() {
  expect(find.text('Ride offer'), findsWidgets);
  expect(find.text('Accra Mall → Accra Market'), findsOneWidget);
  expect(find.text('Accra Mall'), findsWidgets);
  expect(find.text('Accra Market'), findsWidgets);
  expect(find.text('Distance'), findsOneWidget);
  expect(find.text('9.5 km'), findsOneWidget);
  expect(find.text('Est. duration'), findsOneWidget);
  expect(find.text('23 min'), findsOneWidget);
  expect(find.text('Passengers'), findsOneWidget);
  expect(find.text('2'), findsOneWidget);
  expect(find.text('Accept'), findsOneWidget);
  expect(find.text('Decline'), findsOneWidget);
  _expectNoRideOfferLiveContent();
}

void _expectNoRideOfferLiveContent() {
  for (final label in [
    'Fare',
    'Earnings',
    'Customer name',
    'Phone number',
    'Map',
    'Active Assignment',
    'Enable Notifications',
    'Allow Notifications',
  ]) {
    expect(find.text(label), findsNothing);
  }
}

Future<void> _openDriverLocalDemo(WidgetTester tester) async {
  if (find.byKey(const Key('driver-phone-field')).evaluate().isEmpty) {
    return;
  }

  await tester.enterText(
    find.byKey(const Key('driver-phone-field')),
    '0550000000',
  );
  await tester.enterText(find.byKey(const Key('driver-pin-field')), '0000');
  await tester.tap(find.byKey(const Key('driver-continue-local-demo')));
  await tester.pumpAndSettle();
}

Future<void> _openRideOfferPreview(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.byKey(const Key('open-ride-offer-preview')),
    200,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.tap(find.byKey(const Key('open-ride-offer-preview')));
}

Future<void> _completeConcernForm(
  WidgetTester tester, {
  required String description,
}) async {
  await tester.tap(find.byKey(const Key('concern-category')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Vehicle problem').last);
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(const Key('concern-attention')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Urgent').last);
  await tester.pumpAndSettle();

  await tester.enterText(
    find.byKey(const Key('concern-description')),
    description,
  );
  await _scrollToConcernReview(tester);
  await tester.tap(find.byKey(const Key('review-concern')));
  await tester.pumpAndSettle();
}

Future<void> _scrollToConcernReview(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.byKey(const Key('review-concern')),
    200,
    scrollable: find.byType(Scrollable).last,
  );
}

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

class _FakeDriverDutyGateway implements DriverDutyGateway {
  _FakeDriverDutyGateway({
    Future<DriverDutySummary>? duty,
    Future<List<DriverAssignedTrip>>? trips,
    Future<DriverAssignedTrip>? detail,
  }) : duty = duty ?? Future.value(DriverDutySummary.empty()),
       trips = trips ?? Future.value(const <DriverAssignedTrip>[]),
       detail =
           detail ??
           Future.value(const DriverAssignedTrip(reference: 'TRIP-DETAIL'));

  Future<DriverDutySummary> duty;
  Future<List<DriverAssignedTrip>> trips;
  Future<DriverAssignedTrip> detail;
  int dutyCalls = 0;
  int tripsCalls = 0;
  int detailCalls = 0;

  @override
  Future<DriverDutySummary> fetchDuty() {
    dutyCalls += 1;
    return duty;
  }

  @override
  Future<List<DriverAssignedTrip>> fetchTrips() {
    tripsCalls += 1;
    return trips;
  }

  @override
  Future<DriverAssignedTrip> fetchTripDetail(String tripReference) {
    detailCalls += 1;
    return detail;
  }
}

Future<List<DriverAssignedTrip>> _futureTripListError(
  DriverDutyApiException error,
) {
  return Future<List<DriverAssignedTrip>>.delayed(
    Duration.zero,
    () => throw error,
  );
}

DriverDutySummary _sampleDuty() {
  return const DriverDutySummary(
    displayName: 'Driver One',
    driverReference: 'DRV-001',
    phone: '+233200000001',
    status: 'active',
    assignedVehicleReference: 'VEH-009',
    canReceiveAssignments: true,
    activeTripCount: 1,
    assignedTripCount: 2,
  );
}

DriverAssignedTrip _sampleTrip({String reference = 'TRIP-001'}) {
  return DriverAssignedTrip(
    reference: reference,
    status: 'assigned',
    pickupLocation: 'Accra Mall',
    destination: 'Osu',
    requestedPickupTime: '2026-07-13T10:00:00Z',
    createdTime: '2026-07-13T09:00:00Z',
    updatedTime: '2026-07-13T09:30:00Z',
    vehicleReference: 'VEH-009',
    passengerCount: 2,
    controlCenterMessage: 'Meet at the main entrance.',
  );
}
