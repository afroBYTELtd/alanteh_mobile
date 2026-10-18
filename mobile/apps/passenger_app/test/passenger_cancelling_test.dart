import 'dart:async';

import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_auth/asm_auth.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passenger_app/network/ghana_network_resilience.dart';
import 'package:passenger_app/network/passenger_cancellation_gateway.dart';
import 'package:passenger_app/ride_requests/ride_request_history.dart';
import 'package:passenger_app/tracking/passenger_tracking_screens.dart';
import 'package:passenger_app/tracking/ride_tracking_screen.dart';

// "Cancelling…" (Build B item 1). Seen on the test phone: after the cancel
// answer the button came back as "Cancel request" until the next reload,
// and an older poll could put the trip back on screen.
void main() {
  const tripReference = 'TRIP-CANCEL-1';
  const pollInterval = Duration(seconds: 10);

  Future<void> pump(
    WidgetTester tester, {
    required _Trips trips,
    required _Cancels cancels,
    _Requests? requests,
  }) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: PassengerTrackingScope(
          child: RideTrackingScreen(
            repository:
                requests ??
                _Requests(
                  _request(status: 'converted', tripReference: tripReference),
                ),
            requestReference: _requestReference,
            tripRepository: trips,
            pollInterval: pollInterval,
            cancellationGateway: cancels,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
  }

  Future<void> confirmCancel(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('open-cancel-confirmation')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('passenger-cancel-reason-option-no_longer_needed')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('passenger-cancel-reason-confirm')));
    // The sheet closes; no settle, so held answers stay held.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Finder cancelButton() => find.byKey(const Key('open-cancel-confirmation'));

  bool cancelButtonEnabled(WidgetTester tester) =>
      tester.widget<ButtonStyleButton>(cancelButton()).onPressed != null;

  final cancelledCard = find.byKey(
    const Key('trip-cancelled-by-passenger-state'),
  );

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();
  }

  testWidgets('Cancelling… shows at once, and the card comes from the cancel '
      'answer: the button never reads "Cancel request" in between', (
    tester,
  ) async {
    final trips = _Trips('driver_accepted');
    final cancels = _Cancels();
    await pump(tester, trips: trips, cancels: cancels);

    await confirmCancel(tester);
    expect(find.text('Cancelling…'), findsOneWidget);
    expect(cancelButtonEnabled(tester), isFalse);

    // Every reload from here is held: the card must not need one.
    trips.hold = true;
    cancels.answer(0, 'cancelled_by_passenger');
    await tester.pump();

    expect(cancelledCard, findsOneWidget);
    expect(find.text('Cancel request'), findsNothing);
    expect(cancelButton(), findsNothing);

    trips.releaseAll('cancelled_by_passenger');
    await tester.pump();
    expect(cancelledCard, findsOneWidget);
    await dispose(tester);
  });

  testWidgets('a poll that began before the cancel and answers after it is '
      'dropped', (tester) async {
    final trips = _Trips('driver_accepted');
    final cancels = _Cancels();
    await pump(tester, trips: trips, cancels: cancels);

    trips.hold = true;
    await tester.pump(pollInterval);
    expect(trips.held, hasLength(1));

    await confirmCancel(tester);
    cancels.answer(0, 'cancelled_by_passenger');
    await tester.pump();
    expect(cancelledCard, findsOneWidget);

    // The old poll answers with the status from before the cancel.
    trips.held.first.complete(_trip('driver_accepted'));
    await tester.pump();
    expect(cancelledCard, findsOneWidget);

    trips.releaseAll('cancelled_by_passenger');
    await tester.pump();
    await dispose(tester);
  });

  testWidgets('no polls while the cancel is out, even when a poll was '
      'already running at the tap', (tester) async {
    final trips = _Trips('driver_accepted');
    final cancels = _Cancels();
    await pump(tester, trips: trips, cancels: cancels);

    trips.hold = true;
    await tester.pump(pollInterval);
    expect(trips.held, hasLength(1));

    await confirmCancel(tester);
    trips.held.first.complete(_trip('driver_accepted'));
    await tester.pump();
    final callsWhileCancelling = trips.calls;

    await tester.pump(pollInterval * 3);
    expect(trips.calls, callsWhileCancelling);
    expect(find.text('Cancelling…'), findsOneWidget);

    trips.releaseAll('cancelled_by_passenger');
    cancels.answer(0, 'cancelled_by_passenger');
    await tester.pump();
    await dispose(tester);
  });

  testWidgets('a poll that falls due during Cancelling… does not run', (
    tester,
  ) async {
    final trips = _Trips('driver_accepted');
    final cancels = _Cancels();
    await pump(tester, trips: trips, cancels: cancels);
    final callsBefore = trips.calls;

    // The next poll is due 10 s after the first load; the cancel is out
    // well before that and is still out after it.
    await confirmCancel(tester);
    await tester.pump(pollInterval * 2);
    expect(trips.calls, callsBefore);
    expect(find.text('Cancelling…'), findsOneWidget);

    trips.status = 'cancelled_by_passenger';
    cancels.answer(0, 'cancelled_by_passenger');
    await tester.pump();
    await dispose(tester);
  });

  testWidgets('a push reload that began during Cancelling… and answers after '
      'the cancel answer is dropped', (tester) async {
    final trips = _Trips('driver_accepted');
    final cancels = _Cancels();
    await pump(tester, trips: trips, cancels: cancels);

    await confirmCancel(tester);
    trips.hold = true;
    PassengerTrackingScope.maybeOf(
      tester.element(find.byType(RideTrackingScreen)),
    )!.screenFor(_requestReference)!.refresh();
    await tester.pump();
    expect(trips.held, hasLength(1));

    cancels.answer(0, 'cancelled_by_passenger');
    await tester.pump();
    expect(cancelledCard, findsOneWidget);

    // The push reload read the trip before the cancel landed.
    trips.held.first.complete(_trip('driver_accepted'));
    await tester.pump();
    expect(cancelledCard, findsOneWidget);

    trips.releaseAll('cancelled_by_passenger');
    await tester.pump();
    await dispose(tester);
  });

  testWidgets('a cancel answer with any other status reloads and shows no '
      'card', (tester) async {
    final trips = _Trips('driver_accepted');
    final cancels = _Cancels();
    await pump(tester, trips: trips, cancels: cancels);

    await confirmCancel(tester);
    trips.hold = true;
    cancels.answer(0, 'in_progress', duplicate: true);
    await tester.pump();

    expect(cancelledCard, findsNothing);
    expect(find.text('Cancelling…'), findsOneWidget);
    expect(trips.held, hasLength(1));

    trips.releaseAll('in_progress');
    await tester.pump();
    expect(find.byKey(const Key('trip-in-progress-state')), findsOneWidget);
    expect(cancelledCard, findsNothing);
    await dispose(tester);
  });

  testWidgets('not eligible because the trip moved on: the real state and '
      "the server's reason, never Trip cancelled", (tester) async {
    final trips = _Trips('driver_accepted');
    final cancels = _Cancels();
    await pump(tester, trips: trips, cancels: cancels);

    await confirmCancel(tester);
    trips.hold = true;
    cancels.fail(0, const PassengerCancellationException.notEligible());
    await tester.pump();

    // The reload answers first; nothing is said until then.
    expect(find.text('Cancelling…'), findsOneWidget);
    expect(
      find.text(PassengerCancellationException.notEligibleMessage),
      findsNothing,
    );

    trips.releaseAll('in_progress');
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('trip-in-progress-state')), findsOneWidget);
    expect(
      find.text(PassengerCancellationException.notEligibleMessage),
      findsOneWidget,
    );
    expect(cancelledCard, findsNothing);
    expect(find.text('Trip cancelled'), findsNothing);
    await dispose(tester);
  });

  testWidgets('not eligible because dispatch cancelled first: that card, and '
      'no message', (tester) async {
    final trips = _Trips('driver_accepted');
    final cancels = _Cancels();
    await pump(tester, trips: trips, cancels: cancels);

    await confirmCancel(tester);
    cancels.fail(0, const PassengerCancellationException.notEligible());
    trips.status = 'cancelled_by_operations';
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('trip-cancelled-state')), findsOneWidget);
    expect(find.byKey(const Key('cancel-not-eligible-snackbar')), findsNothing);
    await dispose(tester);
  });

  testWidgets('a timeout whose cancel did land: the reload shows the card, '
      'and no error', (tester) async {
    final trips = _Trips('driver_accepted');
    final cancels = _Cancels();
    await pump(tester, trips: trips, cancels: cancels);

    await confirmCancel(tester);
    trips.status = 'cancelled_by_passenger';
    cancels.fail(0, const PassengerCancellationException.network());
    await tester.pump();
    await tester.pump();

    expect(cancelledCard, findsOneWidget);
    expect(find.byKey(const Key('cancel-error-snackbar')), findsNothing);
    expect(find.byKey(const Key('cancel-unconfirmed-snackbar')), findsNothing);
    await dispose(tester);
  });

  testWidgets('a timeout with the trip still live: "Try cancelling again" '
      'sends the same key and reason, without the sheet', (tester) async {
    final trips = _Trips('driver_accepted');
    final cancels = _Cancels();
    await pump(tester, trips: trips, cancels: cancels);

    await confirmCancel(tester);
    cancels.fail(0, const PassengerCancellationException.network());
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const Key('cancel-unconfirmed-snackbar')),
      findsOneWidget,
    );
    expect(
      find.text(
        "We couldn't confirm the cancel. Check your connection and try again.",
      ),
      findsOneWidget,
    );
    expect(find.text('Try cancelling again'), findsOneWidget);
    expect(cancelButtonEnabled(tester), isTrue);

    await tester.tap(cancelButton());
    await tester.pump();

    expect(
      find.byKey(const Key('passenger-cancel-reason-sheet')),
      findsNothing,
    );
    expect(find.text('Cancelling…'), findsOneWidget);
    expect(cancels.keys, hasLength(2));
    expect(cancels.keys[1], cancels.keys[0]);
    expect(cancels.reasons, <PassengerCancellationReason>[
      PassengerCancellationReason.noLongerNeeded,
      PassengerCancellationReason.noLongerNeeded,
    ]);

    trips.status = 'cancelled_by_passenger';
    cancels.answer(1, 'cancelled_by_passenger', duplicate: true);
    await tester.pump();
    expect(cancelledCard, findsOneWidget);
    await dispose(tester);
  });

  testWidgets('after "Try cancelling again" shows, polling resumes, and a '
      'later poll showing the cancel shows the card', (tester) async {
    final trips = _Trips('driver_accepted');
    final cancels = _Cancels();
    await pump(tester, trips: trips, cancels: cancels);

    await confirmCancel(tester);
    cancels.fail(0, const PassengerCancellationException.network());
    await tester.pump();
    await tester.pump();
    expect(find.text('Try cancelling again'), findsOneWidget);

    trips.status = 'cancelled_by_passenger';
    await tester.pump(pollInterval);
    await tester.pump();

    expect(cancelledCard, findsOneWidget);
    expect(cancels.keys, hasLength(1));
    await dispose(tester);
  });

  testWidgets('after 10 s still waiting, a line says the connection is slow; '
      'the button stays disabled', (tester) async {
    final trips = _Trips('driver_accepted');
    final cancels = _Cancels();
    await pump(tester, trips: trips, cancels: cancels);

    await confirmCancel(tester);
    await tester.pump(const Duration(seconds: 9));
    expect(find.byKey(const Key('cancel-slow-note')), findsNothing);

    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const Key('cancel-slow-note')), findsOneWidget);
    expect(
      find.text('Still cancelling — the connection is slow.'),
      findsOneWidget,
    );
    expect(cancelButtonEnabled(tester), isFalse);

    cancels.answer(0, 'cancelled_by_passenger');
    await tester.pump();
    expect(find.byKey(const Key('cancel-slow-note')), findsNothing);
    await dispose(tester);
  });

  testWidgets('a push during Cancelling… that shows a dispatch cancel shows '
      'that card; the not-eligible answer after it says nothing', (
    tester,
  ) async {
    final trips = _Trips('driver_accepted');
    final cancels = _Cancels();
    await pump(tester, trips: trips, cancels: cancels);

    await confirmCancel(tester);
    trips.status = 'cancelled_by_operations';
    PassengerTrackingScope.maybeOf(
      tester.element(find.byType(RideTrackingScreen)),
    )!.screenFor(_requestReference)!.refresh();
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('trip-cancelled-state')), findsOneWidget);

    cancels.fail(0, const PassengerCancellationException.notEligible());
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('trip-cancelled-state')), findsOneWidget);
    expect(find.byKey(const Key('cancel-not-eligible-snackbar')), findsNothing);
    await dispose(tester);
  });

  testWidgets('a request (no trip yet) shows its card from the cancel answer '
      'too', (tester) async {
    final trips = _Trips('driver_accepted');
    final cancels = _Cancels();
    final requests = _Requests(_request(status: 'requested'));
    await pump(tester, trips: trips, cancels: cancels, requests: requests);

    await confirmCancel(tester);
    requests.hold = true;
    cancels.answer(0, 'cancelled', request: true);
    await tester.pump();

    expect(cancelledCard, findsOneWidget);
    expect(find.text('Cancel request'), findsNothing);

    requests.releaseAll(_request(status: 'cancelled'));
    await tester.pump();
    expect(cancelledCard, findsOneWidget);
    await dispose(tester);
  });

  group('the cancel request is tried twice at most', () {
    test('a policy with one backoff makes two attempts', () async {
      var attempts = 0;
      final waits = <Duration>[];
      final policy = GhanaRetryPolicy(
        delay: (wait) async => waits.add(wait),
        backoffs: passengerCancelRetryBackoffs,
      );

      final response = await policy.execute<String>(
        safeToRetry: true,
        operation: () async {
          attempts += 1;
          return ApiResponse.clientException(
            const AsmApiException(
              type: AsmApiExceptionType.timeout,
              message: 'timeout',
            ),
          );
        },
      );

      expect(response.error?.type, AsmApiExceptionType.timeout);
      expect(attempts, 2);
      expect(waits, const <Duration>[Duration(seconds: 2)]);
    });

    test('the cancel gateway uses it; other requests keep four', () {
      final gateway = ApiPassengerCancellationGateway.withDefaultClient(
        tokenStore: MemoryAuthTokenStore(),
        baseUrl: 'https://control.example.test',
      );
      final client = gateway.client as GhanaResilientApiClient;
      expect(client.retryPolicy.backoffs, passengerCancelRetryBackoffs);
      expect(
        GhanaResilientApiClient(
          baseUrl: 'https://control.example.test',
        ).retryPolicy.backoffs,
        GhanaRequestPolicy.retryBackoffs,
      );
    });
  });
}

