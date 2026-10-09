import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passenger_app/ride_requests/ride_request_history.dart';
import 'package:passenger_app/tracking/ride_tracking_screen.dart';

// When the server has really ended the session (the refresh was refused),
// the tracking screen sends the passenger to sign in. It used to treat it
// as a connection problem: "reconnecting", then "offline", polling again.
void main() {
  const poll = Duration(seconds: 10);

  Future<void> pump(
    WidgetTester tester, {
    required _Requests requests,
    _Trips? trips,
    PassengerRideRequestRecord? initialRecord,
    required VoidCallback onSignInRequired,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RideTrackingScreen(
          repository: requests,
          requestReference: 'RR-1',
          tripRepository: trips,
          initialRecord: initialRecord,
          pollInterval: poll,
          onSignInRequired: onSignInRequired,
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('refused on the first load: sign in, no "offline", no polling', (
    tester,
  ) async {
    var signIns = 0;
    final requests = _Requests(
      error: const PassengerRideRequestHistoryException.sessionExpired(),
    );
    await pump(tester, requests: requests, onSignInRequired: () => signIns++);
    await tester.pump(const Duration(seconds: 25));

    expect(signIns, 1);
    expect(find.byKey(const Key('offline-state')), findsNothing);
    expect(find.byKey(const Key('tracking-reconnecting-banner')), findsNothing);
    expect(requests.calls, 1, reason: 'no polling after a refusal');
  });

  testWidgets(
    'refused during the ride: sign in, no "reconnecting", no polling',
    (tester) async {
      var signIns = 0;
      final requests = _Requests(record: _converted());
      final trips = _Trips();
      await pump(
        tester,
        requests: requests,
        trips: trips,
        onSignInRequired: () => signIns++,
      );
      expect(trips.calls, 1);

      trips.error = const PassengerRideRequestHistoryException.sessionExpired();
      await tester.pump(poll);
      await tester.pump();
      await tester.pump(const Duration(seconds: 25));

      expect(signIns, 1);
      expect(
        find.byKey(const Key('tracking-reconnecting-banner')),
        findsNothing,
      );
      expect(trips.calls, 2, reason: 'no polling after a refusal');
    },
  );

  testWidgets('a network failure is still a connection problem', (
    tester,
  ) async {
    var signIns = 0;
    final requests = _Requests(record: _converted());
    final trips = _Trips();
    await pump(
      tester,
      requests: requests,
      trips: trips,
      onSignInRequired: () => signIns++,
    );

    trips.error = const PassengerRideRequestHistoryException.network();
    await tester.pump(poll);
    await tester.pump();

    expect(signIns, 0);
    expect(
      find.byKey(const Key('tracking-reconnecting-banner')),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

PassengerRideRequestRecord _converted() => PassengerRideRequestRecord(
  requestReference: 'RR-1',
  status: 'converted',
  pickupLocation: 'Accra Mall',
  destination: 'Accra Airport',
  passengerCount: 1,
  createdAt: DateTime.utc(2026, 10, 9, 9),
  updatedAt: DateTime.utc(2026, 10, 9, 9, 5),
  hasMobileReceipt: true,
  tripCreated: true,
  tripReference: 'TRIP-1',
);

final class _Requests implements PassengerRideRequestHistoryRepository {
  _Requests({this.record, this.error});

  final PassengerRideRequestRecord? record;
  final Object? error;
  var calls = 0;

  @override
  Future<PassengerRideRequestRecord> fetchRequest(String reference) async {
    calls += 1;
    final failure = error;
    if (failure != null) {
      throw failure;
    }
    return record!;
  }

  @override
  Future<List<PassengerRideRequestRecord>> fetchRequests() async => const [];
}

final class _Trips implements PassengerTripLifecycleRepository {
  Object? error;
  var calls = 0;

  @override
  Future<PassengerTripRecord> fetchTrip(String tripReference) async {
    calls += 1;
    final failure = error;
    if (failure != null) {
      throw failure;
    }
    return const PassengerTripRecord(
      tripReference: 'TRIP-1',
      status: 'driver_en_route',
    );
  }
}
