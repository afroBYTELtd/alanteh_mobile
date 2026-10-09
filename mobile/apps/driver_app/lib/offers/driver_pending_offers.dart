/// Pending trip offers as the server sent them, and the countdown to each
/// offer's expiry measured on the phone's monotonic clock.
library;

/// When an offer expires, in the three states the server can send.
sealed class DriverOfferExpiry {
  const DriverOfferExpiry();
}

/// `offer_expires_at` was missing (an older server): no countdown.
final class DriverOfferExpiryUnknown extends DriverOfferExpiry {
  const DriverOfferExpiryUnknown();
}

/// `offer_expires_at` was null: a staff offer, which never expires.
final class DriverOfferNeverExpires extends DriverOfferExpiry {
  const DriverOfferNeverExpires();
}

/// `offer_expires_at` had a value.
final class DriverOfferExpiresAt extends DriverOfferExpiry {
  const DriverOfferExpiresAt(this.at);

  final DateTime at;
}

/// When the passenger wants to be picked up.
sealed class DriverOfferPickupTime {
  const DriverOfferPickupTime();
}

/// `requested_pickup_time` was missing: not known yet.
final class DriverOfferPickupTimeUnknown extends DriverOfferPickupTime {
  const DriverOfferPickupTimeUnknown();
}

/// `requested_pickup_time` was null: a ride for now.
final class DriverOfferPickupNow extends DriverOfferPickupTime {
  const DriverOfferPickupNow();
}

/// `requested_pickup_time` had a value: a scheduled ride.
final class DriverOfferPickupAt extends DriverOfferPickupTime {
  const DriverOfferPickupAt(this.at);

  final DateTime at;
}

final class DriverPendingOffer {
  const DriverPendingOffer({
    required this.tripReference,
    this.pickupLabel,
    this.passengerCount,
    this.fareAmount,
    this.fareCurrency,
    this.expiry = const DriverOfferExpiryUnknown(),
    this.pickupTime = const DriverOfferPickupTimeUnknown(),
    this.assignedAt,
  });

  final String tripReference;
  final String? pickupLabel;
  final int? passengerCount;
  final String? fareAmount;
  final String? fareCurrency;
  final DriverOfferExpiry expiry;
  final DriverOfferPickupTime pickupTime;
  final DateTime? assignedAt;

  /// The pickup label: what a driver must see before Accept, together with
  /// whether the ride is for now or later. Not the fare: the server sets
  /// none on most offers, and staff confirm it later.
  bool get detailsKnown => pickupLabel?.trim().isNotEmpty ?? false;
}

/// One pending-offers response, and when it arrived on the monotonic clock.
final class DriverPendingOffersSnapshot {
  const DriverPendingOffersSnapshot({
    required this.offers,
    required this.serverTime,
    required this.receivedAt,
    required this.requestDuration,
  });

  /// Earliest expiry first (see [compareDriverPendingOffers]).
  final List<DriverPendingOffer> offers;

  /// `server_time`, or null when the server did not send it.
  final DateTime? serverTime;

  /// The monotonic clock's reading when the response arrived.
  final Duration receivedAt;

  /// How long the request took, from sending to the response.
  final Duration requestDuration;

  DriverPendingOffer? offerFor(String tripReference) {
    final wanted = tripReference.trim();
    for (final offer in offers) {
      if (offer.tripReference == wanted) {
        return offer;
      }
    }
    return null;
  }

  /// Time left on [offer], or null when it has no countdown.
  ///
  /// The server stamped `server_time` somewhere inside the request, so the
  /// whole request duration is subtracted: the countdown errs early, never
  /// late.
  Duration? remaining(DriverPendingOffer offer, Duration monotonicNow) {
    final expiry = offer.expiry;
    final stamped = serverTime;
    if (expiry is! DriverOfferExpiresAt || stamped == null) {
      return null;
    }
    final left =
        expiry.at.difference(stamped) -
        requestDuration -
        (monotonicNow - receivedAt);
    return left.isNegative ? Duration.zero : left;
  }
}

