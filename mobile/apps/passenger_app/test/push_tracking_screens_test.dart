import 'dart:async';

import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_app_config/asm_app_config.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passenger_app/booking/booking_draft.dart';
import 'package:passenger_app/booking/booking_page.dart';
import 'package:passenger_app/booking/booking_submission.dart';
import 'package:passenger_app/notifications/passenger_push_navigation.dart';
import 'package:passenger_app/notifications/push_notification_runtime.dart';
import 'package:passenger_app/ride_requests/ride_request_history.dart';
import 'package:passenger_app/tracking/passenger_tracking_screens.dart';
import 'package:passenger_app/tracking/ride_tracking_screen.dart';

// One tracking screen per ride request (seen on the test phone 16 and 17
// Oct: a push for the trip on screen added a second copy, so one tap on
// "Book again" or the back arrow seemed to do nothing). A foreground push
// for a trip that is not open still opens it, as today; nothing navigates
// over the booking form. Everything here runs through the real push
// listener, the real openPassengerPushTrip, the real tracking screen and
// the real booking page.
void main() {
  late _Requests requests;
  late _Push push;
  late _Submitter submitter;

  setUp(() {
    requests = _Requests();
    push = _Push();
    submitter = _Submitter();
  });

  tearDown(() => push.close());

  Widget bookingPage() => BookingPage(
    market: MarketConfig.ghanaAccra,
    rideRequestSubmitter: submitter,
    rideRequestHistoryRepository: requests,
  );

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        builder: (context, child) => PassengerTrackingScope(child: child!),
        home: Builder(
          builder: (context) => FirebaseForegroundPushListener(
            messageSource: push,
            onNavigationIntent: (intent) => openPassengerPushTrip(
              navigator: Navigator.of(context),
              repository: requests,
              intent: intent,
              canNavigate: () => true,
              buildDestination: (record) => buildPassengerPushTripDestination(
                repository: requests,
                record: record,
              ),
            ),
            child: Scaffold(
              body: Column(
                children: [
                  TextButton(
                    key: const Key('home-open-trip-1'),
                    onPressed: () => Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => RideTrackingScreen(
                          repository: requests,
                          requestReference: 'RR-1',
                          initialRecord: requests.record('RR-1'),
                          tripRepository: requests,
                          pollInterval: const Duration(hours: 1),
                        ),
                      ),
                    ),
                    child: const Text('Trip 1'),
                  ),
                  TextButton(
                    key: const Key('home-book'),
                    onPressed: () => Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(builder: (_) => bookingPage()),
                    ),
                    child: const Text('Book'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  // The push listener acts after the next frame and does not ask for one;
  // on the phone the moving map keeps drawing frames, so ask here too.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i += 1) {
      tester.binding.scheduleFrame();
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> openTrip1(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('home-open-trip-1')));
    await settle(tester);
    expect(trackingScreens(), 1);
  }

  testWidgets('a foreground push for the open trip refreshes that screen and '
      'opens no second one', (tester) async {
    await pumpApp(tester);
    await openTrip1(tester);
    final before = requests.detailCalls;

    push.foreground(_message('driver_accepted', 'TRIP-1'));
    await settle(tester);

    expect(trackingScreens(), 1);
    expect(requests.detailCalls, greaterThan(before));
  });

  testWidgets('after that push, one tap on the round back arrow reaches home', (
    tester,
  ) async {
    await pumpApp(tester);
    await openTrip1(tester);
    push.foreground(_message('driver_accepted', 'TRIP-1'));
    await settle(tester);

    await tester.tap(find.byIcon(Icons.arrow_back).last);
    await settle(tester);

    expect(trackingScreens(), 0);
    expect(find.byKey(const Key('home-open-trip-1')), findsOneWidget);
  });

  testWidgets('after that push, one tap on "Book again" on "Trip cancelled" '
      'reaches home', (tester) async {
    await pumpApp(tester);
    await openTrip1(tester);
    requests.cancel('RR-1');
    push.foreground(_message('trip_cancelled', 'TRIP-1'));
    await settle(tester);
    expect(find.text('Trip cancelled'), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('cancelled-by-passenger-book-again')),
    );
    await settle(tester);

    expect(trackingScreens(), 0);
    expect(find.byKey(const Key('home-open-trip-1')), findsOneWidget);
  });

  testWidgets('trip_created and driver_accepted for the same trip arriving '
      'together open one screen', (tester) async {
    await pumpApp(tester);

    push.foreground(_message('trip_created', 'TRIP-1'));
    push.foreground(_message('driver_accepted', 'TRIP-1'));
    await settle(tester);

    expect(trackingScreens(), 1);
  });

  testWidgets('a foreground push for another trip while one is open opens '
      'that trip, as today: one screen each', (tester) async {
    await pumpApp(tester);
    await openTrip1(tester);

    push.foreground(_message('driver_accepted', 'TRIP-2'));
    await settle(tester);

    expect(trackingScreens(), 2);
    expect(trackingScreensFor('RR-2'), 1);
  });

  testWidgets('a notification tap for the open trip with another page on top '
      'brings that trip back to the top: still one screen', (tester) async {
    await pumpApp(tester);
    await openTrip1(tester);
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(
      nav.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('On top')),
        ),
      ),
    );
    await settle(tester);

    push.opened(_message('driver_accepted', 'TRIP-1'));
    await settle(tester);

    expect(trackingScreens(), 1);
    expect(find.text('On top'), findsNothing);
    expect(find.byType(RideTrackingScreen), findsOneWidget);
  });

  testWidgets('a cold-start tap opens one screen, as today', (tester) async {
    push.initial = _message('driver_accepted', 'TRIP-1');
    await pumpApp(tester);
    await settle(tester);

    expect(trackingScreens(), 1);
  });

  testWidgets('a foreground push while the booking form is on top does not '
      'navigate over it; the booking then opens exactly one tracking screen '
      'and leaves no form behind', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(const Key('home-book')));
    await settle(tester);

    push.foreground(_message('driver_accepted', 'TRIP-1'));
    await settle(tester);
    expect(trackingScreens(), 0);
    expect(find.byType(BookingPage), findsOneWidget);

    await _book(tester);

    expect(find.byType(BookingPage, skipOffstage: false), findsNothing);
    expect(trackingScreens(), 1);
    expect(trackingScreensFor('RR-APP-NEW'), 1);
  });

  testWidgets('trip_created for the booking just sent, arriving right after '
      'the booking opened its tracking screen: still one screen', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(const Key('home-book')));
    await settle(tester);
    await _book(tester);
    expect(trackingScreens(), 1);

    push.foreground(_message('trip_created', 'TRIP-NEW'));
    await settle(tester);

    expect(trackingScreens(), 1);
  });

  testWidgets('a notification tap for a lower trip while a booking is being '
      'sent does not pop the booking; the trip screen refreshes in place', (
    tester,
  ) async {
    await pumpApp(tester);
    await openTrip1(tester);
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(
      nav.push<void>(MaterialPageRoute<void>(builder: (_) => bookingPage())),
    );
    await settle(tester);
    submitter.hold = Completer<void>();
    await _book(tester, finish: false);
    final before = requests.detailCalls;

    push.opened(_message('driver_accepted', 'TRIP-1'));
    await settle(tester);

    expect(find.byType(BookingPage), findsOneWidget);
    expect(requests.detailCalls, greaterThan(before));
    expect(trackingScreens(), 1);

    submitter.hold!.complete();
    await settle(tester);
    expect(find.byType(BookingPage, skipOffstage: false), findsNothing);
    expect(trackingScreensFor('RR-1'), 1);
    expect(trackingScreensFor('RR-APP-NEW'), 1);
  });
}

