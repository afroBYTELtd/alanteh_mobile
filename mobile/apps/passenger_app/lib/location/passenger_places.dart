import 'dart:math';

import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_auth/asm_auth.dart';
import 'package:latlong2/latlong.dart';

import '../network/ghana_network_resilience.dart';
import '../network/passenger_auth_service.dart';

/// Search waits this long after the last keystroke.
const passengerPlacesSearchDebounce = Duration(milliseconds: 300);

/// Shorter input finds nothing useful; longer is refused by the backend.
const passengerPlacesMinimumInput = 2;
const passengerPlacesMaximumInput = 200;

/// The backend gives Google 4 s; past this the search is unavailable.
const passengerPlacesRequestTimeout = Duration(seconds: 6);

final class PassengerPlaceSuggestion {
  const PassengerPlaceSuggestion({
    required this.placeId,
    required this.mainText,
    required this.secondaryText,
  });

  final String placeId;
  final String mainText;
  final String secondaryText;
}

final class PassengerPlaceLocation {
  const PassengerPlaceLocation({
    required this.placeId,
    required this.coordinates,
  });

  final String placeId;
  final LatLng coordinates;
}

/// A suggestion the passenger picked, with where it is.
final class PassengerPickedPlace {
  const PassengerPickedPlace({
    required this.placeId,
    required this.coordinates,
    required this.mainText,
    required this.secondaryText,
  });

  final String placeId;
  final LatLng coordinates;
  final String mainText;
  final String secondaryText;

  String get fullAddress =>
      secondaryText.isEmpty ? mainText : '$mainText, $secondaryText';
}

/// Place search for the pickup through the backend (`/api/places/`).
///
/// One session token per search: every [autocomplete] of the search and
/// the one [details] that ends it carry the same token.
abstract interface class PassengerPlacesRepository {
  Future<List<PassengerPlaceSuggestion>> autocomplete(
    String input, {
    required String sessionToken,
  });

  Future<PassengerPlaceLocation> details(
    String placeId, {
    required String sessionToken,
  });
}

/// Search cannot answer now; the passenger places the pin instead.
final class PassengerPlacesUnavailableException implements Exception {
  const PassengerPlacesUnavailableException();
}

abstract interface class PassengerPlacesApiGateway {
  Future<ApiResponse<T>> post<T>(
    String path, {
    required Map<String, Object?> data,
    required JsonDecoder<T> decoder,
  });
}

final class AsmPassengerPlacesApiGateway implements PassengerPlacesApiGateway {
  const AsmPassengerPlacesApiGateway(this.client);

  final AsmApiClient client;

  @override
  Future<ApiResponse<T>> post<T>(
    String path, {
    required Map<String, Object?> data,
    required JsonDecoder<T> decoder,
  }) {
    return client.post<T>(path, data: data, decoder: decoder);
  }
}

final class ApiPassengerPlacesRepository implements PassengerPlacesRepository {
  const ApiPassengerPlacesRepository(
    this.apiGateway, {
    required this.tokenStore,
    this.authService,
  });

  /// Null when the app has no usable API address.
  static PassengerPlacesRepository? withDefaultClient({
    AuthTokenStore? tokenStore,
    String? baseUrl,
  }) {
    if (!AsmApiBaseUrl.isUsable(baseUrl)) {
      return null;
    }
    final resolvedTokenStore = tokenStore ?? SecureAuthTokenStore();
    final resolvedBaseUrl = baseUrl!.trim();

    // Not the retrying Ghana client: a late answer to a search is no use.
    return ApiPassengerPlacesRepository(
      AsmPassengerPlacesApiGateway(
        AsmApiClient(
          baseUrl: resolvedBaseUrl,
          tokenProvider: _PlacesTokenProvider(resolvedTokenStore),
          connectTimeout: passengerPlacesRequestTimeout,
          sendTimeout: passengerPlacesRequestTimeout,
          receiveTimeout: passengerPlacesRequestTimeout,
          requestTimeout: passengerPlacesRequestTimeout,
        ),
      ),
      tokenStore: resolvedTokenStore,
      authService: passengerAuthService(
        client: GhanaResilientApiClient(baseUrl: resolvedBaseUrl),
        tokenStore: resolvedTokenStore,
      ),
    );
  }

