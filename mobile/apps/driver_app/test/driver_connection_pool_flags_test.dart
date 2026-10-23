import 'package:asm_auth/asm_auth.dart';
import 'package:driver_app/driver_duty_trips.dart';
import 'package:driver_app/network/ghana_network_resilience.dart';
import 'package:driver_app/offers/driver_offer_card_wiring.dart';
import 'package:driver_app/offers/driver_pending_offer_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// Only clients that retry a failed request may use pooled connections
/// (AsmApiClient.retriesFailedRequests). These are the driver's.
void main() {
  const baseUrl = 'https://control.example';

  test('the Ghana client retries, so it may pool', () {
    expect(
      GhanaResilientApiClient(baseUrl: baseUrl).retriesFailedRequests,
      isTrue,
    );
  });

  test('the offer card fetch retries once, so it may pool', () {
    final coordinator = driverOfferCoordinatorFor(
      baseUrl: baseUrl,
      tokenStore: MemoryAuthTokenStore(),
      identity: DriverIdentityCachingDutyGateway(
        AsmDriverDutyGateway(GhanaResilientApiClient(baseUrl: baseUrl)),
      ),
    )!;
    final source = coordinator.store.source as ApiDriverPendingOffersSource;

    expect(source.client.retriesFailedRequests, isTrue);
  });

  test('Accept and Decline are retried, so they may pool', () {
    expect(driverOfferResponseClientFor(baseUrl).retriesFailedRequests, isTrue);
  });
}
