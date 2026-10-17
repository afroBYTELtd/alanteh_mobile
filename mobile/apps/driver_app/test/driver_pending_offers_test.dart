import 'package:driver_app/offers/driver_pending_offers.dart';
import 'package:flutter_test/flutter_test.dart';

/// One offer exactly as `GET /api/driver/trips/pending/` sends it
/// (`api_driver_assignments._offer_payload` on backend 07e86be).
Map<String, Object?> realOffer({
  String reference = 'TRIP-6680F97368CD',
  Object? expiresAt = '2026-10-09T10:00:45.250000+00:00',
  bool includeExpiry = true,
  Object? fare = '35.00',
  Object? pickup = 'Accra Mall, Spintex Road',
  String assignedAt = '2026-10-09T10:00:00.250000+00:00',
  Object? requestedPickupTime,
  bool includePickupTime = false,
}) {
  return <String, Object?>{
    'trip_reference': reference,
    'pickup_location': pickup,
    'destination': 'Kotoka International Airport',
    'passenger_count': 2,
    'pickup_verification_required': true,
    'pickup_latitude': '5.622000',
    'pickup_longitude': '-0.173000',
    'destination_latitude': null,
    'destination_longitude': null,
    'trip_status': 'driver_offer_sent',
    'payment_status': 'unpaid',
    'passenger_first_name': 'Ama',
    'assistance_note': '',
    'service_type': 'approved_request',
    'assigned_vehicle': 'VEH-QA-001',
    'vehicle_plate_number': 'GR-1234-26',
    'vehicle_colour': 'White',
    'offer_status': 'driver_offer_sent',
    'fare_amount': fare,
    'fare_currency': 'GHS',
    'assigned_at': assignedAt,
    if (includeExpiry) 'offer_expires_at': expiresAt,
    'created_at': '2026-10-09T09:59:58.000000+00:00',
    if (includePickupTime) 'requested_pickup_time': requestedPickupTime,
  };
}

Map<String, Object?> response(
  List<Map<String, Object?>> offers, {
  Object? serverTime = '2026-10-09T10:00:05.250000+00:00',
}) => <String, Object?>{'offers': offers, 'server_time': serverTime};

DriverPendingOffersSnapshot parse(
  Object? json, {
  Duration receivedAt = const Duration(seconds: 100),
  Duration requestDuration = const Duration(milliseconds: 800),
}) => parseDriverPendingOffers(
  json,
  receivedAt: receivedAt,
  requestDuration: requestDuration,
);

