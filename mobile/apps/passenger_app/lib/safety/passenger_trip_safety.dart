import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_auth/asm_auth.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

const passengerProfileEndpoint = '/api/passenger/profile/';
const passengerGhanaPoliceNumber = '191';

final Uri passengerEmergency191Uri = Uri(
  scheme: 'tel',
  path: passengerGhanaPoliceNumber,
);

final class PassengerTrustedContact {
  const PassengerTrustedContact({required this.name, required this.phone});

  const PassengerTrustedContact.empty() : name = '', phone = '';

  final String name;
  final String phone;

  bool get isConfigured => name.trim().isNotEmpty && phone.trim().isNotEmpty;

  factory PassengerTrustedContact.fromJson(Object? json) {
    if (json is! Map) {
      throw const FormatException(
        'Passenger profile response was not a JSON object.',
      );
    }

    final map = json.map<String, Object?>(
      (key, value) => MapEntry(key.toString(), value),
    );

    return PassengerTrustedContact(
      name: _optionalString(map, 'emergency_contact_name') ?? '',
      phone: _optionalString(map, 'emergency_contact_phone') ?? '',
    );
  }
}

abstract interface class PassengerTrustedContactRepository {
  Future<PassengerTrustedContact> fetch();

  Future<PassengerTrustedContact> save({
    required String name,
    required String phone,
  });
}

abstract interface class PassengerTrustedContactApiGateway {
  Future<ApiResponse<Map<String, Object?>>> get(String path);

  Future<ApiResponse<Map<String, Object?>>> patch(
    String path, {
    required Map<String, Object?> data,
  });
}

final class AsmPassengerTrustedContactApiGateway
    implements PassengerTrustedContactApiGateway {
  const AsmPassengerTrustedContactApiGateway(this.client);

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

final class ApiPassengerTrustedContactRepository
    implements PassengerTrustedContactRepository {
  const ApiPassengerTrustedContactRepository({
    required this.apiGateway,
    required this.tokenStore,
    required this.connectionConfigured,
  });

  factory ApiPassengerTrustedContactRepository.withDefaultClient({
    required AuthTokenStore tokenStore,
    String? baseUrl,
  }) {
    final configured = AsmApiBaseUrl.isUsable(baseUrl);
    final resolvedBaseUrl = configured
        ? baseUrl!.trim()
        : 'http://127.0.0.1:8000';

    return ApiPassengerTrustedContactRepository(
      apiGateway: AsmPassengerTrustedContactApiGateway(
        AsmApiClient(
          baseUrl: resolvedBaseUrl,
          tokenProvider: _PassengerSafetyTokenProvider(tokenStore),
        ),
      ),
      tokenStore: tokenStore,
      connectionConfigured: configured,
    );
  }

  final PassengerTrustedContactApiGateway apiGateway;
  final AuthTokenStore tokenStore;
  final bool connectionConfigured;

  @override
  Future<PassengerTrustedContact> fetch() async {
    await _requireReady();

    final response = await apiGateway.get(passengerProfileEndpoint);

    if (response.isSuccess &&
        response.statusCode == 200 &&
        response.data != null) {
      return PassengerTrustedContact.fromJson(response.data);
    }

    throw PassengerTrustedContactException(
      response.error?.message ?? 'Unable to load your trusted contact.',
    );
  }

  @override
  Future<PassengerTrustedContact> save({
    required String name,
    required String phone,
  }) async {
    await _requireReady();

    final normalizedName = name.trim();
    final normalizedPhone = phone.trim();

    if (normalizedName.isEmpty || normalizedPhone.isEmpty) {
      throw const PassengerTrustedContactException(
        'Enter both a name and phone number.',
      );
    }

    final payload = <String, Object?>{
      'emergency_contact_name': normalizedName,
      'emergency_contact_phone': normalizedPhone,
    };

    final response = await apiGateway.patch(
      passengerProfileEndpoint,
      data: payload,
    );

    if (response.isSuccess && response.statusCode == 200) {
      if (response.data != null) {
        return PassengerTrustedContact.fromJson(response.data);
      }

      return PassengerTrustedContact(
        name: normalizedName,
        phone: normalizedPhone,
      );
    }

    throw PassengerTrustedContactException(
      response.error?.message ?? 'Unable to save your trusted contact.',
    );
  }

  Future<void> _requireReady() async {
    final accessToken = (await tokenStore.readAccessToken())?.trim();

    if (accessToken == null || accessToken.isEmpty) {
      throw const PassengerTrustedContactException(
        'Please sign in again to continue.',
      );
    }

    if (!connectionConfigured) {
      throw const PassengerTrustedContactException(
        AsmApiClient.connectionNotConfiguredMessage,
      );
    }
  }
}

final class PassengerTrustedContactException implements Exception {
  const PassengerTrustedContactException(this.message);

  final String message;

  @override
  String toString() => 'PassengerTrustedContactException: $message';
}

final class PassengerTripSafetySummary {
  const PassengerTripSafetySummary({
    required this.tripReference,
    required this.tripStatus,
    required this.driverFirstName,
    required this.vehicleType,
    required this.vehicleColour,
    required this.plate,
    required this.pickup,
    required this.destination,
  });

  final String? tripReference;
  final String? tripStatus;
  final String? driverFirstName;
  final String? vehicleType;
  final String? vehicleColour;
  final String? plate;
  final String? pickup;
  final String? destination;

  String build() {
    return <String>[
      'Trip reference: ${_displayValue(tripReference)}',
      'Trip status: ${_displayValue(tripStatus)}',
      'Driver first name: ${_displayValue(driverFirstName)}',
      'Vehicle type: ${_displayValue(vehicleType)}',
      'Vehicle colour: ${_displayValue(vehicleColour)}',
      'Plate: ${_displayValue(plate)}',
      'Pickup: ${_privacySafeLocationValue(pickup)}',
      'Destination: ${_privacySafeLocationValue(destination)}',
    ].join('\n');
  }
}

Uri buildTrustedContactSmsUri({
  required String phone,
  required String summary,
}) {
  return Uri.parse(
    'sms:${phone.trim()}?body=${summary.replaceAll(' ', '%20').replaceAll('\n', '%0A')}',
  );
}

abstract interface class PassengerSafetyUriLauncher {
  Future<bool> canLaunch(Uri uri);

  Future<bool> launch(Uri uri);
}

final class PlatformPassengerSafetyUriLauncher
    implements PassengerSafetyUriLauncher {
  const PlatformPassengerSafetyUriLauncher();

  @override
  Future<bool> canLaunch(Uri uri) => canLaunchUrl(uri);

  @override
  Future<bool> launch(Uri uri) {
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

abstract interface class PassengerSafetyShareGateway {
  Future<void> shareText(String text);
}

final class PlatformPassengerSafetyShareGateway
    implements PassengerSafetyShareGateway {
  const PlatformPassengerSafetyShareGateway();

  @override
  Future<void> shareText(String text) async {
    await SharePlus.instance.share(ShareParams(text: text));
  }
}

final class _PassengerSafetyTokenProvider implements TokenProvider {
  const _PassengerSafetyTokenProvider(this.tokenStore);

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
