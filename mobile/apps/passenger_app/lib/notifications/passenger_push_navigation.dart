import 'package:flutter/material.dart';

import '../network/passenger_cancellation_gateway.dart';
import '../payment_rating/passenger_payment_rating_contract.dart';
import '../ride_requests/ride_request_history.dart';
import '../safety/passenger_trip_safety.dart';
import '../tracking/ride_tracking_screen.dart';
import 'push_notification_runtime.dart';

Future<PassengerRideRequestRecord?> resolvePassengerPushTripRequest({
  required PassengerRideRequestHistoryRepository repository,
  required String tripReference,
}) async {
  final normalizedTripReference = tripReference.trim();
  if (normalizedTripReference.isEmpty) {
    return null;
  }

  final records = await repository.fetchRequests();
  for (final record in records) {
    if (record.normalizedTripReference == normalizedTripReference) {
      return record;
    }
  }

  return null;
}

Widget buildPassengerPushTripDestination({
  required PassengerRideRequestHistoryRepository repository,
  required PassengerRideRequestRecord record,
  PassengerPaymentRatingRepository? paymentRatingRepository,
  PassengerTrustedContactRepository? trustedContactRepository,
  PassengerCancellationGateway? cancellationGateway,
  String? phoneNumber,
  VoidCallback? onSignInRequired,
}) {
  return RideTrackingScreen(
    repository: repository,
    requestReference: record.requestReference,
    initialRecord: record,
    tripRepository: repository is PassengerTripLifecycleRepository
        ? repository as PassengerTripLifecycleRepository
        : null,
    paymentRatingRepository: paymentRatingRepository,
    trustedContactRepository: trustedContactRepository,
    cancellationGateway: cancellationGateway,
    phoneNumber: phoneNumber,
    onSignInRequired: onSignInRequired,
  );
}

/// Opens the trip a push names: finds its ride request, then pushes the
/// screen [buildDestination] makes. [canNavigate] is asked before the
/// lookup and again after it (the passenger may have signed out meanwhile).
Future<void> openPassengerPushTrip({
  required NavigatorState navigator,
  required PassengerRideRequestHistoryRepository repository,
  required PassengerPushNavigationIntent intent,
  required bool Function() canNavigate,
  required Widget Function(PassengerRideRequestRecord record) buildDestination,
}) async {
  if (!canNavigate()) {
    return;
  }

  PassengerRideRequestRecord? record;
  try {
    record = await resolvePassengerPushTripRequest(
      repository: repository,
      tripReference: intent.tripReference,
    );
  } on Object {
    return;
  }

  if (!canNavigate() || record == null) {
    return;
  }

  final found = record;
  await navigator.push<void>(
    MaterialPageRoute<void>(builder: (_) => buildDestination(found)),
  );
}
