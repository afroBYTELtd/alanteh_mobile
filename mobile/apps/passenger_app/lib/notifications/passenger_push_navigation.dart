import 'package:flutter/material.dart';

import '../payment_rating/passenger_payment_rating_contract.dart';
import '../ride_requests/ride_request_history.dart';
import '../safety/passenger_trip_safety.dart';
import '../tracking/ride_tracking_screen.dart';

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
    phoneNumber: phoneNumber,
    onSignInRequired: onSignInRequired,
  );
}
