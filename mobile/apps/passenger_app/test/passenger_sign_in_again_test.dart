import 'dart:convert';

import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_auth/asm_auth.dart';
import 'package:asm_maps/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passenger_app/booking/booking_draft.dart';
import 'package:passenger_app/booking/booking_submission.dart';
import 'package:passenger_app/main.dart';
import 'package:passenger_app/passenger_home.dart';

// "Sign in again" on the trip screen (the banner when the sign-in ends
// soon, then the confirm) is a sign-out the passenger asked for. Sign-in
// build A4: it goes through the server like Account's Sign out.

const _banner = Key('tracking-sign-in-ends-soon');

void main() {
  late _Api api;
  late MemoryAuthTokenStore tokens;
  late String refresh;

  setUp(() async {
    api = _Api();
    tokens = MemoryAuthTokenStore();
    refresh = _jwt(DateTime.now().add(const Duration(minutes: 90)));
    await tokens.saveTokens(
      AuthTokens(accessToken: 'stored-access', refreshToken: refresh),
    );
  });

  Future<void> bookAndOpenTheTripScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      PassengerApp(
        showLoginShell: true,
        rideRequestSubmitter: _Submitter(),
        authTokenStore: tokens,
        authService: AuthService(
          apiGateway: api,
          tokenStore: tokens,
          appContext: AuthAppContext.passenger,
          pendingSignOutStore: MemoryPendingSignOutStore(),
          installationIdStore: MemoryInstallationIdStore('install-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    tester.state<AsmFakeMapState>(find.byType(AsmFakeMap))
      ..dragTo(passengerHomePickupDefaultCenter)
      ..release();
    await tester.pump();
    await tester.tap(find.byKey(const Key('confirm-pickup')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('booking-pickup')), 'Osu');
    await tester.enterText(
      find.byKey(const Key('booking-destination')),
      'Airport',
    );
    await _tapVisible(tester, const Key('request-ride'));
    await tester.pumpAndSettle();
    await _tapVisible(tester, const Key('confirm-and-request'));
    for (var frame = 0; frame < 10; frame += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(_banner), findsOneWidget);
  }

  Future<void> signInAgain(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('tracking-sign-in-again')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tracking-sign-in-again-confirm')));
    await tester.pumpAndSettle();
  }

  testWidgets('Sign in again on the trip screen tells the server', (
    tester,
  ) async {
    await bookAndOpenTheTripScreen(tester);

    await signInAgain(tester);

    expect(api.logouts, [
      {'refresh': refresh, 'installation_id': 'install-1'},
    ]);
    expect(await tokens.readRefreshToken(), isNull);
  });
}

String _jwt(DateTime expiresAt) {
  String part(Map<String, Object?> json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  return '${part({'alg': 'HS256'})}.'
      '${part({'exp': expiresAt.millisecondsSinceEpoch ~/ 1000})}.sig';
}

Future<void> _tapVisible(WidgetTester tester, Key key) async {
  final finder = find.byKey(key);
  for (var attempt = 0; attempt < 15 && finder.evaluate().isEmpty; attempt++) {
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -220));
    await tester.pump(const Duration(milliseconds: 120));
  }
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 120));
  await tester.tap(finder, warnIfMissed: false);
  await tester.pump();
}

/// Logout answers 200 and is recorded; everything else has no network (the
/// stored sign-in is kept, as on a weak connection).
final class _Api implements AuthApiGateway {
  final logouts = <Map<String, Object?>>[];

  @override
  Future<ApiResponse<Map<String, Object?>>> post(
    String path, {
    required Map<String, Object?> body,
  }) async {
    if (path == AuthService.logoutPath) {
      logouts.add(Map.of(body));
      return ApiResponse.success(<String, Object?>{
        'detail': 'Signed out.',
      }, statusCode: 200);
    }
    return ApiResponse.clientException(
      const AsmApiException(
        type: AsmApiExceptionType.network,
        message: 'The API request could not reach the network.',
      ),
    );
  }
}

final class _Submitter implements PassengerRideRequestSubmitter {
  @override
  Future<PassengerRideRequestResult> submit(
    BookingDraft draft, {
    required String idempotencyKey,
  }) async => const PassengerRideRequestResult(
    requestReference: 'RR-APP-3A9F1C2B4E5D',
    status: 'requested',
    message: 'Your ride request was received.',
  );
}
