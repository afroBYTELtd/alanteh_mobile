import 'dart:io';

import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_auth/asm_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:passenger_app/location/passenger_landmarks.dart';

// Google's EEA terms keep Places and Geocoding text off any map, so a pin
// is labelled from ALANTEH's own landmarks (GET /api/landmarks/), then the
// passenger's own words, then "Pinned location" - never Google's text.
const _accraMall = PassengerLandmark(
  id: 1,
  name: 'Accra Mall',
  coordinates: LatLng(5.6227, -0.1737),
  radiusMetres: 150,
);
const _airport = PassengerLandmark(
  id: 2,
  name: 'Kotoka Airport Terminal 3',
  coordinates: LatLng(5.6052, -0.1668),
  radiusMetres: 300,
);

void main() {
  group('the label rule', () {
    test('a pin inside a landmark radius is near it', () {
      // About 100 m north of Accra Mall.
      expect(
        landmarkLabelFor(const LatLng(5.6236, -0.1737), [_accraMall, _airport]),
        'Near Accra Mall',
      );
    });

    test('a pin outside every radius has no landmark', () {
      // About 200 m from Accra Mall, outside its 150 m.
      expect(
        landmarkLabelFor(const LatLng(5.6245, -0.1737), [_accraMall]),
        isNull,
      );
      expect(landmarkLabelFor(const LatLng(5.6236, -0.1737), const []), isNull);
    });

    test('the nearest covering landmark wins', () {
      const wide = PassengerLandmark(
        id: 3,
        name: 'Airport Residential Area',
        coordinates: LatLng(5.6060, -0.1670),
        radiusMetres: 1000,
      );
      expect(
        landmarkLabelFor(const LatLng(5.6053, -0.1668), [wide, _airport]),
        'Near Kotoka Airport Terminal 3',
      );
    });

    test('the fallback is the passenger\'s words, then Pinned location', () {
      expect(
        passengerPinLabel(landmark: 'Near Accra Mall', ownWords: 'Gate 2'),
        'Near Accra Mall',
      );
      expect(
        passengerPinLabel(landmark: null, ownWords: '  Gate 2 '),
        'Gate 2',
      );
      expect(
        passengerPinLabel(landmark: null, ownWords: '  '),
        'Pinned location',
      );
      expect(
        passengerPinLabel(landmark: null, ownWords: null),
        'Pinned location',
      );
    });
  });

  group('the landmark list', () {
    test('is read from GET /api/landmarks/', () async {
      final gateway = _Gateway([
        _Reply.success({
          'landmarks': [
            {
              'id': 1,
              'name': 'Accra Mall',
              'latitude': 5.6227,
              'longitude': -0.1737,
              'radius_metres': 150,
            },
          ],
        }),
      ]);
      final repository = await _repository(gateway);

      final landmarks = await repository.fetch();

      expect(gateway.paths, ['/api/landmarks/']);
      expect(landmarks.single.id, 1);
      expect(landmarks.single.name, 'Accra Mall');
      expect(landmarks.single.coordinates, const LatLng(5.6227, -0.1737));
      expect(landmarks.single.radiusMetres, 150);
    });

    test('skips malformed entries and keeps the rest', () async {
      final repository = await _repository(
        _Gateway([
          _Reply.success({
            'landmarks': [
              {
                'id': 1,
                'name': '',
                'latitude': 5.6,
                'longitude': -0.1,
                'radius_metres': 150,
              },
              {
                'id': 2,
                'name': 'No radius',
                'latitude': 5.6,
                'longitude': -0.1,
              },
              {
                'id': 3,
                'name': 'Good',
                'latitude': 5.6,
                'longitude': -0.1,
                'radius_metres': 90,
              },
              'not a map',
            ],
          }),
        ]),
      );

      final landmarks = await repository.fetch();

      expect(landmarks.map((landmark) => landmark.name), ['Good']);
    });

    for (final status in [404, 503, 500, null]) {
      test('${status ?? 'no connection'} gives no landmarks', () async {
        final repository = await _repository(
          _Gateway([
            status == null ? _Reply.offline() : _Reply.failure(status),
          ]),
        );

        await expectLater(
          repository.fetch(),
          throwsA(isA<PassengerLandmarksUnavailableException>()),
        );
      });
    }

    test('the directory fetches once per session', () async {
      final repository = _CountingRepository([_accraMall]);
      final directory = PassengerLandmarkDirectory(repository);

      expect(await directory.landmarks(), [_accraMall]);
      expect(await directory.landmarks(), [_accraMall]);
      expect(repository.calls, 1);
    });

    test('a failed fetch is no landmarks, and is tried again later', () async {
      final repository = _CountingRepository([_accraMall], failures: 1);
      final directory = PassengerLandmarkDirectory(repository);

      expect(await directory.landmarks(), isEmpty);
      expect(await directory.landmarks(), [_accraMall]);
      expect(repository.calls, 2);
    });

    test(
      'the pin labeller names a pin from the directory or finds none',
      () async {
        final labeller = LandmarkPassengerHomeReverseGeocoder(
          PassengerLandmarkDirectory(_CountingRepository([_accraMall])),
        );

        expect(
          await labeller.reverseGeocode(const LatLng(5.6236, -0.1737)),
          'Near Accra Mall',
        );
        await expectLater(
          labeller.reverseGeocode(const LatLng(5.55, -0.20)),
          throwsA(isA<NoLandmarkNearbyException>()),
        );
      },
    );
  });

  test('the phone geocoder is gone from the passenger app', () {
    expect(
      File('pubspec.yaml').readAsStringSync(),
      isNot(contains('geocoding:')),
    );
    final sources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .map((file) => file.readAsStringSync());
    for (final source in sources) {
      expect(source, isNot(contains('package:geocoding/')));
      expect(source, isNot(contains('placemarkFromCoordinates')));
    }
  });
}

Future<ApiPassengerLandmarkRepository> _repository(_Gateway gateway) async {
  final store = MemoryAuthTokenStore();
  await store.saveTokens(
    AuthTokens(accessToken: 'access', refreshToken: 'refresh'),
  );
  return ApiPassengerLandmarkRepository(gateway, tokenStore: store);
}

final class _CountingRepository implements PassengerLandmarkRepository {
  _CountingRepository(this.landmarks, {this.failures = 0});

  final List<PassengerLandmark> landmarks;
  int failures;
  int calls = 0;

  @override
  Future<List<PassengerLandmark>> fetch() async {
    calls += 1;
    if (failures > 0) {
      failures -= 1;
      throw const PassengerLandmarksUnavailableException();
    }
    return landmarks;
  }
}

final class _Reply {
  _Reply.success(this.payload) : status = 200;
  _Reply.failure(this.status) : payload = null;
  _Reply.offline() : status = null, payload = null;

  final int? status;
  final Object? payload;
}

final class _Gateway implements PassengerLandmarkApiGateway {
  _Gateway(this._replies);

  final List<_Reply> _replies;
  final paths = <String>[];

  @override
  Future<ApiResponse<T>> get<T>(
    String path, {
    required JsonDecoder<T> decoder,
  }) async {
    paths.add(path);
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
          type: AsmApiExceptionType.badResponse,
          message: 'Failed.',
          statusCode: status,
        ),
      );
    }
    return ApiResponse<T>.success(decoder(reply.payload), statusCode: 200);
  }
}
