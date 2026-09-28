import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_app_config/asm_app_config.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passenger_app/booking/booking_draft.dart';
import 'package:passenger_app/booking/booking_page.dart';
import 'package:passenger_app/booking/booking_submission.dart';
import 'package:passenger_app/passenger_shell.dart';
import 'package:passenger_app/ride_requests/ride_request_history.dart';
import 'package:passenger_app/support/new_message_form.dart';
import 'package:passenger_app/tracking/ride_tracking_screen.dart';

// A request staff rejected is final (it can never become a trip), so the
// rejected screen can safely offer a fresh booking and a way to ask why.
void main() {
  testWidgets('a rejected request says so, not "no vehicles available"', (
    tester,
  ) async {
    await _pumpTracking(tester, _rejected());

    expect(find.text("We couldn't accept this ride request"), findsOneWidget);
    expect(
      find.text(
        "You can book again, or contact support if you'd like to know more.",
      ),
      findsOneWidget,
    );
    expect(find.text('No vehicles available right now'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('rejected-book-again')),
        matching: find.text('Book again'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('book again hands the request to the booking flow', (
    tester,
  ) async {
    PassengerRideRequestRecord? bookedAgain;
    await _pumpTracking(
      tester,
      _rejected(),
      onBookAgain: (record) => bookedAgain = record,
    );

    await tester.tap(find.byKey(const Key('rejected-book-again')));
    await _settle(tester);

    expect(bookedAgain?.requestReference, 'RR-APP-REJECTED01');
    expect(bookedAgain?.pickupLocation, 'Osu Oxford Street');
    // The rejected screen closes, so backing out of the new booking does
    // not land on it again.
    expect(find.byKey(const Key('request-rejected-state')), findsNothing);
    expect(find.text('Launcher'), findsOneWidget);
  });

  testWidgets('without a booking flow, book again just closes the screen', (
    tester,
  ) async {
    await _pumpTracking(tester, _rejected());

    await tester.tap(find.byKey(const Key('rejected-book-again')));
    await _settle(tester);

    expect(find.text('Launcher'), findsOneWidget);
  });

  testWidgets('contact support opens the support form about this request', (
    tester,
  ) async {
    await _pumpTracking(
      tester,
      _rejected(),
      passengerName: 'Ama Mensah',
      supportMessageSubmitter: _UnusedSupportSubmitter(),
    );

    await tester.tap(find.byKey(const Key('rejected-contact-support')));
    await _settle(tester);

    expect(find.byType(NewMessageForm), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('new-message-name')))
          .controller
          ?.text,
      'Ama Mensah',
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('new-message-message')))
          .controller
          ?.text,
      'About my ride request RR-APP-REJECTED01, which could not be '
      'accepted: ',
    );
    final category = tester.widget<DropdownButtonFormField<String>>(
      find.byKey(const Key('new-message-category')),
    );
    expect(category.initialValue, isNull);
    expect(category.onChanged, isNotNull);
  });

  testWidgets('from My Ride Requests, book again opens a pre-filled booking', (
    tester,
  ) async {
    _useSurface(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: PassengerShell(
          rideRequestHistoryRepository: _RejectsOnFetch(),
          rideRequestSubmitter: _NeverSubmitter(),
          passengerName: 'Ama Mensah',
        ),
      ),
    );
    await _settle(tester);

    tester
        .widget<AsmBottomNavigationBar>(find.byType(AsmBottomNavigationBar))
        .onDestinationSelected!
        .call(1);
    await _settle(tester);
    await tester.tap(find.byKey(const Key('history-card-view-details')));
    await _settle(tester);
    expect(find.byKey(const Key('request-rejected-state')), findsOneWidget);

    await tester.tap(find.byKey(const Key('rejected-book-again')));
    await _settle(tester);

    _expectPrefilledBooking(tester);
  });

  testWidgets('right after booking, book again opens a pre-filled booking', (
    tester,
  ) async {
    _useSurface(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: _Launcher(
          builder: (_) => BookingPage(
            market: MarketConfig.ghanaAccra,
            initialPickupDescription: 'Osu Oxford Street',
            initialDestinationDescription: 'Kotoka International Airport',
            rideRequestSubmitter: _AcceptingSubmitter(),
            rideRequestHistoryRepository: _RejectsOnFetch(),
            idempotencyKeyFactory: () => 'APP-rejected-flow',
          ),
        ),
      ),
    );
    await tester.tap(find.text('Launcher'));
    await _settle(tester);

    await _tapKey(tester, 'request-ride');
    await _tapKey(tester, 'confirm-and-request');
    expect(find.byKey(const Key('request-rejected-state')), findsOneWidget);

    await tester.tap(find.byKey(const Key('rejected-book-again')));
    await _settle(tester);

    _expectPrefilledBooking(tester);
    // Backing out of the new booking returns to the start, not the
    // rejected screen.
    expect(find.byKey(const Key('request-rejected-state')), findsNothing);
  });
}

