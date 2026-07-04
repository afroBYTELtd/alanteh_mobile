import 'package:asm_ride_domain/asm_ride_domain.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passenger_app/booking/booking_draft.dart';

void main() {
  group('BookingDraft', () {
    test('creates a normalized valid draft with an optional note', () {
      final draft = BookingDraft(
        marketCode: '  accra-test  ',
        serviceContext: RideServiceContextCode.hotelOrAccommodation,
        pickupDescription: '  Solar Hotel  ',
        destinationDescription: '  Accra Airport  ',
        passengerCount: 2,
        assistanceNote: '  Step-free access  ',
      );

      expect(draft.identity.value, BookingDraft.localDraftIdentityValue);
      expect(draft.marketCode.value, 'accra-test');
      expect(draft.serviceContext, RideServiceContextCode.hotelOrAccommodation);
      expect(draft.pickupDescription.value, 'Solar Hotel');
      expect(draft.destinationDescription.value, 'Accra Airport');
      expect(draft.passengerCount.value, 2);
      expect(draft.assistanceNote?.value, 'Step-free access');
      expect(draft.lifecycleState, RideLifecycleState.draft);
      expect(draft.rideDraft, isA<RideDraft>());
    });

    test('normalizes an empty optional note to null', () {
      final draft = _validDraft(assistanceNote: '   ');

      expect(draft.assistanceNote, isNull);
    });

    test('rejects a blank market code with a field-safe exception', () {
      expect(
        () => _validDraft(marketCode: '  \n '),
        throwsA(
          isA<BookingDraftValidationException>()
              .having((error) => error.field, 'field', 'marketCode')
              .having(
                (error) => error.message,
                'message',
                'Enter a market code.',
              ),
        ),
      );
    });

    test('rejects blank pickup and destination values', () {
      expect(
        () => _validDraft(pickupDescription: '   '),
        throwsA(
          isA<BookingDraftValidationException>().having(
            (error) => error.field,
            'field',
            'pickupDescription',
          ),
        ),
      );
      expect(
        () => _validDraft(destinationDescription: '\n  '),
        throwsA(
          isA<BookingDraftValidationException>().having(
            (error) => error.field,
            'field',
            'destinationDescription',
          ),
        ),
      );
    });

    test('rejects matching normalized pickup and destination', () {
      expect(
        () => _validDraft(
          pickupDescription: '  Airport Terminal 3 ',
          destinationDescription: 'airport terminal 3',
        ),
        throwsA(isA<BookingDraftValidationException>()),
      );
    });

    test('accepts passenger boundaries and rejects values outside them', () {
      expect(_validDraft(passengerCount: 1).passengerCount.value, 1);
      expect(_validDraft(passengerCount: 6).passengerCount.value, 6);
      expect(
        () => _validDraft(passengerCount: 0),
        throwsA(isA<BookingDraftValidationException>()),
      );
      expect(
        () => _validDraft(passengerCount: 7),
        throwsA(isA<BookingDraftValidationException>()),
      );
    });

    test('copyWith creates a new valid immutable value', () {
      final original = _validDraft(assistanceNote: 'Wheelchair space');
      final updated = original.copyWith(
        destinationDescription: 'Conference Centre',
        passengerCount: 4,
        clearAssistanceNote: true,
      );

      expect(original.destinationDescription.value, 'Airport');
      expect(original.marketCode.value, 'accra-test');
      expect(original.passengerCount.value, 1);
      expect(original.assistanceNote?.value, 'Wheelchair space');
      expect(updated.destinationDescription.value, 'Conference Centre');
      expect(updated.marketCode.value, 'accra-test');
      expect(updated.passengerCount.value, 4);
      expect(updated.assistanceNote, isNull);
      expect(updated.identity.value, original.identity.value);
    });

    test('copyWith trims and validates an explicit market replacement', () {
      final original = _validDraft();
      final updated = original.copyWith(marketCode: '  test-market  ');

      expect(updated.marketCode.value, 'test-market');
      expect(original.marketCode.value, 'accra-test');
      expect(
        () => original.copyWith(marketCode: '   '),
        throwsA(
          isA<BookingDraftValidationException>().having(
            (error) => error.field,
            'field',
            'marketCode',
          ),
        ),
      );
    });

    test('validates CC4B field length limits', () {
      expect(
        _validDraft(
          pickupDescription: List.filled(161, 'A').join(),
        ).pickupDescription.value.length,
        161,
      );
      expect(
        _validDraft(
          destinationDescription: List.filled(161, 'A').join(),
        ).destinationDescription.value.length,
        161,
      );
      expect(
        _validDraft(
          assistanceNote: List.filled(241, 'A').join(),
        ).assistanceNote?.value.length,
        241,
      );
      expect(
        _validDraft(
          pickupDescription: List.filled(240, 'A').join(),
        ).pickupDescription.value.length,
        240,
      );
      expect(
        _validDraft(
          destinationDescription: List.filled(240, 'A').join(),
        ).destinationDescription.value.length,
        240,
      );
      expect(
        _validDraft(
          assistanceNote: List.filled(1000, 'A').join(),
        ).assistanceNote?.value.length,
        1000,
      );
      expect(
        () => _validDraft(pickupDescription: List.filled(241, 'A').join()),
        throwsA(
          isA<BookingDraftValidationException>()
              .having((error) => error.field, 'field', 'pickupDescription')
              .having(
                (error) => error.message,
                'message',
                'Pickup location is too long.',
              ),
        ),
      );
      expect(
        () => _validDraft(destinationDescription: List.filled(241, 'A').join()),
        throwsA(
          isA<BookingDraftValidationException>()
              .having((error) => error.field, 'field', 'destinationDescription')
              .having(
                (error) => error.message,
                'message',
                'Destination is too long.',
              ),
        ),
      );
      expect(
        () => _validDraft(assistanceNote: List.filled(1001, 'A').join()),
        throwsA(
          isA<BookingDraftValidationException>()
              .having((error) => error.field, 'field', 'assistanceNote')
              .having(
                (error) => error.message,
                'message',
                'Special request is too long.',
              ),
        ),
      );
    });
  });
}

BookingDraft _validDraft({
  String marketCode = 'accra-test',
  String pickupDescription = 'Solar Hotel',
  String destinationDescription = 'Airport',
  int passengerCount = 1,
  String? assistanceNote,
}) {
  return BookingDraft(
    marketCode: marketCode,
    serviceContext: RideServiceContextCode.airportConnection,
    pickupDescription: pickupDescription,
    destinationDescription: destinationDescription,
    passengerCount: passengerCount,
    assistanceNote: assistanceNote,
  );
}
