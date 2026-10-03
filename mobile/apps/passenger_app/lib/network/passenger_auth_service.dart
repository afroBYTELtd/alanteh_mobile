import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_auth/asm_auth.dart';

import 'ghana_network_resilience.dart';

/// Retries a token refresh on the Ghana schedule. Repeating a refresh is
/// safe: refresh tokens are not rotated.
AuthRefreshRetry ghanaAuthRefreshRetry([
  GhanaRetryPolicy policy = const GhanaRetryPolicy(),
]) {
  return (attempt) => policy.execute<Map<String, Object?>>(
    safeToRetry: true,
    operation: attempt,
  );
}

/// The passenger app's auth service. A refresh that cannot reach the
/// server is retried, then keeps the stored sign-in; only a rejection by
/// the server clears it.
AuthService passengerAuthService({
  required AsmApiClient client,
  AuthTokenStore? tokenStore,
  AuthAppContext? appContext,
}) {
  return AuthService.withApiClient(
    client: client,
    tokenStore: tokenStore,
    appContext: appContext,
    refreshRetry: ghanaAuthRefreshRetry(),
  );
}
