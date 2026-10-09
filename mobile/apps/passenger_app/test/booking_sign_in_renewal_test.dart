import 'dart:convert';

import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_app_config/asm_app_config.dart';
import 'package:asm_auth/asm_auth.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:asm_maps/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passenger_app/booking/booking_draft.dart';
import 'package:passenger_app/booking/booking_page.dart';
import 'package:passenger_app/booking/booking_submission.dart';
import 'package:passenger_app/main.dart';
import 'package:passenger_app/passenger_home.dart';
import 'package:passenger_app/passenger_shell.dart';
import 'package:passenger_app/ride_requests/ride_request_history.dart';

// Before booking, a sign-in that ends within 2 hours is renewed first, so
// it does not end in the middle of the ride.
void main() {
  const warning =
      "Your sign-in ends soon. Sign in again now so it doesn't stop you "
      'mid-trip.';

  Future<void> reviewAndConfirm(WidgetTester tester) async {
    await tester.enterText(find.byKey(const Key('booking-pickup')), 'Osu');
    await tester.enterText(
      find.byKey(const Key('booking-destination')),
      'Airport',
    );
    await _tapVisible(tester, const Key('request-ride'));
    await tester.pumpAndSettle();
    await _tapVisible(tester, const Key('confirm-and-request'));
    await tester.pumpAndSettle();
  }

  group('on the booking page', () {
    Future<_Submitter> pump(
      WidgetTester tester,
      Duration? left, {
      VoidCallback? onSignInRequired,
    }) async {
      _useSurface(tester);
      final submitter = _Submitter();
      await tester.pumpWidget(
        MaterialApp(
          theme: AsmThemes.passenger,
          home: BookingPage(
            market: MarketConfig.ghanaAccra,
            rideRequestSubmitter: submitter,
            onSignInRequired: onSignInRequired,
            signInTimeLeft: () async => left,
          ),
        ),
      );
      return submitter;
    }

    testWidgets('90 minutes left: asked first; Continue books', (tester) async {
      final submitter = await pump(tester, const Duration(minutes: 90));
      await reviewAndConfirm(tester);

      expect(find.text(warning), findsOneWidget);
      expect(submitter.submissions, 0);

      await tester.tap(find.byKey(const Key('booking-renew-sign-in-later')));
      await tester.pumpAndSettle();
      expect(find.text(warning), findsNothing);
      expect(submitter.submissions, 1);
    });

    testWidgets('90 minutes left: Sign in again goes to sign in, no booking', (
      tester,
    ) async {
      var signIns = 0;
      final submitter = await pump(
        tester,
        const Duration(minutes: 90),
        onSignInRequired: () => signIns += 1,
      );
      await reviewAndConfirm(tester);

      await tester.tap(find.byKey(const Key('booking-renew-sign-in-now')));
      await tester.pumpAndSettle();
      expect(signIns, 1);
      expect(submitter.submissions, 0);
    });

    testWidgets('exactly 2 hours left: asked', (tester) async {
      final submitter = await pump(tester, const Duration(hours: 2));
      await reviewAndConfirm(tester);

      expect(find.text(warning), findsOneWidget);
      expect(submitter.submissions, 0);
    });

    for (final left in <Duration?>[const Duration(minutes: 121), null]) {
      testWidgets('${left?.inMinutes ?? 'unreadable'} minutes left: books '
          'without asking', (tester) async {
        final submitter = await pump(tester, left);
        await reviewAndConfirm(tester);

        expect(find.text(warning), findsNothing);
        expect(submitter.submissions, 1);
      });
    }
  });

  group('every way into booking passes it on', () {
    Future<_Submitter> pumpShell(
      WidgetTester tester,
      PassengerRideRequestHistoryRepository history,
    ) async {
      _useSurface(tester);
      final submitter = _Submitter();
      await tester.pumpWidget(
        MaterialApp(
          theme: AsmThemes.passenger,
          home: PassengerShell(
            rideRequestHistoryRepository: history,
            rideRequestSubmitter: submitter,
            signInTimeLeft: () async => const Duration(minutes: 90),
          ),
        ),
      );
      await tester.pumpAndSettle();
      tester
          .widget<AsmBottomNavigationBar>(find.byType(AsmBottomNavigationBar))
          .onDestinationSelected!
          .call(1);
      await tester.pumpAndSettle();
      return submitter;
    }

    for (final key in ['history-card-book-again', 'history-card-return']) {
      testWidgets('My Ride Requests, $key', (tester) async {
        final submitter = await pumpShell(tester, _History(_completed()));
        await tester.tap(find.byKey(Key(key)));
        await tester.pumpAndSettle();
        await _tapVisible(tester, const Key('request-ride'));
        await tester.pumpAndSettle();
        await _tapVisible(tester, const Key('confirm-and-request'));
        await tester.pumpAndSettle();

        expect(find.text(warning), findsOneWidget);
        expect(submitter.submissions, 0);
      });
    }

    testWidgets('Book again on a refused request, after a booking', (
      tester,
    ) async {
      _useSurface(tester);
      var left = const Duration(hours: 5);
      final submitter = _Submitter();
      await tester.pumpWidget(
        MaterialApp(
          theme: AsmThemes.passenger,
          home: BookingPage(
            market: MarketConfig.ghanaAccra,
            rideRequestSubmitter: submitter,
            rideRequestHistoryRepository: _History(_rejected()),
            signInTimeLeft: () async => left,
          ),
        ),
      );
      await reviewAndConfirm(tester);
      expect(submitter.submissions, 1);
      await _settle(tester);
      expect(find.byKey(const Key('request-rejected-state')), findsOneWidget);

      left = const Duration(minutes: 90);
      await tester.tap(find.byKey(const Key('rejected-book-again')));
      await _settle(tester);
      await _tapVisible(tester, const Key('request-ride'));
      await tester.pumpAndSettle();
      await _tapVisible(tester, const Key('confirm-and-request'));
      await tester.pumpAndSettle();

      expect(find.text(warning), findsOneWidget);
      expect(submitter.submissions, 1);
    });
  });

  testWidgets('through the app: the stored sign-in\'s own expiry is read', (
    tester,
  ) async {
    _useSurface(tester);
    final store = MemoryAuthTokenStore();
    await store.saveTokens(
      AuthTokens(
        accessToken: 'stored-access',
        refreshToken: _jwt(DateTime.now().add(const Duration(minutes: 90))),
      ),
    );
    final submitter = _Submitter();
    await tester.pumpWidget(
      PassengerApp(
        showLoginShell: true,
        rideRequestSubmitter: submitter,
        authTokenStore: store,
        authService: AuthService(
          apiGateway: _Unreachable(),
          tokenStore: store,
          appContext: AuthAppContext.passenger,
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
    await reviewAndConfirm(tester);

    expect(find.text(warning), findsOneWidget);
    expect(submitter.submissions, 0);
  });
}

String _jwt(DateTime expiresAt) {
  String part(Map<String, Object?> json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  return '${part({'alg': 'HS256'})}.'
      '${part({'exp': expiresAt.millisecondsSinceEpoch ~/ 1000})}.sig';
}

PassengerRideRequestRecord _completed() => PassengerRideRequestRecord(
  requestReference: 'RR-APP-RENEW-DONE',
  status: 'completed_confirmed',
  pickupLocation: 'Accra Mall',
  destination: 'University of Ghana',
  passengerCount: 1,
  createdAt: DateTime.utc(2026, 10, 9, 8),
  updatedAt: DateTime.utc(2026, 10, 9, 9),
  hasMobileReceipt: true,
  tripCreated: true,
);

PassengerRideRequestRecord _rejected() => PassengerRideRequestRecord(
  requestReference: 'RR-APP-3A9F1C2B4E5D',
  status: 'rejected',
  pickupLocation: 'Osu',
  destination: 'Airport',
  passengerCount: 1,
  createdAt: DateTime.utc(2026, 10, 9, 8),
  updatedAt: DateTime.utc(2026, 10, 9, 8),
  hasMobileReceipt: true,
  tripCreated: false,
  controlCenterMessage: 'Your request could not be accepted.',
);

void _useSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(430, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _settle(WidgetTester tester) async {
  for (var frame = 0; frame < 10; frame += 1) {
    await tester.pump(const Duration(milliseconds: 100));
  }
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

final class _Submitter implements PassengerRideRequestSubmitter {
  var submissions = 0;

  @override
  Future<PassengerRideRequestResult> submit(
    BookingDraft draft, {
    required String idempotencyKey,
  }) async {
    submissions += 1;
    return const PassengerRideRequestResult(
      requestReference: 'RR-APP-3A9F1C2B4E5D',
      status: 'requested',
      message: 'Your ride request was received.',
    );
  }
}

final class _History implements PassengerRideRequestHistoryRepository {
  const _History(this.record);

  final PassengerRideRequestRecord record;

  @override
  Future<List<PassengerRideRequestRecord>> fetchRequests() async => [record];

  @override
  Future<PassengerRideRequestRecord> fetchRequest(String reference) async =>
      record;
}

final class _Unreachable implements AuthApiGateway {
  @override
  Future<ApiResponse<Map<String, Object?>>> post(
    String path, {
    required Map<String, Object?> body,
  }) async => ApiResponse.clientException(
    const AsmApiException(
      type: AsmApiExceptionType.network,
      message: 'The API request could not reach the network.',
    ),
  );
}