int trackingScreens() =>
    find.byType(RideTrackingScreen, skipOffstage: false).evaluate().length;

int trackingScreensFor(String reference) => find
    .byWidgetPredicate(
      (widget) =>
          widget is RideTrackingScreen && widget.requestReference == reference,
      skipOffstage: false,
    )
    .evaluate()
    .length;

Future<void> _book(WidgetTester tester, {bool finish = true}) async {
  await tester.enterText(find.byKey(const Key('booking-pickup')), 'Osu');
  await tester.enterText(
    find.byKey(const Key('booking-destination')),
    'Osu Check',
  );
  await _tapVisible(tester, const Key('request-ride'));
  for (var i = 0; i < 10; i += 1) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await _tapVisible(tester, const Key('confirm-and-request'));
  final frames = finish ? 20 : 3;
  for (var i = 0; i < frames; i += 1) {
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

RemoteMessage _message(String eventType, String trip) => RemoteMessage(
  data: <String, dynamic>{'event_type': eventType, 'trip_reference': trip},
);

final class _Requests
    implements
        PassengerRideRequestHistoryRepository,
        PassengerTripLifecycleRepository {
  final _records = <String, PassengerRideRequestRecord>{
    'RR-1': _record('RR-1', 'TRIP-1'),
    'RR-2': _record('RR-2', 'TRIP-2'),
    'RR-APP-NEW': _record('RR-APP-NEW', 'TRIP-NEW'),
  };
  final _cancelled = <String>{};

  /// Reloads of a trip or request: a tracking screen refreshing.
  var detailCalls = 0;

  PassengerRideRequestRecord record(String reference) => _records[reference]!;

  void cancel(String reference) => _cancelled.add(reference);

  @override
  Future<List<PassengerRideRequestRecord>> fetchRequests() async =>
      _records.values.toList();

  @override
  Future<PassengerRideRequestRecord> fetchRequest(String reference) async {
    detailCalls += 1;
    return _records[reference]!;
  }

  @override
  Future<PassengerTripRecord> fetchTrip(String tripReference) async {
    detailCalls += 1;
    final cancelled = _records.values.any(
      (r) =>
          r.normalizedTripReference == tripReference &&
          _cancelled.contains(r.requestReference),
    );
    return PassengerTripRecord(
      tripReference: tripReference,
      status: cancelled ? 'cancelled_by_passenger' : 'driver_en_route',
    );
  }
}

PassengerRideRequestRecord _record(String reference, String trip) =>
    PassengerRideRequestRecord(
      requestReference: reference,
      status: 'converted',
      pickupLocation: 'Pinned location',
      destination: 'Osu Check',
      passengerCount: 1,
      createdAt: DateTime.utc(2026, 10, 17, 2),
      updatedAt: DateTime.utc(2026, 10, 17, 2, 1),
      hasMobileReceipt: true,
      tripCreated: true,
      tripReference: trip,
    );

final class _Submitter implements PassengerRideRequestSubmitter {
  Completer<void>? hold;

  @override
  Future<PassengerRideRequestResult> submit(
    BookingDraft draft, {
    required String idempotencyKey,
  }) async {
    final wait = hold;
    if (wait != null) {
      await wait.future;
    }
    return const PassengerRideRequestResult(
      requestReference: 'RR-APP-NEW',
      status: 'requested',
      message: 'Your ride request was received.',
    );
  }
}

final class _Push implements PassengerPushMessageSource {
  final _foreground = StreamController<RemoteMessage>.broadcast();
  final _opened = StreamController<RemoteMessage>.broadcast();
  RemoteMessage? initial;

  void foreground(RemoteMessage message) => _foreground.add(message);
  void opened(RemoteMessage message) => _opened.add(message);

  Future<void> close() async {
    await _foreground.close();
    await _opened.close();
  }

  @override
  Stream<RemoteMessage> get foregroundMessages => _foreground.stream;

  @override
  Stream<RemoteMessage> get openedMessages => _opened.stream;

  @override
  Future<RemoteMessage?> getInitialMessage() async => initial;
}
