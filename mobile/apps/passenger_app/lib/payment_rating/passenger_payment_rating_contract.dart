import 'dart:math';

import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_auth/asm_auth.dart';

import '../network/ghana_network_resilience.dart';

abstract interface class PassengerPaymentRatingRepository {
  Future<PassengerFareSnapshot> fetchFare(String requestReference);

  Future<PassengerPaymentSnapshot> initiatePayment(
    String requestReference, {
    required String idempotencyKey,
  });

  Future<PassengerPaymentSnapshot> fetchPayment(String requestReference);

  Future<PassengerPaymentReceiptSnapshot> fetchReceipt(String requestReference);

  Future<PassengerRatingSnapshot> fetchRating(String requestReference);

  Future<PassengerRatingSnapshot> submitRating(
    String requestReference,
    PassengerRatingSubmission submission,
  );
}

abstract interface class PassengerPaymentRatingApiGateway {
  Future<ApiResponse<T>> get<T>(String path, {JsonDecoder<T>? decoder});

  Future<ApiResponse<T>> post<T>(
    String path, {
    Object? data,
    Map<String, String>? headers,
    JsonDecoder<T>? decoder,
  });
}

class AsmPassengerPaymentRatingApiGateway
    implements PassengerPaymentRatingApiGateway {
  const AsmPassengerPaymentRatingApiGateway(this.client);

  final AsmApiClient client;

  @override
  Future<ApiResponse<T>> get<T>(String path, {JsonDecoder<T>? decoder}) {
    return client.get<T>(path, decoder: decoder);
  }

  @override
  Future<ApiResponse<T>> post<T>(
    String path, {
    Object? data,
    Map<String, String>? headers,
    JsonDecoder<T>? decoder,
  }) {
    return client.post<T>(path, data: data, headers: headers, decoder: decoder);
  }
}

final class PassengerFareSnapshot {
  const PassengerFareSnapshot({
    required this.requestReference,
    required this.fareStatus,
    required this.canPay,
    this.tripReference,
    this.amount,
    this.currency,
    this.status,
    this.message,
    this.createdAt,
    this.updatedAt,
  });

  final String requestReference;
  final String? tripReference;
  final String fareStatus;
  final double? amount;
  final String? currency;
  final bool canPay;
  final String? status;
  final String? message;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get normalizedFareStatus => fareStatus.trim().toLowerCase();

  bool get isNotReady => normalizedFareStatus == 'fare_not_ready';

  bool get hasAuthoritativeAmount {
    final value = amount;
    final unit = currency?.trim();

    return value != null &&
        value.isFinite &&
        value >= 0 &&
        unit != null &&
        unit.isNotEmpty;
  }

  String? get formattedAmount {
    if (!hasAuthoritativeAmount) {
      return null;
    }

    final value = amount!;
    final amountText = value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(2);

    return '${currency!.trim().toUpperCase()} $amountText';
  }

  factory PassengerFareSnapshot.fromJson(Object? json) {
    final map = _jsonMap(json, label: 'Fare');

    return PassengerFareSnapshot(
      requestReference: _requiredString(
        map,
        'request_reference',
        label: 'Fare',
      ),
      tripReference: _optionalString(map, 'trip_reference'),
      fareStatus: _requiredString(map, 'fare_status', label: 'Fare'),
      amount: _optionalDouble(map, 'amount'),
      currency: _optionalString(map, 'currency'),
      canPay: _optionalBool(map, 'can_pay'),
      status: _optionalString(map, 'status'),
      message: _optionalString(map, 'message'),
      createdAt: _optionalDateTime(map, 'created_at'),
      updatedAt: _optionalDateTime(map, 'updated_at'),
    );
  }
}

final class PassengerPaymentSnapshot {
  const PassengerPaymentSnapshot({
    required this.requestReference,
    required this.paymentStatus,
    required this.canPay,
    required this.canRetry,
    this.tripReference,
    this.fareStatus,
    this.amount,
    this.currency,
    this.paymentProvider,
    this.paymentMethodLabel,
    this.paymentReference,
    this.status,
    this.message,
    this.createdAt,
    this.updatedAt,
  });

