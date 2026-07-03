import 'package:flutter_test/flutter_test.dart';
import 'package:passenger_app/location/session_location_history.dart';

void main() {
  group('SessionLocationHistory', () {
    test('starts empty for one normalized market', () {
      final history = SessionLocationHistory.empty(
        marketCode: '  accra-test  ',
      );

      expect(history.marketCode, 'accra-test');
      expect(history.entries, isEmpty);
    });

    test('rejects blank market codes and descriptions explicitly', () {
      expect(
        () => SessionLocationHistory.empty(marketCode: '  '),
        throwsA(
          isA<SessionLocationHistoryValidationException>()
              .having((error) => error.field, 'field', 'marketCode')
              .having(
                (error) => error.message,
                'message',
                'Enter a market code.',
              ),
        ),
      );
      expect(
        () => _emptyHistory().record('\n '),
        throwsA(
          isA<SessionLocationHistoryValidationException>()
              .having((error) => error.field, 'field', 'description')
              .having(
                (error) => error.message,
                'message',
                'Enter a location description.',
              ),
        ),
      );
    });

    test('trims entries and orders them newest first', () {
      final history = _emptyHistory()
          .record('  Solar Hotel  ')
          .record('  Accra Airport  ');

      expect(history.entries, ['Accra Airport', 'Solar Hotel']);
    });

    test('moves case-insensitive duplicates to newest', () {
      final history = _emptyHistory()
          .record('Solar Hotel')
          .record('Accra Airport')
          .record('  solar hotel  ');

      expect(history.entries, ['solar hotel', 'Accra Airport']);
    });

    test('keeps only the five newest entries', () {
      var history = _emptyHistory();
      for (var index = 1; index <= 6; index++) {
        history = history.record('Place $index');
      }

      expect(history.entries, [
        'Place 6',
        'Place 5',
        'Place 4',
        'Place 3',
        'Place 2',
      ]);
    });

    test('exposes an unmodifiable collection', () {
      final history = _emptyHistory().record('Solar Hotel');

      expect(
        () => history.entries.add('Accra Airport'),
        throwsUnsupportedError,
      );
    });

    test('recording returns a new value without changing the original', () {
      final original = _emptyHistory();
      final updated = original.record('Solar Hotel');

      expect(original.entries, isEmpty);
      expect(updated.entries, ['Solar Hotel']);
      expect(updated.marketCode, original.marketCode);
      expect(identical(original, updated), isFalse);
    });
  });
}

SessionLocationHistory _emptyHistory() {
  return SessionLocationHistory.empty(marketCode: 'accra-test');
}
