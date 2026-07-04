import 'dart:async';

import 'package:dio/dio.dart';

/// Converts decoded JSON response data into the caller's expected type.
typedef JsonDecoder<T> = T Function(Object? json);

/// Supplies an access token for authenticated API requests.
///
/// Storage and refresh behavior are intentionally out of scope for this
/// package. Future auth work can implement this interface with secure storage
/// and token refresh logic.
abstract interface class TokenProvider {
  FutureOr<String?> getAccessToken();
}

/// High-level category for an API response.
enum ApiResponseKind { success, apiFailure, clientException }

/// Supported client exception categories for ASM API calls.
enum AsmApiExceptionType {
  network,
  timeout,
  authentication,
  notFound,
  server,
  badResponse,
}

/// Future mobile API dependencies that remain disabled before PM handoff.
enum MobileApiFeature { cc4aMobileAuthApi, cc4bRideRequestApi }

/// Clear exception raised when blocked mobile API work is requested too early.
class DisabledMobileApiException implements Exception {
  const DisabledMobileApiException(this.message);

  final String message;

  @override
  String toString() => 'DisabledMobileApiException: $message';
}

/// Local guard for future CC4A/CC4B mobile API integration work.
///
/// This guard intentionally defines no endpoint paths, payload schemas, token
/// handling, or request submission behavior.
final class DisabledMobileApiGuard {
  const DisabledMobileApiGuard();

  static const cc4aDisabledMessage =
      'CC4A Mobile auth API is disabled pending Control Center handoff';
  static const cc4bDisabledMessage =
      'CC4B Ride request API is disabled pending Control Center handoff';

  bool get mobileAuthApiAvailable => false;
  bool get rideRequestApiAvailable => true;

  void requireFeature(MobileApiFeature feature) {
    if (feature == MobileApiFeature.cc4bRideRequestApi) {
      return;
    }

    throw DisabledMobileApiException(disabledMessageFor(feature));
  }

  String disabledMessageFor(MobileApiFeature feature) {
    return switch (feature) {
      MobileApiFeature.cc4aMobileAuthApi => cc4aDisabledMessage,
      MobileApiFeature.cc4bRideRequestApi => cc4bDisabledMessage,
    };
  }
}

/// Clear API exception value used by [ApiResponse].
class AsmApiException implements Exception {
  const AsmApiException({
    required this.type,
    required this.message,
    this.statusCode,
    this.cause,
  });

  final AsmApiExceptionType type;
  final String message;
  final int? statusCode;
  final Object? cause;

  @override
  String toString() {
    final status = statusCode == null ? '' : ' statusCode=$statusCode';
    return 'AsmApiException(type=$type,$status, message=$message)';
  }
}

/// Success/failure wrapper for future ASM API responses.
class ApiResponse<T> {
  const ApiResponse._({
    required this.kind,
    this.data,
    this.error,
    this.statusCode,
  });

  factory ApiResponse.success(T data, {int? statusCode}) {
    return ApiResponse._(
      kind: ApiResponseKind.success,
      data: data,
      statusCode: statusCode,
    );
  }

  factory ApiResponse.apiFailure(AsmApiException error) {
    return ApiResponse._(
      kind: ApiResponseKind.apiFailure,
      error: error,
      statusCode: error.statusCode,
    );
  }

  factory ApiResponse.clientException(AsmApiException error) {
    return ApiResponse._(
      kind: ApiResponseKind.clientException,
      error: error,
      statusCode: error.statusCode,
    );
  }

  final ApiResponseKind kind;
  final T? data;
  final AsmApiException? error;
  final int? statusCode;

  bool get isSuccess => kind == ApiResponseKind.success;
  bool get isApiFailure => kind == ApiResponseKind.apiFailure;
  bool get isClientException => kind == ApiResponseKind.clientException;
}

/// Request payload for the accepted CC4B Passenger Ride Request endpoint.
final class PassengerRideRequestSubmission {
  PassengerRideRequestSubmission({
    required String idempotencyKey,
    required String pickupLocation,
    required String destination,
    required int passengerCount,
    String? assistanceNote,
  }) : idempotencyKey = _requiredString(
         idempotencyKey,
         'idempotencyKey',
         maxLength: 160,
       ),
       pickupLocation = _requiredString(
         pickupLocation,
         'pickupLocation',
         maxLength: 240,
       ),
       destination = _requiredString(
         destination,
         'destination',
         maxLength: 240,
       ),
       passengerCount = _validatePassengerCount(passengerCount),
       assistanceNote = _optionalString(
         assistanceNote,
         'assistanceNote',
         maxLength: 1000,
       );

