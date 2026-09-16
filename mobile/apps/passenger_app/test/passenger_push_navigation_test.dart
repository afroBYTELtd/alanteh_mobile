import 'package:flutter_test/flutter_test.dart';
import 'package:passenger_app/notifications/passenger_push_navigation.dart';
import 'package:passenger_app/ride_requests/ride_request_history.dart';
import 'package:passenger_app/tracking/ride_tracking_screen.dart';

void main() {
  final matchingRecord = PassengerRideRequestRecord(
    requestReference: 'RR-APP-PUSH001',
    status: 'converted',
    pickupLocation: 'Pickup',
    destination: 'Destination',
    passengerCount: 1,
    createdAt: DateTime.utc(2026, 9, 13),
    updatedAt: DateTime.utc(2026, 9, 13),
    hasMobileReceipt: true,
    tripCreated: true,
    tripReference: 'TRIP-PUSH-001',
  );

  test('trip reference resolves to the matching ride request', () async {
    final repository = _FakeRepository(
      records: <PassengerRideRequestRecord>[
        PassengerRideRequestRecord(
          requestReference: 'RR-APP-OTHER',
          status: 'converted',
          pickupLocation: 'Other pickup',
          destination: 'Other destination',
          passengerCount: 1,
          createdAt: DateTime.utc(2026, 9, 12),
          updatedAt: DateTime.utc(2026, 9, 12),
          hasMobileReceipt: true,
          tripCreated: true,
          tripReference: 'TRIP-OTHER',
        ),
        matchingRecord,
      ],
    );

    final resolved = await resolvePassengerPushTripRequest(
      repository: repository,
      tripReference: '  TRIP-PUSH-001  ',
    );

    expect(resolved, same(matchingRecord));
  });

  test('unknown trip reference does not fabricate a destination', () async {
    final repository = _FakeRepository(
      records: <PassengerRideRequestRecord>[matchingRecord],
    );

    final resolved = await resolvePassengerPushTripRequest(
      repository: repository,
      tripReference: 'TRIP-NOT-PRESENT',
    );

    expect(resolved, isNull);
  });

  test('push destination propagates the existing request reference', () {
    final repository = _FakeRepository(
      records: <PassengerRideRequestRecord>[matchingRecord],
    );

    final destination = buildPassengerPushTripDestination(
      repository: repository,
      record: matchingRecord,
    );

    expect(destination, isA<RideTrackingScreen>());
    final tracking = destination as RideTrackingScreen;
    expect(tracking.requestReference, 'RR-APP-PUSH001');
    expect(tracking.initialRecord, same(matchingRecord));
    expect(tracking.tripRepository, same(repository));
  });
}

final class _FakeRepository
    implements
        PassengerRideRequestHistoryRepository,
        PassengerTripLifecycleRepository {
  const _FakeRepository({required this.records});

  final List<PassengerRideRequestRecord> records;

  @override
  Future<List<PassengerRideRequestRecord>> fetchRequests() async => records;

  @override
  Future<PassengerRideRequestRecord> fetchRequest(
    String requestReference,
  ) async {
    return records.firstWhere(
      (record) => record.requestReference == requestReference,
    );
  }

  @override
  Future<PassengerTripRecord> fetchTrip(String tripReference) async {
    return PassengerTripRecord(
      tripReference: tripReference,
      status: 'driver_accepted',
    );
  }
}
