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
    double? pickupLatitude,
    double? pickupLongitude,
    required int passengerCount,
    String? assistanceNote,
    String? passengerNote,
    DateTime? requestedPickupTime,
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
    final normalizedPassengerNote = passengerNote?.trim();
    if (normalizedPassengerNote != null &&
        normalizedPassengerNote.length > 160) {
      throw const BookingDraftValidationException(
        field: 'passengerNote',
        message: 'Message to driver is too long.',
      );
    }

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
      normalizedPassengerNote == null || normalizedPassengerNote.isEmpty
          ? null
          : normalizedPassengerNote,
      pickupLatitude,
      pickupLongitude,
      requestedPickupTime?.toUtc(),
    );
  }

  const BookingDraft._(
    this.rideDraft,
    this.passengerNote,
    this.pickupLatitude,
    this.pickupLongitude,
    this.requestedPickupTime,
  );

  final RideDraft rideDraft;
  final String? passengerNote;
  final double? pickupLatitude;
  final double? pickupLongitude;

  /// Pickup time for a ride booked for later (UTC); null books a ride now.
  final DateTime? requestedPickupTime;

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
    double? pickupLatitude,
    double? pickupLongitude,
    int? passengerCount,
    String? assistanceNote,
    bool clearAssistanceNote = false,
    String? passengerNote,
    bool clearPassengerNote = false,
    DateTime? requestedPickupTime,
    bool clearRequestedPickupTime = false,
  }) {
    return BookingDraft(
      identity: identity ?? this.identity,
      marketCode: marketCode ?? this.marketCode.value,
      serviceContext: serviceContext ?? this.serviceContext,
      pickupDescription: pickupDescription ?? this.pickupDescription.value,
      destinationDescription:
          destinationDescription ?? this.destinationDescription.value,
      pickupLatitude: pickupLatitude ?? this.pickupLatitude,
      pickupLongitude: pickupLongitude ?? this.pickupLongitude,
      passengerCount: passengerCount ?? this.passengerCount.value,
      assistanceNote: clearAssistanceNote
          ? null
          : assistanceNote ?? this.assistanceNote?.value,
      passengerNote: clearPassengerNote
          ? null
          : passengerNote ?? this.passengerNote,
      requestedPickupTime: clearRequestedPickupTime
          ? null
          : requestedPickupTime ?? this.requestedPickupTime,
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
          ? 'Pickup location is too long.'
          : 'Enter pickup location.',
    'destinationDescription' =>
      error.code == RideValidationCode.tooLong
          ? 'Destination is too long.'
          : 'Enter destination.',
    'passengerCount' => 'Passenger count must be between 1 and 6.',
    'assistanceNote' => 'Special request is too long.',
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