const _requestReference = 'RR-CANCEL-1';

PassengerRideRequestRecord _request({
  required String status,
  String? tripReference,
}) {
  return PassengerRideRequestRecord(
    requestReference: _requestReference,
    status: status,
    pickupLocation: 'Solar Hotel',
    destination: 'Accra Airport',
    passengerCount: 1,
    createdAt: DateTime.utc(2026, 10, 18, 9),
    updatedAt: DateTime.utc(2026, 10, 18, 9, 5),
    hasMobileReceipt: true,
    tripCreated: false,
    tripReference: tripReference,
  );
}

PassengerTripRecord _trip(String status) =>
    PassengerTripRecord(tripReference: 'TRIP-CANCEL-1', status: status);

/// Trip reloads: answered at once with [status], or held while [hold] is
/// set until the test completes them.
final class _Trips implements PassengerTripLifecycleRepository {
  _Trips(this.status);

  String status;
  bool hold = false;
  int calls = 0;
  final held = <Completer<PassengerTripRecord>>[];

  @override
  Future<PassengerTripRecord> fetchTrip(String tripReference) {
    calls += 1;
    if (!hold) {
      return Future.value(_trip(status));
    }
    final completer = Completer<PassengerTripRecord>();
    held.add(completer);
    return completer.future;
  }

