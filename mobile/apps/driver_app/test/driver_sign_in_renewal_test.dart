import 'dart:convert';

import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_auth/asm_auth.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:driver_app/driver_duty_trips.dart';
import 'package:driver_app/driver_home.dart';
import 'package:driver_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// At the shift check, a sign-in that ends within 12 hours is renewed first,
// so it does not end in the middle of a trip.
void main() {
  const warning =
      "Your sign-in ends soon. Sign in again now so it doesn't stop you "
      'mid-trip.';
  final now = DateTime(2026, 10, 9, 7);

  Future<int> pump(WidgetTester tester, Duration? left) async {
    var signOuts = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.driver,
        home: DriverShell(
          driverDutyGateway: _OfflineNoCheck(now),
          deviceNow: () => now,
          signInTimeLeft: () async => left,
          onSignOut: () async {
            signOuts += 1;
            return true;
          },
        ),
      ),
    );
    for (var i = 0; i < 6; i += 1) {
      await tester.pump();
    }
    return signOuts;
  }

  testWidgets('11 hours left: asked first; Later goes on to the shift check', (
    tester,
  ) async {
    await pump(tester, const Duration(hours: 11));

    expect(find.text(warning), findsOneWidget);
    // Lead, 7 Nov: signing in again takes the driver offline; say so.
    expect(find.text(driverSignInAgainGoesOfflineNote), findsOneWidget);
    expect(
      find.byKey(const Key('driver-shift-readiness-screen')),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('driver-renew-sign-in-later')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('driver-shift-readiness-screen')),
      findsOneWidget,
    );
  });

  testWidgets('11 hours left: Sign in again signs out instead', (tester) async {
    var signOuts = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.driver,
        home: DriverShell(
          driverDutyGateway: _OfflineNoCheck(now),
          deviceNow: () => now,
          signInTimeLeft: () async => const Duration(hours: 11),
          onSignOut: () async {
            signOuts += 1;
            return true;
          },
        ),
      ),
    );
    for (var i = 0; i < 6; i += 1) {
      await tester.pump();
    }

    await tester.tap(find.byKey(const Key('driver-renew-sign-in-now')));
    await tester.pumpAndSettle();
    expect(signOuts, 1);
    expect(
      find.byKey(const Key('driver-shift-readiness-screen')),
      findsNothing,
    );
  });

  for (final left in <Duration?>[const Duration(hours: 13), null]) {
    testWidgets('${left?.inHours ?? 'unknown'} hours left: straight to the '
        'shift check', (tester) async {
      await pump(tester, left);
      expect(find.text(warning), findsNothing);
      expect(
        find.byKey(const Key('driver-shift-readiness-screen')),
        findsOneWidget,
      );
    });
  }

  testWidgets('through the app: the stored sign-in\'s own expiry is read', (
    tester,
  ) async {
    final tokens = MemoryAuthTokenStore();
    final ends = DateTime.now().add(const Duration(hours: 11));
    await tester.pumpWidget(
      DriverApp(
        showLoginShell: true,
        authService: AuthService(
          apiGateway: _LoginApi(_jwt(ends)),
          tokenStore: tokens,
          appContext: AuthAppContext.driver,
        ),
        authTokenStore: tokens,
        driverDutyGateway: _OfflineNoCheck(DateTime.now()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('driver-phone-field')),
      '+233000000001',
    );
    await tester.enterText(find.byKey(const Key('driver-pin-field')), '9876');
    await tester.tap(find.byKey(const Key('driver-sign-in')));
    for (var i = 0; i < 10; i += 1) {
      await tester.pump();
    }

    expect(find.text(warning), findsOneWidget);
  });
}

String _jwt(DateTime expiresAt) {
  String part(Map<String, Object?> json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  return '${part({'alg': 'HS256'})}.'
      '${part({'exp': expiresAt.millisecondsSinceEpoch ~/ 1000})}.sig';
}

final class _LoginApi implements AuthApiGateway {
  _LoginApi(this.refresh);

  final String refresh;

  @override
  Future<ApiResponse<Map<String, Object?>>> post(
    String path, {
    required Map<String, Object?> body,
  }) async => ApiResponse<Map<String, Object?>>.success(<String, Object?>{
    'access': 'driver-access',
    'refresh': refresh,
    'account_type': 'driver',
    'account': <String, Object?>{},
  }, statusCode: 200);
}

final class _OfflineNoCheck implements DriverDutyGateway {
  _OfflineNoCheck(this.now);

  final DateTime now;

  @override
  Future<DriverDutySummary> fetchDuty() async => DriverDutySummary(
    dutyStatus: 'offline',
    dutySince: now.subtract(const Duration(days: 1)),
    shiftCheckToday: false,
  );

  @override
  Future<List<DriverAssignedTrip>> fetchTrips() async => const [];

  @override
  Future<DriverAssignedTrip> fetchTripDetail(String tripReference) =>
      throw UnimplementedError();
}
