import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_auth/asm_auth.dart';
import 'package:driver_app/driver_duty_trips.dart';
import 'package:driver_app/main.dart';
import 'package:flutter/material.dart';
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
      'duty summary': () =>
          Scaffold(body: DriverDutySummaryPanel(gateway: _Expired(expired))),
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
