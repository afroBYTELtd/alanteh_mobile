import 'dart:convert';
import 'dart:io';

import 'package:latlong2/latlong.dart';

import 'passenger_map.dart';

class PassengerRouteEstimate {
  const PassengerRouteEstimate({
    required this.points,
    required this.distanceKilometres,
    required this.durationMinutes,
    this.usedFallback = false,
  });

  final List<LatLng> points;
  final double distanceKilometres;
  final int durationMinutes;
  final bool usedFallback;
}

abstract interface class PassengerRouteService {
  Future<PassengerRouteEstimate> route({
    LatLng pickup = accraPickup,
    LatLng destination = accraDestination,
  });
}

class OsrmPassengerRouteService implements PassengerRouteService {
  const OsrmPassengerRouteService();

  static const host = 'router.project-osrm.org';

  @override
  Future<PassengerRouteEstimate> route({
    LatLng pickup = accraPickup,
    LatLng destination = accraDestination,
  }) async {
    final uri = Uri.https(
      host,
      '/route/v1/driving/'
      '${pickup.longitude},${pickup.latitude};'
      '${destination.longitude},${destination.latitude}',
      const <String, String>{'overview': 'full', 'geometries': 'geojson'},
    );

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);

    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.userAgentHeader, osmUserAgentPackageName);

      final response = await request.close();

      if (response.statusCode != HttpStatus.ok) {
        throw const HttpException('Route service unavailable.');
      }

      final body = await utf8.decoder.bind(response).join();
      return parseOsrmRouteResponse(jsonDecode(body));
    } finally {
      client.close(force: true);
    }
  }
}

PassengerRouteEstimate parseOsrmRouteResponse(Object? payload) {
  if (payload is! Map) {
    throw const FormatException('Route response was not a JSON object.');
  }

  final routes = payload['routes'];

  if (routes is! List || routes.isEmpty) {
    throw const FormatException('Route response did not include a route.');
  }

  final route = routes.first;

  if (route is! Map) {
    throw const FormatException('Route response item was not a JSON object.');
  }

  final geometry = route['geometry'];

  if (geometry is! Map) {
    throw const FormatException('Route geometry was missing.');
  }

  final coordinates = geometry['coordinates'];

  if (coordinates is! List || coordinates.length < 2) {
    throw const FormatException('Route coordinates were missing.');
  }

  final points = <LatLng>[];

  for (final entry in coordinates) {
    if (entry is! List ||
        entry.length < 2 ||
        entry[0] is! num ||
        entry[1] is! num) {
      throw const FormatException('Route coordinate was malformed.');
    }

    points.add(
      LatLng((entry[1] as num).toDouble(), (entry[0] as num).toDouble()),
    );
  }

  final distanceMetres = route['distance'];
  final durationSeconds = route['duration'];

  if (distanceMetres is! num || durationSeconds is! num) {
    throw const FormatException('Route distance or duration was missing.');
  }

  return PassengerRouteEstimate(
    points: List<LatLng>.unmodifiable(points),
    distanceKilometres: distanceMetres.toDouble() / 1000,
    durationMinutes: (durationSeconds.toDouble() / 60).round(),
  );
}

PassengerRouteEstimate safeDirectRouteFallback({
  LatLng pickup = accraPickup,
  LatLng destination = accraDestination,
}) {
  const distance = Distance();

  final kilometres = distance.as(LengthUnit.Kilometer, pickup, destination);

  return PassengerRouteEstimate(
    points: List<LatLng>.unmodifiable(<LatLng>[pickup, destination]),
    distanceKilometres: kilometres,
    durationMinutes: (kilometres / 25 * 60).round(),
    usedFallback: true,
  );
}
