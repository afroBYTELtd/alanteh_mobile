import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_auth/asm_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passenger_app/main.dart';
import 'package:passenger_app/notifications/push_device_registration.dart';
import 'package:passenger_app/notifications/push_notification_runtime.dart';
import 'package:passenger_app/passenger_shell.dart';

// T2b (lead, 12 Nov): when push registration is the first to find a
// REFUSED session, the passenger goes to the sign-in screen at once through
// the existing _returnToSignIn; "not now" keeps the sign-in. Built from the
// 12 Nov probe, with the real AuthService.
void main() {
  late MemoryAuthTokenStore tokens;
  late _Api api;
  late AuthService auth;
  late _Registrar registrar;
  PushSessionRefresh? pushRefresh;

  setUp(() {
    tokens = MemoryAuthTokenStore();
    api = _Api();
    auth = AuthService(
      apiGateway: api,
      tokenStore: tokens,
      appContext: AuthAppContext.passenger,
    );
    registrar = _Registrar();
    pushRefresh = null;
  });

  Future<void> pumpSignedIn(WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      PassengerApp(
        showLoginShell: true,
        authTokenStore: tokens,
        authService: auth,
        pushDeviceRegistrarFactory: (_, {refreshSession}) {
          pushRefresh = refreshSession;
          return registrar;
        },
        pushMessageSource: _NoPushes(),
      ),
    );
    await tester.pumpAndSettle();
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
    expect(find.byKey(const Key('passenger-sign-in')), findsNothing);
    api.paths.clear();
  }

  testWidgets('refused: the sign-in screen at once; the "Signing out…" '
      'dialog closes and nothing is sent', (tester) async {
    await pumpSignedIn(tester);
    api.refreshStatus = 401;

    expect(await pushRefresh!(), isFalse);
    await tester.pumpAndSettle();

    expect(await tokens.readRefreshToken(), isNull);
    expect(find.byKey(const Key('passenger-sign-in')), findsOneWidget);
    expect(find.byKey(const Key('passenger-signing-out')), findsNothing);
    expect(api.paths, isNot(contains(AuthService.logoutPath)));
  });

  testWidgets('not now (503): still signed in, tokens kept', (tester) async {
    await pumpSignedIn(tester);
    api.refreshStatus = 503;

    expect(await pushRefresh!(), isFalse);
    await tester.pumpAndSettle();

    expect(await tokens.readRefreshToken(), 'r');
    expect(find.byKey(const Key('passenger-sign-in')), findsNothing);
    expect(find.byKey(const Key('passenger-signing-out')), findsNothing);
  });

  testWidgets('no refresh token left: a refusal, not "not now"', (
    tester,
  ) async {
    await pumpSignedIn(tester);
    await tokens.clearTokens();

    expect(await pushRefresh!(), isFalse);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('passenger-sign-in')), findsOneWidget);
  });

  testWidgets('refused together with a booking that is refused too: one '
      'return to sign-in, no "Signing out…" left, no error', (tester) async {
    await pumpSignedIn(tester);
    api.refreshStatus = 401;
    final shell = tester.widget<PassengerShell>(find.byType(PassengerShell));

    // The booking's own refresh is refused at the same time, and its screen
    // then asks for sign-in (the booking path's onSignInRequired).
    final push = pushRefresh!();
    final booking = auth.refresh().then((state) {
      if (!state.isAuthenticated) {
        shell.onSignInRequired!();
      }
    });
    expect(await push, isFalse);
    await booking;
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('passenger-sign-in')), findsOneWidget);
    expect(find.byKey(const Key('passenger-signing-out')), findsNothing);
    expect(registrar.sessionEnds, 1, reason: 'one return to sign-in');
    expect(api.paths, isNot(contains(AuthService.logoutPath)));
  });
}

final class _Api implements AuthApiGateway {
  /// The refresh endpoint's answer: 200, 401 refused, 503 not now.
  int refreshStatus = 200;
  final paths = <String>[];

  @override
  Future<ApiResponse<Map<String, Object?>>> post(
    String path, {
    required Map<String, Object?> body,
  }) async {
    paths.add(path);
    if (path == AuthService.refreshPath && refreshStatus != 200) {
      return ApiResponse<Map<String, Object?>>.apiFailure(
        AsmApiException(
          type: refreshStatus == 401
              ? AsmApiExceptionType.authentication
              : AsmApiExceptionType.server,
          message: 'refresh $refreshStatus',
          statusCode: refreshStatus,
        ),
      );
    }
    return ApiResponse<Map<String, Object?>>.success(<String, Object?>{
      'access': 'a',
      'refresh': 'r',
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
  String? get deviceToken => null;

  @override
  Future<bool> registerForAuthenticatedSession() async => true;

  @override
  Future<bool> requestNotificationPermission() async => true;

  /// Each return to sign-in ends the push session once.
  int sessionEnds = 0;

  @override
  void endAuthenticatedSession() => sessionEnds += 1;

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
