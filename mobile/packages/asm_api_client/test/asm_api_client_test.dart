import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:asm_api_client/asm_api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DisabledMobileApiGuard', () {
    test('keeps CC4A mobile auth API unavailable', () {
      const guard = DisabledMobileApiGuard();

      expect(guard.mobileAuthApiAvailable, isFalse);
    });

    test('keeps CC4B ride request API unavailable', () {
      const guard = DisabledMobileApiGuard();

      expect(guard.rideRequestApiAvailable, isFalse);
    });

    test('requires CC4A with the disabled handoff message', () {
      const guard = DisabledMobileApiGuard();

      expect(
        () => guard.requireFeature(MobileApiFeature.cc4aMobileAuthApi),
        throwsA(
          isA<DisabledMobileApiException>().having(
            (error) => error.message,
            'message',
            'CC4A Mobile auth API is disabled pending Control Center handoff',
          ),
        ),
      );
    });

    test('requires CC4B with the disabled handoff message', () {
      const guard = DisabledMobileApiGuard();

      expect(
        () => guard.requireFeature(MobileApiFeature.cc4bRideRequestApi),
        throwsA(
          isA<DisabledMobileApiException>().having(
            (error) => error.message,
            'message',
            'CC4B Ride request API is disabled pending Control Center handoff',
          ),
        ),
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

AsmApiClient _client(_MockHttpClientAdapter adapter, {String? token}) {
  final dio = Dio()..httpClientAdapter = adapter;
  return AsmApiClient(
    baseUrl: 'https://control.example/api/',
    dio: dio,
    tokenProvider: _FixedTokenProvider(token),
  );
}

class _FixedTokenProvider implements TokenProvider {
  const _FixedTokenProvider(this.token);

  final String? token;

  @override
  FutureOr<String?> getAccessToken() => token;
}

class _MockHttpClientAdapter implements HttpClientAdapter {
  _MockHttpClientAdapter({this.statusCode = 200, this.failureType});

  final int statusCode;
  final DioExceptionType? failureType;

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
    final type = failureType;
    if (type != null) {
      throw DioException(
        requestOptions: options,
        type: type,
        error: 'mock failure',
      );
    }

    return ResponseBody.fromString(
      jsonEncode(const <String, Object?>{'ok': true}),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}
