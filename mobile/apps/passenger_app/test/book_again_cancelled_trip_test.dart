import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_app_config/asm_app_config.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passenger_app/booking/booking_draft.dart';
import 'package:passenger_app/booking/booking_page.dart';
import 'package:passenger_app/booking/booking_submission.dart';
import 'package:passenger_app/notifications/passenger_push_navigation.dart';
import 'package:passenger_app/passenger_shell.dart';
import 'package:passenger_app/ride_requests/ride_request_history.dart';
import 'package:passenger_app/tracking/ride_tracking_screen.dart';

// Phone session 23 Oct: "Book again" on a "Trip cancelled" card opened the
// Trips list, not the booking form. Both cancelled cards only closed the
// screen; the "no vehicles" card already handed the trip to the booking
// form. Every route that opens tracking now gets the form, pre-filled.
void main() {
  for (final (status, state, button) in const [
    (
      'cancelled_by_operations',
      'trip-cancelled-state',
      'cancelled-by-operations-book-again',
    ),
    (
      'cancelled_by_passenger',
      'trip-cancelled-by-passenger-state',
      'cancelled-by-passenger-book-again',
    ),
  ]) {
    testWidgets('$status: book again hands the trip to the booking form and '
        'closes this screen', (tester) async {
      PassengerRideRequestRecord? bookedAgain;
      await _pumpTracking(
        tester,
        _cancelled(status),
        onBookAgain: (record) => bookedAgain = record,
      );

      expect(find.byKey(Key(state)), findsOneWidget);
      await tester.tap(find.byKey(Key(button)));
      await _settle(tester);

      expect(bookedAgain?.requestReference, 'RR-APP-CANCELLED01');
      expect(bookedAgain?.pickupLocation, 'Osu Oxford Street');
      expect(bookedAgain?.destination, 'Kotoka International Airport');
      expect(find.byKey(Key(state)), findsNothing);
      expect(find.text('Launcher'), findsOneWidget);
    });
  }

  testWidgets('without a booking form, book again just closes the screen', (
    tester,
  ) async {
    await _pumpTracking(tester, _cancelled('cancelled_by_operations'));

    await tester.tap(
      find.byKey(const Key('cancelled-by-operations-book-again')),
    );
    await _settle(tester);

    expect(find.text('Launcher'), findsOneWidget);
  });

  testWidgets('from Trips, a trip cancelled while open: book again opens a '
      'pre-filled booking', (tester) async {
    _useSurface(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: PassengerShell(
          rideRequestHistoryRepository: _CancelledOnFetch(
            'cancelled_by_operations',
          ),
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
    expect(find.byKey(const Key('trip-cancelled-state')), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('cancelled-by-operations-book-again')),
    );
    await _settle(tester);

    _expectPrefilledBooking(tester);
    expect(find.byKey(const Key('trip-cancelled-state')), findsNothing);
  });

  testWidgets('right after booking, a cancelled trip: book again opens a '
      'pre-filled booking', (tester) async {
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
            rideRequestHistoryRepository: _CancelledOnFetch(
              'cancelled_by_passenger',
            ),
            idempotencyKeyFactory: () => 'APP-cancelled-flow',
          ),
        ),
      ),
    );
    await tester.tap(find.text('Launcher'));
    await _settle(tester);

    await _tapKey(tester, 'request-ride');
    await _tapKey(tester, 'confirm-and-request');
    expect(
      find.byKey(const Key('trip-cancelled-by-passenger-state')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('cancelled-by-passenger-book-again')),
    );
    await _settle(tester);

    _expectPrefilledBooking(tester);
    expect(
      find.byKey(const Key('trip-cancelled-by-passenger-state')),
      findsNothing,
    );
  });

  testWidgets('opened from a push: book again hands the trip to the booking '
      'form', (tester) async {
    _useSurface(tester);
    final record = _cancelled('cancelled_by_operations');
    PassengerRideRequestRecord? bookedAgain;
    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: _Launcher(
          builder: (_) => buildPassengerPushTripDestination(
            repository: _Static(record),
            record: record,
            onBookAgain: (record) => bookedAgain = record,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Launcher'));
    await _settle(tester);

    await tester.tap(
      find.byKey(const Key('cancelled-by-operations-book-again')),
    );
    await _settle(tester);

    expect(bookedAgain?.pickupLocation, 'Osu Oxford Street');
    expect(find.text('Launcher'), findsOneWidget);
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

PassengerRideRequestRecord _cancelled(String status) {
  return PassengerRideRequestRecord(
    requestReference: 'RR-APP-CANCELLED01',
    status: status,
    pickupLocation: 'Osu Oxford Street',
    destination: 'Kotoka International Airport',
    passengerCount: 1,
    createdAt: DateTime.utc(2026, 10, 23, 12),
    updatedAt: DateTime.utc(2026, 10, 23, 12),
    hasMobileReceipt: true,
    tripCreated: false,
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

/// Lists the request as still waiting; it is cancelled by the time the
/// tracking screen fetches it.
class _CancelledOnFetch implements PassengerRideRequestHistoryRepository {
  _CancelledOnFetch(this.status);

  final String status;

  @override
  Future<List<PassengerRideRequestRecord>> fetchRequests() async =>
      <PassengerRideRequestRecord>[_cancelled('requested')];

  @override
  Future<PassengerRideRequestRecord> fetchRequest(String reference) async =>
      _cancelled(status);
}

class _AcceptingSubmitter implements PassengerRideRequestSubmitter {
  @override
  Future<PassengerRideRequestResult> submit(
    BookingDraft draft, {
    required String idempotencyKey,
  }) async {
    return const PassengerRideRequestResult(
      requestReference: 'RR-APP-CANCELLED01',
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