  final String requestReference;
  final String? tripReference;
  final String? fareStatus;
  final double? amount;
  final String? currency;
  final bool canPay;
  final String paymentStatus;
  final String? paymentProvider;
  final String? paymentMethodLabel;
  final String? paymentReference;
  final bool canRetry;
  final String? status;
  final String? message;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get normalizedPaymentStatus => paymentStatus.trim().toLowerCase();

  bool get isConfirmed => const <String>{
    'payment_confirmed',
    'manual_verified',
    'partner_paid',
  }.contains(normalizedPaymentStatus);

  bool get isPending =>
      const <String>{'pending', 'processing'}.contains(normalizedPaymentStatus);

  bool get isFailed => const <String>{
    'failed',
    'expired',
    'cancelled',
    'canceled',
  }.contains(normalizedPaymentStatus);

  factory PassengerPaymentSnapshot.fromJson(Object? json) {
    final map = _jsonMap(json, label: 'Payment');

    return PassengerPaymentSnapshot(
      requestReference: _requiredString(
        map,
        'request_reference',
        label: 'Payment',
      ),
      tripReference: _optionalString(map, 'trip_reference'),
      fareStatus: _optionalString(map, 'fare_status'),
      amount: _optionalDouble(map, 'amount'),
      currency: _optionalString(map, 'currency'),
      canPay: _optionalBool(map, 'can_pay'),
      paymentStatus: _requiredString(map, 'payment_status', label: 'Payment'),
      paymentProvider: _optionalString(map, 'payment_provider'),
      paymentMethodLabel: _optionalString(map, 'payment_method_label'),
      paymentReference: _optionalString(map, 'payment_reference'),
      canRetry: _optionalBool(map, 'can_retry'),
      status: _optionalString(map, 'status'),
      message: _optionalString(map, 'message'),
      createdAt: _optionalDateTime(map, 'created_at'),
      updatedAt: _optionalDateTime(map, 'updated_at'),
    );
  }
}

final class PassengerPaymentReceiptSnapshot {
  const PassengerPaymentReceiptSnapshot({
    required this.requestReference,
    required this.receiptStatus,
    this.tripReference,
    this.amount,
    this.currency,
    this.paymentStatus,
    this.paymentProvider,
    this.paymentMethodLabel,
    this.paymentReference,
    this.status,
    this.message,
    this.createdAt,
    this.updatedAt,
  });

  final String requestReference;
  final String? tripReference;
  final String receiptStatus;
  final double? amount;
  final String? currency;
  final String? paymentStatus;
  final String? paymentProvider;
  final String? paymentMethodLabel;
  final String? paymentReference;
  final String? status;
  final String? message;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get normalizedReceiptStatus => receiptStatus.trim().toLowerCase();

  bool get isAvailable => normalizedReceiptStatus != 'receipt_not_available';

  String? get formattedAmount {
    final value = amount;
    final unit = currency?.trim();

    if (value == null ||
        !value.isFinite ||
        value < 0 ||
        unit == null ||
        unit.isEmpty) {
      return null;
    }

    final amountText = value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(2);

    return '${unit.toUpperCase()} $amountText';
  }

  factory PassengerPaymentReceiptSnapshot.fromJson(Object? json) {
    final map = _jsonMap(json, label: 'Receipt');

    return PassengerPaymentReceiptSnapshot(
      requestReference: _requiredString(
        map,
        'request_reference',
        label: 'Receipt',
      ),
      tripReference: _optionalString(map, 'trip_reference'),
      receiptStatus: _requiredString(map, 'receipt_status', label: 'Receipt'),
      amount: _optionalDouble(map, 'amount'),
      currency: _optionalString(map, 'currency'),
      paymentStatus: _optionalString(map, 'payment_status'),
      paymentProvider: _optionalString(map, 'payment_provider'),
      paymentMethodLabel: _optionalString(map, 'payment_method_label'),
      paymentReference: _optionalString(map, 'payment_reference'),
      status: _optionalString(map, 'status'),
      message: _optionalString(map, 'message'),
      createdAt: _optionalDateTime(map, 'created_at'),
      updatedAt: _optionalDateTime(map, 'updated_at'),
    );
  }
}

final class PassengerRatingSnapshot {
  const PassengerRatingSnapshot({
    required this.requestReference,
    required this.ratingStatus,
    required this.canRate,
    this.tripReference,
    this.overallScore,
    this.comfortScore,
    this.conductScore,
    this.cleanlinessScore,
    this.feedbackNote,
    this.status,
    this.message,
    this.createdAt,
    this.updatedAt,
  });

