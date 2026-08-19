enum DriverConcernAttentionLevel {
  reviewBeforeDriving(label: 'Urgent', urgency: 'urgent'),
  nonUrgentObservation(label: 'Not urgent', urgency: 'normal');

  const DriverConcernAttentionLevel({
    required this.label,
    required this.urgency,
  });

  final String label;
  final String urgency;
}

final class DriverConcernDraftValidationException implements Exception {
  const DriverConcernDraftValidationException(this.message);

  final String message;

  @override
  String toString() => 'DriverConcernDraftValidationException: $message';
}

final class DriverConcernDraft {
  factory DriverConcernDraft({
    required String marketCode,
    required String category,
    required DriverConcernAttentionLevel attentionLevel,
    required String description,
  }) {
    final normalizedMarketCode = marketCode.trim();
    final normalizedCategory = category.trim();
    final normalizedDescription = description.trim();

    if (normalizedMarketCode.isEmpty) {
      throw const DriverConcernDraftValidationException(
        'Market code must not be blank.',
      );
    }
    if (normalizedCategory.isEmpty) {
      throw const DriverConcernDraftValidationException(
        'Category must not be blank.',
      );
    }
    if (normalizedDescription.isEmpty) {
      throw const DriverConcernDraftValidationException(
        'Description must not be blank.',
      );
    }
    if (normalizedDescription.length > 240) {
      throw const DriverConcernDraftValidationException(
        'Description must be 240 characters or fewer.',
      );
    }

    return DriverConcernDraft._(
      marketCode: normalizedMarketCode,
      category: normalizedCategory,
      attentionLevel: attentionLevel,
      description: normalizedDescription,
    );
  }

  const DriverConcernDraft._({
    required this.marketCode,
    required this.category,
    required this.attentionLevel,
    required this.description,
  });

  final String marketCode;
  final String category;
  final DriverConcernAttentionLevel attentionLevel;
  final String description;

  String get urgency => attentionLevel.urgency;

  DriverConcernDraft copyWith({
    String? marketCode,
    String? category,
    DriverConcernAttentionLevel? attentionLevel,
    String? description,
  }) {
    return DriverConcernDraft(
      marketCode: marketCode ?? this.marketCode,
      category: category ?? this.category,
      attentionLevel: attentionLevel ?? this.attentionLevel,
      description: description ?? this.description,
    );
  }
}
