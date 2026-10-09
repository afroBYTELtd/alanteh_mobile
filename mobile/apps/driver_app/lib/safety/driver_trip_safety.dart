import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_auth/asm_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

const driverProfileEndpoint = '/api/driver/profile/';
const driverSafetyAlertEndpoint = '/api/driver/safety-alert/';
const driverGhanaPoliceNumber = '191';

final Uri driverEmergency191Uri = Uri(
  scheme: 'tel',
  path: driverGhanaPoliceNumber,
);

final class DriverTrustedContact {
  const DriverTrustedContact({required this.name, required this.phone});

  const DriverTrustedContact.empty() : name = '', phone = '';

  final String name;
  final String phone;

  bool get isConfigured => name.trim().isNotEmpty && phone.trim().isNotEmpty;

  factory DriverTrustedContact.fromJson(Object? json) {
    if (json is! Map) {
      throw const FormatException(
        'Driver profile response was not a JSON object.',
      );
    }

    final map = json.map<String, Object?>(
      (key, value) => MapEntry(key.toString(), value),
    );

    return DriverTrustedContact(
      name: _optionalString(map, 'emergency_contact_name') ?? '',
      phone: _optionalString(map, 'emergency_contact_phone') ?? '',
    );
  }
}

abstract interface class DriverTrustedContactRepository {
  Future<DriverTrustedContact> fetch();

  Future<DriverTrustedContact> save({
    required String name,
    required String phone,
  });
}

abstract interface class DriverTrustedContactApiGateway {
  Future<ApiResponse<Map<String, Object?>>> get(String path);

  Future<ApiResponse<Map<String, Object?>>> patch(
    String path, {
    required Map<String, Object?> data,
  });
}

final class AsmDriverTrustedContactApiGateway
    implements DriverTrustedContactApiGateway {
  const AsmDriverTrustedContactApiGateway(this.client);

  final AsmApiClient client;

  @override
  Future<ApiResponse<Map<String, Object?>>> get(String path) {
    return client.get<Map<String, Object?>>(path, decoder: _decodeObjectMap);
  }

  @override
  Future<ApiResponse<Map<String, Object?>>> patch(
    String path, {
    required Map<String, Object?> data,
  }) {
    return client.request<Map<String, Object?>>(
      method: 'PATCH',
      path: path,
      data: data,
      decoder: _decodeObjectMap,
    );
  }
}

final class ApiDriverTrustedContactRepository
    implements DriverTrustedContactRepository {
  const ApiDriverTrustedContactRepository({
    required this.apiGateway,
    required this.tokenStore,
    required this.connectionConfigured,
  });

  factory ApiDriverTrustedContactRepository.withDefaultClient({
    required AuthTokenStore tokenStore,
    String? baseUrl,
  }) {
    final configured = AsmApiBaseUrl.isUsable(baseUrl);
    final resolvedBaseUrl = configured
        ? baseUrl!.trim()
        : 'http://127.0.0.1:8000';

    return ApiDriverTrustedContactRepository(
      apiGateway: AsmDriverTrustedContactApiGateway(
        AsmApiClient(
          baseUrl: resolvedBaseUrl,
          tokenProvider: _DriverSafetyTokenProvider(tokenStore),
        ),
      ),
      tokenStore: tokenStore,
      connectionConfigured: configured,
    );
  }

  final DriverTrustedContactApiGateway apiGateway;
  final AuthTokenStore tokenStore;
  final bool connectionConfigured;

  @override
  Future<DriverTrustedContact> fetch() async {
    await _requireReady();

    final response = await apiGateway.get(driverProfileEndpoint);

    if (response.isSuccess &&
        response.statusCode == 200 &&
        response.data != null) {
      return DriverTrustedContact.fromJson(response.data);
    }

    throw DriverTrustedContactException(
      response.error?.message ?? 'Unable to load your trusted contact.',
    );
  }

  @override
  Future<DriverTrustedContact> save({
    required String name,
    required String phone,
  }) async {
    await _requireReady();

    final normalizedName = name.trim();
    final normalizedPhone = phone.trim();

    if (normalizedName.isEmpty || normalizedPhone.isEmpty) {
      throw const DriverTrustedContactException(
        'Enter both a name and phone number.',
      );
    }

    final payload = <String, Object?>{
      'emergency_contact_name': normalizedName,
      'emergency_contact_phone': normalizedPhone,
    };

    final response = await apiGateway.patch(
      driverProfileEndpoint,
      data: payload,
    );

    if (response.isSuccess && response.statusCode == 200) {
      if (response.data != null) {
        return DriverTrustedContact.fromJson(response.data);
      }

      return DriverTrustedContact(
        name: normalizedName,
        phone: normalizedPhone,
      );
    }

    throw DriverTrustedContactException(
      response.error?.message ?? 'Unable to save your trusted contact.',
    );
  }

  Future<void> _requireReady() async {
    final accessToken = (await tokenStore.readAccessToken())?.trim();

    if (accessToken == null || accessToken.isEmpty) {
      throw const DriverTrustedContactException(
        'Please sign in again to continue.',
      );
    }

    if (!connectionConfigured) {
      throw const DriverTrustedContactException(
        AsmApiClient.connectionNotConfiguredMessage,
      );
    }
  }
}