  final String requestReference;
  final String? tripReference;
  final String ratingStatus;
  final bool canRate;
  final int? overallScore;
  final int? comfortScore;
  final int? conductScore;
  final int? cleanlinessScore;
  final String? feedbackNote;
  final String? status;
  final String? message;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get normalizedRatingStatus => ratingStatus.trim().toLowerCase();

  bool get isOpen => normalizedRatingStatus == 'rating_open' && canRate;

  bool get isSubmitted => normalizedRatingStatus == 'rating_submitted';

  bool get hasStoredScores =>
      _isValidScore(overallScore) &&
      _isValidScore(comfortScore) &&
      _isValidScore(conductScore) &&
      _isValidScore(cleanlinessScore);

  factory PassengerRatingSnapshot.fromJson(Object? json) {
    final map = _jsonMap(json, label: 'Rating');

    return PassengerRatingSnapshot(
      requestReference: _requiredString(
        map,
        'request_reference',
        label: 'Rating',
      ),
      tripReference: _optionalString(map, 'trip_reference'),
      ratingStatus: _requiredString(map, 'rating_status', label: 'Rating'),
      canRate: _optionalBool(map, 'can_rate'),
      overallScore: _optionalInt(map, 'overall_score'),
      comfortScore: _optionalInt(map, 'comfort_score'),
      conductScore: _optionalInt(map, 'conduct_score'),
      cleanlinessScore: _optionalInt(map, 'cleanliness_score'),
      feedbackNote: _optionalString(map, 'feedback_note'),
      status: _optionalString(map, 'status'),
      message: _optionalString(map, 'message'),
      createdAt: _optionalDateTime(map, 'created_at'),
      updatedAt: _optionalDateTime(map, 'updated_at'),
    );
  }

  static bool _isValidScore(int? value) =>
      value != null && value >= 1 && value <= 5;
}

final class PassengerRatingSubmission {
  factory PassengerRatingSubmission({
    required int overallScore,
    required int comfortScore,
    required int conductScore,
    required int cleanlinessScore,
    String? feedbackNote,
  }) {
    _validateScore(overallScore, 'overallScore');
    _validateScore(comfortScore, 'comfortScore');
    _validateScore(conductScore, 'conductScore');
    _validateScore(cleanlinessScore, 'cleanlinessScore');

    final normalizedNote = feedbackNote?.trim();

    if (normalizedNote != null && normalizedNote.length > 240) {
      throw ArgumentError.value(
        feedbackNote,
        'feedbackNote',
        'must be 240 characters or fewer',
      );
    }

    return PassengerRatingSubmission._(
      overallScore: overallScore,
      comfortScore: comfortScore,
      conductScore: conductScore,
      cleanlinessScore: cleanlinessScore,
      feedbackNote: normalizedNote == null || normalizedNote.isEmpty
          ? null
          : normalizedNote,
    );
  }

  const PassengerRatingSubmission._({
    required this.overallScore,
    required this.comfortScore,
    required this.conductScore,
    required this.cleanlinessScore,
    required this.feedbackNote,
  });

  final int overallScore;
  final int comfortScore;
  final int conductScore;
  final int cleanlinessScore;
  final String? feedbackNote;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'overall_score': overallScore,
      'comfort_score': comfortScore,
      'conduct_score': conductScore,
      'cleanliness_score': cleanlinessScore,
      if (feedbackNote != null) 'feedback_note': feedbackNote,
    };
  }

  static void _validateScore(int value, String fieldName) {
    if (value < 1 || value > 5) {
      throw ArgumentError.value(value, fieldName, 'must be between 1 and 5');
    }
  }
}

final class PassengerPaymentIdempotencyKey {
  PassengerPaymentIdempotencyKey._();

  static String generate() {
    final timestamp = DateTime.now().toUtc().microsecondsSinceEpoch;
    final randomValue = Random.secure()
        .nextInt(0x7fffffff)
        .toRadixString(16)
        .padLeft(8, '0');

    return 'APP-PAY-$timestamp-$randomValue';
  }
}