/// Parses `GET /api/driver/trips/pending/`. Entries without a trip
/// reference are dropped; a body that is not an object with an `offers`
/// list throws a [FormatException].
DriverPendingOffersSnapshot parseDriverPendingOffers(
  Object? json, {
  required Duration receivedAt,
  required Duration requestDuration,
}) {
  if (json is! Map) {
    throw const FormatException('Pending offers response is not an object.');
  }
  final rawOffers = json['offers'];
  if (rawOffers is! List) {
    throw const FormatException('Pending offers response has no offers list.');
  }

  final offers = <DriverPendingOffer>[];
  for (final raw in rawOffers) {
    if (raw is! Map) {
      continue;
    }
    final reference = _text(raw['trip_reference']);
    if (reference == null) {
      continue;
    }
    offers.add(
      DriverPendingOffer(
        tripReference: reference,
        pickupLabel: _text(raw['pickup_location']),
        passengerCount: raw['passenger_count'] is int
            ? raw['passenger_count'] as int
            : null,
        fareAmount: _fare(raw['fare_amount']),
        fareCurrency: _text(raw['fare_currency']),
        expiry: _expiry(raw),
        pickupTime: _pickupTime(raw),
        assignedAt: _time(raw['assigned_at']),
      ),
    );
  }
  offers.sort(compareDriverPendingOffers);

  return DriverPendingOffersSnapshot(
    offers: List<DriverPendingOffer>.unmodifiable(offers),
    serverTime: _time(json['server_time']),
    receivedAt: receivedAt,
    requestDuration: requestDuration,
  );
}

DriverOfferExpiry _expiry(Map<dynamic, dynamic> raw) {
  if (!raw.containsKey('offer_expires_at')) {
    return const DriverOfferExpiryUnknown();
  }
  final value = raw['offer_expires_at'];
  if (value == null) {
    return const DriverOfferNeverExpires();
  }
  final at = _time(value);
  return at == null
      ? const DriverOfferExpiryUnknown()
      : DriverOfferExpiresAt(at);
}

DriverOfferPickupTime _pickupTime(Map<dynamic, dynamic> raw) {
  if (!raw.containsKey('requested_pickup_time')) {
    return const DriverOfferPickupTimeUnknown();
  }
  final value = raw['requested_pickup_time'];
  if (value == null) {
    return const DriverOfferPickupNow();
  }
  final at = _time(value);
  return at == null
      ? const DriverOfferPickupTimeUnknown()
      : DriverOfferPickupAt(at);
}

String? _text(Object? value) {
  if (value is! String) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

String? _fare(Object? value) {
  if (value is num && value.isFinite) {
    return value.toString();
  }
  return _text(value);
}

DateTime? _time(Object? value) {
  final text = _text(value);
  return text == null ? null : DateTime.tryParse(text)?.toUtc();
}

/// Earliest expiry first; then offers with no known expiry; then staff
/// offers, which never expire. Ties: earliest assignment, then reference.
int compareDriverPendingOffers(DriverPendingOffer a, DriverPendingOffer b) {
  final byExpiry = _expiryRank(a.expiry).compareTo(_expiryRank(b.expiry));
  if (byExpiry != 0) {
    return byExpiry;
  }
  final aExpiry = a.expiry;
  final bExpiry = b.expiry;
  if (aExpiry is DriverOfferExpiresAt && bExpiry is DriverOfferExpiresAt) {
    final byTime = aExpiry.at.compareTo(bExpiry.at);
    if (byTime != 0) {
      return byTime;
    }
  }
  final aAssigned = a.assignedAt;
  final bAssigned = b.assignedAt;
  if (aAssigned != null && bAssigned != null) {
    final byAssignment = aAssigned.compareTo(bAssigned);
    if (byAssignment != 0) {
      return byAssignment;
    }
  } else if (aAssigned != null || bAssigned != null) {
    return aAssigned != null ? -1 : 1;
  }
  return a.tripReference.compareTo(b.tripReference);
}

int _expiryRank(DriverOfferExpiry expiry) => switch (expiry) {
  DriverOfferExpiresAt() => 0,
  DriverOfferExpiryUnknown() => 1,
  DriverOfferNeverExpires() => 2,
};
