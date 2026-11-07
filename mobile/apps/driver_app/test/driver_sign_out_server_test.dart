import 'dart:async';

import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_auth/asm_auth.dart';
import 'package:driver_app/driver_duty_trips.dart';
import 'package:driver_app/main.dart';
import 'package:driver_app/notifications/push_device_registration.dart';
import 'package:driver_app/notifications/push_notification_runtime.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Sign-in build A3: the driver app signs out through the server (A1), shows
// the server's words on 409 active_trip and stays signed in, keeps a failed
// sign-out pending, sends pending sign-outs at start only when no one is
// signed in, and after a new sign-in sends them before Work loads duty.

const _activeTripText =
    'You have an active trip. Call dispatch before signing out.';

void main() {
  late List<String> events;
  late _AuthApi api;
  late MemoryAuthTokenStore tokens;
  late MemoryPendingSignOutStore pending;
  late _Duty duty;

  setUp(() {
    events = <String>[];
    api = _AuthApi(events);
    tokens = MemoryAuthTokenStore();
    pending = MemoryPendingSignOutStore();
    duty = _Duty(events);
  });

  Widget app() => DriverApp(
    showLoginShell: true,
    authService: AuthService(
      apiGateway: api,
      tokenStore: tokens,
      appContext: AuthAppContext.driver,
      pendingSignOutStore: pending,
      installationIdStore: MemoryInstallationIdStore('install-1'),
    ),
    authTokenStore: tokens,
    driverDutyGateway: duty,
    pushDeviceRegistrarFactory: (_) => _Registrar(),
    pushMessageSource: _NoPushes(),
  );

  Future<void> signIn(WidgetTester tester) async {
    await tester.enterText(
      find.byKey(const Key('driver-phone-field')),
      '+233000000001',
    );
    await tester.enterText(find.byKey(const Key('driver-pin-field')), '9876');
    await tester.tap(find.byKey(const Key('driver-sign-in')));
    await tester.pumpAndSettle();
  }

  Future<void> tapSignOut(WidgetTester tester) async {
    await tester.tap(find.text('Account'));
    await tester.pumpAndSettle();
    final button = find.byKey(const Key('driver-account-sign-out'));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
  }

  testWidgets('Sign out tells the server, then shows sign-in', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await signIn(tester);

    await tapSignOut(tester);
    await tester.pumpAndSettle();

    expect(api.logouts.single, {
      'refresh': 'driver-refresh',
      'device_token': 'fcm-1',
      'installation_id': 'install-1',
    });
    expect(find.byKey(const Key('driver-sign-in')), findsOneWidget);
    expect(await tokens.readRefreshToken(), isNull);
    expect(await pending.read(), isEmpty);
  });

  testWidgets('while the server is asked, "Signing out…" is shown', (
    tester,
  ) async {
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
    expect(find.byKey(const Key('driver-sign-in')), findsOneWidget);
  });

  testWidgets('409 active_trip: the server words, and still signed in', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await signIn(tester);
    api.logoutAnswer = () async => ApiResponse.apiFailure(
      const AsmApiException(
        type: AsmApiExceptionType.badResponse,
        message: 'conflict',
        statusCode: 409,
        cause: {'detail': _activeTripText, 'code': 'active_trip'},
      ),
    );
    final dutyLoadsBefore = duty.fetches;

    await tapSignOut(tester);
    await tester.pumpAndSettle();

    expect(find.text(_activeTripText), findsOneWidget);
    await tester.tap(find.byKey(const Key('driver-sign-out-refused-ok')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('driver-sign-in')), findsNothing);
    expect(await tokens.readRefreshToken(), 'driver-refresh');
    expect(await pending.read(), isEmpty);
    expect(duty.fetches, greaterThan(dutyLoadsBefore));
  });

  testWidgets('no answer: signed out on the phone, sign-out kept pending', (
    tester,
  ) async {
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

    expect(find.byKey(const Key('driver-sign-in')), findsOneWidget);
    expect(await tokens.readRefreshToken(), isNull);
    expect((await pending.read()).single.refresh, 'driver-refresh');
  });

  testWidgets('app start, no one signed in: pending sign-outs are sent', (
    tester,
  ) async {
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

  testWidgets('after a new sign-in the pending sign-out goes before Work '
      'loads duty, then is gone', (tester) async {
    api.logoutAnswer = () async => ApiResponse.clientException(
      const AsmApiException(
        type: AsmApiExceptionType.network,
        message: 'no network',
      ),
    );
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await pending.write([
      PendingSignOut(refresh: 'refresh-old', createdAt: DateTime.now()),
    ]);
    events.clear();

    await signIn(tester);

    expect(events.take(3), ['sign-in', 'logout refresh-old', 'duty']);
    expect(await pending.read(), isEmpty);
  });
}

ApiResponse<Map<String, Object?>> _signedOut() => ApiResponse.success(
  <String, Object?>{'detail': 'Signed out.'},
  statusCode: 200,
);

final class _AuthApi implements AuthApiGateway {
  _AuthApi(this.events);

  final List<String> events;
  final logouts = <Map<String, Object?>>[];
  Future<ApiResponse<Map<String, Object?>>> Function()? logoutAnswer;

  @override
  Future<ApiResponse<Map<String, Object?>>> post(
    String path, {
    required Map<String, Object?> body,
  }) async {
    if (path == AuthService.logoutPath) {
      logouts.add(Map.of(body));
      events.add('logout ${body['refresh']}');
      return (logoutAnswer ?? () async => _signedOut())();
    }
    events.add('sign-in');
    return ApiResponse<Map<String, Object?>>.success(<String, Object?>{
      'access': 'driver-access',
      'refresh': 'driver-refresh',
      'account_type': 'driver',
      'account': <String, Object?>{},
    }, statusCode: 200);
  }
}

final class _Duty implements DriverDutyGateway {
  _Duty(this.events);

  final List<String> events;
  int fetches = 0;

  @override
  Future<DriverDutySummary> fetchDuty() async {
    fetches += 1;
    events.add('duty');
    return DriverDutySummary(
      driverReference: 'DRV-1',
      dutyStatus: 'online',
      dutySince: DateTime(2026, 11, 7, 8),
      shiftCheckToday: true,
      canReceiveAssignments: true,
    );
  }

  @override
  Future<List<DriverAssignedTrip>> fetchTrips() async =>
      const <DriverAssignedTrip>[];

  @override
  Future<DriverAssignedTrip> fetchTripDetail(String tripReference) async =>
      throw const DriverDutyApiException(
        DriverDutyApiFailureType.notFound,
        'not found',
      );
}

final class _Registrar implements PushDeviceRegistrar {
  @override
  String? get deviceToken => 'fcm-1';

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
