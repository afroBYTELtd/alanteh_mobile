import 'package:asm_auth/asm_auth.dart';
import 'package:asm_offline_queue/asm_offline_queue.dart';
import 'package:driver_app/driver_duty_trips.dart';
import 'package:driver_app/main.dart'
    show driverOfferResponseControllerFactoryFor;
import 'package:driver_app/network/driver_offer_response_gateway.dart';
import 'package:driver_app/network/driver_offer_response_resilience.dart';
import 'package:driver_app/network/driver_trip_action_resilience.dart';
import 'package:driver_app/offers/driver_offer_card_wiring.dart';
import 'package:driver_app/offers/driver_pending_offer_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// A trip can be offered to the same driver again: after a decline, after an
// offer ran out, or after staff took it back. Each offer has its own
// `assigned_at`, and its answer must go out under its own idempotency key
// with the time of its own tap. The server (07e86be) stores a receipt only
// for an answer it applied and replays it for a key it has seen, so an old
// key sent for a new offer changes nothing: a second decline would retry
// forever. The queue here is the real SQLite one, which keeps synced
// records just as the phone does.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  const trip = 'TRIP-REOFFER-1';
  final firstOffer = DateTime.utc(2026, 10, 16, 2, 50, 10, 123, 456);
  final secondOffer = DateTime.utc(2026, 10, 16, 2, 52, 30, 0, 789);

  late _Server server;
  late PersistentDriverTripActionQueue queue;
  late DateTime now;

  setUp(() {
    server = _Server(trip);
    queue = PersistentDriverTripActionQueue(
      managerFactory: QueueManager.openInMemory,
    );
    now = DateTime.utc(2026, 10, 16, 2, 50, 20);
  });

  tearDown(() => queue.close());

  DriverOfferResponseResilienceController controllerFor(
    DateTime? assignedAt, {
    bool unknownOffer = false,
  }) {
    return DriverOfferResponseResilienceController(
      queue: queue,
      gateway: server,
      tripReference: trip,
      driverId: 'DRV-1',
      assignedAt: assignedAt,
      unknownOffer: unknownOffer,
      utcNow: () => now,
      // As on the card: the receipt carries the trip's status.
      verifyServerState: (receipt) async => DriverOfferVerifiedTrip(
        tripReference: receipt.tripReference ?? trip,
        status: receipt.tripStatus,
      ),
    );
  }

  Future<DriverOfferAcceptanceResult> decline(
    DriverOfferResponseResilienceController controller,
  ) {
    return controller.decline(reason: DriverDeclineReason.endOfShift);
  }

  String offerTag(DateTime assignedAt) =>
      '${assignedAt.microsecondsSinceEpoch}';

  void expectKeyFor(String key, DateTime assignedAt) {
    expect(key, contains(trip));
    expect(key, contains(offerTag(assignedAt)));
  }

  test('a second decline of a re-offered trip goes out under a new key and '
      'succeeds', () async {
    final first = controllerFor(firstOffer);
    await first.prepareWhenOfferDisplayed();
    final firstResult = await decline(first);
    expect(firstResult.succeeded, isTrue);
    expect(server.status, 'driver_declined');

    server.reOffer();
    now = DateTime.utc(2026, 10, 16, 2, 52, 40);
    final second = controllerFor(secondOffer);
    await second.prepareWhenOfferDisplayed();
    final secondResult = await decline(second);

    expect(secondResult.succeeded, isTrue);
    expect(server.status, 'driver_declined');
    expect(server.applied, 2);
    expect(server.keys, hasLength(2));
    expect(server.keys.last, isNot(server.keys.first));
    expectKeyFor(server.keys.first, firstOffer);
    expectKeyFor(server.keys.last, secondOffer);
    expect(server.timestamps.last, '2026-10-16T02:52:40.000Z');
  });

  test('a second accept of a re-offered trip goes out under a new key and '
      'succeeds', () async {
    final first = controllerFor(firstOffer);
    await first.prepareWhenOfferDisplayed();
    expect((await first.accept()).accepted, isTrue);

    // Staff take the trip back and offer it to the same driver again.
    server.reOffer();
    now = DateTime.utc(2026, 10, 16, 2, 52, 41);
    final second = controllerFor(secondOffer);
    await second.prepareWhenOfferDisplayed();
    final secondResult = await second.accept();

    expect(secondResult.accepted, isTrue);
    expect(secondResult.disposition, DriverOfferAcceptanceDisposition.accepted);
    expect(server.applied, 2);
    expect(server.keys.last, isNot(server.keys.first));
    expectKeyFor(server.keys.last, secondOffer);
    expect(server.timestamps.last, '2026-10-16T02:52:41.000Z');
  });

  group('guards', () {
    test('an accept refused because the offer expired, then a re-offer: '
        'Accept goes out under a new key with the new tap time', () async {
      final first = controllerFor(firstOffer);
      await first.prepareWhenOfferDisplayed();
      server.expire();
      final refused = await first.accept();
      expect(refused.accepted, isFalse);
      expect(
        refused.error?.type,
        DriverOfferResponseFailureType.offerUnavailable,
      );

      server.reOffer();
      now = DateTime.utc(2026, 10, 16, 2, 52, 42);
      final second = controllerFor(secondOffer);
      await second.prepareWhenOfferDisplayed();
      // Nothing is sent until the driver taps.
      expect(server.keys, hasLength(1));
      final secondResult = await second.accept();

      expect(secondResult.accepted, isTrue);
      expect(server.keys.last, isNot(server.keys.first));
      expectKeyFor(server.keys.last, secondOffer);
      expect(server.timestamps.last, '2026-10-16T02:52:42.000Z');
    });

    test('an accept refused because the offer ended (taken back), then a '
        're-offer: Accept goes out under a new key', () async {
      final first = controllerFor(firstOffer);
      await first.prepareWhenOfferDisplayed();
      server.takeBack();
      final refused = await first.accept();
      expect(
        refused.error?.type,
        DriverOfferResponseFailureType.offerUnavailable,
      );

      server.reOffer();
      now = DateTime.utc(2026, 10, 16, 2, 52, 43);
      final second = controllerFor(secondOffer);
      await second.prepareWhenOfferDisplayed();
      final secondResult = await second.accept();

      expect(secondResult.accepted, isTrue);
      expect(server.keys.last, isNot(server.keys.first));
      expectKeyFor(server.keys.last, secondOffer);
      expect(server.timestamps.last, '2026-10-16T02:52:43.000Z');
    });

    test(
      'a decline, then a re-offer: Accept goes out under a new key',
      () async {
        final first = controllerFor(firstOffer);
        await first.prepareWhenOfferDisplayed();
        expect((await decline(first)).succeeded, isTrue);

        server.reOffer();
        now = DateTime.utc(2026, 10, 16, 2, 52, 44);
        final second = controllerFor(secondOffer);
        await second.prepareWhenOfferDisplayed();
        final secondResult = await second.accept();

        expect(secondResult.accepted, isTrue);
        expectKeyFor(server.keys.last, secondOffer);
        expect(server.timestamps.last, '2026-10-16T02:52:44.000Z');
      },
    );

    test('a network retry of the same offer reuses its key and its first '
        'tap time', () async {
      final controller = controllerFor(firstOffer);
      await controller.prepareWhenOfferDisplayed();
      server.failNext = true;
      final failed = await controller.accept();
      expect(failed.permitsManualRetry, isTrue);

      now = DateTime.utc(2026, 10, 16, 2, 50, 31);
      final retried = await controller.retry();

      expect(retried.accepted, isTrue);
      expect(server.keys, hasLength(2));
      expect(server.keys.last, server.keys.first);
      expect(server.timestamps.last, server.timestamps.first);
      expectKeyFor(server.keys.first, firstOffer);
    });

    test('the same offer opened again (a new card) reuses its key', () async {
      final first = controllerFor(firstOffer);
      await first.prepareWhenOfferDisplayed();
      server.failNext = true;
      await first.accept();

      final reopened = controllerFor(firstOffer);
      await reopened.prepareWhenOfferDisplayed();
      final result = await reopened.accept();

      expect(result.accepted, isTrue);
      expect(server.keys.last, server.keys.first);
    });

    Future<List<QueuedEvent>> pendingFor(
      String kind,
      DateTime assignedAt,
    ) async => (await queue.pendingEvents())
        .where(
          (event) =>
              event.id ==
              'driver-offer-$kind:${trip.toLowerCase()}:${offerTag(assignedAt)}',
        )
        .toList();

    test('an offline Accept on this offer stays pending through a new card '
        'and a failed retry, and then goes out under its own key', () async {
      final first = controllerFor(firstOffer);
      await first.prepareWhenOfferDisplayed();
      server.failNext = true;
      await first.accept();
      final waiting = await pendingFor('accept', firstOffer);
      expect(waiting, hasLength(1));

      final reopened = controllerFor(firstOffer);
      await reopened.prepareWhenOfferDisplayed();
      expect(await pendingFor('accept', firstOffer), hasLength(1));

      server.failNext = true;
      await reopened.accept();
      expect(await pendingFor('accept', firstOffer), hasLength(1));

      final result = await reopened.accept();
      expect(result.accepted, isTrue);
      expect(server.keys.toSet(), {waiting.single.idempotencyKey});
    });

    test('an offline Decline on this offer likewise', () async {
      final first = controllerFor(firstOffer);
      await first.prepareWhenOfferDisplayed();
      server.failNext = true;
      await decline(first);
      final waiting = await pendingFor('decline', firstOffer);
      expect(waiting, hasLength(1));

      final reopened = controllerFor(firstOffer);
      server.failNext = true;
      await decline(reopened);
      expect(await pendingFor('decline', firstOffer), hasLength(1));

      final result = await decline(reopened);
      expect(result.succeeded, isTrue);
      expect(server.keys.toSet(), {waiting.single.idempotencyKey});
    });

    test("an older offer's unsent record is retired, never sent, and does "
        'not block the re-offer', () async {
      final first = controllerFor(firstOffer);
      await first.prepareWhenOfferDisplayed();
      server.expire();
      await first.accept();

      server.reOffer();
      final second = controllerFor(secondOffer);
      await second.prepareWhenOfferDisplayed();

      final pending = await queue.pendingEvents();
      expect(pending, hasLength(1));
      expect(pending.single.idempotencyKey, contains(offerTag(secondOffer)));
      expect(server.keys, hasLength(1));
    });

    test('a record left by the build that keyed by trip only does not block '
        'a new offer, and is never sent', () async {
      await queue.enqueue(
        QueuedEvent(
          id: 'driver-offer-accept:${trip.toLowerCase()}',
          eventType:
              '${driverOfferResponsePath(trip)}'
              '$driverOfferAcceptanceEventIdentity',
          tripReference: trip,
          driverId: 'DRV-1',
          payloadJson: const <String, Object?>{
            'response': driverOfferAcceptResponse,
            'device_timestamp': '2026-10-16T02:40:00.000Z',
          },
          idempotencyKey: 'DRIVER-OFFER-$trip-legacy',
        ),
      );

      final controller = controllerFor(secondOffer);
      await controller.prepareWhenOfferDisplayed();
      now = DateTime.utc(2026, 10, 16, 2, 52, 45);
      final result = await controller.accept();

      expect(result.accepted, isTrue);
      expect(server.keys, hasLength(1));
      expect(server.keys.single, isNot('DRIVER-OFFER-$trip-legacy'));
      expectKeyFor(server.keys.single, secondOffer);
      expect(server.timestamps.single, '2026-10-16T02:52:45.000Z');
      expect(await queue.pendingEvents(), isEmpty);
    });

    QueuedEvent pendingAccept(String id) => QueuedEvent(
      id: id,
      eventType:
          '${driverOfferResponsePath(trip)}'
          '$driverOfferAcceptanceEventIdentity',
      tripReference: trip,
      driverId: 'DRV-1',
      payloadJson: const <String, Object?>{
        'response': driverOfferAcceptResponse,
      },
      idempotencyKey: 'DRIVER-OFFER-$trip-other',
    );

    test('a pending record that belongs to no offer of this trip still '
        'blocks, and is kept', () async {
      await queue.enqueue(pendingAccept('some-other-record'));

      await expectLater(
        controllerFor(secondOffer).prepareWhenOfferDisplayed(),
        throwsA(
          isA<DriverOfferPreparationException>().having(
            (error) => error.code,
            'code',
            DriverOfferPreparationFailureCode.conflictingOfferRecord,
          ),
        ),
      );
      expect(await queue.pendingEvents(), hasLength(1));
      expect(server.keys, isEmpty);
    });

    test('without an assigned_at (an older server) nothing is retired: '
        "another offer's record blocks, as before", () async {
      await queue.enqueue(
        pendingAccept(
          'driver-offer-accept:${trip.toLowerCase()}:${offerTag(firstOffer)}',
        ),
      );

      await expectLater(
        controllerFor(null).prepareWhenOfferDisplayed(),
        throwsA(
          isA<DriverOfferPreparationException>().having(
            (error) => error.code,
            'code',
            DriverOfferPreparationFailureCode.conflictingOfferRecord,
          ),
        ),
      );
      expect(await queue.pendingEvents(), hasLength(1));
    });
  });

  group('which records an offer may retire', () {
    QueuedEvent pendingAcceptFor(DateTime assignedAt) => QueuedEvent(
      id: 'driver-offer-accept:${trip.toLowerCase()}:${offerTag(assignedAt)}',
      eventType:
          '${driverOfferResponsePath(trip)}'
          '$driverOfferAcceptanceEventIdentity',
      tripReference: trip,
      driverId: 'DRV-1',
      payloadJson: const <String, Object?>{
        'response': driverOfferAcceptResponse,
      },
      idempotencyKey: 'DRIVER-OFFER-$trip-${offerTag(assignedAt)}-x',
    );

    test("a newer offer's pending record is not retired by an older offer: "
        'it blocks, and is kept', () async {
      await queue.enqueue(pendingAcceptFor(secondOffer));

      await expectLater(
        controllerFor(firstOffer).prepareWhenOfferDisplayed(),
        throwsA(
          isA<DriverOfferPreparationException>().having(
            (error) => error.code,
            'code',
            DriverOfferPreparationFailureCode.conflictingOfferRecord,
          ),
        ),
      );
      final pending = await queue.pendingEvents();
      expect(pending.single.id, endsWith(offerTag(secondOffer)));
      expect(server.keys, isEmpty);
    });

    test('a pending record from an answer whose offer was not known is '
        'retired once the offer is known', () async {
      final unknown = controllerFor(null, unknownOffer: true);
      server.failNext = true;
      await decline(unknown);
      expect(await queue.pendingEvents(), hasLength(1));

      final known = controllerFor(secondOffer);
      final result = await decline(known);

      expect(result.succeeded, isTrue);
      expect(server.keys.last, contains(offerTag(secondOffer)));
      final pending = await queue.pendingEvents();
      expect(pending.where((e) => e.id.contains(':once-')), isEmpty);
    });

    test("an older offer's pending record is retired by a newer one", () async {
      await queue.enqueue(pendingAcceptFor(firstOffer));

      await controllerFor(secondOffer).prepareWhenOfferDisplayed();

      final pending = await queue.pendingEvents();
      expect(pending.single.id, endsWith(offerTag(secondOffer)));
    });
  });

  group('an answer whose offer is not known', () {
    QueuedEvent oldDecline({required QueueSyncStatus status}) => QueuedEvent(
      id: 'driver-offer-decline:${trip.toLowerCase()}',
      eventType:
          '${driverOfferResponsePath(trip)}'
          '$driverOfferDeclineEventIdentity',
      tripReference: trip,
      driverId: 'DRV-1',
      payloadJson: <String, Object?>{
        'response': driverOfferDeclineResponse,
        'reason': DriverDeclineReason.endOfShift.code,
        'device_timestamp': '2026-10-16T02:40:00.000Z',
      },
      idempotencyKey: 'DRIVER-OFFER-DECLINE-$trip-old',
      syncStatus: status,
    );

    test('never reuses the synced record the installed build left: it goes '
        'out once under a fresh key', () async {
      await queue.enqueue(oldDecline(status: QueueSyncStatus.synced));
      server.markSeen('DRIVER-OFFER-DECLINE-$trip-old');
      now = DateTime.utc(2026, 10, 16, 2, 52, 50);

      final result = await decline(controllerFor(null, unknownOffer: true));

      expect(result.succeeded, isTrue);
      expect(server.keys.single, isNot('DRIVER-OFFER-DECLINE-$trip-old'));
      expect(server.keys.single, startsWith('DRIVER-OFFER-DECLINE-$trip-'));
      expect(server.timestamps.single, '2026-10-16T02:52:50.000Z');
    });

    test(
      "leaves this trip's other records alone and is not blocked by them",
      () async {
        await queue.enqueue(oldDecline(status: QueueSyncStatus.pending));

        final result = await decline(controllerFor(null, unknownOffer: true));

        expect(result.succeeded, isTrue);
        expect(server.keys.single, isNot('DRIVER-OFFER-DECLINE-$trip-old'));
        final pending = await queue.pendingEvents();
        expect(pending.map((event) => event.idempotencyKey), [
          'DRIVER-OFFER-DECLINE-$trip-old',
        ]);
      },
    );

    test('two such controllers never share a key', () async {
      final first = controllerFor(null, unknownOffer: true);
      server.failNext = true;
      await decline(first);

      server.reOffer();
      await decline(controllerFor(null, unknownOffer: true));

      expect(server.keys, hasLength(2));
      expect(server.keys.last, isNot(server.keys.first));
    });
  });

  group('the factories pass the offer on', () {
    test('the card factory', () async {
      final factory = driverOfferCardControllerFactoryFor(
        baseUrl: 'https://offers.invalid',
        tokenStore: MemoryAuthTokenStore(),
        identity: DriverIdentityCachingDutyGateway(_Duty()),
        persistentQueue: queue,
      );

      final controller = await factory(trip, assignedAt: secondOffer);

      expect(controller.assignedAt, secondOffer);
      expect(controller.unknownOffer, isFalse);
      final unknown = await factory(trip, unknownOffer: true);
      expect(unknown.unknownOffer, isTrue);
    });

    test('the trip screen factory', () async {
      final factory = driverOfferResponseControllerFactoryFor(
        baseUrl: 'https://offers.invalid',
        tokenStore: MemoryAuthTokenStore(),
        dutyGateway: _Duty(),
        persistentQueue: queue,
        offerGateway: server,
      )!;

      final controller = await factory(trip, assignedAt: secondOffer);

      expect(controller.assignedAt, secondOffer);
      expect(controller.unknownOffer, isFalse);
      final unknown = await factory(trip, unknownOffer: true);
      expect(unknown.unknownOffer, isTrue);
    });
  });
}

