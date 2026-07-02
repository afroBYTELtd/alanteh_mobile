enum RideServiceContextCode {
  hotelOrAccommodation,
  airportConnection,
  corporateOrOrganisation,
  eventOrScheduledTransport,
  otherApprovedRequest,
}

extension RideServiceContextCodeBackendCode on RideServiceContextCode {
  String get backendCode {
    return switch (this) {
      RideServiceContextCode.hotelOrAccommodation => 'hotel',
      RideServiceContextCode.airportConnection => 'airport',
      RideServiceContextCode.corporateOrOrganisation => 'corporate',
      RideServiceContextCode.eventOrScheduledTransport => 'event',
      RideServiceContextCode.otherApprovedRequest => 'approved_request',
    };
  }
}

// These states describe backend-owned lifecycle data. A future backend remains
// authoritative; this package intentionally defines no lifecycle transitions.
enum RideLifecycleState {
  draft,
  requested,
  dispatchReview,
  offered,
  driverAssigned,
  driverEnRoute,
  driverArrived,
  passengerConfirmed,
  inProgress,
  completed,
  cancelled,
  noShow,
}

enum RideValidationCode {
  blank,
  tooLong,
  outOfRange,
  matchingLocations,
  negative,
}

enum RideValidationField {
  marketCode,
  locationDescription,
  passengerCount,
  assistanceNote,
  draftIdentity,
  offerPreviewIdentity,
  route,
  fareAmount,
  fareCurrency,
  ratingOverall,
  ratingNote,
}

final class RideDomainValidationException implements Exception {
  const RideDomainValidationException({
    required this.code,
    required this.field,
  });

  final RideValidationCode code;
  final RideValidationField field;

  @override
  String toString() =>
      'RideDomainValidationException(field: ${field.name}, code: ${code.name})';
}

enum PaymentStatus {
  notStarted,
  pending,
  processing,
  paid,
  failed,
  expired,
  cancelled,
  partnerBilled,
  manualVerified,
}

extension PaymentStatusBackendCode on PaymentStatus {
  String get backendCode {
    return switch (this) {
      PaymentStatus.notStarted => 'not_started',
      PaymentStatus.pending => 'pending',
      PaymentStatus.processing => 'processing',
      PaymentStatus.paid => 'paid',
      PaymentStatus.failed => 'failed',
      PaymentStatus.expired => 'expired',
      PaymentStatus.cancelled => 'cancelled',
      PaymentStatus.partnerBilled => 'partner_billed',
      PaymentStatus.manualVerified => 'manual_verified',
    };
  }
}

enum PaymentMethod {
  mtnMomo,
  telecelCash,
  airteltigoMoney,
  partnerBilling,
  manual,
}

extension PaymentMethodBackendCode on PaymentMethod {
  String get backendCode {
    return switch (this) {
      PaymentMethod.mtnMomo => 'mtn_momo',
      PaymentMethod.telecelCash => 'vod',
      PaymentMethod.airteltigoMoney => 'airteltigo_money',
      PaymentMethod.partnerBilling => 'partner_billing',
      PaymentMethod.manual => 'manual',
    };
  }
}

extension PaymentMethodDisplayLabel on PaymentMethod {
  String get displayLabel {
    return switch (this) {
      PaymentMethod.mtnMomo => 'MTN MoMo',
      PaymentMethod.telecelCash => 'Telecel Cash',
      PaymentMethod.airteltigoMoney => 'AirtelTigo Money',
      PaymentMethod.partnerBilling => 'Partner Billing',
      PaymentMethod.manual => 'Manual Review',
    };
  }
}

enum TripComfortRating { good, okay, poor }

enum TripConductRating { good, issue }

enum TripCleanlinessRating { good, issue }

final class RideFare {
  factory RideFare({required num amount, required String currency}) {
    if (amount < 0) {
      throw const RideDomainValidationException(
        code: RideValidationCode.negative,
        field: RideValidationField.fareAmount,
      );
    }
    final normalizedCurrency = currency.trim().toUpperCase();
    if (normalizedCurrency.isEmpty) {
      throw const RideDomainValidationException(
        code: RideValidationCode.blank,
        field: RideValidationField.fareCurrency,
      );
    }
    return RideFare._(amount: amount.toDouble(), currency: normalizedCurrency);
  }

  const RideFare._({required this.amount, required this.currency});

  final double amount;
  final String currency;

  String get formattedDisplay => '$currency ${amount.toStringAsFixed(2)}';
}

final class TripRatingDraft {
  factory TripRatingDraft({
    required int overall,
    required TripComfortRating comfort,
    required TripConductRating conduct,
    required TripCleanlinessRating cleanliness,
    String? note,
  }) {
    if (overall < 1 || overall > 5) {
      throw const RideDomainValidationException(
        code: RideValidationCode.outOfRange,
        field: RideValidationField.ratingOverall,
      );
    }
    final normalizedNote = note?.trim();
    if (normalizedNote != null && normalizedNote.length > 240) {
      throw const RideDomainValidationException(
        code: RideValidationCode.tooLong,
        field: RideValidationField.ratingNote,
      );
    }
    return TripRatingDraft._(
      overall: overall,
      comfort: comfort,
      conduct: conduct,
      cleanliness: cleanliness,
      note: normalizedNote == null || normalizedNote.isEmpty
          ? null
          : normalizedNote,
    );
  }

  const TripRatingDraft._({
    required this.overall,
    required this.comfort,
    required this.conduct,
    required this.cleanliness,
    required this.note,
  });

