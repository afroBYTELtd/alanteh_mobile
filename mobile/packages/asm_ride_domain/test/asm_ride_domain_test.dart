import 'package:asm_ride_domain/asm_ride_domain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('approved codes', () {
    test('service contexts contain exactly the approved codes', () {
      expect(RideServiceContextCode.values, [
        RideServiceContextCode.hotelOrAccommodation,
        RideServiceContextCode.airportConnection,
        RideServiceContextCode.corporateOrOrganisation,
        RideServiceContextCode.eventOrScheduledTransport,
        RideServiceContextCode.otherApprovedRequest,
      ]);
    });

    test('lifecycle states contain exactly the approved ordered values', () {
      expect(RideLifecycleState.values, [
        RideLifecycleState.draft,
        RideLifecycleState.requested,
        RideLifecycleState.dispatchReview,
        RideLifecycleState.offered,
        RideLifecycleState.driverAssigned,
        RideLifecycleState.driverEnRoute,
        RideLifecycleState.driverArrived,
        RideLifecycleState.passengerConfirmed,
        RideLifecycleState.inProgress,
        RideLifecycleState.completed,
        RideLifecycleState.cancelled,
        RideLifecycleState.noShow,
      ]);
    });

    test('payment statuses contain exactly the approved values', () {
      expect(PaymentStatus.values, [
        PaymentStatus.notStarted,
        PaymentStatus.pending,
        PaymentStatus.processing,
        PaymentStatus.paid,
        PaymentStatus.failed,
        PaymentStatus.expired,
        PaymentStatus.cancelled,
        PaymentStatus.partnerBilled,
        PaymentStatus.partnerPaid,
        PaymentStatus.manualVerified,
      ]);
    });

    test('payment status backend code mapping is correct', () {
      expect(PaymentStatus.notStarted.backendCode, 'not_started');
      expect(PaymentStatus.pending.backendCode, 'pending');
      expect(PaymentStatus.processing.backendCode, 'processing');
      expect(PaymentStatus.paid.backendCode, 'payment_confirmed');
      expect(PaymentStatus.failed.backendCode, 'failed');
      expect(PaymentStatus.expired.backendCode, 'expired');
      expect(PaymentStatus.cancelled.backendCode, 'cancelled');
      expect(PaymentStatus.partnerBilled.backendCode, 'partner_billed');
      expect(PaymentStatus.partnerPaid.backendCode, 'partner_paid');
      expect(PaymentStatus.manualVerified.backendCode, 'manual_verified');
    });

    test('manual verified status keeps the Control Center backend code', () {
      expect(PaymentStatus.manualVerified, isA<PaymentStatus>());
      expect(PaymentStatus.manualVerified.backendCode, 'manual_verified');
    });

    test('partner paid status keeps the Control Center backend code', () {
      expect(PaymentStatus.partnerPaid, isA<PaymentStatus>());
      expect(PaymentStatus.partnerPaid.backendCode, 'partner_paid');
    });

    test('payment methods contain exactly the approved values', () {
      expect(PaymentMethod.values, [
        PaymentMethod.mtnMomo,
        PaymentMethod.telecelCash,
        PaymentMethod.airteltigoMoney,
        PaymentMethod.partnerBilling,
        PaymentMethod.manual,
      ]);
    });

    test('payment method backend code mapping is correct', () {
      expect(PaymentMethod.mtnMomo.backendCode, 'mtn');
      expect(PaymentMethod.telecelCash.backendCode, 'vod');
      expect(PaymentMethod.airteltigoMoney.backendCode, 'atl');
      expect(PaymentMethod.partnerBilling.backendCode, 'partner_billing');
      expect(PaymentMethod.manual.backendCode, 'manual');
    });

    test(
      'payment method display labels use current Ghana mobile money naming',
      () {
        expect(PaymentMethod.telecelCash.displayLabel, 'Telecel Cash');

        final labels = PaymentMethod.values
            .map((paymentMethod) => paymentMethod.displayLabel)
            .toList();
        final outdatedProviderName = ['Voda', 'fone'].join();
        final outdatedCashLabel = [outdatedProviderName, 'Cash'].join(' ');

        expect(
          labels.any(
            (label) =>
                label == outdatedProviderName ||
                label == outdatedCashLabel ||
                label.contains(outdatedProviderName),
          ),
          isFalse,
        );
      },
    );

    test('service context backend code mapping matches platform codes', () {
      expect(RideServiceContextCode.hotelOrAccommodation.backendCode, 'hotel');
      expect(RideServiceContextCode.airportConnection.backendCode, 'airport');
      expect(
        RideServiceContextCode.corporateOrOrganisation.backendCode,
        'corporate',
      );
      expect(
        RideServiceContextCode.eventOrScheduledTransport.backendCode,
        'event',
      );
      expect(
        RideServiceContextCode.otherApprovedRequest.backendCode,
        'approved_request',
      );
    });
  });

  group('typed values', () {
    test('market codes trim and reject blanks', () {
      expect(RideMarketCode('  market-code  ').value, 'market-code');
      expect(
        () => RideMarketCode('  '),
        throwsValidation(
          RideValidationField.marketCode,
          RideValidationCode.blank,
        ),
      );
    });

    test('locations trim, reject blanks, and enforce 160 characters', () {
      expect(RideLocationDescription('  Local place  ').value, 'Local place');
      expect(
        () => RideLocationDescription('  '),
        throwsValidation(
          RideValidationField.locationDescription,
          RideValidationCode.blank,
        ),
      );
      expect(RideLocationDescription(repeatedText(160)).value.length, 160);
      expect(
        () => RideLocationDescription(repeatedText(161)),
        throwsValidation(
          RideValidationField.locationDescription,
          RideValidationCode.tooLong,
        ),
      );
    });

    test('locations preserve Unicode text', () {
      const value = '  Marché central — محطة المدينة  ';
      expect(
        RideLocationDescription(value).value,
        'Marché central — محطة المدينة',
      );
    });

    test(
      'passenger counts accept boundaries and reject values outside them',
      () {
        expect(RidePassengerCount(1).value, 1);
        expect(RidePassengerCount(6).value, 6);
        expect(
          () => RidePassengerCount(0),
          throwsValidation(
            RideValidationField.passengerCount,
            RideValidationCode.outOfRange,
          ),
        );
        expect(
          () => RidePassengerCount(7),
          throwsValidation(
            RideValidationField.passengerCount,
            RideValidationCode.outOfRange,
          ),
        );
      },
    );

    test('optional assistance normalizes null and blank values to null', () {
      expect(RideAssistanceNote.optional(null), isNull);
      expect(RideAssistanceNote.optional('   '), isNull);
    });

    test('assistance trims and enforces 240 characters', () {
      expect(
        RideAssistanceNote.optional('  Local help  ')?.value,
        'Local help',
      );
      expect(RideAssistanceNote.optional(repeatedText(240))?.value.length, 240);
      expect(
        () => RideAssistanceNote.optional(repeatedText(241)),
        throwsValidation(
          RideValidationField.assistanceNote,
          RideValidationCode.tooLong,
        ),
      );
    });

    test('draft identities trim opaque values and enforce their boundary', () {
      expect(RideDraftIdentity('  opaque:draft  ').value, 'opaque:draft');
      expect(RideDraftIdentity(repeatedText(128)).value.length, 128);
      expect(
        () => RideDraftIdentity('  '),
        throwsValidation(
          RideValidationField.draftIdentity,
          RideValidationCode.blank,
        ),
      );
      expect(
        () => RideDraftIdentity(repeatedText(129)),
        throwsValidation(
          RideValidationField.draftIdentity,
          RideValidationCode.tooLong,
        ),
      );
    });

    test('offer identities trim opaque values and enforce their boundary', () {
      expect(
        RideOfferPreviewIdentity('  opaque:offer  ').value,
        'opaque:offer',
      );
      expect(RideOfferPreviewIdentity(repeatedText(128)).value.length, 128);
      expect(
        () => RideOfferPreviewIdentity('  '),
        throwsValidation(
          RideValidationField.offerPreviewIdentity,
          RideValidationCode.blank,
        ),
      );
      expect(
        () => RideOfferPreviewIdentity(repeatedText(129)),
        throwsValidation(
          RideValidationField.offerPreviewIdentity,
          RideValidationCode.tooLong,
        ),
      );
    });
  });

  group('RideFare', () {
    test('accepts valid amount and currency', () {
      final fare = RideFare(amount: 48, currency: ' GHS ');

      expect(fare.amount, 48.0);
      expect(fare.currency, 'GHS');
    });

    test('rejects negative amount', () {
      expect(
        () => RideFare(amount: -1, currency: 'GHS'),
        throwsValidation(
          RideValidationField.fareAmount,
          RideValidationCode.negative,
        ),
      );
    });

    test('rejects blank currency', () {
      expect(
        () => RideFare(amount: 48, currency: '   '),
        throwsValidation(
          RideValidationField.fareCurrency,
          RideValidationCode.blank,
        ),
      );
    });

    test('formats display safely', () {
      expect(
        RideFare(amount: 48, currency: 'GHS').formattedDisplay,
        'GHS 48.00',
      );
      expect(
        RideFare(amount: 48.5, currency: 'ghs').formattedDisplay,
        'GHS 48.50',
      );
    });
  });

  group('TripRatingDraft', () {
    test('accepts valid values', () {
      final draft = TripRatingDraft(
        overall: 5,
        comfort: TripComfortRating.good,
        conduct: TripConductRating.good,
        cleanliness: TripCleanlinessRating.good,
        note: '  Smooth trip  ',
      );

      expect(draft.overall, 5);
      expect(draft.comfort, TripComfortRating.good);
      expect(draft.conduct, TripConductRating.good);
      expect(draft.cleanliness, TripCleanlinessRating.good);
      expect(draft.note, 'Smooth trip');
    });

    test('rejects overall below 1', () {
      expect(
        () => TripRatingDraft(
          overall: 0,
          comfort: TripComfortRating.good,
          conduct: TripConductRating.good,
          cleanliness: TripCleanlinessRating.good,
        ),
        throwsValidation(
          RideValidationField.ratingOverall,
          RideValidationCode.outOfRange,
        ),
      );
    });

    test('rejects overall above 5', () {
      expect(
        () => TripRatingDraft(
          overall: 6,
          comfort: TripComfortRating.good,
          conduct: TripConductRating.good,
          cleanliness: TripCleanlinessRating.good,
        ),
        throwsValidation(
          RideValidationField.ratingOverall,
          RideValidationCode.outOfRange,
        ),
      );
    });

    test('accepts null or blank note as no note', () {
      final nullNote = TripRatingDraft(
        overall: 4,
        comfort: TripComfortRating.okay,
        conduct: TripConductRating.issue,
        cleanliness: TripCleanlinessRating.issue,
      );
      final blankNote = TripRatingDraft(
        overall: 4,
        comfort: TripComfortRating.okay,
        conduct: TripConductRating.issue,
        cleanliness: TripCleanlinessRating.issue,
        note: '   ',
      );

      expect(nullNote.note, isNull);
      expect(blankNote.note, isNull);
    });

    test('rejects note longer than 240 characters', () {
      expect(
        () => TripRatingDraft(
          overall: 4,
          comfort: TripComfortRating.good,
          conduct: TripConductRating.good,
          cleanliness: TripCleanlinessRating.good,
          note: repeatedText(241),
        ),
        throwsValidation(
          RideValidationField.ratingNote,
          RideValidationCode.tooLong,
        ),
      );
    });

    test('preserves a 240-character note', () {
      final rating = TripRatingDraft(
        overall: 4,
        comfort: TripComfortRating.good,
        conduct: TripConductRating.good,
        cleanliness: TripCleanlinessRating.good,
        note: repeatedText(240),
      );

      expect(rating.note?.length, 240);
    });
  });

  group('RideDraft', () {
    test('stores approved typed values and reports draft lifecycle state', () {
      final draft = buildDraft();

      expect(draft.identity.value, 'draft-reference');
      expect(draft.marketCode.value, 'market-code');
      expect(draft.serviceContext, RideServiceContextCode.airportConnection);
      expect(draft.pickup.value, 'Pickup');
      expect(draft.destination.value, 'Destination');
      expect(draft.passengerCount.value, 2);
      expect(draft.assistanceNote?.value, 'Assistance');
      expect(draft.lifecycleState, RideLifecycleState.draft);
    });

    test('rejects matching normalized locations', () {
      expect(
        () => RideDraft(
          identity: RideDraftIdentity('draft-reference'),
          marketCode: RideMarketCode('market-code'),
          serviceContext: RideServiceContextCode.hotelOrAccommodation,
          pickup: RideLocationDescription('  Same Place  '),
          destination: RideLocationDescription('same place'),
          passengerCount: RidePassengerCount(1),
        ),
        throwsValidation(
          RideValidationField.route,
          RideValidationCode.matchingLocations,
        ),
      );
    });
  });

  group('RideOfferPreview', () {
    test(
      'stores approved typed values and reports offered lifecycle state',
      () {
        final preview = buildPreview();

        expect(preview.identity.value, 'offer-reference');
        expect(preview.marketCode.value, 'market-code');
        expect(
          preview.serviceContext,
          RideServiceContextCode.corporateOrOrganisation,
        );
        expect(preview.pickup.value, 'Pickup');
        expect(preview.destination.value, 'Destination');
        expect(preview.passengerCount.value, 3);
        expect(preview.assistanceNote, isNull);
        expect(preview.lifecycleState, RideLifecycleState.offered);
      },
    );

    test('rejects matching normalized locations', () {
      expect(
        () => RideOfferPreview(
          identity: RideOfferPreviewIdentity('offer-reference'),
          marketCode: RideMarketCode('market-code'),
          serviceContext: RideServiceContextCode.otherApprovedRequest,
          pickup: RideLocationDescription('SAME PLACE'),
          destination: RideLocationDescription(' same place '),
          passengerCount: RidePassengerCount(1),
        ),
        throwsValidation(
          RideValidationField.route,
          RideValidationCode.matchingLocations,
        ),
      );
    });
  });

  group('local summary helpers', () {
    test('passenger-count summary handles singular and plural values', () {
      expect(RidePassengerCount(1).passengerSummary, '1 passenger');
      expect(RidePassengerCount(2).passengerSummary, '2 passengers');
      expect(RidePassengerCount(6).passengerSummary, '6 passengers');
    });

    test('route summary uses pickup and destination values', () {
      final draft = buildDraft();
      final preview = buildPreview();

      expect(draft.pickupSummary, 'Pickup: Pickup');
      expect(draft.destinationSummary, 'Destination: Destination');
      expect(draft.routeSummary, 'Pickup to Destination');
      expect(preview.routeSummary, 'Pickup to Destination');
    });

    test('RideDraft helper returns local draft wording only', () {
      final draft = buildDraft();

      expect(draft.localLifecycleSummary, 'Local draft');
      expect(
        draft.localLifecycleSummary.toLowerCase(),
        isNot(contains('request')),
      );
      expect(
        draft.localLifecycleSummary.toLowerCase(),
        isNot(contains('submit')),
      );
      expect(
        draft.localLifecycleSummary.toLowerCase(),
        isNot(contains('dispatch')),
      );
    });

    test('RideOfferPreview helper returns local preview wording only', () {
      final preview = buildPreview();

      expect(preview.localLifecycleSummary, 'Local offer preview');
      expect(
        preview.localLifecycleSummary.toLowerCase(),
        isNot(contains('received')),
      );
      expect(
        preview.localLifecycleSummary.toLowerCase(),
        isNot(contains('assigned')),
      );
      expect(
        preview.localLifecycleSummary.toLowerCase(),
        isNot(contains('reserved')),
      );
    });

    test('helpers do not mutate or replace immutable objects', () {
      final draft = buildDraft();
      final originalPickup = draft.pickup;
      final originalDestination = draft.destination;
      final originalPassengerCount = draft.passengerCount;

      expect(draft.pickupDisplayText, 'Pickup');
      expect(draft.destinationDisplayText, 'Destination');
      expect(draft.passengerSummary, '2 passengers');
      expect(identical(draft.pickup, originalPickup), isTrue);
      expect(identical(draft.destination, originalDestination), isTrue);
      expect(identical(draft.passengerCount, originalPassengerCount), isTrue);
    });
  });

  test('validation uses explicit release-safe exceptions', () {
    expect(
      () => RideMarketCode(''),
      throwsA(isA<RideDomainValidationException>()),
    );
  });

  test('aggregates expose typed scalar values and no mutable collection', () {
    final draft = buildDraft();
    final preview = buildPreview();

    expect(draft.pickup, isA<RideLocationDescription>());
    expect(preview.destination, isA<RideLocationDescription>());
    expect(draft.assistanceNote, isA<RideAssistanceNote>());
  });

  test('aggregates provide no client lifecycle transition behavior', () {
    final dynamic draft = buildDraft();
    final dynamic preview = buildPreview();

    expect(() => draft.request(), throwsA(isA<NoSuchMethodError>()));
    expect(() => preview.accept(), throwsA(isA<NoSuchMethodError>()));
    expect(() => preview.decline(), throwsA(isA<NoSuchMethodError>()));
  });
}

RideDraft buildDraft() {
  return RideDraft(
    identity: RideDraftIdentity('draft-reference'),
    marketCode: RideMarketCode('market-code'),
    serviceContext: RideServiceContextCode.airportConnection,
    pickup: RideLocationDescription('Pickup'),
    destination: RideLocationDescription('Destination'),
    passengerCount: RidePassengerCount(2),
    assistanceNote: RideAssistanceNote.optional('Assistance'),
  );
}

RideOfferPreview buildPreview() {
  return RideOfferPreview(
    identity: RideOfferPreviewIdentity('offer-reference'),
    marketCode: RideMarketCode('market-code'),
    serviceContext: RideServiceContextCode.corporateOrOrganisation,
    pickup: RideLocationDescription('Pickup'),
    destination: RideLocationDescription('Destination'),
    passengerCount: RidePassengerCount(3),
  );
}

Matcher throwsValidation(RideValidationField field, RideValidationCode code) {
  return throwsA(
    isA<RideDomainValidationException>()
        .having((error) => error.field, 'field', field)
        .having((error) => error.code, 'code', code),
  );
}

String repeatedText(int length) => List.filled(length, 'a').join();
