import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:asm_api_client/asm_api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DisabledMobileApiGuard', () {
    test('exposes CC4A mobile auth API after accepted handoff', () {
      const guard = DisabledMobileApiGuard();

      expect(guard.mobileAuthApiAvailable, isTrue);
    });

    test('exposes CC4B ride request API after accepted handoff', () {
      const guard = DisabledMobileApiGuard();

      expect(guard.rideRequestApiAvailable, isTrue);
    });

    test('allows CC4A after accepted auth handoff', () {
      const guard = DisabledMobileApiGuard();

      expect(
        () => guard.requireFeature(MobileApiFeature.cc4aMobileAuthApi),
        returnsNormally,
      );
    });

    test('allows CC4B after accepted ride request handoff', () {
      const guard = DisabledMobileApiGuard();

      expect(
        () => guard.requireFeature(MobileApiFeature.cc4bRideRequestApi),
        returnsNormally,
      );
    });

    test(
      'does not expose endpoint URLs, tokens, secrets, or request references',
      () {
        const guard = DisabledMobileApiGuard();
        final exposedText = [
          guard.disabledMessageFor(MobileApiFeature.cc4aMobileAuthApi),
          guard.disabledMessageFor(MobileApiFeature.cc4bRideRequestApi),
        ].join(' ').toLowerCase();

        expect(exposedText, isNot(contains('://')));
        expect(exposedText, isNot(contains('/')));
        expect(exposedText, isNot(contains('api/auth')));
        expect(exposedText, isNot(contains('token')));
        expect(exposedText, isNot(contains('secret')));
        expect(exposedText, isNot(contains('request_reference')));
      },
    );
  });

  group('AsmApiClient', () {
    test('validates mobile API base URL values', () {
      expect(AsmApiBaseUrl.environmentKey, 'ASM_API_BASE_URL');
      expect(AsmApiBaseUrl.isUsable('https://example.com'), isTrue);
      expect(AsmApiBaseUrl.isUsable('http://localhost:8000'), isTrue);
      expect(AsmApiBaseUrl.isUsable('http://127.0.0.1:8000'), isTrue);
      expect(AsmApiBaseUrl.isUsable(''), isFalse);
      expect(AsmApiBaseUrl.isUsable('not a url'), isFalse);
      expect(AsmApiBaseUrl.isUsable('ftp://example.com'), isFalse);
      expect(AsmApiBaseUrl.isUsable('https:///missing-host'), isFalse);
    });

    test('rejects invalid API base URL safely', () {
      expect(() => AsmApiClient(baseUrl: ''), throwsA(isA<ArgumentError>()));
      expect(
        () => AsmApiClient(baseUrl: 'not a url'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('exposes compile-time dart-define API base URL value', () {
      const value = String.fromEnvironment('ASM_API_BASE_URL');

      expect(AsmApiClient.apiBaseUrlEnvironmentKey, 'ASM_API_BASE_URL');
      expect(AsmApiClient.defaultBaseUrl, value);
    });

    test('keeps configured base URL on the client', () {
      final client = AsmApiClient(baseUrl: 'https://example.test');

      expect(client.baseUrl, 'https://example.test');
      expect(AsmApiClient.defaultBaseUrl, isA<String>());
    });

    test('applies the default mobile API request timeout', () {
      final client = AsmApiClient(baseUrl: 'https://example.test');

      expect(AsmApiClient.defaultRequestTimeout, const Duration(seconds: 15));
      expect(client.requestTimeout, const Duration(seconds: 15));
    });

    test('sends standard JSON headers', () async {
      final adapter = _MockHttpClientAdapter();
      final client = _client(adapter);

      final response = await client.get<Object?>('/status');

      expect(response.isSuccess, isTrue);
      expect(_header(adapter.lastOptions, 'Accept'), 'application/json');
      expect(_header(adapter.lastOptions, 'Content-Type'), 'application/json');
    });

    test('sends Authorization header when a token exists', () async {
      final adapter = _MockHttpClientAdapter();
      final client = _client(adapter, token: 'test-token');

      await client.get<Object?>('/status');

      expect(
        _header(adapter.lastOptions, 'Authorization'),
        'Bearer test-token',
      );
    });

    test('does not send Authorization header when token is null', () async {
      final adapter = _MockHttpClientAdapter();
      final client = _client(adapter);

      await client.get<Object?>('/status');

      expect(_header(adapter.lastOptions, 'Authorization'), isNull);
    });

    test('supports POST requests with request data', () async {
      final adapter = _MockHttpClientAdapter();
      final client = _client(adapter);

      final response = await client.post<Object?>(
        '/status',
        data: const <String, Object?>{'message': 'hello'},
      );

      expect(response.isSuccess, isTrue);
      expect(adapter.lastOptions.method, 'POST');
    });

    test('posts passenger ride request to accepted CC4B endpoint', () async {
      final adapter = _MockHttpClientAdapter(
        statusCode: 201,
        responseBody: _rideRequestBody(),
      );
      final client = _client(adapter, token: 'passenger-access-token');

      final response = await client.submitPassengerRideRequest(
        PassengerRideRequestSubmission(
          idempotencyKey: 'APP-a1b2c3d4-e5f6-4890-abcd-ef0000067890',
          pickupLocation: ' Kempinski Hotel Gold Coast City, Accra ',
          destination: 'Kotoka International Airport',
          passengerCount: 2,
          assistanceNote: ' Passenger has two suitcases. ',
        ),
      );

      expect(response.isSuccess, isTrue);
      expect(response.statusCode, 201);
      expect(adapter.lastOptions.method, 'POST');
      expect(adapter.lastOptions.path, '/api/rides/request/');
      expect(
        _header(adapter.lastOptions, 'Authorization'),
        'Bearer passenger-access-token',
      );
      expect(
        _header(adapter.lastOptions, 'Idempotency-Key'),
        'APP-a1b2c3d4-e5f6-4890-abcd-ef0000067890',
      );
      expect(adapter.lastOptions.data, {
        'pickup_location': 'Kempinski Hotel Gold Coast City, Accra',
        'destination': 'Kotoka International Airport',
        'passenger_count': 2,
        'assistance_note': 'Passenger has two suitcases.',
      });
      expect(
        (adapter.lastOptions.data as Map<String, Object?>).containsKey(
          'service_context',
        ),
        isFalse,
      );
      expect(
        (adapter.lastOptions.data as Map<String, Object?>).containsKey(
          'request_reference',
        ),
        isFalse,
      );
      expect(response.data?.requestReference, 'RR-APP-3A9F1C2B4E5D');
      expect(response.data?.status, 'requested');
      expect(
        response.data?.message,
        'Ride request received by the Control Center.',
      );
    });

    test('omits assistance_note when it is blank', () async {
      final adapter = _MockHttpClientAdapter(
        statusCode: 201,
        responseBody: _rideRequestBody(requestReference: null),
      );
      final client = _client(adapter, token: 'passenger-access-token');

      final response = await client.submitPassengerRideRequest(
        PassengerRideRequestSubmission(
          idempotencyKey: 'APP-a1b2c3d4-e5f6-4890-abcd-ef0000067890',
          pickupLocation: 'Osu',
          destination: 'Airport',
          passengerCount: 1,
          assistanceNote: '   ',
        ),
      );

      expect(response.isSuccess, isTrue);
      expect(
        (adapter.lastOptions.data as Map<String, Object?>).containsKey(
          'assistance_note',
        ),
        isFalse,
      );
      expect(response.data?.requestReference, isNull);
    });

    test('handles 200 idempotent duplicate success', () async {
      final response =
          await _client(
            _MockHttpClientAdapter(
              statusCode: 200,
              responseBody: _rideRequestBody(),
            ),
            token: 'passenger-access-token',
          ).submitPassengerRideRequest(
            PassengerRideRequestSubmission(
              idempotencyKey: 'APP-a1b2c3d4-e5f6-4890-abcd-ef0000067890',
              pickupLocation: 'Osu',
              destination: 'Airport',
              passengerCount: 1,
            ),
          );

      expect(response.isSuccess, isTrue);
      expect(response.statusCode, 200);
      expect(response.data?.status, 'requested');
    });

    test('handles ride request validation and permission failures', () async {
      for (final statusCode in [400, 403, 409, 503]) {
        final response =
            await _client(
              _MockHttpClientAdapter(
                statusCode: statusCode,
                responseBody: {
                  'detail': statusCode == 503
                      ? 'Mobile API is not enabled.'
                      : 'Passenger account required.',
                  if (statusCode == 400) 'code': 'pickup_location_required',
                  if (statusCode == 503) 'code': 'mobile_api_disabled',
                },
              ),
              token: 'passenger-access-token',
            ).submitPassengerRideRequest(
              PassengerRideRequestSubmission(
                idempotencyKey: 'APP-a1b2c3d4-e5f6-4890-abcd-ef0000067890',
                pickupLocation: 'Osu',
                destination: 'Airport',
                passengerCount: 1,
              ),
            );

        expect(response.isApiFailure, isTrue);
        expect(response.statusCode, statusCode);
      }
    });

    test('validates ride request submission values locally', () {
      expect(
        () => PassengerRideRequestSubmission(
          idempotencyKey: '',
          pickupLocation: 'Osu',
          destination: 'Airport',
          passengerCount: 1,
        ),
        throwsArgumentError,
      );
      expect(
        () => PassengerRideRequestSubmission(
          idempotencyKey: 'APP-a1b2c3d4-e5f6-4890-abcd-ef0000067890',
          pickupLocation: 'Osu',
          destination: 'Airport',
          passengerCount: 7,
        ),
        throwsArgumentError,
      );
    });

    test('maps 401 to authentication error', () async {
      final response = await _client(
        _MockHttpClientAdapter(statusCode: 401),
      ).get<Object?>('/status');

      expect(response.isApiFailure, isTrue);
      expect(response.statusCode, 401);
      expect(response.error?.type, AsmApiExceptionType.authentication);
    });

    test('maps 404 to not found error', () async {
      final response = await _client(
        _MockHttpClientAdapter(statusCode: 404),
      ).get<Object?>('/missing');

      expect(response.isApiFailure, isTrue);
      expect(response.statusCode, 404);
      expect(response.error?.type, AsmApiExceptionType.notFound);
    });

    test('maps 5xx to server error', () async {
      final response = await _client(
        _MockHttpClientAdapter(statusCode: 503),
      ).get<Object?>('/status');

      expect(response.isApiFailure, isTrue);
      expect(response.statusCode, 503);
      expect(response.error?.type, AsmApiExceptionType.server);
    });

    test('maps connection timeout to timeout error', () async {
      final response = await _client(
        _MockHttpClientAdapter(failureType: DioExceptionType.connectionTimeout),
      ).get<Object?>('/status');

      expect(response.isClientException, isTrue);
      expect(response.error?.type, AsmApiExceptionType.timeout);
    });

    test('maps receive timeout to timeout error', () async {
      final response = await _client(
        _MockHttpClientAdapter(failureType: DioExceptionType.receiveTimeout),
      ).get<Object?>('/status');

      expect(response.isClientException, isTrue);
      expect(response.error?.type, AsmApiExceptionType.timeout);
    });

    test('maps transform timeout to timeout error when available', () async {
      final transformTimeout = _dioExceptionTypeByName('transformTimeout');
      if (transformTimeout == null) {
        return;
      }

      final response = await _client(
        _MockHttpClientAdapter(failureType: transformTimeout),
      ).get<Object?>('/status');

      expect(response.isClientException, isTrue);
      expect(response.error?.type, AsmApiExceptionType.timeout);
    });

    test('allows a shorter injected request timeout for tests', () async {
      final pending = Completer<ResponseBody>();
      final adapter = _MockHttpClientAdapter(pendingResponse: pending);
      final response = await _client(
        adapter,
        requestTimeout: const Duration(milliseconds: 1),
      ).get<Object?>('/status');

      expect(adapter.lastOptions.path, '/status');
      expect(response.isClientException, isTrue);
      expect(response.error?.type, AsmApiExceptionType.timeout);
      expect(response.error?.message, 'The API request timed out.');
    });

    test('maps network failure to network error', () async {
      final response = await _client(
        _MockHttpClientAdapter(failureType: DioExceptionType.connectionError),
      ).get<Object?>('/status');

      expect(response.isClientException, isTrue);
      expect(response.error?.type, AsmApiExceptionType.network);
    });

    test('keeps ApiResponse success and failure state clear', () async {
      final success = ApiResponse.success(const <String, Object?>{
        'ok': true,
      }, statusCode: 200);
      final failure = ApiResponse.apiFailure(
        const AsmApiException(
          type: AsmApiExceptionType.badResponse,
          message: 'Bad response',
          statusCode: 400,
        ),
      );

      expect(success.isSuccess, isTrue);
      expect(success.isApiFailure, isFalse);
      expect(success.isClientException, isFalse);
      expect(success.statusCode, 200);
      expect(success.data, const <String, Object?>{'ok': true});

      expect(failure.isSuccess, isFalse);
      expect(failure.isApiFailure, isTrue);
      expect(failure.isClientException, isFalse);
      expect(failure.statusCode, 400);
      expect(failure.error?.type, AsmApiExceptionType.badResponse);
    });
  });
}

DioExceptionType? _dioExceptionTypeByName(String name) {
  for (final type in DioExceptionType.values) {
    if (type.name == name) {
      return type;
    }
  }
  return null;
}

String? _header(RequestOptions options, String name) {
  for (final entry in options.headers.entries) {
    if (entry.key.toLowerCase() == name.toLowerCase()) {
      return entry.value?.toString();
    }
  }
  return null;
}

AsmApiClient _client(
  _MockHttpClientAdapter adapter, {
  String? token,
  Duration? requestTimeout,
}) {
  final dio = Dio()..httpClientAdapter = adapter;
  return AsmApiClient(
    baseUrl: 'https://control.example/api/',
    dio: dio,
    tokenProvider: _FixedTokenProvider(token),
    requestTimeout: requestTimeout ?? AsmApiClient.defaultRequestTimeout,
  );
}

class _FixedTokenProvider implements TokenProvider {
  const _FixedTokenProvider(this.token);

  final String? token;

  @override
  FutureOr<String?> getAccessToken() => token;
}

class _MockHttpClientAdapter implements HttpClientAdapter {
  _MockHttpClientAdapter({
    this.statusCode = 200,
    this.failureType,
    this.responseBody = const <String, Object?>{'ok': true},
    this.pendingResponse,
  });

  final int statusCode;
  final DioExceptionType? failureType;
  final Object? responseBody;
  final Completer<ResponseBody>? pendingResponse;

  late RequestOptions lastOptions;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastOptions = options;

    final pending = pendingResponse;
    if (pending != null) {
      return pending.future;
    }

    final type = failureType;
    if (type != null) {
      throw DioException(
        requestOptions: options,
        type: type,
        error: 'mock failure',
      );
    }

    return ResponseBody.fromString(
      jsonEncode(responseBody),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

Map<String, Object?> _rideRequestBody({
  String? requestReference = 'RR-APP-3A9F1C2B4E5D',
}) {
  return <String, Object?>{
    if (requestReference != null) 'request_reference': requestReference,
    'status': 'requested',
    'message': 'Ride request received by the Control Center.',
  };
}
