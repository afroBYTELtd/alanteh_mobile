import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_auth/asm_auth.dart';

import '../network/driver_offer_response_gateway.dart';
import '../network/driver_offer_response_resilience.dart';
import '../network/driver_trip_action_gateway.dart';
import '../network/driver_trip_action_resilience.dart';
import '../network/ghana_network_resilience.dart';
import 'driver_offer_coordinator.dart';
import 'driver_pending_offer_store.dart';
import 'driver_pending_offers.dart';

/// The offer store and its poll, or null when the app has no API address.
DriverOfferCoordinator? driverOfferCoordinatorFor({
  required String? baseUrl,
  required AuthTokenStore tokenStore,
  required DriverIdentityCachingDutyGateway? identity,
  DriverAccessTokenRefresh? refreshAccessToken,
  Future<void> Function()? onSessionExpired,
}) {
  if (!AsmApiBaseUrl.isUsable(baseUrl) || identity == null) {
    return null;
  }
  return DriverOfferCoordinator(
    store: DriverPendingOfferStore(
      source: ApiDriverPendingOffersSource(
        client: AsmApiClient(
          baseUrl: baseUrl!,
          tokenProvider: DriverStoredAccessTokenProvider(tokenStore),
          connectTimeout: DriverOfferCardTiming.fetchConnectTimeout,
          sendTimeout: DriverOfferCardTiming.fetchConnectTimeout,
          receiveTimeout: DriverOfferCardTiming.fetchRequestTimeout,
          requestTimeout: DriverOfferCardTiming.fetchRequestTimeout,
        ),
        refreshAccessToken: refreshAccessToken,
      ),
      onSessionExpired: onSessionExpired,
    ),
    identity: identity,
  );
}

/// Accept and decline for the card: short timeouts, at most three tries with
/// the same idempotency key, and the driver reference from the duty data the
/// app already loaded (fetched only if missing).
DriverOfferResponseControllerFactory driverOfferCardControllerFactoryFor({
  required String baseUrl,
  required AuthTokenStore tokenStore,
  required DriverIdentityCachingDutyGateway identity,
  DriverAccessTokenRefresh? refreshAccessToken,
  DriverTripActionPersistentQueue? persistentQueue,
}) {
  final gateway = ApiDriverOfferResponseGateway(
    apiGateway: AsmDriverOfferResponseApiGateway(
      AsmApiClient(
        baseUrl: baseUrl,
        connectTimeout: DriverOfferCardTiming.responseConnectTimeout,
        sendTimeout: DriverOfferCardTiming.responseConnectTimeout,
        receiveTimeout: DriverOfferCardTiming.responseRequestTimeout,
        requestTimeout: DriverOfferCardTiming.responseRequestTimeout,
      ),
    ),
    tokenStore: tokenStore,
    refreshAccessToken: refreshAccessToken,
    retryPolicy: const GhanaRetryPolicy(
      backoffs: DriverOfferCardTiming.responseRetryBackoffs,
    ),
  );
  final queue = persistentQueue ?? PersistentDriverTripActionQueue();

  return (tripReference, {assignedAt, unknownOffer = false}) async {
    var driverReference = identity.driverReference;
    if (driverReference == null) {
      try {
        driverReference = (await identity.fetchDuty()).driverReference?.trim();
      } on Object {
        throw const DriverOfferPreparationException(
          DriverOfferPreparationFailureCode.driverDutyFetchFailed,
        );
      }
    }
    if (driverReference == null || driverReference.isEmpty) {
      throw const DriverOfferPreparationException(
        DriverOfferPreparationFailureCode.driverReferenceMissing,
      );
    }
    return DriverOfferResponseResilienceController(
      queue: queue,
      gateway: gateway,
      tripReference: tripReference,
      driverId: driverReference,
      assignedAt: assignedAt,
      unknownOffer: unknownOffer,
      // The receipt carries the trip's status after the answer, so no second
      // request stands between the server's answer and the driver.
      verifyServerState: (receipt) async => DriverOfferVerifiedTrip(
        tripReference: receipt.tripReference ?? tripReference,
        status: receipt.tripStatus,
        source: receipt,
      ),
    );
  };
}

/// Whether an offer is for now or later, from the trip detail (whose
/// `requested_pickup_time` is null for a ride now).
DriverOfferPickupTimeLookupFn driverOfferPickupTimeLookupFor(
  DriverIdentityCachingDutyGateway identity,
) {
  return (tripReference) async {
    final trip = await identity.fetchTripDetail(tripReference);
    final raw = trip.requestedPickupTime?.trim();
    final at = raw == null || raw.isEmpty ? null : DateTime.tryParse(raw);
    return at == null
        ? const DriverOfferPickupNow()
        : DriverOfferPickupAt(at.toUtc());
  };
}

typedef DriverOfferPickupTimeLookupFn =
    Future<DriverOfferPickupTime> Function(String tripReference);
