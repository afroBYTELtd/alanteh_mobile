import 'package:asm_ride_domain/asm_ride_domain.dart';

extension PassengerRideServiceContextLabel on RideServiceContextCode {
  String get label {
    return switch (this) {
      RideServiceContextCode.hotelOrAccommodation => 'Hotel or accommodation',
      RideServiceContextCode.airportConnection => 'Airport connection',
      RideServiceContextCode.corporateOrOrganisation =>
        'Corporate or organisation',
      RideServiceContextCode.eventOrScheduledTransport =>
        'Event or scheduled transport',
      RideServiceContextCode.otherApprovedRequest => 'Other approved request',
    };
  }
}

class BookingDraft {
  static const localDraftIdentityValue = 'local-passenger-draft';

  factory BookingDraft({
    RideDraftIdentity? identity,
    required String marketCode,
    required RideServiceContextCode serviceContext,
    required String pickupDescription,
    required String destinationDescription,
    required int passengerCount,
    String? assistanceNote,
  }) {
    final RideDraftIdentity draftIdentity =
        identity ??
        _mapRideValidation(
          () => RideDraftIdentity(localDraftIdentityValue),
          field: 'draftIdentity',
        );
    final rideMarketCode = _mapRideValidation(
      () => RideMarketCode(marketCode),
      field: 'marketCode',
    );
    final pickup = _mapRideValidation(
      () => RideLocationDescription(pickupDescription),
      field: 'pickupDescription',
    );
    final destination = _mapRideValidation(
      () => RideLocationDescription(destinationDescription),
      field: 'destinationDescription',
    );
    final count = _mapRideValidation(
      () => RidePassengerCount(passengerCount),
      field: 'passengerCount',
    );
    final note = _mapRideValidation(
      () => RideAssistanceNote.optional(assistanceNote),
      field: 'assistanceNote',
    );

    return BookingDraft._(
      _mapRideValidation(
        () => RideDraft(
          identity: draftIdentity,
          marketCode: rideMarketCode,
          serviceContext: serviceContext,
          pickup: pickup,
          destination: destination,
          passengerCount: count,
          assistanceNote: note,
        ),
        field: 'destinationDescription',
      ),
    );
  }

  const BookingDraft._(this.rideDraft);

  final RideDraft rideDraft;

  RideDraftIdentity get identity => rideDraft.identity;
  RideLifecycleState get lifecycleState => rideDraft.lifecycleState;
  RideMarketCode get marketCode => rideDraft.marketCode;
  RideServiceContextCode get serviceContext => rideDraft.serviceContext;
  RideLocationDescription get pickupDescription => rideDraft.pickup;
  RideLocationDescription get destinationDescription => rideDraft.destination;
  RidePassengerCount get passengerCount => rideDraft.passengerCount;
  RideAssistanceNote? get assistanceNote => rideDraft.assistanceNote;

  BookingDraft copyWith({
    RideDraftIdentity? identity,
    String? marketCode,
    RideServiceContextCode? serviceContext,
    String? pickupDescription,
    String? destinationDescription,
    int? passengerCount,
    String? assistanceNote,
    bool clearAssistanceNote = false,
  }) {
    return BookingDraft(
      identity: identity ?? this.identity,
      marketCode: marketCode ?? this.marketCode.value,
      serviceContext: serviceContext ?? this.serviceContext,
      pickupDescription: pickupDescription ?? this.pickupDescription.value,
      destinationDescription:
          destinationDescription ?? this.destinationDescription.value,
      passengerCount: passengerCount ?? this.passengerCount.value,
      assistanceNote: clearAssistanceNote
          ? null
          : assistanceNote ?? this.assistanceNote?.value,
    );
  }
}

T _mapRideValidation<T>(T Function() create, {required String field}) {
  try {
    return create();
  } on RideDomainValidationException catch (error) {
    throw BookingDraftValidationException(
      field: field,
      message: _messageForRideValidation(error, field),
    );
  }
}

String _messageForRideValidation(
  RideDomainValidationException error,
  String field,
) {
  if (error.code == RideValidationCode.matchingLocations) {
    return 'Destination must be different from pickup.';
  }

  return switch (field) {
    'marketCode' => 'Enter a market code.',
    'pickupDescription' =>
      error.code == RideValidationCode.tooLong
          ? 'Pickup description must be 160 characters or fewer.'
          : 'Enter a pickup description.',
    'destinationDescription' =>
      error.code == RideValidationCode.tooLong
          ? 'Destination description must be 160 characters or fewer.'
          : 'Enter a destination description.',
    'passengerCount' => 'Passenger count must be between 1 and 6.',
    'assistanceNote' => 'Assistance note must be 240 characters or fewer.',
    'draftIdentity' => 'Enter a draft identity.',
    _ => 'Enter a valid ride detail.',
  };
}

class BookingDraftValidationException implements Exception {
  const BookingDraftValidationException({
    required this.field,
    required this.message,
  });

  final String field;
  final String message;

  @override
  String toString() => message;
}