  static const autocompletePath = '/api/places/autocomplete/';
  static const detailsPath = '/api/places/details/';

  final PassengerPlacesApiGateway apiGateway;
  final AuthTokenStore tokenStore;
  final AuthService? authService;

  @override
  Future<List<PassengerPlaceSuggestion>> autocomplete(
    String input, {
    required String sessionToken,
  }) {
    return _post(autocompletePath, {
      'input': input,
      'session_token': sessionToken,
    }, _suggestionsFromJson);
  }

  @override
  Future<PassengerPlaceLocation> details(
    String placeId, {
    required String sessionToken,
  }) {
    return _post(detailsPath, {
      'place_id': placeId,
      'session_token': sessionToken,
    }, _locationFromJson);
  }

  /// Any answer but success is "unavailable": 503 (Google or a cap), 429
  /// (the passenger's limit), 404 (an older backend), 409 and 400 alike.
  Future<T> _post<T>(
    String path,
    Map<String, Object?> data,
    JsonDecoder<T> decoder,
  ) async {
    var response = await apiGateway.post<T>(path, data: data, decoder: decoder);
    if (response.statusCode == 401 && await _refreshAccessToken()) {
      response = await apiGateway.post<T>(path, data: data, decoder: decoder);
    }
    final value = response.data;
    if (response.isSuccess && value != null) {
      return value;
    }
    throw const PassengerPlacesUnavailableException();
  }

  /// True when refreshed. A refresh that cannot reach the server keeps the
  /// stored sign-in; only a rejection by the server clears it.
  Future<bool> _refreshAccessToken() async {
    final refreshToken = (await tokenStore.readRefreshToken())?.trim();
    final service = authService;
    if (refreshToken == null || refreshToken.isEmpty || service == null) {
      return false;
    }

    final AuthState state;
    try {
      state = await service.refresh();
    } on Object {
      return false;
    }
    if (state.isAuthenticated) {
      return true;
    }
    if (!state.isTemporarilyUnavailable) {
      await tokenStore.clearTokens();
    }
    return false;
  }
}

List<PassengerPlaceSuggestion> _suggestionsFromJson(Object? json) {
  final suggestions = _map(json)['suggestions'];
  if (suggestions is! List) {
    throw const FormatException('suggestions must be a list.');
  }
  return [
    for (final item in suggestions)
      PassengerPlaceSuggestion(
        placeId: _text(_map(item)['place_id']),
        mainText: _text(_map(item)['main_text']),
        secondaryText: _map(item)['secondary_text'] is String
            ? (_map(item)['secondary_text'] as String).trim()
            : '',
      ),
  ];
}

PassengerPlaceLocation _locationFromJson(Object? json) {
  final map = _map(json);
  final latitude = map['latitude'];
  final longitude = map['longitude'];
  if (latitude is! num || longitude is! num) {
    throw const FormatException('latitude and longitude must be numbers.');
  }
  return PassengerPlaceLocation(
    placeId: _text(map['place_id']),
    coordinates: LatLng(latitude.toDouble(), longitude.toDouble()),
  );
}

Map<Object?, Object?> _map(Object? json) {
  if (json is! Map) {
    throw const FormatException('Expected a JSON object.');
  }
  return json;
}

String _text(Object? value) {
  final text = value is String ? value.trim() : '';
  if (text.isEmpty) {
    throw const FormatException('Expected text.');
  }
  return text;
}

final class _PlacesTokenProvider implements TokenProvider {
  const _PlacesTokenProvider(this.tokenStore);

  final AuthTokenStore tokenStore;

  @override
  Future<String?> getAccessToken() => tokenStore.readAccessToken();
}

final Random _tokenRandom = Random.secure();

/// A fresh UUID v4 for one search session.
String newPlacesSessionToken() {
  final bytes = List<int>.generate(16, (_) => _tokenRandom.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;

  String hex(int value) => value.toRadixString(16).padLeft(2, '0');
  return [
    bytes.sublist(0, 4).map(hex).join(),
    bytes.sublist(4, 6).map(hex).join(),
    bytes.sublist(6, 8).map(hex).join(),
    bytes.sublist(8, 10).map(hex).join(),
    bytes.sublist(10, 16).map(hex).join(),
  ].join('-');
}
