import 'package:flutter_test/flutter_test.dart';
import 'package:passenger_app/network/ghana_network_resilience.dart';

/// Only clients that retry a failed request may use pooled connections
/// (AsmApiClient.retriesFailedRequests).
void main() {
  test('the Ghana client retries, so it may pool', () {
    expect(
      GhanaResilientApiClient(
        baseUrl: 'https://control.example',
      ).retriesFailedRequests,
      isTrue,
    );
  });
}
