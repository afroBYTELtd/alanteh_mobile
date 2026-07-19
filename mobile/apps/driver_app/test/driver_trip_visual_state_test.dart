import 'package:driver_app/trip_progress/driver_trip_route.dart';
import 'package:driver_app/trip_progress/driver_trip_visual_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pickup and destination routes use safe static fallbacks', () {
    final pickup = safeDriverPickupRouteFallback();
    final destination = safeDriverDestinationRouteFallback();

    expect(pickup.usedFallback, isTrue);
    expect(pickup.points.length, greaterThanOrEqualTo(2));
    expect(pickup.vehiclePosition, driverPickupStaticPosition);
    expect(pickup.distanceKilometres, 1.2);
    expect(pickup.durationMinutes, 5);

    expect(destination.usedFallback, isTrue);
    expect(destination.points.length, greaterThanOrEqualTo(2));
    expect(destination.vehiclePosition, driverActiveStaticPosition);
    expect(destination.distanceKilometres, 9.5);
    expect(destination.durationMinutes, 23);
  });

  test('trip visual state follows the approved local sequence immutably', () {
    const initial = DriverTripVisualState.initial();

    final arrivedPickup = initial.markArrivedAtPickup();
    final confirming = arrivedPickup.openPassengerOnboardConfirmation();
    final active = confirming.confirmPassengerOnboard();
    final arrivedDestination = active.markArrivedAtDestination();
    final completed = arrivedDestination.completeTrip();

    expect(initial.stage, DriverTripVisualStage.navigatingToPickup);
    expect(arrivedPickup.stage, DriverTripVisualStage.arrivedAtPickup);
    expect(confirming.stage, DriverTripVisualStage.confirmingPassengerOnboard);
    expect(active.stage, DriverTripVisualStage.activeTrip);
    expect(
      arrivedDestination.stage,
      DriverTripVisualStage.arrivedAtDestination,
    );
    expect(completed.stage, DriverTripVisualStage.completed);

    expect(identical(initial, arrivedPickup), isFalse);
    expect(identical(arrivedPickup, confirming), isFalse);
    expect(identical(confirming, active), isFalse);
    expect(identical(active, arrivedDestination), isFalse);
    expect(identical(arrivedDestination, completed), isFalse);
  });

  test('passenger confirmation can return to arrived pickup state', () {
    final confirming = const DriverTripVisualState.initial()
        .markArrivedAtPickup()
        .openPassengerOnboardConfirmation();

    final returned = confirming.cancelPassengerOnboardConfirmation();

    expect(returned.stage, DriverTripVisualStage.arrivedAtPickup);
  });

  test('out-of-order local trip transitions are rejected', () {
    const initial = DriverTripVisualState.initial();

    expect(
      initial.completeTrip,
      throwsA(isA<DriverTripVisualStateException>()),
    );
    expect(
      initial.confirmPassengerOnboard,
      throwsA(isA<DriverTripVisualStateException>()),
    );

    final completed = initial
        .markArrivedAtPickup()
        .openPassengerOnboardConfirmation()
        .confirmPassengerOnboard()
        .markArrivedAtDestination()
        .completeTrip();

    expect(
      completed.completeTrip,
      throwsA(isA<DriverTripVisualStateException>()),
    );
  });
}