void main() {
  group('parsing a real pending-offers response', () {
    test('reads the card fields from the backend payload', () {
      final snapshot = parse(response([realOffer()]));
      final offer = snapshot.offers.single;

      expect(offer.tripReference, 'TRIP-6680F97368CD');
      expect(offer.pickupLabel, 'Accra Mall, Spintex Road');
      expect(offer.passengerCount, 2);
      expect(offer.fareAmount, '35.00');
      expect(offer.fareCurrency, 'GHS');
      expect(offer.assignedAt, DateTime.utc(2026, 10, 9, 10, 0, 0, 250));
      expect(snapshot.serverTime, DateTime.utc(2026, 10, 9, 10, 0, 5, 250));
      expect(offer.detailsKnown, isTrue);
    });

    test('expiry: a value gives a time', () {
      final offer = parse(response([realOffer()])).offers.single;
      expect(offer.expiry, isA<DriverOfferExpiresAt>());
      expect(
        (offer.expiry as DriverOfferExpiresAt).at,
        DateTime.utc(2026, 10, 9, 10, 0, 45, 250),
      );
    });

    test('expiry: null is a staff offer that never expires', () {
      final offer = parse(response([realOffer(expiresAt: null)])).offers.single;
      expect(offer.expiry, isA<DriverOfferNeverExpires>());
    });

    test('expiry: a missing field (older server) is unknown', () {
      final offer = parse(
        response([realOffer(includeExpiry: false)]),
      ).offers.single;
      expect(offer.expiry, isA<DriverOfferExpiryUnknown>());
    });

    test('expiry: an unreadable value is unknown, never a guess', () {
      final offer = parse(
        response([realOffer(expiresAt: 'soon')]),
      ).offers.single;
      expect(offer.expiry, isA<DriverOfferExpiryUnknown>());
    });

    test('pickup time: missing is unknown, null is now, a value is a time', () {
      final snapshot = parse(
        response([
          realOffer(reference: 'TRIP-A'),
          realOffer(reference: 'TRIP-B', includePickupTime: true),
          realOffer(
            reference: 'TRIP-C',
            includePickupTime: true,
            requestedPickupTime: '2026-10-09T14:30:00+00:00',
          ),
        ]),
      );
      expect(
        snapshot.offerFor('TRIP-A')!.pickupTime,
        isA<DriverOfferPickupTimeUnknown>(),
      );
      expect(
        snapshot.offerFor('TRIP-B')!.pickupTime,
        isA<DriverOfferPickupNow>(),
      );
      final scheduled = snapshot.offerFor('TRIP-C')!.pickupTime;
      expect(scheduled, isA<DriverOfferPickupAt>());
      expect(
        (scheduled as DriverOfferPickupAt).at,
        DateTime.utc(2026, 10, 9, 14, 30),
      );
    });

    test('a fare sent as a number is read as text', () {
      final offer = parse(response([realOffer(fare: 35)])).offers.single;
      expect(offer.fareAmount, '35');
    });

    test('details are known with a pickup label, with or without a fare', () {
      final snapshot = parse(
        response([
          realOffer(reference: 'TRIP-NOPICKUP', pickup: '  '),
          realOffer(reference: 'TRIP-NOFARE', fare: null),
        ]),
      );
      expect(snapshot.offerFor('TRIP-NOPICKUP')!.detailsKnown, isFalse);
      // The server sets no fare on most offers; staff confirm it later.
      expect(snapshot.offerFor('TRIP-NOFARE')!.detailsKnown, isTrue);
      expect(snapshot.offerFor('TRIP-NOFARE')!.fareAmount, isNull);
    });

    test('entries without a trip reference are dropped', () {
      final snapshot = parse(
        response([
          realOffer(reference: ''),
          <String, Object?>{'pickup_location': 'x'},
          realOffer(reference: 'TRIP-OK'),
        ]),
      );
      expect(snapshot.offers.map((o) => o.tripReference), ['TRIP-OK']);
    });

    test('a missing server_time leaves every countdown off', () {
      final snapshot = parse(response([realOffer()], serverTime: null));
      expect(snapshot.serverTime, isNull);
      expect(
        snapshot.remaining(
          snapshot.offers.single,
          const Duration(seconds: 100),
        ),
        isNull,
      );
    });

    test('a body that is not an offers object is rejected', () {
      expect(() => parse('nope'), throwsFormatException);
      expect(
        () => parse(<String, Object?>{'offers': 'x'}),
        throwsFormatException,
      );
    });

    test('offerFor finds nothing for an unknown reference', () {
      expect(parse(response([realOffer()])).offerFor('TRIP-X'), isNull);
    });
  });

  group('when the request left', () {
    test('arrival minus the request duration', () {
      final snapshot = parseDriverPendingOffers(
        const <String, Object?>{'offers': <Object?>[]},
        receivedAt: const Duration(seconds: 10),
        requestDuration: const Duration(seconds: 3),
      );
      expect(snapshot.requestedAt, const Duration(seconds: 7));
    });

    test(
      'a request duration of zero (not measured) gives the arrival time',
      () {
        final snapshot = parseDriverPendingOffers(
          const <String, Object?>{'offers': <Object?>[]},
          receivedAt: const Duration(seconds: 10),
          requestDuration: Duration.zero,
        );
        expect(snapshot.requestedAt, const Duration(seconds: 10));
      },
    );
  });

  group('countdown', () {
    test('time left = expires_at - server_time - request duration, '
        'then counts down on the monotonic clock', () {
      // expires 10:00:45.250, server_time 10:00:05.250 -> 40 s on the
      // server; the 0.8 s request is subtracted -> 39.2 s at arrival.
      final snapshot = parse(response([realOffer()]));
      final offer = snapshot.offers.single;

      expect(
        snapshot.remaining(offer, const Duration(seconds: 100)),
        const Duration(milliseconds: 39200),
      );
      expect(
        snapshot.remaining(offer, const Duration(seconds: 110)),
        const Duration(milliseconds: 29200),
      );
    });

    test('never goes below zero', () {
      final snapshot = parse(response([realOffer()]));
      expect(
        snapshot.remaining(snapshot.offers.single, const Duration(minutes: 5)),
        Duration.zero,
      );
    });

    test('ignores the phone clock entirely', () {
      // Same response, different monotonic origin: same countdown.
      final early = parse(response([realOffer()]), receivedAt: Duration.zero);
      final late = parse(
        response([realOffer()]),
        receivedAt: const Duration(days: 3),
      );
      expect(
        early.remaining(early.offers.single, Duration.zero),
        late.remaining(late.offers.single, const Duration(days: 3)),
      );
    });

    test('a staff offer and an unknown expiry have no countdown', () {
      final snapshot = parse(
        response([
          realOffer(reference: 'TRIP-STAFF', expiresAt: null),
          realOffer(reference: 'TRIP-OLD', includeExpiry: false),
        ]),
      );
      for (final offer in snapshot.offers) {
        expect(snapshot.remaining(offer, const Duration(seconds: 100)), isNull);
      }
    });
  });

  group('several offers', () {
    test('earliest expiry first, then unknown, then staff offers', () {
      final snapshot = parse(
        response([
          realOffer(reference: 'TRIP-STAFF', expiresAt: null),
          realOffer(
            reference: 'TRIP-LATER',
            expiresAt: '2026-10-09T10:00:50+00:00',
          ),
          realOffer(reference: 'TRIP-OLD', includeExpiry: false),
          realOffer(
            reference: 'TRIP-SOONER',
            expiresAt: '2026-10-09T10:00:20+00:00',
          ),
        ]),
      );
      expect(snapshot.offers.map((o) => o.tripReference), [
        'TRIP-SOONER',
        'TRIP-LATER',
        'TRIP-OLD',
        'TRIP-STAFF',
      ]);
    });

    test('ties go to the earliest assignment, then the reference', () {
      final snapshot = parse(
        response([
          realOffer(
            reference: 'TRIP-B',
            expiresAt: null,
            assignedAt: '2026-10-09T09:00:00+00:00',
          ),
          realOffer(
            reference: 'TRIP-C',
            expiresAt: null,
            assignedAt: '2026-10-09T08:00:00+00:00',
          ),
          realOffer(
            reference: 'TRIP-A',
            expiresAt: null,
            assignedAt: '2026-10-09T09:00:00+00:00',
          ),
        ]),
      );
      expect(snapshot.offers.map((o) => o.tripReference), [
        'TRIP-C',
        'TRIP-A',
        'TRIP-B',
      ]);
    });
  });
}
