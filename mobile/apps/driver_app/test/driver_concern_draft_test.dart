import 'package:driver_app/concern/driver_concern_draft.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DriverConcernDraft', () {
    test('creates a valid normalized immutable draft', () {
      final draft = DriverConcernDraft(
        marketCode: '  gh-accra  ',
        category: DriverConcernCategory.vehicleCondition,
        attentionLevel: DriverConcernAttentionLevel.reviewBeforeDriving,
        description: '  Loose exterior mirror  ',
      );

      expect(draft.marketCode, 'gh-accra');
      expect(draft.description, 'Loose exterior mirror');
      expect(draft.category, DriverConcernCategory.vehicleCondition);
      expect(
        draft.attentionLevel,
        DriverConcernAttentionLevel.reviewBeforeDriving,
      );
    });

    test('rejects blank market codes and descriptions', () {
      expect(
        () => DriverConcernDraft(
          marketCode: '  ',
          category: DriverConcernCategory.otherConcern,
          attentionLevel: DriverConcernAttentionLevel.nonUrgentObservation,
          description: 'Observation',
        ),
        throwsA(
          isA<DriverConcernDraftValidationException>().having(
            (error) => error.message,
            'message',
            'Market code must not be blank.',
          ),
        ),
      );
      expect(
        () => DriverConcernDraft(
          marketCode: 'gh-accra',
          category: DriverConcernCategory.otherConcern,
          attentionLevel: DriverConcernAttentionLevel.nonUrgentObservation,
          description: '\n  ',
        ),
        throwsA(
          isA<DriverConcernDraftValidationException>().having(
            (error) => error.message,
            'message',
            'Description must not be blank.',
          ),
        ),
      );
    });

    test('rejects descriptions longer than 240 normalized characters', () {
      expect(
        () => DriverConcernDraft(
          marketCode: 'gh-accra',
          category: DriverConcernCategory.batteryOrCharging,
          attentionLevel: DriverConcernAttentionLevel.reviewBeforeDriving,
          description: 'x' * 241,
        ),
        throwsA(
          isA<DriverConcernDraftValidationException>().having(
            (error) => error.message,
            'message',
            'Description must be 240 characters or fewer.',
          ),
        ),
      );
    });

    test('copyWith preserves the original and validates replacements', () {
      final original = DriverConcernDraft(
        marketCode: 'gh-accra',
        category: DriverConcernCategory.vehicleCondition,
        attentionLevel: DriverConcernAttentionLevel.reviewBeforeDriving,
        description: 'Loose mirror',
      );
      final updated = original.copyWith(
        category: DriverConcernCategory.cabinOrSafetyEquipment,
        description: '  Seat belt concern  ',
      );

      expect(updated.marketCode, original.marketCode);
      expect(updated.attentionLevel, original.attentionLevel);
      expect(updated.category, DriverConcernCategory.cabinOrSafetyEquipment);
      expect(updated.description, 'Seat belt concern');
      expect(original.category, DriverConcernCategory.vehicleCondition);
      expect(original.description, 'Loose mirror');
      expect(identical(original, updated), isFalse);
      expect(
        () => original.copyWith(marketCode: ' '),
        throwsA(isA<DriverConcernDraftValidationException>()),
      );
      expect(
        () => original.copyWith(description: ' '),
        throwsA(isA<DriverConcernDraftValidationException>()),
      );
    });
  });
}
