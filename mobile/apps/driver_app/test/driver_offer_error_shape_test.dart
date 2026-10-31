import 'dart:convert';
import 'dart:typed_data';

import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_auth/asm_auth.dart';
import 'package:dio/dio.dart';
import 'package:driver_app/network/driver_offer_response_gateway.dart';
import 'package:driver_app/network/ghana_network_resilience.dart';
import 'package:flutter_test/flutter_test.dart';

/// The bodies exactly as backend 07e86be returns them
/// (api_driver_assignments.py: `_error` line 56, the 404 at line 227, and
/// Django REST framework's answer for get_object_or_404 at line 206).
const _offerNotPending = <String, Object?>{
  'detail': 'Trip is not waiting for a driver offer response.',
  'code': 'offer_not_pending',
};
const _notAssigned = <String, Object?>{
  'detail': 'Trip offer is not assigned to this driver.',
};
const _noTrip = <String, Object?>{'detail': 'No Trip matches the given query.'};

void main() {
  test('through the real AsmApiClient, a 400 body reaches error.cause with '
      'its code', () async {
    final client = _client(400, jsonEncode(_offerNotPending));
    final response = await client.post<Map<String, Object?>>(
      '/api/driver/trips/TRIP-1/response/',
      data: const <String, Object?>{'response': 'accept'},
    );

    expect(response.statusCode, 400);
    final cause = response.error?.cause;
    expect(cause, isA<Map>());
    expect((cause! as Map)['code'], 'offer_not_pending');
  });

  for (final (status, body, message) in [
    (400, _offerNotPending, 'This offer is no longer available'),
    // B9: a cancel or staff release answers 404 too; only the card, which
    // knows the offer's expiry, says "expired".
    (404, _notAssigned, 'This offer is no longer available'),
    (404, _noTrip, 'This offer is no longer available'),
  ]) {
    test('Accept through the real client: $status ${body['detail']} -> '
        '"$message"', () async {
      final error = await _acceptFailure(_client(status, jsonEncode(body)));
      expect(error.type, DriverOfferResponseFailureType.offerUnavailable);
      expect(error.message, message);
    });
  }

  test(
    'a 400 that is not JSON (a proxy page) stays a client failure',
    () async {
      final error = await _acceptFailure(
        _client(400, '<html>Bad Request</html>', contentType: 'text/html'),
      );
      expect(error.type, DriverOfferResponseFailureType.clientFailure);
    },
  );
}

AsmApiClient _client(
  int status,
  String body, {
  String contentType = 'application/json',
}) {
  final dio = Dio()
    ..httpClientAdapter = _FixedAdapter(status, body, contentType);
  return AsmApiClient(baseUrl: 'https://alanteh.test', dio: dio);
}

Future<DriverOfferResponseException> _acceptFailure(AsmApiClient client) async {
  final tokens = MemoryAuthTokenStore();
  String encode(Object value) =>
      base64UrlEncode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  await tokens.saveTokens(
    AuthTokens(
      accessToken:
          '${encode({'alg': 'none'})}.${encode({'exp': 4102444800})}.sig',
      refreshToken: 'refresh',
    ),
  );
  final gateway = ApiDriverOfferResponseGateway(
    apiGateway: AsmDriverOfferResponseApiGateway(client),
    tokenStore: tokens,
    retryPolicy: GhanaRetryPolicy(delay: (_) async {}),
  );
  try {
    await gateway.accept(
      tripReference: 'TRIP-1',
      idempotencyKey: 'key-1',
      deviceTimestamp: '2026-10-09T10:00:00.000Z',
    );
  } on DriverOfferResponseException catch (error) {
    return error;
  }
  fail('accept should have failed');
}

/// Answers every request with one fixed HTTP response.
final class _FixedAdapter implements HttpClientAdapter {
  _FixedAdapter(this.status, this.body, this.contentType);

  final int status;
  final String body;
  final String contentType;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      body,
      status,
      headers: {
        Headers.contentTypeHeader: [contentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
