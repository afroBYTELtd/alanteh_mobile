import 'package:asm_ride_domain/asm_ride_domain.dart';

extension DriverRideServiceContextLabel on RideServiceContextCode {
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

enum DriverRideOfferPreviewStatus { pending, acceptedPreview, declinedPreview }

final class DriverRideOfferPreviewValidationException implements Exception {
  const DriverRideOfferPreviewValidationException({
    required this.field,
    required this.code,
  });

  final RideValidationField field;
  final RideValidationCode code;

  @override
  String toString() =>
      'DriverRideOfferPreviewValidationException(field: ${field.name}, code: ${code.name})';
}

final class DriverRideOfferPreviewStateException implements Exception {
  const DriverRideOfferPreviewStateException(this.message);

  final String message;

  @override
  String toString() => 'DriverRideOfferPreviewStateException: $message';
}

final class DriverRideOfferPreview {
  static const localPreviewIdentityValue = 'local-driver-offer-preview';

  factory DriverRideOfferPreview({
    RideOfferPreviewIdentity? identity,
    required String marketCode,
    required RideServiceContextCode serviceContext,
    required String pickupDescription,
    required String destinationDescription,
    required int passengerCount,
    String? assistanceNote,
  }) {
    final RideOfferPreviewIdentity previewIdentity =
        identity ??
        _mapRideValidation(() {
          return RideOfferPreviewIdentity(localPreviewIdentityValue);
        });
    final rideMarketCode = _mapRideValidation(() {
      return RideMarketCode(marketCode);
    });
    final pickup = _mapRideValidation(() {
      return RideLocationDescription(pickupDescription);
    });
    final destination = _mapRideValidation(() {
      return RideLocationDescription(destinationDescription);
    });
    final count = _mapRideValidation(() {
      return RidePassengerCount(passengerCount);
    });
    final note = _mapRideValidation(() {
      return RideAssistanceNote.optional(assistanceNote);
    });

    return DriverRideOfferPreview._(
      _mapRideValidation(() {
        return RideOfferPreview(
          identity: previewIdentity,
          marketCode: rideMarketCode,
          serviceContext: serviceContext,
          pickup: pickup,
          destination: destination,
          passengerCount: count,
          assistanceNote: note,
        );
      }),
      DriverRideOfferPreviewStatus.pending,
    );
  }

  const DriverRideOfferPreview._(this.rideOfferPreview, this.status);

  final RideOfferPreview rideOfferPreview;
  final DriverRideOfferPreviewStatus status;

  RideOfferPreviewIdentity get identity => rideOfferPreview.identity;
  RideLifecycleState get lifecycleState => rideOfferPreview.lifecycleState;
  RideMarketCode get marketCode => rideOfferPreview.marketCode;
  RideServiceContextCode get serviceContext => rideOfferPreview.serviceContext;
  RideLocationDescription get pickupDescription => rideOfferPreview.pickup;
  RideLocationDescription get destinationDescription =>
      rideOfferPreview.destination;
  RidePassengerCount get passengerCount => rideOfferPreview.passengerCount;
  RideAssistanceNote? get assistanceNote => rideOfferPreview.assistanceNote;

  DriverRideOfferPreview acceptPreview() =>
      _withLocalDecision(DriverRideOfferPreviewStatus.acceptedPreview);

  DriverRideOfferPreview declinePreview() =>
      _withLocalDecision(DriverRideOfferPreviewStatus.declinedPreview);

  DriverRideOfferPreview _withLocalDecision(
    DriverRideOfferPreviewStatus nextStatus,
  ) {
    if (status != DriverRideOfferPreviewStatus.pending) {
      throw DriverRideOfferPreviewStateException(
        'A ${status.name} local preview cannot be decided again.',
      );
    }

    return DriverRideOfferPreview._(rideOfferPreview, nextStatus);
  }
}

T _mapRideValidation<T>(T Function() create) {
  try {
    return create();
  } on RideDomainValidationException catch (error) {
    throw DriverRideOfferPreviewValidationException(
      field: error.field,
      code: error.code,
    );
  }
}
