import 'dart:math';

import 'package:asm_api_client/asm_api_client.dart';

import '../network/ghana_network_resilience.dart';

enum PassengerRegistrationFailureType {
  duplicatePhone,
  offline,
  server,
  invalidResponse,
}

final class PassengerRegistrationException implements Exception {
  const PassengerRegistrationException({
    required this.type,
    required this.message,
  });

  final PassengerRegistrationFailureType type;
  final String message;

  @override
  String toString() =>
      'PassengerRegistrationException(type: $type, message: $message)';
}

final class PassengerRegistrationResult {
  const PassengerRegistrationResult({
    required this.status,
    required this.registrationReference,
  });

  final String status;
  final String registrationReference;
}

abstract interface class PassengerRegistrationSubmitter {
  Future<PassengerRegistrationResult> submit({
    required String phoneNumber,
    required String fullName,
    required String pin,
    required String idempotencyKey,
  });
}

abstract interface class PassengerRegistrationApiGateway {
  Future<ApiResponse<Map<String, Object?>>> post(
    String path, {
    required Map<String, Object?> body,
    required Map<String, String> headers,
  });
}

final class AsmPassengerRegistrationApiGateway
    implements PassengerRegistrationApiGateway {
  const AsmPassengerRegistrationApiGateway(this.client);

  final AsmApiClient client;

  @override
  Future<ApiResponse<Map<String, Object?>>> post(
    String path, {
    required Map<String, Object?> body,
    required Map<String, String> headers,
  }) {
    return client.post<Map<String, Object?>>(
      path,
      data: body,
      headers: headers,
      decoder: _decodeJsonMap,
    );
  }

  static Map<String, Object?> _decodeJsonMap(Object? json) {
    if (json is Map<String, Object?>) {
      return json;
    }
    if (json is Map) {
      return json.map((key, value) => MapEntry(key.toString(), value));
    }
    throw const PassengerRegistrationException(
      type: PassengerRegistrationFailureType.invalidResponse,
      message: 'Registration response was invalid.',
    );
  }
}

