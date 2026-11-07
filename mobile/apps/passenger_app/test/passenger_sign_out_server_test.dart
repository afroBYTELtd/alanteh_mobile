import 'dart:async';

import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_auth/asm_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passenger_app/main.dart';
import 'package:passenger_app/notifications/push_device_registration.dart';
import 'package:passenger_app/notifications/push_notification_runtime.dart';

// Sign-in build A4: the passenger app signs out through the server (A1),
// keeps a sign-out the server did not get, and sends pending sign-outs at
// start only when no one is signed in (after a new sign-in, A1 sends them
// before login returns). The 2 h check before booking is unchanged.

void main() {
  late _AuthApi api;
  late MemoryAuthTokenStore tokens;
  late MemoryPendingSignOutStore pending;

  setUp(() {
    api = _AuthApi();
    tokens = MemoryAuthTokenStore();
    pending = MemoryPendingSignOutStore();
  });

  Widget app() => PassengerApp(
    showLoginShell: true,
    authTokenStore: tokens,
    authService: AuthService(
      apiGateway: api,
      tokenStore: tokens,
      appContext: AuthAppContext.passenger,
      pendingSignOutStore: pending,
      installationIdStore: MemoryInstallationIdStore('install-1'),
    ),
    pushDeviceRegistrarFactory: (_) => _Registrar(),
    pushMessageSource: _NoPushes(),
  );

  void useSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> signIn(WidgetTester tester) async {
    await tester.enterText(
      find.byKey(const Key('passenger-phone-field')),
      '+233000000002',
    );
    await tester.enterText(
      find.byKey(const Key('passenger-pin-field')),
      '1234',
    );
    final button = find.byKey(const Key('passenger-sign-in'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  Future<void> tapSignOut(WidgetTester tester) async {
    await tester.tap(find.text('Account'));
    await tester.pumpAndSettle();
    final button = find.byKey(const Key('passenger-account-sign-out'));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
  }

  testWidgets('Sign out tells the server, then shows sign-in', (tester) async {
    useSurface(tester);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await signIn(tester);

    await tapSignOut(tester);
    await tester.pumpAndSettle();

    expect(api.logouts.single, {
      'refresh': 'passenger-refresh',
      'device_token': 'fcm-p',
      'installation_id': 'install-1',
    });
    expect(find.byKey(const Key('passenger-sign-in')), findsOneWidget);
    expect(await tokens.readRefreshToken(), isNull);
    expect(await pending.read(), isEmpty);
  });

  testWidgets('while the server is asked, "Signing out…" is shown', (
    tester,
  ) async {
    useSurface(tester);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await signIn(tester);
    final answer = Completer<ApiResponse<Map<String, Object?>>>();
    api.logoutAnswer = () => answer.future;

    await tapSignOut(tester);
    await tester.pump();
    await tester.pump();

    expect(find.text('Signing out…'), findsOneWidget);
    answer.complete(_signedOut());
    await tester.pumpAndSettle();
    expect(find.text('Signing out…'), findsNothing);
    expect(find.byKey(const Key('passenger-sign-in')), findsOneWidget);
  });

  testWidgets('no answer: signed out on the phone, sign-out kept pending', (
    tester,
  ) async {
    useSurface(tester);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await signIn(tester);
    api.logoutAnswer = () async => ApiResponse.clientException(
      const AsmApiException(
        type: AsmApiExceptionType.network,
        message: 'no network',
      ),
    );

    await tapSignOut(tester);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('passenger-sign-in')), findsOneWidget);
    expect(await tokens.readRefreshToken(), isNull);
    expect((await pending.read()).single.refresh, 'passenger-refresh');
  });

  testWidgets('app start, no one signed in: pending sign-outs are sent', (
    tester,
  ) async {
    useSurface(tester);
    await pending.write([
      PendingSignOut(refresh: 'refresh-old', createdAt: DateTime.now()),
    ]);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(api.logouts.single, {'refresh': 'refresh-old'});
    expect(await pending.read(), isEmpty);
  });

  testWidgets('app start, signed in: pending sign-outs are not sent', (
    tester,
  ) async {
    useSurface(tester);
    await pending.write([
      PendingSignOut(refresh: 'refresh-old', createdAt: DateTime.now()),
    ]);
    await tokens.saveTokens(
      AuthTokens(accessToken: 'access-now', refreshToken: 'refresh-now'),
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(api.logouts, isEmpty);
    expect(await pending.read(), hasLength(1));
  });
}

ApiResponse<Map<String, Object?>> _signedOut() => ApiResponse.success(
  <String, Object?>{'detail': 'Signed out.'},
  statusCode: 200,
);

final class _AuthApi implements AuthApiGateway {
  final logouts = <Map<String, Object?>>[];
  Future<ApiResponse<Map<String, Object?>>> Function()? logoutAnswer;

  @override
  Future<ApiResponse<Map<String, Object?>>> post(
    String path, {
    required Map<String, Object?> body,
  }) async {
    if (path == AuthService.logoutPath) {
      logouts.add(Map.of(body));
      return (logoutAnswer ?? () async => _signedOut())();
    }
    return ApiResponse<Map<String, Object?>>.success(<String, Object?>{
      'access': 'passenger-access',
      'refresh': 'passenger-refresh',
      'account_type': 'passenger',
      'account': <String, Object?>{
        'display_name': 'Ama',
        'phone': '+233000000002',
      },
    }, statusCode: 200);
  }
}

final class _Registrar implements PushDeviceRegistrar {
  @override
  String? get deviceToken => 'fcm-p';

  @override
  Future<bool> registerForAuthenticatedSession() async => true;

  @override
  Future<bool> requestNotificationPermission() async => true;

  @override
  void endAuthenticatedSession() {}

  @override
  Future<void> dispose() async {}
}

final class _NoPushes implements PassengerPushMessageSource {
  @override
  Stream<RemoteMessage> get foregroundMessages =>
      const Stream<RemoteMessage>.empty();

  @override
  Stream<RemoteMessage> get openedMessages =>
      const Stream<RemoteMessage>.empty();

  @override
  Future<RemoteMessage?> getInitialMessage() async => null;
}