  void releaseAll(String answer) {
    hold = false;
    status = answer;
    for (final completer in held) {
      if (!completer.isCompleted) {
        completer.complete(_trip(answer));
      }
    }
  }
}

final class _Requests implements PassengerRideRequestHistoryRepository {
  _Requests(this.record);

  PassengerRideRequestRecord record;
  bool hold = false;
  final held = <Completer<PassengerRideRequestRecord>>[];

  @override
  Future<List<PassengerRideRequestRecord>> fetchRequests() async => [record];

  @override
  Future<PassengerRideRequestRecord> fetchRequest(String requestReference) {
    if (!hold) {
      return Future.value(record);
    }
    final completer = Completer<PassengerRideRequestRecord>();
    held.add(completer);
    return completer.future;
  }

  void releaseAll(PassengerRideRequestRecord answer) {
    hold = false;
    record = answer;
    for (final completer in held) {
      if (!completer.isCompleted) {
        completer.complete(answer);
      }
    }
  }
}

/// Every cancel is held until the test answers or fails it.
final class _Cancels implements PassengerCancellationGateway {
  final keys = <String>[];
  final reasons = <PassengerCancellationReason>[];
  final _calls = <Completer<PassengerCancellationResult>>[];

  Future<PassengerCancellationResult> _call(
    PassengerCancellationReason reason,
    String idempotencyKey,
  ) {
    keys.add(idempotencyKey);
    reasons.add(reason);
    final completer = Completer<PassengerCancellationResult>();
    _calls.add(completer);
    return completer.future;
  }

  void answer(
    int call,
    String status, {
    bool duplicate = false,
    bool request = false,
  }) {
    _calls[call].complete(
      PassengerCancellationResult(
        reference: request ? _requestReference : 'TRIP-CANCEL-1',
        status: status,
        duplicate: duplicate,
      ),
    );
  }

  void fail(int call, PassengerCancellationException error) =>
      _calls[call].completeError(error);

  @override
  Future<PassengerCancellationResult> cancelRideRequest({
    required String requestReference,
    required PassengerCancellationReason reason,
    String? reasonNote,
    required String idempotencyKey,
  }) => _call(reason, idempotencyKey);

  @override
  Future<PassengerCancellationResult> cancelTripBooking({
    required String tripReference,
    required PassengerCancellationReason reason,
    String? reasonNote,
    required String idempotencyKey,
  }) => _call(reason, idempotencyKey);
}