final class _Duty implements DriverDutyGateway {
  @override
  Future<DriverDutySummary> fetchDuty() async =>
      const DriverDutySummary(driverReference: 'DRV-1');

  @override
  Future<List<DriverAssignedTrip>> fetchTrips() async => const [];

  @override
  Future<DriverAssignedTrip> fetchTripDetail(String tripReference) =>
      throw UnimplementedError();
}

/// The offer-response rules of the server at 07e86be, for one trip and one
/// driver: a receipt is stored only for an answer that was applied, a key
/// seen before is answered as a duplicate with the trip as it is now, and an
/// answer to an offer that is not live is refused.
final class _Server implements DriverOfferResponseGateway {
  _Server(this.trip);

  final String trip;
  String status = 'driver_offer_sent';
  final _receipts = <String>{};
  final keys = <String>[];
  final timestamps = <String>[];
  var applied = 0;
  var failNext = false;

  void reOffer() => status = 'driver_offer_sent';
  void markSeen(String key) => _receipts.add(key);
  void expire() => status = 'requested';
  void takeBack() => status = 'under_review';

  Future<DriverOfferResponseReceipt> _answer(
    String key,
    String timestamp,
    String newStatus,
  ) async {
    keys.add(key);
    timestamps.add(timestamp);
    if (failNext) {
      failNext = false;
      throw const DriverOfferResponseException(
        type: DriverOfferResponseFailureType.temporarilyUnavailable,
        message: 'Network is slow.',
      );
    }
    if (_receipts.contains(key)) {
      return DriverOfferResponseReceipt(
        tripReference: trip,
        tripStatus: status,
        duplicate: true,
      );
    }
    if (status != 'driver_offer_sent') {
      throw const DriverOfferResponseException(
        type: DriverOfferResponseFailureType.offerUnavailable,
        message: driverOfferNoLongerAvailableMessage,
      );
    }
    status = newStatus;
    applied += 1;
    _receipts.add(key);
    return DriverOfferResponseReceipt(
      tripReference: trip,
      tripStatus: status,
      duplicate: false,
    );
  }

  @override
  Future<DriverOfferResponseReceipt> accept({
    required String tripReference,
    required String idempotencyKey,
    required String deviceTimestamp,
    DriverOfferSubmissionTelemetrySink? telemetrySink,
  }) => _answer(idempotencyKey, deviceTimestamp, 'driver_accepted');

  @override
  Future<DriverOfferResponseReceipt> decline({
    required String tripReference,
    required String idempotencyKey,
    required String deviceTimestamp,
    required DriverDeclineReason reason,
    String? reasonNote,
    DriverOfferSubmissionTelemetrySink? telemetrySink,
  }) => _answer(idempotencyKey, deviceTimestamp, 'driver_declined');
}
