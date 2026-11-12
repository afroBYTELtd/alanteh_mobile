import 'dart:async';

import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_auth/asm_auth.dart';
import 'package:driver_app/driver_duty_trips.dart';
import 'package:driver_app/main.dart';
import 'package:driver_app/network/ghana_network_resilience.dart';
import 'package:driver_app/notifications/push_device_registration.dart';
import 'package:driver_app/notifications/push_notification_runtime.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// T2b (lead, 12 Nov): when push registration is the first to find a
// REFUSED session, the driver goes to the sign-in screen at once; "not
// now" keeps the sign-in. Built from the 12 Nov probe, with the real
// DriverSessionRefreshController behind the shared refresh.
void main() {
  late MemoryAuthTokenStore tokens;
  late _RefreshEndpoint refreshEndpoint;
  late _Duty duty;
  late _Routes routes;
  PushSessionRefresh? pushRefresh;
  PushDeviceRegistrar Function(PushSessionRefresh? refresh)? makeRegistrar;

  setUp(() {
    makeRegistrar = null;
    tokens = MemoryAuthTokenStore();
    refreshEndpoint = _RefreshEndpoint();
    duty = _Duty();
    routes = _Routes();
    pushRefresh = null;
  });

  Future<void> pumpSignedIn(WidgetTester tester) async {
    final controller = DriverSessionRefreshController(
      apiGateway: refreshEndpoint,
      tokenStore: tokens,
      retryPolicy: GhanaRetryPolicy(delay: (_) async {}),
    );
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [routes],
        home: DriverLoginShell(
          authService: AuthService(
            apiGateway: _SignIn(),
            tokenStore: tokens,
            appContext: AuthAppContext.driver,
          ),
          authTokenStore: tokens,
          driverDutyGateway: duty,
          accessTokenRefresh: controller.refresh,
          pushDeviceRegistrarFactory: (_, {refreshSession}) {
            pushRefresh = refreshSession;
            return makeRegistrar?.call(refreshSession) ?? _Registrar();
          },
          pushMessageSource: _NoPushes(),
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
    expect(find.byKey(const Key('driver-sign-in')), findsNothing);
    routes.reset();
  }

  testWidgets('refused: the sign-in screen at once, with the message', (
    tester,
  ) async {
    await pumpSignedIn(tester);
    refreshEndpoint.status = 401;

    expect(await pushRefresh!(), isFalse);
    await tester.pumpAndSettle();

    expect(await tokens.readRefreshToken(), isNull);
    expect(find.byKey(const Key('driver-sign-in')), findsOneWidget);
    expect(find.text(driverSessionExpiredMessage), findsOneWidget);
  });

  testWidgets('not now (503): still signed in, tokens kept', (tester) async {
    await pumpSignedIn(tester);
    refreshEndpoint.status = 503;

    expect(await pushRefresh!(), isFalse);
    await tester.pumpAndSettle();

    expect(await tokens.readRefreshToken(), 'r');
    expect(find.byKey(const Key('driver-sign-in')), findsNothing);
  });

  testWidgets('refused together with a duty load that ends the session: '
      'one sign-in screen, no other navigation, no error', (tester) async {
    await pumpSignedIn(tester);
    refreshEndpoint.status = 401;
    duty.expired = true;

    final push = pushRefresh!();
    for (final state in const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    expect(await push, isFalse);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(duty.expiredAnswers, greaterThan(0), reason: 'Work reloaded');
    expect(find.byKey(const Key('driver-sign-in')), findsOneWidget);
    expect(find.text(driverSessionExpiredMessage), findsOneWidget);
    expect(routes.pushes, 0);
    expect(routes.pops, 0);
  });

  // T2c (lead, 12 Nov): a deliberate sign-out while the registration post
  // is out; its 401 then comes back. No second end of the session.
  testWidgets('T2c: a deliberate sign-out while a registration is out, '
      'then its 401: no "session expired", no error, one session end', (
    tester,
  ) async {
    final gateway = _GatedPushGateway();
    late _CountingRegistrar registrar;
    makeRegistrar = (refresh) => registrar = _CountingRegistrar(
      FirebasePushDeviceRegistrar(
        tokenSource: _FcmToken(),
        apiGateway: gateway,
        refreshSession: refresh,
      ),
    );
    await pumpSignedIn(tester);
    expect(gateway.posts, 1, reason: 'the registration is out');

    await tester.tap(find.text('Account'));
    await tester.pumpAndSettle();
    final signOut = find.byKey(const Key('driver-account-sign-out'));
    await tester.ensureVisible(signOut);
    await tester.pumpAndSettle();
    await tester.tap(signOut);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('driver-sign-in')), findsOneWidget);
    final endsAfterSignOut = registrar.sessionEnds;

    gateway.answer.complete();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('driver-sign-in')), findsOneWidget);
    expect(find.text(driverSessionExpiredMessage), findsNothing);
    expect(registrar.sessionEnds, endsAfterSignOut);
    expect(gateway.posts, 1);
  });
}

