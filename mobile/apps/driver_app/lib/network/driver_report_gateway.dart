import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_auth/asm_auth.dart';

import 'driver_access_token_refresh_guard.dart';
import 'driver_trip_action_gateway.dart';
import 'ghana_network_resilience.dart';

const String driverReportCategoriesPath =
    '/api/content/driver-report-categories/';
const String driverReportSubmissionPath = '/api/driver/report/';

abstract interface class DriverReportApiGateway {
  Future<ApiResponse<T>> get<T>(String path, {JsonDecoder<T>? decoder});

  Future<ApiResponse<T>> post<T>(
    String path, {
    Object? data,
    Map<String, String>? headers,
    JsonDecoder<T>? decoder,
  });
}

final class AsmDriverReportApiGateway implements DriverReportApiGateway {
  const AsmDriverReportApiGateway(this.client);

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

final class DriverReportReceipt {
  const DriverReportReceipt({
    required this.reportReference,
    required this.status,
  });

  factory DriverReportReceipt.fromJson(Object? json) {
    if (json is! Map) {
      throw const FormatException(
        'Driver report response was not a JSON object.',
      );
    }

    final normalized = json.map(
      (key, value) => MapEntry(key.toString(), value),
    );
    final rawReference = normalized['report_reference'];
    final rawStatus = normalized['status'];

    if (rawReference is! String ||
        !RegExp(r'^RPT-[A-Z0-9]{10}$').hasMatch(rawReference.trim()) ||
        rawStatus is! String ||
        rawStatus.trim() != 'received') {
      throw const FormatException('Driver report response was incomplete.');
    }

    return DriverReportReceipt(
      reportReference: rawReference.trim(),
      status: rawStatus.trim(),
    );
  }

  final String reportReference;
  final String status;

  bool confirms(int? statusCode) {
    return statusCode == 201 &&
        status == 'received' &&
        RegExp(r'^RPT-[A-Z0-9]{10}$').hasMatch(reportReference);
  }
}

enum DriverReportFailureType {
  signInRequired,
  clientFailure,
  temporarilyUnavailable,
  badResponse,
}

final class DriverReportException implements Exception {
  const DriverReportException({required this.type, required this.message});

  final DriverReportFailureType type;
  final String message;

  bool get retryable =>
      type == DriverReportFailureType.clientFailure ||
      type == DriverReportFailureType.temporarilyUnavailable;

  @override
  String toString() => 'DriverReportException(type=$type)';
}

abstract interface class DriverReportGateway {
  Future<List<String>> fetchCategories({bool forceRefresh = false});

  Future<DriverReportReceipt> submit({
    required String category,
    required String description,
    required String urgency,
  });

  void clearSessionCache();
}

final class ApiDriverReportGateway implements DriverReportGateway {
  ApiDriverReportGateway({
    required this.apiGateway,
    required AuthTokenStore tokenStore,
    this.refreshAccessToken,
    GhanaRetryPolicy? retryPolicy,
    this.connectionConfigured = true,
  }) : _retryPolicy = retryPolicy ?? const GhanaRetryPolicy(),
       _tokenGuard = DriverAccessTokenRefreshGuard(
         tokenStore: tokenStore,
         refreshAccessToken: refreshAccessToken,
       );

  final DriverReportApiGateway apiGateway;
  final DriverAccessTokenRefresh? refreshAccessToken;
  final GhanaRetryPolicy _retryPolicy;
  final DriverAccessTokenRefreshGuard _tokenGuard;
  final bool connectionConfigured;

  List<String>? _cachedCategories;

  @override
  Future<List<String>> fetchCategories({bool forceRefresh = false}) async {
    if (!connectionConfigured) {
      throw const DriverReportException(
        type: DriverReportFailureType.badResponse,
        message: AsmApiClient.connectionNotConfiguredMessage,
      );
    }

    final cached = _cachedCategories;
    if (!forceRefresh && cached != null) {
      return cached;
    }

    final response = await _retryPolicy.execute<List<String>>(
      safeToRetry: true,
      operation: () => apiGateway.get<List<String>>(
        driverReportCategoriesPath,
        decoder: _decodeCategories,
      ),
    );

    final categories = response.data;
    if (response.isSuccess &&
        response.statusCode == 200 &&
        categories != null &&
        categories.isNotEmpty) {
      final immutable = List<String>.unmodifiable(categories);
      _cachedCategories = immutable;
      return immutable;
    }

    throw _exceptionFromResponse(
      response,
      fallbackMessage:
          'Report categories are temporarily unavailable. '
          'Check your connection and retry.',
    );
  }