final class ApiPassengerRegistrationSubmitter
    implements PassengerRegistrationSubmitter {
  ApiPassengerRegistrationSubmitter({
    required PassengerRegistrationApiGateway gateway,
    Future<void> Function(Duration duration)? retryDelay,
  }) : _apiGateway = gateway,
       _delay = retryDelay;

  factory ApiPassengerRegistrationSubmitter.withDefaultClient({
    required String baseUrl,
    Future<void> Function(Duration duration)? delay,
  }) {
    final client = AsmApiClient(
      baseUrl: baseUrl,
      connectTimeout: GhanaRequestPolicy.connectTimeout,
      sendTimeout: GhanaRequestPolicy.sendTimeout,
      receiveTimeout: GhanaRequestPolicy.receiveTimeout,
      requestTimeout: GhanaRequestPolicy.requestTimeout,
    );
    return ApiPassengerRegistrationSubmitter(
      gateway: AsmPassengerRegistrationApiGateway(client),
      retryDelay: delay,
    );
  }

  static const path = '/api/passenger/register/';
  static const duplicatePhoneMessage =
      'An account with this phone number already exists. Sign in instead.';
  static const offlineMessage =
      'No connection.\nPlease check your network and try again.';
  static const serverMessage =
      'Service is temporarily unavailable. Please try again later.';
  static const invalidResponseMessage =
      'Something went wrong. Please try again.';

  final PassengerRegistrationApiGateway _apiGateway;
  final Future<void> Function(Duration duration)? _delay;

  @override
  Future<PassengerRegistrationResult> submit({
    required String phoneNumber,
    required String fullName,
    required String pin,
    required String idempotencyKey,
  }) async {
    final normalizedPhone = phoneNumber.trim();
    final normalizedName = fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .join(' ');
    final normalizedPin = pin.trim();
    final normalizedIdempotencyKey = idempotencyKey.trim();

    for (
      var attempt = 0;
      attempt < GhanaRequestPolicy.maxAttempts;
      attempt += 1
    ) {
      final response = await _apiGateway.post(
        path,
        body: <String, Object?>{
          'phone_number': normalizedPhone,
          'full_name': normalizedName,
          'pin': normalizedPin,
        },
        headers: GhanaRequestPolicy.headersFor(<String, String>{
          'Idempotency-Key': normalizedIdempotencyKey,
        }),
      );

      if (response.isSuccess &&
          (response.statusCode == 200 || response.statusCode == 201)) {
        return _successResult(response.data);
      }

      if (response.statusCode == 409) {
        throw const PassengerRegistrationException(
          type: PassengerRegistrationFailureType.duplicatePhone,
          message: duplicatePhoneMessage,
        );
      }

      final retryable = GhanaRequestPolicy.shouldRetry(response);
      final retriesExhausted =
          attempt >= GhanaRequestPolicy.retryBackoffs.length;

      if (retryable && !retriesExhausted) {
        final wait = GhanaRequestPolicy.retryBackoffs[attempt];
        final customDelay = _delay;
        if (customDelay == null) {
          await Future<void>.delayed(wait);
        } else {
          await customDelay(wait);
        }
        continue;
      }

      final error = response.error;
      if (error?.type == AsmApiExceptionType.network ||
          error?.type == AsmApiExceptionType.timeout) {
        throw const PassengerRegistrationException(
          type: PassengerRegistrationFailureType.offline,
          message: offlineMessage,
        );
      }

      if (response.statusCode == 502 ||
          response.statusCode == 503 ||
          response.statusCode == 504 ||
          error?.type == AsmApiExceptionType.server) {
        throw const PassengerRegistrationException(
          type: PassengerRegistrationFailureType.server,
          message: serverMessage,
        );
      }

      throw PassengerRegistrationException(
        type: PassengerRegistrationFailureType.invalidResponse,
        message: _safeDetail(error?.cause) ?? invalidResponseMessage,
      );
    }

    throw const PassengerRegistrationException(
      type: PassengerRegistrationFailureType.invalidResponse,
      message: invalidResponseMessage,
    );
  }

  static PassengerRegistrationResult _successResult(
    Map<String, Object?>? data,
  ) {
    final status = data?['status'];
    final reference = data?['registration_reference'];

    if (status is! String ||
        status.trim() != 'pending_approval' ||
        reference is! String ||
        reference.trim().isEmpty) {
      throw const PassengerRegistrationException(
        type: PassengerRegistrationFailureType.invalidResponse,
        message: invalidResponseMessage,
      );
    }

    return PassengerRegistrationResult(
      status: status.trim(),
      registrationReference: reference.trim(),
    );
  }

  static String? _safeDetail(Object? cause) {
    if (cause is Map) {
      final detail = cause['detail'];
      if (detail is String) {
        final normalized = detail.trim();
        if (normalized.isNotEmpty && normalized.length <= 240) {
          return normalized;
        }
      }
    }
    return null;
  }
}

final class PassengerRegistrationIdempotencyKey {
  PassengerRegistrationIdempotencyKey._();

  static final Random _random = Random.secure();

  static String generate() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    String hex(int value) => value.toRadixString(16).padLeft(2, '0');

    return <String>[
      bytes.sublist(0, 4).map(hex).join(),
      bytes.sublist(4, 6).map(hex).join(),
      bytes.sublist(6, 8).map(hex).join(),
      bytes.sublist(8, 10).map(hex).join(),
      bytes.sublist(10, 16).map(hex).join(),
    ].join('-');
  }
}

String? validatePassengerRegistrationName(String value) {
  final normalized = value
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .join(' ');
  if (normalized.length < 2 || normalized.length > 80) {
    return 'Full name must be 2 to 80 characters.';
  }
  return null;
}

String? validatePassengerRegistrationPin(String value) {
  if (!RegExp(r'^\d{4}$').hasMatch(value.trim())) {
    return 'PIN must be exactly 4 numeric digits.';
  }
  return null;
}

String? validatePassengerRegistrationPinConfirmation(
  String pin,
  String confirmation,
) {
  if (pin.trim() != confirmation.trim()) {
    return 'PINs do not match.';
  }
  return null;
}
