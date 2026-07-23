import 'package:asm_design_system/asm_design_system.dart';
import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_auth/asm_auth.dart';
import 'package:driver_app/foundation/driver_foundation_widgets.dart';
import 'package:driver_app/main.dart';
import 'package:driver_app/readiness/driver_readiness_check.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Driver splash matches the approved foundation sequence', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: DriverSplashScreen()));

    expect(find.byKey(const Key('driver-splash-screen')), findsOneWidget);
    expect(find.byKey(const Key('driver-splash-logo')), findsOneWidget);
    expect(find.text('ALANTEH Driver'), findsOneWidget);
    expect(find.text('Safe, reliable electric mobility'), findsOneWidget);
  });

  testWidgets('Driver phone and PIN login includes safe error treatment', (
    tester,
  ) async {
    _useSurface(tester);

    final store = MemoryAuthTokenStore();
    final gateway = _DriverAuthGateway(statusCode: 401);

    await tester.pumpWidget(
      DriverApp(
        showLoginShell: true,
        authTokenStore: store,
        authService: AuthService(
          apiGateway: gateway,
          tokenStore: store,
          appContext: AuthAppContext.driver,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Driver sign in'), findsOneWidget);
    expect(
      find.text('Enter your phone number and PIN to start your shift.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('driver-phone-field')), findsOneWidget);
    expect(find.byKey(const Key('driver-pin-field')), findsOneWidget);
    expect(find.text('Forgot your PIN?'), findsOneWidget);

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
    expect(await store.readAccessToken(), isNull);
  });

  testWidgets(
    'Driver readiness remains local-only and never claims operational online state',
    (tester) async {
      _useSurface(tester, const Size(430, 1300));

      await tester.pumpWidget(const DriverApp());
      await tester.pumpAndSettle();

      expect(find.text('Good morning, Driver'), findsOneWidget);
      expect(find.text('You’re offline'), findsOneWidget);
      expect(find.byKey(const Key('driver-start-readiness')), findsOneWidget);

      await tester.tap(find.byKey(const Key('driver-start-readiness')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('driver-shift-readiness-screen')),
        findsOneWidget,
      );
      expect(find.text('Shift check'), findsOneWidget);
      expect(find.text('LOCAL ONLY'), findsOneWidget);
      expect(
        find.text(
          'Completing this checklist updates this device only. '
          'It is not submitted to the Control Center.',
        ),
        findsOneWidget,
      );
      expect(find.text('Local pre-shift checklist'), findsOneWidget);
      expect(
        find.byKey(const Key('driver-pre-shift-vehicle-check')),
        findsOneWidget,
      );

      for (final item in DriverReadinessItem.values) {
        expect(find.text(item.label), findsOneWidget);
        expect(find.text(item.description), findsOneWidget);
      }

      await tester.ensureVisible(
        find.byKey(const Key('readiness-battery-needs-attention')),
      );
      await tester.tap(
        find.byKey(const Key('readiness-battery-needs-attention')),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('readiness-failed')), findsOneWidget);
      expect(find.text('One check needs attention'), findsOneWidget);
      expect(find.text('Recheck battery'), findsOneWidget);

      await tester.tap(find.byKey(const Key('readiness-recheck-battery')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('readiness-failed')), findsNothing);

      for (final item in DriverReadinessItem.values) {
        final itemFinder = find.byKey(ValueKey('readiness-${item.name}'));
        await tester.ensureVisible(itemFinder);
        await tester.pumpAndSettle();
        await tester.tap(itemFinder);
      }
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('readiness-complete')), findsOneWidget);
      expect(find.text('Local checklist complete'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.byKey(const Key('readiness-ready')),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('readiness-ready')));
      await tester.pumpAndSettle();

      expect(find.text('You’re offline'), findsOneWidget);
      expect(find.text('You’re online'), findsNothing);
      expect(find.byKey(const Key('driver-waiting-for-offer')), findsNothing);
      expect(find.byKey(const Key('driver-duty-toggle')), findsNothing);
      expect(find.text('Waiting for offers'), findsNothing);
    },
  );

  testWidgets('production Driver foundation hides internal and money wording', (
    tester,
  ) async {
    _useSurface(tester, const Size(430, 1200));

    await tester.pumpWidget(const DriverApp());
    await tester.pumpAndSettle();

    expect(find.textContaining('demo'), findsNothing);
    expect(find.textContaining('placeholder'), findsNothing);
    expect(find.textContaining('WebSocket'), findsNothing);
    expect(find.textContaining('GPS movement'), findsNothing);
    expect(find.textContaining('earnings'), findsNothing);
    expect(find.textContaining('commission'), findsNothing);
    expect(find.textContaining('payout'), findsNothing);
    expect(find.textContaining('wallet'), findsNothing);
    expect(find.textContaining('fare'), findsNothing);
  });

  testWidgets('Driver dedicated offline state matches approved sequence', (
    tester,
  ) async {
    var retryPressed = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.driver,
        home: DriverOfflineState(onRetry: () => retryPressed = true),
      ),
    );

    expect(find.byKey(const Key('driver-offline-screen')), findsOneWidget);
    expect(find.byKey(const Key('driver-offline-icon')), findsOneWidget);
    expect(find.text('You’re offline'), findsOneWidget);
    expect(
      find.textContaining("You can't receive ride offers"),
      findsOneWidget,
    );
    expect(find.textContaining('update your shift status'), findsOneWidget);
    expect(find.byKey(const Key('driver-offline-retry')), findsOneWidget);

    await tester.tap(find.byKey(const Key('driver-offline-retry')));
    await tester.pump();

    expect(retryPressed, isTrue);
  });
}

void _useSurface(WidgetTester tester, [Size size = const Size(430, 1100)]) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;

  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

class _DriverAuthGateway implements AuthApiGateway {
  const _DriverAuthGateway({required this.statusCode});

  final int statusCode;

  @override
  Future<ApiResponse<Map<String, Object?>>> post(
    String path, {
    required Map<String, Object?> body,
  }) async {
    return ApiResponse.apiFailure(
      AsmApiException(
        type: AsmApiExceptionType.authentication,
        message: 'Request rejected.',
        statusCode: statusCode,
      ),
    );
  }
}