final class ApiPassengerPaymentRatingRepository
    implements PassengerPaymentRatingRepository {
  const ApiPassengerPaymentRatingRepository(
    this.apiGateway, {
    required this.tokenStore,
    this.authService,
    this.connectionConfigured = true,
  });

  factory ApiPassengerPaymentRatingRepository.withDefaultClient({
    AuthTokenStore? tokenStore,
    String? baseUrl,
  }) {
    final resolvedTokenStore = tokenStore ?? SecureAuthTokenStore();
    final configured = AsmApiBaseUrl.isUsable(baseUrl);

    if (!configured) {
      return ApiPassengerPaymentRatingRepository(
        const _UnconfiguredPassengerPaymentRatingApiGateway(),
        tokenStore: resolvedTokenStore,
        connectionConfigured: false,
      );
    }

    final resolvedBaseUrl = baseUrl!.trim();

    return ApiPassengerPaymentRatingRepository(
      AsmPassengerPaymentRatingApiGateway(
        GhanaResilientApiClient(
          baseUrl: resolvedBaseUrl,
          tokenProvider: _PaymentRatingTokenProvider(resolvedTokenStore),
        ),
      ),
      tokenStore: resolvedTokenStore,
      authService: AuthService.withApiClient(
        client: GhanaResilientApiClient(baseUrl: resolvedBaseUrl),
        tokenStore: resolvedTokenStore,
      ),
    );
  }

  final PassengerPaymentRatingApiGateway apiGateway;
  final AuthTokenStore tokenStore;
  final AuthService? authService;
  final bool connectionConfigured;

  static String farePath(String requestReference) {
    return '${_ridePrefix(requestReference)}fare/';
  }

  static String paymentPath(String requestReference) {
    return '${_ridePrefix(requestReference)}payment/';
  }

  static String receiptPath(String requestReference) {
    return '${_ridePrefix(requestReference)}payment/receipt/';
  }

  static String ratingPath(String requestReference) {
    return '${_ridePrefix(requestReference)}rating/';
  }

  static String _ridePrefix(String requestReference) {
    final normalized = requestReference.trim();

    if (normalized.isEmpty) {
      throw const PassengerPaymentRatingException.unknown();
    }

    return '/api/passenger/rides/${Uri.encodeComponent(normalized)}/';
  }

  @override
  Future<PassengerFareSnapshot> fetchFare(String requestReference) {
    final path = farePath(requestReference);

    return _execute<PassengerFareSnapshot>(
      () => apiGateway.get<PassengerFareSnapshot>(
        path,
        decoder: PassengerFareSnapshot.fromJson,
      ),
    );
  }

  @override
  Future<PassengerPaymentSnapshot> initiatePayment(
    String requestReference, {
    required String idempotencyKey,
  }) {
    final normalizedKey = idempotencyKey.trim();

    if (normalizedKey.isEmpty || normalizedKey.length > 160) {
      throw const PassengerPaymentRatingException.unknown();
    }

    final path = paymentPath(requestReference);

    return _execute<PassengerPaymentSnapshot>(
      () => apiGateway.post<PassengerPaymentSnapshot>(
        path,
        data: const <String, Object?>{},
        headers: <String, String>{'Idempotency-Key': normalizedKey},
        decoder: PassengerPaymentSnapshot.fromJson,
      ),
    );
  }

  @override
  Future<PassengerPaymentSnapshot> fetchPayment(String requestReference) {
    final path = paymentPath(requestReference);

    return _execute<PassengerPaymentSnapshot>(
      () => apiGateway.get<PassengerPaymentSnapshot>(
        path,
        decoder: PassengerPaymentSnapshot.fromJson,
      ),
    );
  }

  @override
  Future<PassengerPaymentReceiptSnapshot> fetchReceipt(
    String requestReference,
  ) {
    final path = receiptPath(requestReference);

    return _execute<PassengerPaymentReceiptSnapshot>(
      () => apiGateway.get<PassengerPaymentReceiptSnapshot>(
        path,
        decoder: PassengerPaymentReceiptSnapshot.fromJson,
      ),
    );
  }

  @override
  Future<PassengerRatingSnapshot> fetchRating(String requestReference) {
    final path = ratingPath(requestReference);

    return _execute<PassengerRatingSnapshot>(
      () => apiGateway.get<PassengerRatingSnapshot>(
        path,
        decoder: PassengerRatingSnapshot.fromJson,
      ),
    );
  }

  @override
  Future<PassengerRatingSnapshot> submitRating(
    String requestReference,
    PassengerRatingSubmission submission,
  ) {
    final path = ratingPath(requestReference);

    return _execute<PassengerRatingSnapshot>(
      () => apiGateway.post<PassengerRatingSnapshot>(
        path,
        data: submission.toJson(),
        decoder: PassengerRatingSnapshot.fromJson,
      ),
    );
  }

  Future<T> _execute<T>(Future<ApiResponse<T>> Function() request) async {
    final accessToken = (await tokenStore.readAccessToken())?.trim();

    if (accessToken == null || accessToken.isEmpty) {
      throw const PassengerPaymentRatingException.sessionExpired();
    }

    if (!connectionConfigured) {
      throw const PassengerPaymentRatingException.connectionNotConfigured();
    }

    final response = await request();

    if (response.isSuccess && response.data != null) {
      return response.data as T;
    }

    if (response.statusCode == 401) {
      final refreshed = await _refreshAccessToken();

      if (!refreshed) {
        throw const PassengerPaymentRatingException.sessionExpired();
      }

      final retryResponse = await request();

      if (retryResponse.isSuccess && retryResponse.data != null) {
        return retryResponse.data as T;
      }

      if (retryResponse.statusCode == 401) {
        await tokenStore.clearTokens();
      }

      throw PassengerPaymentRatingException.fromResponse(retryResponse);
    }

    throw PassengerPaymentRatingException.fromResponse(response);
  }

  Future<bool> _refreshAccessToken() async {
    final refreshToken = (await tokenStore.readRefreshToken())?.trim();
    final service = authService;

    if (refreshToken == null || refreshToken.isEmpty || service == null) {
      await tokenStore.clearTokens();
      return false;
    }

    try {
      final state = await service.refresh();

      if (state.isAuthenticated) {
        return true;
      }
    } on Object {
      // User-facing error handling remains generic.
    }

    await tokenStore.clearTokens();
    return false;
  }
}

