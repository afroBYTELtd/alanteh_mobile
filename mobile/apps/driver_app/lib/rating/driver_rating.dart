class DriverRatingSnapshot {
  const DriverRatingSnapshot({
    required this.tripReference,
    required this.submitted,
    this.overallScore,
    this.comfortScore,
    this.conductScore,
    this.cleanlinessScore,
    this.feedbackNote,
    this.submittedAt,
    this.status,
    this.message,
  });

  factory DriverRatingSnapshot.fromJson(Object? json) {
    if (json is! Map) {
      throw const FormatException(
        'Driver rating response was not a JSON object.',
      );
    }

    final map = json.map(
      (key, value) => MapEntry(key.toString(), value),
    );

    final rating = map['rating'];

    Map<String, Object?>? ratingMap;
    if (rating is Map) {
      ratingMap = rating.map(
        (key, value) => MapEntry(key.toString(), value),
      );
    }

    return DriverRatingSnapshot(
      tripReference: _requiredString(map['trip_reference']),
      submitted: map['submitted'] == true,
      overallScore: _optionalInt(ratingMap?['overall_score']),
      comfortScore: _optionalInt(ratingMap?['comfort_score']),
      conductScore: _optionalInt(ratingMap?['conduct_score']),
      cleanlinessScore: _optionalInt(ratingMap?['cleanliness_score']),
      feedbackNote: _optionalString(ratingMap?['feedback_note']),
      submittedAt: _optionalDateTime(ratingMap?['submitted_at']),
      status: _optionalString(map['status']),
      message: _optionalString(map['message']),
    );
  }

  final String tripReference;
  final bool submitted;
  final int? overallScore;
  final int? comfortScore;
  final int? conductScore;
  final int? cleanlinessScore;
  final String? feedbackNote;
  final DateTime? submittedAt;
  final String? status;
  final String? message;

  bool get hasValidScores {
    return _validScore(overallScore) &&
        _validScore(comfortScore) &&
        _validScore(conductScore) &&
        _validScore(cleanlinessScore);
  }

  static bool _validScore(int? value) {
    return value != null && value >= 1 && value <= 5;
  }

  static String _requiredString(Object? value) {
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    throw const FormatException('Driver rating trip reference missing.');
  }

  static String? _optionalString(Object? value) {
    return value is String ? value.trim() : null;
  }

  static int? _optionalInt(Object? value) {
    return value is int ? value : null;
  }

  static DateTime? _optionalDateTime(Object? value) {
    if (value is! String || value.trim().isEmpty) {
      return null;
    }
    return DateTime.tryParse(value.trim());
  }
}

bool isValidDriverRatingScore(int? score) {
  return score != null && score >= 1 && score <= 5;
}

bool isValidDriverRatingFeedback(String feedback) {
  return feedback.length <= 1000;
}
