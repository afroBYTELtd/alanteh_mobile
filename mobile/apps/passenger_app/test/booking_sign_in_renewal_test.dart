import 'dart:async';
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

// A sign-in that ends within 2 hours is flagged after the booking, as a
// banner on the trip screen with "Sign in again", so it does not end in the
// middle of the ride. It used to be a dialog between Confirm and the
// booking, which held the booking until answered (phone session 23 Oct).
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

  const banner = Key('tracking-sign-in-ends-soon');

  group('on the booking page', () {
    Future<_Submitter> pump(
      WidgetTester tester,
      Duration? left, {
      VoidCallback? onSignInRequired,
      _Submitter? submitter,
    }) async {
      _useSurface(tester);
      final sending = submitter ?? _Submitter();
      await tester.pumpWidget(
        MaterialApp(
          theme: AsmThemes.passenger,
          home: BookingPage(
            market: MarketConfig.ghanaAccra,
            rideRequestSubmitter: sending,
            rideRequestHistoryRepository: _History(_requested()),
            onSignInRequired: onSignInRequired,
            signInTimeLeft: () async => left,
          ),
        ),
      );
      return sending;
    }

    testWidgets('90 minutes left: Confirm books at once, then the trip '
        'screen shows the banner', (tester) async {
      final submitter = await pump(tester, const Duration(minutes: 90));
      await reviewAndConfirm(tester);

      expect(submitter.submissions, 1);
      expect(find.byType(AlertDialog), findsNothing);
      await _settle(tester);
      expect(find.byKey(banner), findsOneWidget);
      expect(find.text(warning), findsOneWidget);
      expect(find.byKey(const Key('tracking-bottom-sheet')), findsOneWidget);
    });

    testWidgets('nothing waits for the sign-in check: a slow one does not '
        'hold the booking', (tester) async {
      _useSurface(tester);
      final submitter = _Submitter();
      final check = Completer<Duration?>();
      await tester.pumpWidget(
        MaterialApp(
          theme: AsmThemes.passenger,
          home: BookingPage(
            market: MarketConfig.ghanaAccra,
            rideRequestSubmitter: submitter,
            rideRequestHistoryRepository: _History(_requested()),
            signInTimeLeft: () => check.future,
          ),
        ),
      );
      await reviewAndConfirm(tester);

      expect(submitter.submissions, 1);
      await _settle(tester);
      expect(find.byKey(const Key('tracking-bottom-sheet')), findsOneWidget);
      expect(find.byKey(banner), findsNothing);

      check.complete(const Duration(minutes: 90));
      await _settle(tester);
      expect(find.byKey(banner), findsOneWidget);
    });

    // Signing out clears this phone's sign-in while the ride is booked, so
    // it asks once first.
    const signOutWarning =
        "You won't see updates about this ride in the app until you sign in "
        'again. Your ride stays booked.';

    Future<int Function()> openSignInQuestion(WidgetTester tester) async {
      var signIns = 0;
      final submitter = await pump(
        tester,
        const Duration(minutes: 90),
        onSignInRequired: () => signIns += 1,
      );
      await reviewAndConfirm(tester);
      await _settle(tester);

      await tester.tap(find.byKey(const Key('tracking-sign-in-again')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text(signOutWarning), findsOneWidget);
      expect(signIns, 0, reason: 'nothing happens before the answer');
      expect(submitter.submissions, 1);
      return () => signIns;
    }

    testWidgets('Sign in again on the banner asks once; Sign in again goes '
        'to sign in', (tester) async {
      final signIns = await openSignInQuestion(tester);

      await tester.tap(find.byKey(const Key('tracking-sign-in-again-confirm')));
      await tester.pumpAndSettle();

      expect(signIns(), 1);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('Stay signed in keeps the sign-in and the banner', (
      tester,
    ) async {
      final signIns = await openSignInQuestion(tester);

      await tester.tap(find.byKey(const Key('tracking-sign-in-again-stay')));
      await tester.pumpAndSettle();

      expect(signIns(), 0);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byKey(banner), findsOneWidget);
    });

    testWidgets('the banner can be closed', (tester) async {
      var signIns = 0;
      await pump(
        tester,
        const Duration(minutes: 90),
        onSignInRequired: () => signIns += 1,
      );
      await reviewAndConfirm(tester);
      await _settle(tester);

      await tester.tap(
        find.byKey(const Key('tracking-sign-in-ends-soon-close')),
      );
      await tester.pump();
      expect(find.byKey(banner), findsNothing);
      expect(signIns, 0);
    });

    testWidgets('exactly 2 hours left: the banner shows', (tester) async {
      final submitter = await pump(tester, const Duration(hours: 2));
      await reviewAndConfirm(tester);
      await _settle(tester);

      expect(submitter.submissions, 1);
      expect(find.byKey(banner), findsOneWidget);
    });

    for (final left in <Duration?>[const Duration(minutes: 121), null]) {
      testWidgets('${left?.inMinutes ?? 'unreadable'} minutes left: books, '
          'no banner', (tester) async {
        final submitter = await pump(tester, left);
        await reviewAndConfirm(tester);
        await _settle(tester);

        expect(submitter.submissions, 1);
        expect(find.byKey(banner), findsNothing);
      });
    }

    testWidgets('a booking that fails shows no banner', (tester) async {
      final submitter = await pump(
        tester,
        const Duration(minutes: 90),
        submitter: _Submitter(fail: true),
      );
      await reviewAndConfirm(tester);
      await _settle(tester);

      expect(submitter.submissions, 1);
      expect(find.byKey(banner), findsNothing);
      expect(find.text(warning), findsNothing);
    });
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
        await _settle(tester);

        expect(submitter.submissions, 1);
        expect(find.byKey(banner), findsOneWidget);
      });
    }

    testWidgets('the home\'s Continue (no button calls it today)', (
      tester,
    ) async {
      final submitter = await pumpShell(tester, _History(_completed()));
      tester
          .widget<AsmBottomNavigationBar>(find.byType(AsmBottomNavigationBar))
          .onDestinationSelected!
          .call(0);
      await tester.pumpAndSettle();
      for (final (choose, words) in [
        ('pickup', 'Osu'),
        ('destination', 'Airport'),
      ]) {
        final home = tester.widget<PassengerHome>(find.byType(PassengerHome));
        choose == 'pickup' ? home.onChoosePickup() : home.onChooseDestination();
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('location-description')),
          words,
        );
        await tester.tap(find.byKey(const Key('use-location-description')));
        await tester.pumpAndSettle();
      }
      tester.widget<PassengerHome>(find.byType(PassengerHome)).onContinue();
      await tester.pumpAndSettle();
      await _tapVisible(tester, const Key('request-ride'));
      await tester.pumpAndSettle();
      await _tapVisible(tester, const Key('confirm-and-request'));
      await _settle(tester);

      expect(submitter.submissions, 1);
      expect(find.byKey(banner), findsOneWidget);
    });

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
      expect(find.byKey(banner), findsNothing);

      left = const Duration(minutes: 90);
      await tester.tap(find.byKey(const Key('rejected-book-again')));
      await _settle(tester);
      await _tapVisible(tester, const Key('request-ride'));
      await tester.pumpAndSettle();
      await _tapVisible(tester, const Key('confirm-and-request'));
      await _settle(tester);

      expect(submitter.submissions, 2);
      expect(find.byKey(banner), findsOneWidget);
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
    await _settle(tester);

    expect(submitter.submissions, 1);
    expect(find.byKey(banner), findsOneWidget);
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

PassengerRideRequestRecord _requested() => PassengerRideRequestRecord(
  requestReference: 'RR-APP-3A9F1C2B4E5D',
  status: 'requested',
  pickupLocation: 'Osu',
  destination: 'Airport',
  passengerCount: 1,
  createdAt: DateTime.utc(2026, 10, 9, 8),
  updatedAt: DateTime.utc(2026, 10, 9, 8),
  hasMobileReceipt: true,
  tripCreated: false,
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
  _Submitter({this.fail = false});

  final bool fail;
  var submissions = 0;

  @override
  Future<PassengerRideRequestResult> submit(
    BookingDraft draft, {
    required String idempotencyKey,
  }) async {
    submissions += 1;
    if (fail) {
      throw const PassengerRideRequestSubmissionException(
        PassengerRideRequestSubmissionException.unknownErrorMessage,
      );
    }
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