final class DriverTrustedContactException implements Exception {
  const DriverTrustedContactException(this.message);

  final String message;

  @override
  String toString() => 'DriverTrustedContactException: $message';
}

final class DriverTripSafetySummary {
  const DriverTripSafetySummary({
    required this.tripReference,
    required this.tripStatus,
    required this.pickup,
    required this.destination,
    required this.passengerCount,
  });

  final String? tripReference;
  final String? tripStatus;
  final String? pickup;
  final String? destination;
  final int? passengerCount;

  String build() {
    return <String>[
      'Trip reference: ${_displayValue(tripReference)}',
      'Trip status: ${_displayValue(tripStatus)}',
      'Passengers: ${passengerCount == null ? 'Not available' : passengerCount.toString()}',
      'Pickup: ${_privacySafeLocationValue(pickup)}',
      'Destination: ${_privacySafeLocationValue(destination)}',
    ].join('\n');
  }
}

Uri buildDriverTrustedContactSmsUri({
  required String phone,
  required String summary,
}) {
  return Uri.parse(
    'sms:${phone.trim()}?body=${summary.replaceAll(' ', '%20').replaceAll('\n', '%0A')}',
  );
}

abstract interface class DriverSafetyUriLauncher {
  Future<bool> canLaunch(Uri uri);

  Future<bool> launch(Uri uri);
}

final class PlatformDriverSafetyUriLauncher implements DriverSafetyUriLauncher {
  const PlatformDriverSafetyUriLauncher();

  @override
  Future<bool> canLaunch(Uri uri) => canLaunchUrl(uri);

