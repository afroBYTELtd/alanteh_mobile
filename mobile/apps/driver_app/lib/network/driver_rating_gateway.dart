import 'package:asm_api_client/asm_api_client.dart';

import '../rating/driver_rating.dart';

const String driverRatingPathPrefix = '/api/driver/trips/';

final class AsmDriverRatingApiGateway implements DriverRatingApiGateway {
  const AsmDriverRatingApiGateway(this.client);

  final AsmApiClient client;

  @override
  Future<ApiResponse<T>> get<T>(String path, {JsonDecoder<T>? decoder}) {
    return client.get<T>(path, decoder: decoder);
  }

  @override
  Future<ApiResponse<T>> post<T>(
    String path, {
    Object? data,
    JsonDecoder<T>? decoder,
  }) {
    return client.post<T>(path, data: data, decoder: decoder);
  }
}

abstract interface class DriverRatingApiGateway {
  Future<ApiResponse<T>> get<T>(String path, {JsonDecoder<T>? decoder});

  Future<ApiResponse<T>> post<T>(
    String path, {
    Object? data,
    JsonDecoder<T>? decoder,
  });
}

final class ApiDriverRatingGateway {
  ApiDriverRatingGateway({required this.apiGateway});

  final DriverRatingApiGateway apiGateway;

  Future<DriverRatingSnapshot> fetchRating(String tripReference) async {
    final response = await apiGateway.get<DriverRatingSnapshot>(
      _path(tripReference),
      decoder: DriverRatingSnapshot.fromJson,
    );

    if (response.isSuccess && response.data != null) {
      return response.data!;
    }

    throw DriverRatingException('Driver rating could not be loaded.');
  }

  Future<DriverRatingSnapshot> submitRating({
    required String tripReference,
    required int overallScore,
    required int comfortScore,
    required int conductScore,
    required int cleanlinessScore,
    String feedbackNote = '',
  }) async {
    if (!isValidDriverRatingScore(overallScore) ||
        !isValidDriverRatingScore(comfortScore) ||
        !isValidDriverRatingScore(conductScore) ||
        !isValidDriverRatingScore(cleanlinessScore) ||
        !isValidDriverRatingFeedback(feedbackNote)) {
      throw DriverRatingException('Driver rating values are invalid.');
    }

    final response = await apiGateway.post<DriverRatingSnapshot>(
      _path(tripReference),
      data: <String, Object?>{
        'overall_score': overallScore,
        'comfort_score': comfortScore,
        'conduct_score': conductScore,
        'cleanliness_score': cleanlinessScore,
        'feedback_note': feedbackNote.trim(),
      },
      decoder: DriverRatingSnapshot.fromJson,
    );

    if (response.isSuccess && response.data != null) {
      return response.data!;
    }

    throw DriverRatingException('Driver rating could not be submitted.');
  }

  String _path(String tripReference) {
    final encoded = Uri.encodeComponent(tripReference.trim());
    return '$driverRatingPathPrefix$encoded/rating/';
  }
}

final class DriverRatingException implements Exception {
  const DriverRatingException(this.message);

  final String message;

  @override
  String toString() => message;
}