  final int overall;
  final TripComfortRating comfort;
  final TripConductRating conduct;
  final TripCleanlinessRating cleanliness;
  final String? note;
}

final class RideMarketCode {
  factory RideMarketCode(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw const RideDomainValidationException(
        code: RideValidationCode.blank,
        field: RideValidationField.marketCode,
      );
    }
    return RideMarketCode._(normalized);
  }

  const RideMarketCode._(this.value);

  final String value;
}

final class RideLocationDescription {
  factory RideLocationDescription(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw const RideDomainValidationException(
        code: RideValidationCode.blank,
        field: RideValidationField.locationDescription,
      );
    }
    if (normalized.length > 160) {
      throw const RideDomainValidationException(
        code: RideValidationCode.tooLong,
        field: RideValidationField.locationDescription,
      );
    }
    return RideLocationDescription._(normalized);
  }

  const RideLocationDescription._(this.value);

  final String value;
}

final class RidePassengerCount {
  factory RidePassengerCount(int value) {
    if (value < 1 || value > 6) {
      throw const RideDomainValidationException(
        code: RideValidationCode.outOfRange,
        field: RideValidationField.passengerCount,
      );
    }
    return RidePassengerCount._(value);
  }

  const RidePassengerCount._(this.value);

  final int value;
}

final class RideAssistanceNote {
  static RideAssistanceNote? optional(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    if (normalized.length > 240) {
      throw const RideDomainValidationException(
        code: RideValidationCode.tooLong,
        field: RideValidationField.assistanceNote,
      );
    }
    return RideAssistanceNote._(normalized);
  }

  const RideAssistanceNote._(this.value);

  final String value;
}

final class RideDraftIdentity {
  factory RideDraftIdentity(String value) {
    final normalized = _normalizeIdentity(
      value,
      RideValidationField.draftIdentity,
    );
    return RideDraftIdentity._(normalized);
  }

  const RideDraftIdentity._(this.value);

  final String value;
}

final class RideOfferPreviewIdentity {
  factory RideOfferPreviewIdentity(String value) {
    final normalized = _normalizeIdentity(
      value,
      RideValidationField.offerPreviewIdentity,
    );
    return RideOfferPreviewIdentity._(normalized);
  }

  const RideOfferPreviewIdentity._(this.value);

  final String value;
}

String _normalizeIdentity(String value, RideValidationField field) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw RideDomainValidationException(
      code: RideValidationCode.blank,
      field: field,
    );
  }
  if (normalized.length > 128) {
    throw RideDomainValidationException(
      code: RideValidationCode.tooLong,
      field: field,
    );
  }
  return normalized;
}

final class RideDraft {
  RideDraft({
    required this.identity,
    required this.marketCode,
    required this.serviceContext,
    required this.pickup,
    required this.destination,
    required this.passengerCount,
    this.assistanceNote,
  }) {
    _validateDifferentLocations(pickup, destination);
  }

  final RideDraftIdentity identity;
  final RideMarketCode marketCode;
  final RideServiceContextCode serviceContext;
  final RideLocationDescription pickup;
  final RideLocationDescription destination;
  final RidePassengerCount passengerCount;
  final RideAssistanceNote? assistanceNote;

  RideLifecycleState get lifecycleState => RideLifecycleState.draft;
}

final class RideOfferPreview {
  RideOfferPreview({
    required this.identity,
    required this.marketCode,
    required this.serviceContext,
    required this.pickup,
    required this.destination,
    required this.passengerCount,
    this.assistanceNote,
  }) {
    _validateDifferentLocations(pickup, destination);
  }

  final RideOfferPreviewIdentity identity;
  final RideMarketCode marketCode;
  final RideServiceContextCode serviceContext;
  final RideLocationDescription pickup;
  final RideLocationDescription destination;
  final RidePassengerCount passengerCount;
  final RideAssistanceNote? assistanceNote;

  RideLifecycleState get lifecycleState => RideLifecycleState.offered;
}

extension RideLocationDescriptionSummary on RideLocationDescription {
  String get displayText => value;
  String get pickupSummary => 'Pickup: $value';
  String get destinationSummary => 'Destination: $value';
}

extension RidePassengerCountSummary on RidePassengerCount {
  String get passengerSummary {
    return value == 1 ? '1 passenger' : '$value passengers';
  }
}

extension RideDraftLocalSummary on RideDraft {
  String get pickupDisplayText => pickup.displayText;
  String get destinationDisplayText => destination.displayText;
  String get pickupSummary => pickup.pickupSummary;
  String get destinationSummary => destination.destinationSummary;
  String get passengerSummary => passengerCount.passengerSummary;
  String get routeSummary {
    return '${pickup.displayText} to ${destination.displayText}';
  }

  String get localLifecycleSummary => 'Local draft';
}

extension RideOfferPreviewLocalSummary on RideOfferPreview {
  String get pickupDisplayText => pickup.displayText;
  String get destinationDisplayText => destination.displayText;
  String get pickupSummary => pickup.pickupSummary;
  String get destinationSummary => destination.destinationSummary;
  String get passengerSummary => passengerCount.passengerSummary;
  String get routeSummary {
    return '${pickup.displayText} to ${destination.displayText}';
  }

  String get localLifecycleSummary => 'Local offer preview';
}

void _validateDifferentLocations(
  RideLocationDescription pickup,
  RideLocationDescription destination,
) {
  if (pickup.value.toLowerCase() == destination.value.toLowerCase()) {
    throw const RideDomainValidationException(
      code: RideValidationCode.matchingLocations,
      field: RideValidationField.route,
    );
  }
}
