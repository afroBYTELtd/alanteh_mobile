import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_auth/asm_auth.dart';
import 'package:driver_app/driver_duty_trips.dart';
import 'package:driver_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// A "Session expired" panel used to offer only Refresh, which cannot work
// once the tokens are gone. It now offers Sign in.
void main() {
  const expired = DriverDutyApiException(
    DriverDutyApiFailureType.sessionExpired,
    driverSessionExpiredMessage,
  );

  group('the three panels', () {
    var signIns = 0;

    setUp(() {
      signIns = 0;
      DriverSessionEnd.signIn = () async => signIns += 1;
    });
    tearDown(() => DriverSessionEnd.signIn = null);

    final screens = <String, Widget Function()>{
      'trips list': () => DriverAssignedTripsScreen(gateway: _Expired(expired)),
      'trip detail': () => DriverTripDetailScreen(
        gateway: _Expired(expired),
        tripReference: 'TRIP-1',
      ),
      // (Work's duty summary panel no longer fetches: it shows the shell's
      // summary, B9.)
    };

    for (final entry in screens.entries) {
      testWidgets('${entry.key}: Sign in, not Refresh', (tester) async {
        await tester.pumpWidget(MaterialApp(home: entry.value()));
        await tester.pumpAndSettle();

        expect(find.text(driverSessionExpiredMessage), findsOneWidget);
        expect(find.byKey(const Key('driver-session-sign-in')), findsOneWidget);
        expect(find.text('Refresh'), findsNothing);

        await tester.tap(find.byKey(const Key('driver-session-sign-in')));
        await tester.pump();
        expect(signIns, 1);
      });
    }
  });

  testWidgets('through the app: Sign in goes to the sign-in screen and clears '
      'the session', (tester) async {
    final tokens = MemoryAuthTokenStore();
    await tester.pumpWidget(
      DriverApp(
        showLoginShell: true,
        authService: AuthService(
          apiGateway: _LoginApi(),
          tokenStore: tokens,
          appContext: AuthAppContext.driver,
        ),
        authTokenStore: tokens,
        driverDutyGateway: _Expired(expired, dutyWorks: true),
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
    expect(await tokens.readRefreshToken(), 'driver-refresh');

    await tester.tap(find.text('Trips'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('driver-session-sign-in')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('driver-sign-in')), findsOneWidget);
    expect(find.text(driverSessionExpiredMessage), findsOneWidget);
    expect(await tokens.readRefreshToken(), isNull);
  });

  // Lead, 24 Oct (checklist item 17): a sign-out closes every pushed
  // screen. On the driver app the only way to sign in again from a pushed
  // screen is an ended session (Sign out is on Work and Account); this pins
  // that it leaves only the sign-in screen and Back leaves the app.
  testWidgets('through the app: Sign in from a pushed trip screen leaves only '
      'the sign-in screen; Back leaves the app', (tester) async {
    final tokens = MemoryAuthTokenStore();
    final platformCalls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        platformCalls.add(call.method);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      DriverApp(
        showLoginShell: true,
        authService: AuthService(
          apiGateway: _LoginApi(),
          tokenStore: tokens,
          appContext: AuthAppContext.driver,
        ),
        authTokenStore: tokens,
        driverDutyGateway: _TripThenExpired(),
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
    await tester.tap(find.text('Trips'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Near Accra Mall'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('driver-trip-detail-session-expired')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('driver-session-sign-in')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('driver-sign-in')), findsOneWidget);
    expect(
      find.byKey(const Key('driver-trip-detail-session-expired')),
      findsNothing,
    );
    expect(
      tester.state<NavigatorState>(find.byType(Navigator).first).canPop(),
      isFalse,
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(platformCalls, contains('SystemNavigator.pop'));
  });

  testWidgets('the app sets Sign in while it is shown and clears it after', (
    tester,
  ) async {
    final tokens = MemoryAuthTokenStore();
    await tester.pumpWidget(
      DriverApp(
        showLoginShell: true,
        authService: AuthService(
          apiGateway: _LoginApi(),
          tokenStore: tokens,
          appContext: AuthAppContext.driver,
        ),
        authTokenStore: tokens,
        driverDutyGateway: _Expired(expired, dutyWorks: true),
      ),
    );
    await tester.pumpAndSettle();
    expect(DriverSessionEnd.signIn, isNotNull);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(DriverSessionEnd.signIn, isNull);
  });
}

final class _Expired implements DriverDutyGateway {
  _Expired(this.error, {this.dutyWorks = false});

  final DriverDutyApiException error;
  final bool dutyWorks;

  @override
  Future<DriverDutySummary> fetchDuty() async {
    if (dutyWorks) {
      return DriverDutySummary(
        driverReference: 'DRV-1',
        dutyStatus: 'online',
        dutySince: DateTime(2026, 10, 9, 8),
        shiftCheckToday: true,
        canReceiveAssignments: true,
      );
    }
    throw error;
  }

  @override
  Future<List<DriverAssignedTrip>> fetchTrips() async => throw error;

  @override
  Future<DriverAssignedTrip> fetchTripDetail(String tripReference) async =>
      throw error;
}

final class _LoginApi implements AuthApiGateway {
  @override
  Future<ApiResponse<Map<String, Object?>>> post(
    String path, {
    required Map<String, Object?> body,
  }) async => ApiResponse<Map<String, Object?>>.success(<String, Object?>{
    'access': 'driver-access',
    'refresh': 'driver-refresh',
    'account_type': 'driver',
    'account': <String, Object?>{},
  }, statusCode: 200);
}

/// Work loads; the Trips list has one trip; its detail answers 401.
final class _TripThenExpired implements DriverDutyGateway {
  static const _expired = DriverDutyApiException(
    DriverDutyApiFailureType.sessionExpired,
    driverSessionExpiredMessage,
  );

  @override
  Future<DriverDutySummary> fetchDuty() async => DriverDutySummary(
    driverReference: 'DRV-1',
    dutyStatus: 'online',
    dutySince: DateTime(2026, 10, 9, 8),
    shiftCheckToday: true,
    canReceiveAssignments: true,
  );

  @override
  Future<List<DriverAssignedTrip>> fetchTrips() async => const [
    DriverAssignedTrip(
      reference: 'TRIP-ITEM17-1',
      status: 'assigned',
      pickupLocation: 'Near Accra Mall',
      destination: 'Airport, Terminal 3',
    ),
  ];

  @override
  Future<DriverAssignedTrip> fetchTripDetail(String tripReference) async =>
      throw _expired;
}
