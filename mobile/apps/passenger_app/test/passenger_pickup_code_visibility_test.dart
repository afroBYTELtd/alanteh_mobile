import 'package:flutter_test/flutter_test.dart';
import 'package:passenger_app/ride_requests/ride_request_history.dart';

// The pickup code is for the moment the driver meets the passenger: from the
// driver's accept until the driver is at the pickup. The server now sends it
// only then, but a saved copy of the trip, or a reply from an older server,
// can still hold one: code 0660 stayed on screen after a dispatch cancel
// (24 Oct) and 1031 on a completed trip (23 Oct).
void main() {
  const shown = {
    'driver_accepted',
    'dispatched',
    'driver_en_route',
    'arrived_at_pickup',
  };
  const everyTripStatus = [
    'requested',
    'under_review',
    'fare_confirmed',
    'awaiting_payment',
    'payment_confirmed',
    'driver_offer_sent',
    'driver_accepted',
    'driver_declined',
    'assigned',
    'dispatched',
    'driver_en_route',
    'arrived_at_pickup',
    'passenger_onboard',
    'in_progress',
    'arrived_at_destination',
    'completed_pending_review',
    'completed_confirmed',
    'review_overdue',
    'cancelled_by_passenger',
    'cancelled_by_operations',
    'no_show',
    'disputed',
  ];

  test('the code shows only from accept until the driver is at the pickup', () {
    for (final status in everyTripStatus) {
      expect(
        _record(status).shownPickupVerificationCode,
        shown.contains(status) ? '0660' : isNull,
        reason: status,
      );
    }
  });

  test('a cancel reply without the code hides the saved one', () {
    final saved = _record(
      'converted',
    ).withTrip(_trip('driver_accepted', pickupVerificationCode: '0660'));
    expect(saved.shownPickupVerificationCode, '0660');

    // An older reply leaves the code out; the merge keeps the saved one, so
    // only the status can hide it.
    final cancelled = saved.withTrip(_trip('cancelled_by_operations'));

    expect(cancelled.pickupVerificationCode, '0660');
    expect(cancelled.shownPickupVerificationCode, isNull);
  });

  test('a cancel answered directly hides the code and the driver', () {
    final cancelled = _record(
      'driver_en_route',
    ).withStatus('cancelled_by_passenger');

    expect(cancelled.shownPickupVerificationCode, isNull);
    expect(cancelled.shownDriverName, isNull);
    expect(cancelled.shownPlateNumber, isNull);
  });

  test('cancelled and no-show trips show no driver or vehicle', () {
    for (final status in const [
      'cancelled_by_passenger',
      'cancelled_by_operations',
      'no_show',
    ]) {
      final record = _record(status);
      expect(record.shownDriverName, isNull, reason: status);
      expect(record.shownVehicleType, isNull, reason: status);
      expect(record.shownVehicleColour, isNull, reason: status);
      expect(record.shownPlateNumber, isNull, reason: status);
    }
  });

  test('completed trips keep the driver and vehicle, for the receipt and '
      'the rating', () {
    for (final status in const [
      'arrived_at_destination',
      'completed_pending_review',
      'completed_confirmed',
      'review_overdue',
      'disputed',
    ]) {
      final record = _record(status);
      expect(record.shownDriverName, 'Kwame Mensah', reason: status);
      expect(record.shownVehicleType, 'Solar Taxi', reason: status);
      expect(record.shownVehicleColour, 'Green', reason: status);
      expect(record.shownPlateNumber, 'GT 1234-26', reason: status);
      expect(record.shownPickupVerificationCode, isNull, reason: status);
    }
  });
}

PassengerRideRequestRecord _record(String status) => PassengerRideRequestRecord(
  requestReference: 'RR-CODE-001',
  status: status,
  pickupLocation: 'Osu pickup',
  destination: 'Airport destination',
  passengerCount: 1,
  createdAt: DateTime.utc(2026, 10, 24, 9),
  updatedAt: DateTime.utc(2026, 10, 24, 9, 5),
  hasMobileReceipt: true,
  tripCreated: true,
  tripReference: 'TRIP-CODE-001',
  plateNumber: 'GT 1234-26',
  pickupVerificationCode: '0660',
  driverName: 'Kwame Mensah',
  vehicleType: 'Solar Taxi',
  vehicleColour: 'Green',
);

PassengerTripRecord _trip(String status, {String? pickupVerificationCode}) =>
    PassengerTripRecord(
      tripReference: 'TRIP-CODE-001',
      status: status,
      controlCenterMessage: 'Passenger-safe trip update.',
      pickupVerificationCode: pickupVerificationCode,
    );
