final class PassengerLocalRatingRecord {
  const PassengerLocalRatingRecord({
    required this.requestReference,
    required this.overallScore,
    required this.comfortScore,
    required this.conductScore,
    required this.cleanlinessScore,
    required this.savedAt,
    this.feedbackNote,
  });

  final String requestReference;
  final int overallScore;
  final int comfortScore;
  final int conductScore;
  final int cleanlinessScore;
  final String? feedbackNote;
  final DateTime savedAt;
}

abstract interface class PassengerLocalRatingStore {
  PassengerLocalRatingRecord? read(String requestReference);

  void save(PassengerLocalRatingRecord record);

  void clear(String requestReference);
}

final class PassengerSessionRatingStore implements PassengerLocalRatingStore {
  PassengerSessionRatingStore._();

  static final PassengerSessionRatingStore instance =
      PassengerSessionRatingStore._();

  final Map<String, PassengerLocalRatingRecord> _records =
      <String, PassengerLocalRatingRecord>{};

  @override
  PassengerLocalRatingRecord? read(String requestReference) {
    return _records[_normalizeReference(requestReference)];
  }

  @override
  void save(PassengerLocalRatingRecord record) {
    _records[_normalizeReference(record.requestReference)] = record;
  }

  @override
  void clear(String requestReference) {
    _records.remove(_normalizeReference(requestReference));
  }
}

final class MemoryPassengerLocalRatingStore
    implements PassengerLocalRatingStore {
  final Map<String, PassengerLocalRatingRecord> _records =
      <String, PassengerLocalRatingRecord>{};

  @override
  PassengerLocalRatingRecord? read(String requestReference) {
    return _records[_normalizeReference(requestReference)];
  }

  @override
  void save(PassengerLocalRatingRecord record) {
    _records[_normalizeReference(record.requestReference)] = record;
  }

  @override
  void clear(String requestReference) {
    _records.remove(_normalizeReference(requestReference));
  }
}

String _normalizeReference(String value) {
  final normalized = value.trim();

  if (normalized.isEmpty) {
    throw ArgumentError.value(value, 'requestReference', 'must not be empty');
  }

  return normalized;
}