final class UnavailablePassengerPaymentRatingRepository
    implements PassengerPaymentRatingRepository {
  const UnavailablePassengerPaymentRatingRepository();

  Future<T> _failure<T>() {
    return Future<T>.error(
      const PassengerPaymentRatingException.connectionNotConfigured(),
    );
  }

  @override
  Future<PassengerFareSnapshot> fetchFare(String requestReference) {
    return _failure<PassengerFareSnapshot>();
  }

  @override
  Future<PassengerPaymentSnapshot> initiatePayment(
    String requestReference, {
    required String idempotencyKey,
  }) {
    return _failure<PassengerPaymentSnapshot>();
  }

  @override
  Future<PassengerPaymentSnapshot> fetchPayment(String requestReference) {
    return _failure<PassengerPaymentSnapshot>();
  }

  @override
  Future<PassengerPaymentReceiptSnapshot> fetchReceipt(
    String requestReference,
  ) {
    return _failure<PassengerPaymentReceiptSnapshot>();
  }

  @override
  Future<PassengerRatingSnapshot> fetchRating(String requestReference) {
    return _failure<PassengerRatingSnapshot>();
  }

  @override
  Future<PassengerRatingSnapshot> submitRating(
    String requestReference,
    PassengerRatingSubmission submission,
  ) {
    return _failure<PassengerRatingSnapshot>();
  }
}

final class PassengerPaymentRatingException implements Exception {
  const PassengerPaymentRatingException(
    this.message, {
    this.requiresSignIn = false,
    this.statusCode,
  });

  const PassengerPaymentRatingException.sessionExpired()
    : message = sessionExpiredMessage,
      requiresSignIn = true,
      statusCode = 401;

  const PassengerPaymentRatingException.connectionNotConfigured()
    : message = AsmApiClient.connectionNotConfiguredMessage,
      requiresSignIn = false,
      statusCode = null;

  const PassengerPaymentRatingException.network()
    : message = networkMessage,
      requiresSignIn = false,
      statusCode = null;

  const PassengerPaymentRatingException.server()
    : message = serverMessage,
      requiresSignIn = false,
      statusCode = null;

  const PassengerPaymentRatingException.notFound()
    : message = unavailableMessage,
      requiresSignIn = false,
      statusCode = 404;

  const PassengerPaymentRatingException.conflict()
    : message = unavailableMessage,
      requiresSignIn = false,
      statusCode = 409;

  const PassengerPaymentRatingException.unknown()
    : message = unknownMessage,
      requiresSignIn = false,
      statusCode = null;