  final String idempotencyKey;
  final String pickupLocation;
  final String destination;
  final int passengerCount;
  final String? assistanceNote;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'pickup_location': pickupLocation,
      'destination': destination,
      'passenger_count': passengerCount,
      if (assistanceNote != null) 'assistance_note': assistanceNote,
    };
  }

  static String _requiredString(
    String value,
    String fieldName, {
    required int maxLength,
  }) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(value, fieldName, 'must not be empty');
    }
    if (trimmed.length > maxLength) {
      throw ArgumentError.value(
        value,
        fieldName,
        'must be $maxLength characters or fewer',
      );
    }
    return trimmed;
  }

  static String? _optionalString(
    String? value,
    String fieldName, {
    required int maxLength,
  }) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    if (trimmed.length > maxLength) {
      throw ArgumentError.value(
        value,
        fieldName,
        'must be $maxLength characters or fewer',
      );
    }
    return trimmed;
  }

  static int _validatePassengerCount(int value) {
    if (value < 1 || value > 6) {
      throw ArgumentError.value(
        value,
        'passengerCount',
        'must be between 1 and 6',
      );
    }
    return value;
  }
}

/// Accepted response for Passenger Ride Request submission.
final class PassengerRideRequestResult {
  const PassengerRideRequestResult({
    this.requestReference,
    required this.status,
    required this.message,
  });

  final String? requestReference;
  final String status;
  final String message;

  static PassengerRideRequestResult fromJson(Object? json) {
    if (json is! Map) {
      throw const FormatException(
        'Ride request response was not a JSON object.',
      );
    }

    final requestReference = json['request_reference'];
    final status = json['status'];
    final message = json['message'];

    if (status is! String || status.trim().isEmpty) {
      throw const FormatException('Ride request response status is missing.');
    }
    if (message is! String || message.trim().isEmpty) {
      throw const FormatException('Ride request response message is missing.');
    }

    return PassengerRideRequestResult(
      requestReference:
          requestReference is String && requestReference.trim().isNotEmpty
          ? requestReference.trim()
          : null,
      status: status.trim(),
      message: message.trim(),
    );
  }
}

/// Shared HTTP client foundation for future Django Control Center API calls.
class AsmApiClient {
  AsmApiClient({
    required String baseUrl,
    TokenProvider? tokenProvider,
    Dio? dio,
    Duration connectTimeout = const Duration(seconds: 10),
    Duration sendTimeout = const Duration(seconds: 10),
    Duration receiveTimeout = const Duration(seconds: 20),
  }) : _dio = dio ?? Dio(),
       _tokenProvider = tokenProvider {
    final cleanedBaseUrl = baseUrl.trim();
    if (cleanedBaseUrl.isEmpty) {
      throw ArgumentError.value(baseUrl, 'baseUrl', 'must not be empty');
    }

    _dio.options
      ..baseUrl = cleanedBaseUrl
      ..connectTimeout = connectTimeout
      ..sendTimeout = sendTimeout
      ..receiveTimeout = receiveTimeout
      ..responseType = ResponseType.json
      ..validateStatus = (_) => true;
    _dio.options.headers.addAll(jsonHeaders);
  }

  /// Safe compile-time default for local development and tests only.
  static const defaultBaseUrl = String.fromEnvironment(
    'ASM_API_BASE_URL',
    defaultValue: 'http://localhost:8000/api/',
  );

  static const jsonHeaders = <String, String>{
    'Accept': 'application/json',
    'Content-Type': 'application/json',
  };

  final Dio _dio;
  final TokenProvider? _tokenProvider;

