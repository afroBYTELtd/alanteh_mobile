final class SessionLocationHistory {
  factory SessionLocationHistory.empty({required String marketCode}) {
    final normalizedMarketCode = marketCode.trim();
    if (normalizedMarketCode.isEmpty) {
      throw const SessionLocationHistoryValidationException(
        field: 'marketCode',
        message: 'Enter a market code.',
      );
    }

    return SessionLocationHistory._(
      marketCode: normalizedMarketCode,
      entries: const [],
    );
  }

  SessionLocationHistory._({
    required this.marketCode,
    required List<String> entries,
  }) : entries = List.unmodifiable(entries);

  static const int maximumEntries = 5;

  final String marketCode;
  final List<String> entries;

  SessionLocationHistory record(String description) {
    final normalizedDescription = description.trim();
    if (normalizedDescription.isEmpty) {
      throw const SessionLocationHistoryValidationException(
        field: 'description',
        message: 'Enter a location description.',
      );
    }

    final comparisonValue = normalizedDescription.toLowerCase();
    final updatedEntries = [
      normalizedDescription,
      ...entries.where((entry) => entry.toLowerCase() != comparisonValue),
    ].take(maximumEntries).toList(growable: false);

    return SessionLocationHistory._(
      marketCode: marketCode,
      entries: updatedEntries,
    );
  }
}

final class SessionLocationHistoryValidationException implements Exception {
  const SessionLocationHistoryValidationException({
    required this.field,
    required this.message,
  });

  final String field;
  final String message;

  @override
  String toString() => message;
}