  static const sessionExpiredMessage =
      'Your session has expired. Please sign in again.';

  static const networkMessage =
      'Cannot reach the server. Check your connection and try again.';

  static const serverMessage =
      'Service is temporarily unavailable. Please try again later.';

  static const unavailableMessage =
      'This payment or rating action is not available right now.';

  static const passengerRequiredMessage = 'Passenger account required.';

  static const unknownMessage = 'Something went wrong. Please try again.';

  final String message;
  final bool requiresSignIn;
  final int? statusCode;

  static PassengerPaymentRatingException fromResponse<T>(
    ApiResponse<T> response,
  ) {
    final statusCode = response.statusCode;
    final error = response.error;

    if (statusCode == 401) {
      return const PassengerPaymentRatingException.sessionExpired();
    }

    if (statusCode == 403) {
      return const PassengerPaymentRatingException(
        passengerRequiredMessage,
        statusCode: 403,
      );
    }

    if (statusCode == 404) {
      return const PassengerPaymentRatingException.notFound();
    }

    if (statusCode == 409) {
      return const PassengerPaymentRatingException.conflict();
    }

    if (error?.type == AsmApiExceptionType.network ||
        error?.type == AsmApiExceptionType.timeout) {
      return const PassengerPaymentRatingException.network();
    }

    if (statusCode == 503 || error?.type == AsmApiExceptionType.server) {
      return const PassengerPaymentRatingException.server();
    }

    return PassengerPaymentRatingException(
      unknownMessage,
      statusCode: statusCode,
    );
  }

  @override
  String toString() => message;
}

final class _PaymentRatingTokenProvider implements TokenProvider {
  const _PaymentRatingTokenProvider(this.tokenStore);

  final AuthTokenStore tokenStore;

  @override
  Future<String?> getAccessToken() {
    return tokenStore.readAccessToken();
  }
}

final class _UnconfiguredPassengerPaymentRatingApiGateway
    implements PassengerPaymentRatingApiGateway {
  const _UnconfiguredPassengerPaymentRatingApiGateway();

  ApiResponse<T> _failure<T>() {
    return ApiResponse<T>.apiFailure(
      const AsmApiException(
        type: AsmApiExceptionType.badResponse,
        message: AsmApiClient.connectionNotConfiguredMessage,
      ),
    );
  }

  @override
  Future<ApiResponse<T>> get<T>(String path, {JsonDecoder<T>? decoder}) async {
    return _failure<T>();
  }

  @override
  Future<ApiResponse<T>> post<T>(
    String path, {
    Object? data,
    Map<String, String>? headers,
    JsonDecoder<T>? decoder,
  }) async {
    return _failure<T>();
  }
}

Map<String, Object?> _jsonMap(Object? json, {required String label}) {
  if (json is Map<String, Object?>) {
    return json;
  }

  if (json is Map) {
    return json.map((key, value) => MapEntry(key.toString(), value));
  }

  throw FormatException('$label response was not a JSON object.');
}

String _requiredString(
  Map<String, Object?> map,
  String key, {
  required String label,
}) {
  final value = map[key];

  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$label response field $key is missing.');
  }

  return value.trim();
}

String? _optionalString(Map<String, Object?> map, String key) {
  final value = map[key];

  if (value is! String) {
    return null;
  }

  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}

double? _optionalDouble(Map<String, Object?> map, String key) {
  final value = map[key];

  if (value is num) {
    final result = value.toDouble();
    return result.isFinite ? result : null;
  }

  if (value is String) {
    final result = double.tryParse(value.trim());

    if (result != null && result.isFinite) {
      return result;
    }
  }

  return null;
}

int? _optionalInt(Map<String, Object?> map, String key) {
  final value = map[key];

  if (value is int) {
    return value;
  }

  if (value is num && value == value.roundToDouble()) {
    return value.toInt();
  }

  if (value is String) {
    return int.tryParse(value.trim());
  }

  return null;
}

bool _optionalBool(Map<String, Object?> map, String key) {
  final value = map[key];
  return value is bool ? value : false;
}

DateTime? _optionalDateTime(Map<String, Object?> map, String key) {
  final value = map[key];

  if (value is! String || value.trim().isEmpty) {
    return null;
  }

  return DateTime.tryParse(value.trim());
}
