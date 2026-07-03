enum DriverConcernCategory {
  vehicleCondition('Vehicle'),
  batteryOrCharging('Battery'),
  cabinOrSafetyEquipment('Safety'),
  shiftDetailsOrDocuments('Documents'),
  otherConcern('Other');

  const DriverConcernCategory(this.label);

  final String label;
}

enum DriverConcernAttentionLevel {
  reviewBeforeDriving('Urgent'),
  nonUrgentObservation('Not urgent');

  const DriverConcernAttentionLevel(this.label);

  final String label;
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
    required DriverConcernCategory category,
    required DriverConcernAttentionLevel attentionLevel,
    required String description,
  }) {
    final normalizedMarketCode = marketCode.trim();
    final normalizedDescription = description.trim();

    if (normalizedMarketCode.isEmpty) {
      throw const DriverConcernDraftValidationException(
        'Market code must not be blank.',
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
      category: category,
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
  final DriverConcernCategory category;
  final DriverConcernAttentionLevel attentionLevel;
  final String description;

  DriverConcernDraft copyWith({
    String? marketCode,
    DriverConcernCategory? category,
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