  Future<ApiResponse<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    JsonDecoder<T>? decoder,
  }) {
    return request<T>(
      method: 'GET',
      path: path,
      queryParameters: queryParameters,
      decoder: decoder,
    );
  }

  Future<ApiResponse<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
    JsonDecoder<T>? decoder,
  }) {
    return request<T>(
      method: 'POST',
      path: path,
      data: data,
      queryParameters: queryParameters,
      headers: headers,
      decoder: decoder,
    );
  }

  Future<ApiResponse<PassengerRideRequestResult>> submitPassengerRideRequest(
    PassengerRideRequestSubmission submission,
  ) {
    return post<PassengerRideRequestResult>(
      '/api/rides/request/',
      data: submission.toJson(),
      headers: <String, String>{'Idempotency-Key': submission.idempotencyKey},
      decoder: PassengerRideRequestResult.fromJson,
    );
  }

  Future<ApiResponse<T>> request<T>({
    required String method,
    required String path,
    Object? data,
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
    JsonDecoder<T>? decoder,
  }) async {
    try {
      final requestHeaders = await _requestHeaders(additionalHeaders: headers);
      final response = await _dio.request<Object?>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: Options(method: method, headers: requestHeaders),
      );
      return _mapResponse(response, decoder);
    } on DioException catch (error) {
      return ApiResponse.clientException(_mapDioException(error));
    } on TimeoutException catch (error) {
      return ApiResponse.clientException(
        AsmApiException(
          type: AsmApiExceptionType.timeout,
          message: 'The API request timed out.',
          cause: error,
        ),
      );
    } catch (error) {
      return ApiResponse.clientException(
        AsmApiException(
          type: AsmApiExceptionType.badResponse,
          message: 'The API request failed before a valid response was read.',
          cause: error,
        ),
      );
    }
  }

  Future<Map<String, String>> _requestHeaders({
    Map<String, String>? additionalHeaders,
  }) async {
    final headers = Map<String, String>.of(jsonHeaders);
    final token = await _tokenProvider?.getAccessToken();
    if (token != null && token.trim().isNotEmpty) {
      headers['Authorization'] = 'Bearer ${token.trim()}';
    }
    if (additionalHeaders != null) {
      headers.addAll(additionalHeaders);
    }
    return headers;
  }

  ApiResponse<T> _mapResponse<T>(
    Response<Object?> response,
    JsonDecoder<T>? decoder,
  ) {
    final statusCode = response.statusCode ?? 0;
    if (statusCode >= 200 && statusCode < 300) {
      final value = decoder == null
          ? response.data as T
          : decoder(response.data);
      return ApiResponse.success(value, statusCode: statusCode);
    }

    return ApiResponse.apiFailure(_mapStatusCode(statusCode, response.data));
  }

  AsmApiException _mapStatusCode(int statusCode, Object? body) {
    if (statusCode == 401) {
      return AsmApiException(
        type: AsmApiExceptionType.authentication,
        message: 'Authentication failed.',
        statusCode: statusCode,
        cause: body,
      );
    }

    if (statusCode == 404) {
      return AsmApiException(
        type: AsmApiExceptionType.notFound,
        message: 'The requested API resource was not found.',
        statusCode: statusCode,
        cause: body,
      );
    }

    if (statusCode >= 500 && statusCode < 600) {
      return AsmApiException(
        type: AsmApiExceptionType.server,
        message: 'The API server returned an error.',
        statusCode: statusCode,
        cause: body,
      );
    }

    return AsmApiException(
      type: AsmApiExceptionType.badResponse,
      message: 'The API returned an unexpected response.',
      statusCode: statusCode,
      cause: body,
    );
  }

  AsmApiException _mapDioException(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return _timeoutException(error);
      case DioExceptionType.connectionError:
      case DioExceptionType.badCertificate:
      case DioExceptionType.unknown:
        return AsmApiException(
          type: AsmApiExceptionType.network,
          message: 'The API request could not reach the network.',
          cause: error,
        );
      case DioExceptionType.badResponse:
        return _mapStatusCode(
          error.response?.statusCode ?? 0,
          error.response?.data,
        );
      case DioExceptionType.cancel:
        return AsmApiException(
          type: AsmApiExceptionType.badResponse,
          message: 'The API request was cancelled.',
          cause: error,
        );
      default:
        if (error.type.name == 'transformTimeout') {
          return _timeoutException(error);
        }
        return AsmApiException(
          type: AsmApiExceptionType.badResponse,
          message: 'The API returned an unexpected response.',
          cause: error,
        );
    }
  }

  AsmApiException _timeoutException(DioException error) {
    return AsmApiException(
      type: AsmApiExceptionType.timeout,
      message: 'The API request timed out.',
      cause: error,
    );
  }
}
