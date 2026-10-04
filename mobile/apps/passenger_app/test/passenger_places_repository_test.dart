import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_auth/asm_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:passenger_app/location/passenger_places.dart';

void main() {
  test('autocomplete sends the text and the session token', () async {
    final gateway = _RecordingPlacesGateway([
      _Reply.success({
        'suggestions': [
          {
            'place_id': 'ChIJ_accra_mall',
            'main_text': 'Accra Mall',
            'secondary_text': 'Tetteh Quarshie, Accra',
          },
        ],
      }),
    ]);
    final repository = await _repository(gateway);

    final suggestions = await repository.autocomplete(
      'Accra',
      sessionToken: _token,
    );

    expect(gateway.paths, ['/api/places/autocomplete/']);
    expect(gateway.bodies.single, {'input': 'Accra', 'session_token': _token});
    expect(suggestions.single.placeId, 'ChIJ_accra_mall');
    expect(suggestions.single.mainText, 'Accra Mall');
    expect(suggestions.single.secondaryText, 'Tetteh Quarshie, Accra');
  });

  test('no matches is an empty list', () async {
    final repository = await _repository(
      _RecordingPlacesGateway([
        _Reply.success({'suggestions': <Object?>[]}),
      ]),
    );

    expect(
      await repository.autocomplete('zzzz', sessionToken: _token),
      isEmpty,
    );
  });

  test('details sends the place and the same token', () async {
    final gateway = _RecordingPlacesGateway([
      _Reply.success({
        'place_id': 'ChIJ_accra_mall',
        'latitude': 5.6227,
        'longitude': -0.1737,
      }),
    ]);
    final repository = await _repository(gateway);

    final place = await repository.details(
      'ChIJ_accra_mall',
      sessionToken: _token,
    );

    expect(gateway.paths, ['/api/places/details/']);
    expect(gateway.bodies.single, {
      'place_id': 'ChIJ_accra_mall',
      'session_token': _token,
    });
    expect(place.placeId, 'ChIJ_accra_mall');
    expect(place.coordinates, const LatLng(5.6227, -0.1737));
  });

  for (final status in [503, 429, 404, 409, 400, 500]) {
    test('$status means search is unavailable', () async {
      final repository = await _repository(
        _RecordingPlacesGateway([_Reply.failure(status)]),
      );

      await expectLater(
        repository.autocomplete('Accra', sessionToken: _token),
        throwsA(isA<PassengerPlacesUnavailableException>()),
      );
    });
  }

  test('no connection means search is unavailable', () async {
    final repository = await _repository(
      _RecordingPlacesGateway([_Reply.offline()]),
    );

    await expectLater(
      repository.details('ChIJ_accra_mall', sessionToken: _token),
      throwsA(isA<PassengerPlacesUnavailableException>()),
    );
  });

  test('a malformed answer means search is unavailable', () async {
    final repository = await _repository(
      _RecordingPlacesGateway([
        _Reply.success({'place_id': 'ChIJ_accra_mall', 'latitude': 'north'}),
      ]),
    );

    await expectLater(
      repository.details('ChIJ_accra_mall', sessionToken: _token),
      throwsA(isA<PassengerPlacesUnavailableException>()),
    );
  });

  test('a 401 refreshes once and repeats the same call', () async {
    final store = MemoryAuthTokenStore();
    await store.saveTokens(
      AuthTokens(accessToken: 'expired', refreshToken: 'stored-refresh'),
    );
    final gateway = _RecordingPlacesGateway([
      _Reply.failure(401),
      _Reply.success({'suggestions': <Object?>[]}),
    ]);
    final authGateway = _RecordingAuthGateway();
    final repository = ApiPassengerPlacesRepository(
      gateway,
      tokenStore: store,
      authService: AuthService(apiGateway: authGateway, tokenStore: store),
    );

    await repository.autocomplete('Accra', sessionToken: _token);

    expect(gateway.bodies, [
      {'input': 'Accra', 'session_token': _token},
      {'input': 'Accra', 'session_token': _token},
    ]);
    expect(authGateway.paths, [AuthService.refreshPath]);
  });

  test('session tokens are fresh UUID v4s', () {
    final first = newPlacesSessionToken();
    final second = newPlacesSessionToken();

    final uuidV4 = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );
    expect(first, matches(uuidV4));
    expect(second, matches(uuidV4));
    expect(first, isNot(second));
  });
}

const _token = '6f1c2b4e-5d3a-4c9f-8a1b-2c3d4e5f6a7b';

Future<ApiPassengerPlacesRepository> _repository(
  PassengerPlacesApiGateway gateway,
) async {
  final store = MemoryAuthTokenStore();
  await store.saveTokens(
    AuthTokens(accessToken: 'access', refreshToken: 'refresh'),
  );
  return ApiPassengerPlacesRepository(gateway, tokenStore: store);
}

final class _Reply {
  _Reply.success(this.payload) : status = 200;
  _Reply.failure(this.status) : payload = null;
  _Reply.offline() : status = null, payload = null;

  final int? status;
  final Object? payload;
}

final class _RecordingPlacesGateway implements PassengerPlacesApiGateway {
  _RecordingPlacesGateway(this._replies);

  final List<_Reply> _replies;
  final paths = <String>[];
  final bodies = <Map<String, Object?>>[];

  @override
  Future<ApiResponse<T>> post<T>(
    String path, {
    required Map<String, Object?> data,
    required JsonDecoder<T> decoder,
  }) async {
    paths.add(path);
    bodies.add(Map.of(data));
    final reply = _replies.removeAt(0);
    final status = reply.status;
    if (status == null) {
      return ApiResponse<T>.clientException(
        const AsmApiException(
          type: AsmApiExceptionType.network,
          message: 'No connection.',
        ),
      );
    }
    if (status != 200) {
      return ApiResponse<T>.apiFailure(
        AsmApiException(
          type: status == 401
              ? AsmApiExceptionType.authentication
              : AsmApiExceptionType.badResponse,
          message: 'Failed.',
          statusCode: status,
        ),
      );
    }
    try {
      return ApiResponse<T>.success(decoder(reply.payload), statusCode: 200);
    } on FormatException catch (error) {
      return ApiResponse<T>.clientException(
        AsmApiException(
          type: AsmApiExceptionType.badResponse,
          message: 'Bad answer.',
          cause: error,
        ),
      );
    }
  }
}

class _RecordingAuthGateway implements AuthApiGateway {
  final paths = <String>[];

  @override
  Future<ApiResponse<Map<String, Object?>>> post(
    String path, {
    required Map<String, Object?> body,
  }) async {
    paths.add(path);
    return ApiResponse<Map<String, Object?>>.success(const <String, Object?>{
      'access': 'refreshed-access',
    }, statusCode: 200);
  }
}