final class _SignIn implements AuthApiGateway {
  @override
  Future<ApiResponse<Map<String, Object?>>> post(
    String path, {
    required Map<String, Object?> body,
  }) async => ApiResponse<Map<String, Object?>>.success(<String, Object?>{
    'access': 'a',
    'refresh': 'r',
    'account_type': 'driver',
    'account': <String, Object?>{},
  }, statusCode: 200);
}

/// The refresh endpoint: answers [status] (401 refused, 503 not now).
final class _RefreshEndpoint implements DriverSessionRefreshApiGateway {
  int status = 401;

  @override
  Future<ApiResponse<T>> post<T>(
    String path, {
    required Map<String, Object?> body,
    JsonDecoder<T>? decoder,
  }) async => ApiResponse<T>.apiFailure(
    AsmApiException(
      type: status == 401
          ? AsmApiExceptionType.authentication
          : AsmApiExceptionType.server,
      message: 'refresh $status',
      statusCode: status,
    ),
  );
}

/// Online with today's check; once [expired], the duty load says the
/// session ended.
final class _Duty implements DriverDutyGateway {
  bool expired = false;
  var expiredAnswers = 0;

  @override
  Future<DriverDutySummary> fetchDuty() async {
    if (expired) {
      expiredAnswers += 1;
      throw const DriverDutyApiException(
        DriverDutyApiFailureType.sessionExpired,
        driverSessionExpiredMessage,
      );
    }
    return DriverDutySummary(
      driverReference: 'DRV-1',
      dutyStatus: 'online',
      dutySince: DateTime(2026, 11, 12, 8),
      shiftCheckToday: true,
    );
  }

  @override
  Future<List<DriverAssignedTrip>> fetchTrips() async => const [];

  @override
  Future<DriverAssignedTrip> fetchTripDetail(String tripReference) =>
      throw UnimplementedError();
}

final class _Routes extends NavigatorObserver {
  var pushes = 0;
  var pops = 0;

  void reset() {
    pushes = 0;
    pops = 0;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      pushes += 1;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => pops += 1;
}

final class _Registrar implements PushDeviceRegistrar {
  @override
  String? get deviceToken => null;

  @override
  Future<bool> registerForAuthenticatedSession() async => true;

  @override
  Future<bool> requestNotificationPermission() async => true;

  @override
  void endAuthenticatedSession() {}

  @override
  Future<void> dispose() async {}
}

final class _NoPushes implements DriverPushMessageSource {
  @override
  Stream<RemoteMessage> get foregroundMessages =>
      const Stream<RemoteMessage>.empty();

  @override
  Stream<RemoteMessage> get openedMessages =>
      const Stream<RemoteMessage>.empty();

  @override
  Future<RemoteMessage?> getInitialMessage() async => null;
}

/// T2c: a real registrar whose first registration post waits for
/// [answer] and then says 401.
final class _GatedPushGateway implements PushDeviceRegistrationApiGateway {
  final answer = Completer<void>();
  var posts = 0;

  @override
  Future<ApiResponse<Map<String, Object?>>> post(
    String path, {
    required Map<String, Object?> data,
  }) async {
    posts += 1;
    await answer.future;
    return ApiResponse<Map<String, Object?>>.apiFailure(
      const AsmApiException(
        type: AsmApiExceptionType.authentication,
        message: 'Unauthenticated.',
        statusCode: 401,
      ),
    );
  }
}

final class _FcmToken implements PushMessagingTokenSource {
  @override
  Future<String?> getToken() async => 'FCM-T2C';

  @override
  Stream<String> get onTokenRefresh => const Stream<String>.empty();

  @override
  Future<bool> requestNotificationPermission() async => true;
}

/// Counts the session ends of the real registrar it wraps.
final class _CountingRegistrar implements PushDeviceRegistrar {
  _CountingRegistrar(this.inner);

  final PushDeviceRegistrar inner;
  var sessionEnds = 0;

  @override
  String? get deviceToken => inner.deviceToken;

  @override
  Future<bool> registerForAuthenticatedSession() =>
      inner.registerForAuthenticatedSession();

  @override
  Future<bool> requestNotificationPermission() =>
      inner.requestNotificationPermission();

  @override
  void endAuthenticatedSession() {
    sessionEnds += 1;
    inner.endAuthenticatedSession();
  }

  @override
  Future<void> dispose() => inner.dispose();
}
