import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_auth/asm_auth.dart';
import 'package:latlong2/latlong.dart';

import '../network/ghana_network_resilience.dart';
import '../network/passenger_auth_service.dart';
import '../passenger_home.dart';

/// The label of a pin with no landmark near it and no words of the
/// passenger's own.
const passengerPinnedLocationLabel = 'Pinned location';

/// One of ALANTEH's own named places (GET /api/landmarks/). Google's EEA
/// terms keep Places and Geocoding text off any map, so a pin on a map
/// screen is labelled from these instead.
final class PassengerLandmark {
  const PassengerLandmark({
    required this.id,
    required this.name,
    required this.coordinates,
    required this.radiusMetres,
  });

  final int id;
  final String name;
  final LatLng coordinates;
  final int radiusMetres;
}

/// "Near {name}" for the nearest landmark whose radius covers [pin].
String? landmarkLabelFor(LatLng pin, List<PassengerLandmark> landmarks) {
  const distance = Distance();
  PassengerLandmark? nearest;
  var nearestMetres = double.infinity;
  for (final landmark in landmarks) {
    final metres = distance.as(LengthUnit.Meter, pin, landmark.coordinates);
    if (metres <= landmark.radiusMetres && metres < nearestMetres) {
      nearest = landmark;
      nearestMetres = metres;
    }
  }
  return nearest == null ? null : 'Near ${nearest.name}';
}

/// A pin's label: a landmark, else the passenger's own words, else
/// "Pinned location" - never Google's text.
String passengerPinLabel({
  required String? landmark,
  required String? ownWords,
}) {
  if (landmark != null && landmark.trim().isNotEmpty) {
    return landmark.trim();
  }
  final words = ownWords?.trim() ?? '';
  return words.isEmpty ? passengerPinnedLocationLabel : words;
}

abstract interface class PassengerLandmarkRepository {
  Future<List<PassengerLandmark>> fetch();
}

/// The landmarks could not be read now; pins fall back to the passenger's
/// words or "Pinned location".
final class PassengerLandmarksUnavailableException implements Exception {
  const PassengerLandmarksUnavailableException();
}

/// No landmark covers the pin.
final class NoLandmarkNearbyException implements Exception {
  const NoLandmarkNearbyException();
}

abstract interface class PassengerLandmarkApiGateway {
  Future<ApiResponse<T>> get<T>(String path, {required JsonDecoder<T> decoder});
}

final class AsmPassengerLandmarkApiGateway
    implements PassengerLandmarkApiGateway {
  const AsmPassengerLandmarkApiGateway(this.client);

  final AsmApiClient client;

  @override
  Future<ApiResponse<T>> get<T>(
    String path, {
    required JsonDecoder<T> decoder,
  }) {
    return client.get<T>(path, decoder: decoder);
  }
}

final class ApiPassengerLandmarkRepository
    implements PassengerLandmarkRepository {
  const ApiPassengerLandmarkRepository(
    this.apiGateway, {
    required this.tokenStore,
    this.authService,
  });

  /// Null when the app has no usable API address.
  static PassengerLandmarkRepository? withDefaultClient({
    AuthTokenStore? tokenStore,
    String? baseUrl,
  }) {
    if (!AsmApiBaseUrl.isUsable(baseUrl)) {
      return null;
    }
    final resolvedTokenStore = tokenStore ?? SecureAuthTokenStore();
    final resolvedBaseUrl = baseUrl!.trim();
    return ApiPassengerLandmarkRepository(
      AsmPassengerLandmarkApiGateway(
        GhanaResilientApiClient(
          baseUrl: resolvedBaseUrl,
          tokenProvider: _LandmarksTokenProvider(resolvedTokenStore),
        ),
      ),
      tokenStore: resolvedTokenStore,
      authService: passengerAuthService(
        client: GhanaResilientApiClient(baseUrl: resolvedBaseUrl),
        tokenStore: resolvedTokenStore,
      ),
    );
  }

  static const path = '/api/landmarks/';

  final PassengerLandmarkApiGateway apiGateway;
  final AuthTokenStore tokenStore;
  final AuthService? authService;

  @override
  Future<List<PassengerLandmark>> fetch() async {
    var response = await apiGateway.get(path, decoder: _landmarksFromJson);
    if (response.statusCode == 401 && await _refreshAccessToken()) {
      response = await apiGateway.get(path, decoder: _landmarksFromJson);
    }
    final landmarks = response.data;
    if (response.isSuccess && landmarks != null) {
      return landmarks;
    }
    // A 404 is an older backend without landmarks: the same as none.
    throw const PassengerLandmarksUnavailableException();
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

/// The landmarks, fetched once per app session. A failed fetch counts as
/// none and is tried again next time.
final class PassengerLandmarkDirectory {
  PassengerLandmarkDirectory(this.repository);

  final PassengerLandmarkRepository repository;
  Future<List<PassengerLandmark>>? _landmarks;

  Future<List<PassengerLandmark>> landmarks() {
    return _landmarks ??= repository.fetch().catchError((Object _) {
      _landmarks = null;
      return const <PassengerLandmark>[];
    });
  }
}

/// Names a pin from the landmarks: "Near Accra Mall", or
/// [NoLandmarkNearbyException] so the pin falls back to the passenger's
/// words or "Pinned location".
final class LandmarkPassengerHomeReverseGeocoder
    implements PassengerHomeReverseGeocoder {
  const LandmarkPassengerHomeReverseGeocoder(this.directory);

  final PassengerLandmarkDirectory directory;

  @override
  Future<String> reverseGeocode(LatLng coordinates) async {
    final label = landmarkLabelFor(coordinates, await directory.landmarks());
    if (label == null) {
      throw const NoLandmarkNearbyException();
    }
    return label;
  }
}

List<PassengerLandmark> _landmarksFromJson(Object? json) {
  if (json is! Map || json['landmarks'] is! List) {
    throw const FormatException('landmarks must be a list.');
  }
  return [
    for (final item in json['landmarks'] as List) ?_landmarkFromJson(item),
  ];
}

PassengerLandmark? _landmarkFromJson(Object? item) {
  if (item is! Map) {
    return null;
  }
  final id = item['id'];
  final name = item['name'];
  final latitude = item['latitude'];
  final longitude = item['longitude'];
  final radius = item['radius_metres'];
  if (id is! int ||
      name is! String ||
      name.trim().isEmpty ||
      latitude is! num ||
      longitude is! num ||
      radius is! int ||
      radius <= 0 ||
      latitude.abs() > 90 ||
      longitude.abs() > 180) {
    return null;
  }
  return PassengerLandmark(
    id: id,
    name: name.trim(),
    coordinates: LatLng(latitude.toDouble(), longitude.toDouble()),
    radiusMetres: radius,
  );
}

final class _LandmarksTokenProvider implements TokenProvider {
  const _LandmarksTokenProvider(this.tokenStore);

  final AuthTokenStore tokenStore;

  @override
  Future<String?> getAccessToken() => tokenStore.readAccessToken();
}