void _expectPrefilledBooking(WidgetTester tester) {
  expect(
    tester
        .widget<TextFormField>(find.byKey(const Key('booking-pickup')))
        .controller!
        .text,
    'Osu Oxford Street',
  );
  expect(
    tester
        .widget<TextFormField>(find.byKey(const Key('booking-destination')))
        .controller!
        .text,
    'Kotoka International Airport',
  );
}

PassengerRideRequestRecord _rejected({String status = 'rejected'}) {
  return PassengerRideRequestRecord(
    requestReference: 'RR-APP-REJECTED01',
    status: status,
    pickupLocation: 'Osu Oxford Street',
    destination: 'Kotoka International Airport',
    passengerCount: 1,
    createdAt: DateTime.utc(2026, 9, 29, 12),
    updatedAt: DateTime.utc(2026, 9, 29, 12),
    hasMobileReceipt: true,
    tripCreated: false,
    controlCenterMessage: status == 'rejected'
        ? 'Your request could not be accepted.'
        : null,
  );
}

void _useSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);
}

Future<void> _settle(WidgetTester tester) async {
  for (var frame = 0; frame < 10; frame += 1) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  for (var attempt = 0; attempt < 20 && finder.evaluate().isEmpty; attempt++) {
    await tester.drag(find.byType(ListView).last, const Offset(0, -220));
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(finder);
  await _settle(tester);
}

Future<void> _pumpTracking(
  WidgetTester tester,
  PassengerRideRequestRecord record, {
  ValueChanged<PassengerRideRequestRecord>? onBookAgain,
  String? passengerName,
  PassengerSupportMessageSubmitter? supportMessageSubmitter,
}) async {
  _useSurface(tester);
  await tester.pumpWidget(
    MaterialApp(
      theme: AsmThemes.passenger,
      home: _Launcher(
        builder: (_) => RideTrackingScreen(
          repository: _Static(record),
          requestReference: record.requestReference,
          initialRecord: record,
          pollInterval: const Duration(hours: 1),
          onBookAgain: onBookAgain,
          passengerName: passengerName,
          supportMessageSubmitter: supportMessageSubmitter,
        ),
      ),
    ),
  );
  await tester.tap(find.text('Launcher'));
  await _settle(tester);
}

class _Launcher extends StatelessWidget {
  const _Launcher({required this.builder});

  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () => Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: builder)),
          child: const Text('Launcher'),
        ),
      ),
    );
  }
}

class _Static implements PassengerRideRequestHistoryRepository {
  _Static(this.record);

  final PassengerRideRequestRecord record;

  @override
  Future<List<PassengerRideRequestRecord>> fetchRequests() async =>
      <PassengerRideRequestRecord>[record];

  @override
  Future<PassengerRideRequestRecord> fetchRequest(String reference) async =>
      record;
}

/// Lists the request as still awaiting review; staff have rejected it by
/// the time the tracking screen fetches it.
class _RejectsOnFetch implements PassengerRideRequestHistoryRepository {
  @override
  Future<List<PassengerRideRequestRecord>> fetchRequests() async =>
      <PassengerRideRequestRecord>[_rejected(status: 'requested')];

  @override
  Future<PassengerRideRequestRecord> fetchRequest(String reference) async =>
      _rejected();
}

class _AcceptingSubmitter implements PassengerRideRequestSubmitter {
  @override
  Future<PassengerRideRequestResult> submit(
    BookingDraft draft, {
    required String idempotencyKey,
  }) async {
    return const PassengerRideRequestResult(
      requestReference: 'RR-APP-REJECTED01',
      status: 'requested',
      message: 'Ride request received by the Control Center.',
    );
  }
}

class _NeverSubmitter implements PassengerRideRequestSubmitter {
  @override
  Future<PassengerRideRequestResult> submit(
    BookingDraft draft, {
    required String idempotencyKey,
  }) {
    throw StateError('No booking is submitted in this test.');
  }
}

class _UnusedSupportSubmitter implements PassengerSupportMessageSubmitter {
  @override
  Future<PassengerSupportMessageResult> submit({
    required String category,
    required String? tripReference,
    required String name,
    required String message,
  }) {
    throw StateError('No support message is sent in this test.');
  }
}