  @override
  Future<DriverReportReceipt> submit({
    required String category,
    required String description,
    required String urgency,
  }) async {
    final normalizedCategory = category.trim();
    final normalizedDescription = description.trim();
    final normalizedUrgency = urgency.trim();

    if (normalizedCategory.isEmpty ||
        normalizedDescription.isEmpty ||
        (normalizedUrgency != 'normal' && normalizedUrgency != 'urgent')) {
      throw const DriverReportException(
        type: DriverReportFailureType.badResponse,
        message: 'The report could not be prepared safely.',
      );
    }

    if (!connectionConfigured) {
      throw const DriverReportException(
        type: DriverReportFailureType.badResponse,
        message: AsmApiClient.connectionNotConfiguredMessage,
      );
    }

    final firstAccessToken = await _resolveAccessToken();
    final firstResponse = await _postOnce(
      category: normalizedCategory,
      description: normalizedDescription,
      urgency: normalizedUrgency,
      accessToken: firstAccessToken,
    );

    final firstReceipt = _validatedReceipt(firstResponse);
    if (firstReceipt != null) {
      return firstReceipt;
    }

    if (firstResponse.statusCode == 401) {
      final refreshedAccessToken = await _resolveAccessToken(
        forceRefresh: true,
      );
      final retryResponse = await _postOnce(
        category: normalizedCategory,
        description: normalizedDescription,
        urgency: normalizedUrgency,
        accessToken: refreshedAccessToken,
      );
      final retryReceipt = _validatedReceipt(retryResponse);
      if (retryReceipt != null) {
        return retryReceipt;
      }
      throw _exceptionFromResponse(
        retryResponse,
        fallbackMessage:
            'Your report could not be sent. '
            'Check your connection and retry.',
      );
    }

    throw _exceptionFromResponse(
      firstResponse,
      fallbackMessage:
          'Your report could not be sent. '
          'Check your connection and retry.',
    );
  }

  @override
  void clearSessionCache() {
    _cachedCategories = null;
  }

  Future<String> _resolveAccessToken({bool forceRefresh = false}) async {
    try {
      final resolution = await _tokenGuard.resolve(forceRefresh: forceRefresh);
      return resolution.accessToken;
    } on DriverAccessTokenRefreshException {
      throw const DriverReportException(
        type: DriverReportFailureType.signInRequired,
        message: 'Please sign in again to send your report.',
      );
    }
  }

  Future<ApiResponse<DriverReportReceipt>> _postOnce({
    required String category,
    required String description,
    required String urgency,
    required String accessToken,
  }) {
    return _retryPolicy.execute<DriverReportReceipt>(
      safeToRetry: false,
      operation: () => apiGateway.post<DriverReportReceipt>(
        driverReportSubmissionPath,
        data: <String, Object?>{
          'category': category,
          'description': description,
          'urgency': urgency,
        },
        headers: <String, String>{
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        decoder: DriverReportReceipt.fromJson,
      ),
    );
  }

  DriverReportReceipt? _validatedReceipt(
    ApiResponse<DriverReportReceipt> response,
  ) {
    final receipt = response.data;
    if (!response.isSuccess || receipt == null) {
      return null;
    }

    if (!receipt.confirms(response.statusCode)) {
      throw const DriverReportException(
        type: DriverReportFailureType.badResponse,
        message: 'The report response could not be confirmed.',
      );
    }

    return receipt;
  }

  DriverReportException _exceptionFromResponse<T>(
    ApiResponse<T> response, {
    required String fallbackMessage,
  }) {
    final statusCode = response.statusCode;
    final error = response.error;

    if (statusCode == 401 ||
        error?.type == AsmApiExceptionType.authentication) {
      return const DriverReportException(
        type: DriverReportFailureType.signInRequired,
        message: 'Please sign in again to send your report.',
      );
    }

    if (error?.type == AsmApiExceptionType.network ||
        error?.type == AsmApiExceptionType.timeout ||
        error?.type == AsmApiExceptionType.server ||
        statusCode == 502 ||
        statusCode == 503 ||
        statusCode == 504) {
      return DriverReportException(
        type: DriverReportFailureType.temporarilyUnavailable,
        message: fallbackMessage,
      );
    }

    if (statusCode != null && statusCode >= 400 && statusCode < 500) {
      return DriverReportException(
        type: DriverReportFailureType.clientFailure,
        message: fallbackMessage,
      );
    }

    return DriverReportException(
      type: DriverReportFailureType.badResponse,
      message: fallbackMessage,
    );
  }

  static List<String> _decodeCategories(Object? json) {
    if (json is! Map) {
      throw const FormatException(
        'Driver report categories response was not a JSON object.',
      );
    }

    final normalized = json.map(
      (key, value) => MapEntry(key.toString(), value),
    );
    final rawCategories = normalized['categories'];

    if (rawCategories is! List || rawCategories.isEmpty) {
      throw const FormatException(
        'Driver report categories response was incomplete.',
      );
    }

    final categories = <String>[];
    for (final rawCategory in rawCategories) {
      if (rawCategory is! String || rawCategory.trim().isEmpty) {
        throw const FormatException('Driver report category was invalid.');
      }
      categories.add(rawCategory.trim());
    }

    return categories;
  }
}
