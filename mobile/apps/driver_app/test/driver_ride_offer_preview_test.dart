import 'package:asm_ride_domain/asm_ride_domain.dart';
import 'package:driver_app/ride_offer/driver_ride_offer_preview.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DriverRideOfferPreview pending({
    String marketCode = 'gh-accra',
    RideServiceContextCode serviceContext =
        RideServiceContextCode.airportConnection,
    String pickup = 'Solar Hotel',
    String destination = 'Accra Airport',
    int passengers = 2,
    String? assistanceNote,
  }) {
    return DriverRideOfferPreview(
      marketCode: marketCode,
      serviceContext: serviceContext,
      pickupDescription: pickup,
      destinationDescription: destination,
      passengerCount: passengers,
      assistanceNote: assistanceNote,
    );
  }

  test('valid input maps into shared ride-domain values', () {
    final preview = pending(
      marketCode: '  gh-accra  ',
      pickup: '  Solar Hotel ',
      destination: ' Accra Airport  ',
      assistanceNote: '  Meet at reception  ',
    );

    expect(preview.rideOfferPreview, isA<RideOfferPreview>());
    expect(
      preview.identity.value,
      DriverRideOfferPreview.localPreviewIdentityValue,
    );
    expect(preview.marketCode.value, 'gh-accra');
    expect(preview.serviceContext, RideServiceContextCode.airportConnection);
    expect(preview.pickupDescription.value, 'Solar Hotel');
    expect(preview.destinationDescription.value, 'Accra Airport');
    expect(preview.passengerCount.value, 2);
    expect(preview.assistanceNote!.value, 'Meet at reception');
  });

  test('new local previews begin pending and lifecycle remains offered', () {
    final preview = pending();

    expect(preview.status, DriverRideOfferPreviewStatus.pending);
    expect(preview.lifecycleState, RideLifecycleState.offered);
    expect(preview.rideOfferPreview.lifecycleState, RideLifecycleState.offered);
  });

  test(
    'blank market and location values are rejected by shared validation',
    () {
      expect(
        () => pending(marketCode: '  '),
        throwsA(isA<DriverRideOfferPreviewValidationException>()),
      );
      expect(
        () => pending(pickup: '\t'),
        throwsA(isA<DriverRideOfferPreviewValidationException>()),
      );
      expect(
        () => pending(destination: '\n'),
        throwsA(isA<DriverRideOfferPreviewValidationException>()),
      );
    },
  );

  test('matching locations are rejected after normalization', () {
    expect(
      () => pending(pickup: ' Solar Hotel ', destination: 'solar hotel'),
      throwsA(
        isA<DriverRideOfferPreviewValidationException>()
            .having((error) => error.field, 'field', RideValidationField.route)
            .having(
              (error) => error.code,
              'code',
              RideValidationCode.matchingLocations,
            ),
      ),
    );
  });

  test('passenger boundaries are accepted and outside values rejected', () {
    expect(pending(passengers: 1).passengerCount.value, 1);
    expect(pending(passengers: 6).passengerCount.value, 6);
    expect(
      () => pending(passengers: 0),
      throwsA(isA<DriverRideOfferPreviewValidationException>()),
    );
    expect(
      () => pending(passengers: 7),
      throwsA(isA<DriverRideOfferPreviewValidationException>()),
    );
  });

  test('assistance note remains optional and capped by shared validation', () {
    expect(pending(assistanceNote: null).assistanceNote, isNull);
    expect(pending(assistanceNote: '   ').assistanceNote, isNull);
    expect(
      pending(
        assistanceNote: List.filled(241, 'A').join(),
      ).assistanceNote?.value.length,
      241,
    );
    expect(
      pending(
        assistanceNote: List.filled(1000, 'A').join(),
      ).assistanceNote?.value.length,
      1000,
    );
    expect(
      () => pending(assistanceNote: List.filled(1001, 'A').join()),
      throwsA(
        isA<DriverRideOfferPreviewValidationException>()
            .having(
              (error) => error.field,
              'field',
              RideValidationField.assistanceNote,
            )
            .having((error) => error.code, 'code', RideValidationCode.tooLong),
      ),
    );
  });

  test('accept and decline only change local preview state immutably', () {
    final original = pending();
    final accepted = original.acceptPreview();
    final declined = original.declinePreview();

    expect(original.status, DriverRideOfferPreviewStatus.pending);
    expect(original.lifecycleState, RideLifecycleState.offered);
    expect(accepted.status, DriverRideOfferPreviewStatus.acceptedPreview);
    expect(declined.status, DriverRideOfferPreviewStatus.declinedPreview);
    expect(accepted.lifecycleState, RideLifecycleState.offered);
    expect(declined.lifecycleState, RideLifecycleState.offered);
    expect(identical(original, accepted), isFalse);
    expect(identical(original, declined), isFalse);
    expect(
      identical(original.rideOfferPreview, accepted.rideOfferPreview),
      isTrue,
    );
    expect(
      identical(original.rideOfferPreview, declined.rideOfferPreview),
      isTrue,
    );
  });

  test('accepted previews reject repeated and conflicting local decisions', () {
    final accepted = pending().acceptPreview();

    expect(
      accepted.acceptPreview,
      throwsA(isA<DriverRideOfferPreviewStateException>()),
    );
    expect(
      accepted.declinePreview,
      throwsA(isA<DriverRideOfferPreviewStateException>()),
    );
  });

  test('declined previews reject repeated and conflicting local decisions', () {
    final declined = pending().declinePreview();

    expect(
      declined.declinePreview,
      throwsA(isA<DriverRideOfferPreviewStateException>()),
    );
    expect(
      declined.acceptPreview,
      throwsA(isA<DriverRideOfferPreviewStateException>()),
    );
  });
}
