enum DriverTripVisualStage {
  navigatingToPickup,
  arrivedAtPickup,
  confirmingPassengerOnboard,
  activeTrip,
  arrivedAtDestination,
  completed,
}

final class DriverTripVisualStateException implements Exception {
  const DriverTripVisualStateException(this.message);

  final String message;

  @override
  String toString() => 'DriverTripVisualStateException: $message';
}

final class DriverTripVisualState {
  const DriverTripVisualState._(this.stage);

  const DriverTripVisualState.initial()
    : stage = DriverTripVisualStage.navigatingToPickup;

  factory DriverTripVisualState.fromBackendStatus(String? status) {
    return DriverTripVisualState._(switch (status?.trim()) {
      'arrived_at_pickup' => DriverTripVisualStage.arrivedAtPickup,
      'passenger_onboard' => DriverTripVisualStage.confirmingPassengerOnboard,
      'in_progress' => DriverTripVisualStage.activeTrip,
      'completed_pending_review' => DriverTripVisualStage.completed,
      _ => DriverTripVisualStage.navigatingToPickup,
    });
  }

  final DriverTripVisualStage stage;

  DriverTripVisualState markArrivedAtPickup() {
    return _transition(
      expected: DriverTripVisualStage.navigatingToPickup,
      next: DriverTripVisualStage.arrivedAtPickup,
    );
  }

  DriverTripVisualState openPassengerOnboardConfirmation() {
    return _transition(
      expected: DriverTripVisualStage.arrivedAtPickup,
      next: DriverTripVisualStage.confirmingPassengerOnboard,
    );
  }

  DriverTripVisualState cancelPassengerOnboardConfirmation() {
    return _transition(
      expected: DriverTripVisualStage.confirmingPassengerOnboard,
      next: DriverTripVisualStage.arrivedAtPickup,
    );
  }

  DriverTripVisualState confirmPassengerOnboard() {
    return _transition(
      expected: DriverTripVisualStage.confirmingPassengerOnboard,
      next: DriverTripVisualStage.activeTrip,
    );
  }

  DriverTripVisualState markArrivedAtDestination() {
    return _transition(
      expected: DriverTripVisualStage.activeTrip,
      next: DriverTripVisualStage.arrivedAtDestination,
    );
  }

  DriverTripVisualState completeTrip() {
    return _transition(
      expected: DriverTripVisualStage.arrivedAtDestination,
      next: DriverTripVisualStage.completed,
    );
  }

  DriverTripVisualState _transition({
    required DriverTripVisualStage expected,
    required DriverTripVisualStage next,
  }) {
    if (stage != expected) {
      throw DriverTripVisualStateException(
        'Cannot move from ${stage.name} to ${next.name}.',
      );
    }

    return DriverTripVisualState._(next);
  }
}