  @override
  Future<bool> launch(Uri uri) {
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

abstract interface class DriverSafetyShareGateway {
  Future<void> shareText(String text);
}

final class PlatformDriverSafetyShareGateway
    implements DriverSafetyShareGateway {
  const PlatformDriverSafetyShareGateway();

  @override
  Future<void> shareText(String text) async {
    await SharePlus.instance.share(ShareParams(text: text));
  }
}

final class DriverSafetyAlertException implements Exception {
  const DriverSafetyAlertException(this.message);

  final String message;

  @override
  String toString() => 'DriverSafetyAlertException: $message';
}

abstract interface class DriverSafetyAlertRepository {
  Future<void> send({String? tripReference, double? latitude, double? longitude});
}

abstract interface class DriverSafetyAlertApiGateway {
  Future<ApiResponse<Map<String, Object?>>> post(
    String path, {
    required Map<String, Object?> data,
  });
}

final class AsmDriverSafetyAlertApiGateway
    implements DriverSafetyAlertApiGateway {
  const AsmDriverSafetyAlertApiGateway(this.client);

  final AsmApiClient client;

  @override
  Future<ApiResponse<Map<String, Object?>>> post(
    String path, {
    required Map<String, Object?> data,
  }) {
    return client.request<Map<String, Object?>>(
      method: 'POST',
      path: path,
      data: data,
      decoder: _decodeObjectMap,
    );
  }
}

final class ApiDriverSafetyAlertRepository
    implements DriverSafetyAlertRepository {
  const ApiDriverSafetyAlertRepository({
    required this.apiGateway,
    required this.tokenStore,
    required this.connectionConfigured,
  });

  factory ApiDriverSafetyAlertRepository.withDefaultClient({
    required AuthTokenStore tokenStore,
    String? baseUrl,
  }) {
    final configured = AsmApiBaseUrl.isUsable(baseUrl);
    final resolvedBaseUrl = configured
        ? baseUrl!.trim()
        : 'http://127.0.0.1:8000';

    return ApiDriverSafetyAlertRepository(
      apiGateway: AsmDriverSafetyAlertApiGateway(
        AsmApiClient(
          baseUrl: resolvedBaseUrl,
          tokenProvider: _DriverSafetyTokenProvider(tokenStore),
        ),
      ),
      tokenStore: tokenStore,
      connectionConfigured: configured,
    );
  }

  final DriverSafetyAlertApiGateway apiGateway;
  final AuthTokenStore tokenStore;
  final bool connectionConfigured;

  @override
  Future<void> send({
    String? tripReference,
    double? latitude,
    double? longitude,
  }) async {
    final accessToken = (await tokenStore.readAccessToken())?.trim();

    if (accessToken == null || accessToken.isEmpty) {
      throw const DriverSafetyAlertException(
        'Please sign in again to continue.',
      );
    }

    if (!connectionConfigured) {
      throw const DriverSafetyAlertException(
        AsmApiClient.connectionNotConfiguredMessage,
      );
    }

    final payload = <String, Object?>{
      if (tripReference != null && tripReference.trim().isNotEmpty)
        'trip_reference': tripReference.trim(),
      if (latitude != null) 'latitude': latitude.toString(),
      if (longitude != null) 'longitude': longitude.toString(),
    };

    final response = await apiGateway.post(
      driverSafetyAlertEndpoint,
      data: payload,
    );

    if (response.isSuccess && response.statusCode == 201) {
      return;
    }

    throw DriverSafetyAlertException(
      response.error?.message ?? 'Unable to send your alert.',
    );
  }
}

abstract interface class DriverCurrentLocationResolver {
  Future<({double latitude, double longitude})?> resolveBestEffort();
}

final class GeolocatorDriverCurrentLocationResolver
    implements DriverCurrentLocationResolver {
  const GeolocatorDriverCurrentLocationResolver();

  @override
  Future<({double latitude, double longitude})?> resolveBestEffort() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return null;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      final position = await Geolocator.getCurrentPosition();
      return (latitude: position.latitude, longitude: position.longitude);
    } on Object {
      return null;
    }
  }
}

final class _DriverSafetyTokenProvider implements TokenProvider {
  const _DriverSafetyTokenProvider(this.tokenStore);

  final AuthTokenStore tokenStore;

  @override
  Future<String?> getAccessToken() => tokenStore.readAccessToken();
}

Map<String, Object?> _decodeObjectMap(Object? json) {
  if (json is Map<String, Object?>) {
    return json;
  }

  if (json is Map) {
    return json.map<String, Object?>(
      (key, value) => MapEntry(key.toString(), value),
    );
  }

  throw const FormatException('Expected a JSON object.');
}

String? _optionalString(Map<String, Object?> map, String key) {
  final value = map[key];

  if (value is! String) {
    return null;
  }

  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}

String _displayValue(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty
      ? 'Not available'
      : normalized;
}

final RegExp _coordinateOnlyLocationPattern = RegExp(
  r'^[+-]?(?:\d+(?:\.\d+)?|\.\d+)\s*,\s*[+-]?(?:\d+(?:\.\d+)?|\.\d+)$',
);

String _privacySafeLocationValue(String? value) {
  final normalized = value?.trim();

  if (normalized == null || normalized.isEmpty) {
    return 'Not available';
  }

  if (_coordinateOnlyLocationPattern.hasMatch(normalized)) {
    return 'Not shared for privacy';
  }

  return normalized;
}
