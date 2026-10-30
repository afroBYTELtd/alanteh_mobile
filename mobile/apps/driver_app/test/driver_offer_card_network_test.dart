import 'dart:async';
import 'dart:convert';

import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_auth/asm_auth.dart';
import 'package:asm_offline_queue/asm_offline_queue.dart';
import 'package:driver_app/driver_duty_trips.dart';
import 'package:driver_app/network/driver_offer_response_gateway.dart';
import 'package:driver_app/network/driver_offer_response_resilience.dart';
import 'package:driver_app/network/driver_trip_action_gateway.dart';
import 'package:driver_app/network/driver_trip_action_resilience.dart';
import 'package:driver_app/network/ghana_network_resilience.dart';
import 'package:driver_app/offers/driver_pending_offer_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('bounded retries', () {
    test('the default Ghana schedule is unchanged: 4 tries, 2/4/8 s', () async {
      final waits = <Duration>[];
      var calls = 0;
      await GhanaRetryPolicy(delay: (d) async => waits.add(d)).execute<Object?>(
        safeToRetry: true,
        operation: () async {
          calls += 1;
          return _networkFailure<Object?>();
        },
      );
      expect(calls, 4);
      expect(waits, const [
        Duration(seconds: 2),
        Duration(seconds: 4),
        Duration(seconds: 8),
      ]);
    });

    test('the card schedule: 3 tries, 1 s then 2 s apart', () async {
      final waits = <Duration>[];
      var calls = 0;
      await GhanaRetryPolicy(
        delay: (d) async => waits.add(d),
        backoffs: DriverOfferCardTiming.responseRetryBackoffs,
      ).execute<Object?>(
        safeToRetry: true,
        operation: () async {
          calls += 1;
          return _networkFailure<Object?>();
        },
      );
      expect(calls, 3);
      expect(waits, const [Duration(seconds: 1), Duration(seconds: 2)]);
    });

    test(
      'Accept with the card schedule retries with the same key and stops',
      () async {
        final api = _ScriptedOfferApi([
          _networkFailure(),
          _networkFailure(),
          _networkFailure(),
          _networkFailure(),
        ]);
        final gateway = ApiDriverOfferResponseGateway(
          apiGateway: api,
          tokenStore: await _tokenStore(),
          retryPolicy: GhanaRetryPolicy(
            delay: (_) async {},
            backoffs: DriverOfferCardTiming.responseRetryBackoffs,
          ),
        );

        await expectLater(
          gateway.accept(
            tripReference: 'TRIP-1',
            idempotencyKey: 'DRIVER-OFFER-TRIP-1-key',
            deviceTimestamp: '2026-10-09T10:00:00.000Z',
          ),
          throwsA(
            isA<DriverOfferResponseException>().having(
              (e) => e.type,
              'type',
              DriverOfferResponseFailureType.temporarilyUnavailable,
            ),
          ),
        );
        expect(api.keys, List.filled(3, 'DRIVER-OFFER-TRIP-1-key'));
      },
    );
  });

  group('offer-ended mappings', () {
    Future<DriverOfferResponseException> acceptFailure(
      ApiResponse<DriverOfferResponseReceipt> response,
    ) async {
      final gateway = ApiDriverOfferResponseGateway(
        apiGateway: _ScriptedOfferApi([response]),
        tokenStore: await _tokenStore(),
        retryPolicy: GhanaRetryPolicy(delay: (_) async {}),
      );
      try {
        await gateway.accept(
          tripReference: 'TRIP-1',
          idempotencyKey: 'key-1',
          deviceTimestamp: '2026-10-09T10:00:00.000Z',
        );
      } on DriverOfferResponseException catch (error) {
        return error;
      }
      fail('accept should have failed');
    }

    test(
      '404 after an expiry race: "This offer expired", never retried',
      () async {
        final error = await acceptFailure(
          _apiFailure(404, {
            'detail': 'Trip offer is not assigned to this driver.',
          }),
        );
        expect(error.type, DriverOfferResponseFailureType.offerUnavailable);
        expect(error.message, 'This offer expired');
        expect(error.permitsManualRetry, isFalse);
      },
    );

    test('offer_not_pending: "This offer is no longer available"', () async {
      final error = await acceptFailure(
        _apiFailure(400, {
          'detail': 'Trip is not waiting for a driver offer response.',
          'code': 'offer_not_pending',
        }),
      );
      expect(error.type, DriverOfferResponseFailureType.offerUnavailable);
      expect(error.message, 'This offer is no longer available');
    });

    test('any other 400 keeps the existing client-failure handling', () async {
      final error = await acceptFailure(
        _apiFailure(400, {'detail': 'x', 'code': 'response_invalid'}),
      );
      expect(error.type, DriverOfferResponseFailureType.clientFailure);
    });

    test('decline maps the same two cases', () async {
      final gateway = ApiDriverOfferResponseGateway(
        apiGateway: _ScriptedOfferApi([
          _apiFailure(400, {'code': 'offer_not_pending'}),
        ]),
        tokenStore: await _tokenStore(),
        retryPolicy: GhanaRetryPolicy(delay: (_) async {}),
      );
      await expectLater(
        gateway.decline(
          tripReference: 'TRIP-1',
          idempotencyKey: 'key-2',
          deviceTimestamp: '2026-10-09T10:00:00.000Z',
          reason: DriverDeclineReason.values.first,
        ),
        throwsA(
          isA<DriverOfferResponseException>().having(
            (e) => e.message,
            'message',
            'This offer is no longer available',
          ),
        ),
      );
    });

    test(
      'the controller treats an ended offer as final, with no retry',
      () async {
        final controller = DriverOfferResponseResilienceController(
          queue: _MemoryQueue(),
          gateway: ApiDriverOfferResponseGateway(
            apiGateway: _ScriptedOfferApi([_apiFailure(404, {})]),
            tokenStore: await _tokenStore(),
            retryPolicy: GhanaRetryPolicy(delay: (_) async {}),
          ),
          tripReference: 'TRIP-1',
          driverId: 'DRV-1',
          verifyServerState: (_) async => const DriverOfferVerifiedTrip(
            tripReference: 'TRIP-1',
            status: '',
          ),
        );
        await controller.prepareWhenOfferDisplayed();
        final result = await controller.accept();
        expect(result.disposition, DriverOfferAcceptanceDisposition.rejected);
        expect(result.permitsManualRetry, isFalse);
        expect(result.message, 'This offer expired');
      },
    );
  });

  group('pending-offers source', () {
    test('a success returns the body', () async {
      final client = _ScriptedClient([
        _ok({'offers': [], 'server_time': 'x'}),
      ]);
      final result = await ApiDriverPendingOffersSource(client: client).fetch();
      expect(result, isA<DriverPendingOffersFetched>());
      expect(client.paths, ['/api/driver/trips/pending/']);
    });

    test(
      'a network failure is tried once more after 1 s, then given up',
      () async {
        final waits = <Duration>[];
        final client = _ScriptedClient([
          _networkFailure(),
          _networkFailure(),
          _ok({'offers': []}),
        ]);
        final result = await ApiDriverPendingOffersSource(
          client: client,
          delay: (d) async => waits.add(d),
        ).fetch();
        expect(result, isA<DriverPendingOffersUnavailable>());
        expect(client.paths.length, 2);
        expect(waits, const [Duration(seconds: 1)]);
      },
    );

    test('a 502 is retried like a network failure', () async {
      final client = _ScriptedClient([
        _apiFailure<Object?>(502, null),
        _ok({'offers': []}),
      ]);
      final result = await ApiDriverPendingOffersSource(
        client: client,
        delay: (_) async {},
      ).fetch();
      expect(result, isA<DriverPendingOffersFetched>());
    });

    test('a 401 refreshes once, then asks again', () async {
      var refreshes = 0;
      final client = _ScriptedClient([
        _apiFailure<Object?>(401, null),
        _ok({'offers': []}),
      ]);
      final result = await ApiDriverPendingOffersSource(
        client: client,
        refreshAccessToken: () async {
          refreshes += 1;
          return DriverTokenRefreshOutcome.refreshed;
        },
      ).fetch();
      expect(result, isA<DriverPendingOffersFetched>());
      expect(refreshes, 1);
      expect(client.paths.length, 2);
    });

    test('a 401 whose refresh is rejected is a session end', () async {
      final result = await ApiDriverPendingOffersSource(
        client: _ScriptedClient([_apiFailure<Object?>(401, null)]),
        refreshAccessToken: () async =>
            DriverTokenRefreshOutcome.sessionExpired,
      ).fetch();
      expect(result, isA<DriverPendingOffersSessionExpired>());
    });

    test(
      'a 401 whose refresh could not reach the server is unavailable',
      () async {
        final result = await ApiDriverPendingOffersSource(
          client: _ScriptedClient([_apiFailure<Object?>(401, null)]),
          refreshAccessToken: () async =>
              DriverTokenRefreshOutcome.temporarilyUnavailable,
        ).fetch();
        expect(result, isA<DriverPendingOffersUnavailable>());
      },
    );
  });

  group('pending-offer store', () {
    test(
      'records arrival and request duration on the monotonic clock',
      () async {
        final clock = _ManualClock(const Duration(seconds: 50));
        final source = _ControlledSource();
        final store = DriverPendingOfferStore(source: source, clock: clock);

        final refreshing = store.refresh();
        clock.value = const Duration(seconds: 50, milliseconds: 700);
        source.complete(_offersJson());
        await refreshing;

        final snapshot = store.snapshot!;
        expect(
          snapshot.receivedAt,
          const Duration(seconds: 50, milliseconds: 700),
        );
        expect(snapshot.requestDuration, const Duration(milliseconds: 700));
        // 40 s on the server, minus the 0.7 s request.
        expect(store.remaining('TRIP-1'), const Duration(milliseconds: 39300));
        clock.value = const Duration(seconds: 60, milliseconds: 700);
        expect(store.remaining('TRIP-1'), const Duration(milliseconds: 29300));
      },
    );

    test('callers during a running fetch share it', () async {
      final source = _ControlledSource();
      final store = DriverPendingOfferStore(
        source: source,
        clock: _ManualClock(Duration.zero),
      );
      final first = store.refresh();
      final second = store.refresh();
      source.complete(_offersJson());
      await Future.wait([first, second]);
      expect(source.calls, 1);
    });

    test('clear() forgets offers and ignores a fetch still running', () async {
      final source = _ControlledSource();
      final store = DriverPendingOfferStore(
        source: source,
        clock: _ManualClock(Duration.zero),
      );
      final running = store.refresh();
      store.clear();
      source.complete(_offersJson());
      await running;
      expect(store.snapshot, isNull);
      expect(store.firstOffer, isNull);
    });

    test('the first offer is the earliest expiry', () async {
      final source = _ControlledSource();
      final store = DriverPendingOfferStore(
        source: source,
        clock: _ManualClock(Duration.zero),
      );
      final refreshing = store.refresh();
      source.complete({
        'server_time': '2026-10-09T10:00:05+00:00',
        'offers': [
          _offer('TRIP-LATE', '2026-10-09T10:00:40+00:00'),
          _offer('TRIP-SOON', '2026-10-09T10:00:20+00:00'),
        ],
      });
      await refreshing;
      expect(store.firstOffer!.tripReference, 'TRIP-SOON');
      store.forget('TRIP-SOON');
      expect(store.firstOffer!.tripReference, 'TRIP-LATE');
      expect(store.offerFor('TRIP-SOON'), isNull);
    });

    group('a forgotten offer is that offer, not the whole trip', () {
      Future<DriverPendingOfferStore> storeWith(
        _ControlledSource source,
        List<Map<String, Object?>> offers,
      ) async {
        final store = DriverPendingOfferStore(
          source: source,
          clock: _ManualClock(Duration.zero),
        );
        await _deliver(store, source, offers);
        return store;
      }

      test('the same offer listed again stays forgotten', () async {
        final source = _ControlledSource();
        final store = await storeWith(source, [_offer('TRIP-1', null)]);
        store.forget('TRIP-1');

        await _deliver(store, source, [_offer('TRIP-1', null)]);

        expect(store.offerFor('TRIP-1'), isNull);
        expect(store.firstOffer, isNull);
      });

      test('a re-offer of the same trip (a new assigned_at) shows', () async {
        final source = _ControlledSource();
        final store = await storeWith(source, [_offer('TRIP-1', null)]);
        store.forget('TRIP-1');

        await _deliver(store, source, [
          _offer('TRIP-1', null, assignedAt: '2026-10-09T10:05:00+00:00'),
        ]);

        expect(store.offerFor('TRIP-1'), isNotNull);
        expect(store.firstOffer!.tripReference, 'TRIP-1');
      });

      test('answered before any fetch listed it (a push tap): the offer '
          'stays hidden when a fetch then lists it', () async {
        final source = _ControlledSource();
        final store = DriverPendingOfferStore(
          source: source,
          clock: _ManualClock(Duration.zero),
        );
        store.forget('TRIP-1');

        await _deliver(store, source, [_offer('TRIP-1', null)]);

        expect(store.offerFor('TRIP-1'), isNull);
      });

      test('without assigned_at (an older server), the whole trip stays '
          'forgotten until a fetch leaves it out', () async {
        final source = _ControlledSource();
        final store = await storeWith(source, [
          _offer('TRIP-1', null, assignedAt: null),
        ]);
        store.forget('TRIP-1');

        await _deliver(store, source, [
          _offer('TRIP-1', null, assignedAt: null),
        ]);
        expect(store.offerFor('TRIP-1'), isNull);

        await _deliver(store, source, const []);
        await _deliver(store, source, [
          _offer('TRIP-1', null, assignedAt: null),
        ]);
        expect(store.offerFor('TRIP-1'), isNotNull);
      });
    });

    test('a failed fetch keeps the last offers and says it failed', () async {
      final source = _ControlledSource();
      final store = DriverPendingOfferStore(
        source: source,
        clock: _ManualClock(Duration.zero),
      );
      var refreshing = store.refresh();
      source.complete(_offersJson());
      await refreshing;
      refreshing = store.refresh();
      source.fail();
      await refreshing;
      expect(store.lastFetchFailed, isTrue);
      expect(store.offerFor('TRIP-1'), isNotNull);
    });

    test('an unreadable body counts as a failed fetch', () async {
      final source = _ControlledSource();
      final store = DriverPendingOfferStore(
        source: source,
        clock: _ManualClock(Duration.zero),
      );
      final refreshing = store.refresh();
      source.complete('<html>wifi login</html>');
      await refreshing;
      expect(store.lastFetchFailed, isTrue);
      expect(store.snapshot, isNull);
    });

    test('a session end clears the offers and reports it', () async {
      var reported = 0;
      final source = _ControlledSource();
      final store = DriverPendingOfferStore(
        source: source,
        clock: _ManualClock(Duration.zero),
        onSessionExpired: () async => reported += 1,
      );
      var refreshing = store.refresh();
      source.complete(_offersJson());
      await refreshing;
      refreshing = store.refresh();
      source.endSession();
      await refreshing;
      expect(store.snapshot, isNull);
      expect(reported, 1);
    });
  });

  group('driver identity cache', () {
    test(
      'remembers the driver reference and duty from each duty fetch',
      () async {
        final inner = _DutyGateway(
          const DriverDutySummary(
            driverReference: 'DRV-7',
            dutyStatus: 'online',
          ),
        );
        final gateway = DriverIdentityCachingDutyGateway(inner);
        expect(gateway.driverReference, isNull);
        expect(gateway.onDuty, isFalse);

        await gateway.fetchDuty();
        expect(gateway.driverReference, 'DRV-7');
        expect(gateway.onDuty, isTrue);

        gateway.clear();
        expect(gateway.driverReference, isNull);
        expect(gateway.onDuty, isFalse);
      },
    );

    test('a failed duty fetch keeps nothing it did not see', () async {
      final gateway = DriverIdentityCachingDutyGateway(_DutyGateway(null));
      await expectLater(gateway.fetchDuty(), throwsStateError);
      expect(gateway.driverReference, isNull);
    });

    // B7.2: the app wraps every duty gateway in this cache, and it did not
    // pass duty changes on, so GO OFFLINE and GO ONLINE on Work never
    // reached the server (seen 25 Oct: the server kept the driver online).
    test('passes GO OFFLINE and GO ONLINE on to the server', () async {
      final inner = _StatusDutyGateway();
      final DriverDutyGateway gateway = DriverIdentityCachingDutyGateway(inner);
      expect(gateway, isA<DriverDutyStatusGateway>());
      final status = gateway as DriverDutyStatusGateway;

      final online = await status.updateDutyStatus(
        DriverOperationalDutyStatus.online,
      );
      expect(online.dutyStatus, 'online');
      expect((gateway as DriverIdentityCachingDutyGateway).onDuty, isTrue);

      await status.updateDutyStatus(DriverOperationalDutyStatus.offline);
      expect(inner.updates, [
        DriverOperationalDutyStatus.online,
        DriverOperationalDutyStatus.offline,
      ]);
      expect(gateway.onDuty, isFalse);
    });

    test('a gateway that cannot change duty says so', () async {
      final gateway = DriverIdentityCachingDutyGateway(_DutyGateway(null));
      await expectLater(
        gateway.updateDutyStatus(DriverOperationalDutyStatus.offline),
        throwsA(
          isA<DriverDutyApiException>().having(
            (error) => error.type,
            'type',
            DriverDutyApiFailureType.badResponse,
          ),
        ),
      );
    });
  });
}

// ---------------------------------------------------------------- helpers

Map<String, Object?> _offer(
  String reference,
  Object? expiresAt, {
  Object? assignedAt = '2026-10-09T10:00:00+00:00',
}) => <String, Object?>{
  'trip_reference': reference,
  'pickup_location': 'Accra Mall',
  'passenger_count': 1,
  'fare_amount': '35.00',
  'fare_currency': 'GHS',
  'assigned_at': assignedAt,
  'offer_expires_at': expiresAt,
};

Future<void> _deliver(
  DriverPendingOfferStore store,
  _ControlledSource source,
  List<Map<String, Object?>> offers,
) async {
  final refreshing = store.refresh();
  source.complete(<String, Object?>{
    'server_time': '2026-10-09T10:00:05+00:00',
    'offers': offers,
  });
  await refreshing;
}

Map<String, Object?> _offersJson() => <String, Object?>{
  'server_time': '2026-10-09T10:00:05+00:00',
  'offers': [_offer('TRIP-1', '2026-10-09T10:00:45+00:00')],
};

ApiResponse<T> _networkFailure<T>() => ApiResponse<T>.clientException(
  const AsmApiException(
    type: AsmApiExceptionType.network,
    message: 'no network',
  ),
);

ApiResponse<T> _apiFailure<T>(int status, Object? body) =>
    ApiResponse<T>.apiFailure(
      AsmApiException(
        type: status == 401
            ? AsmApiExceptionType.authentication
            : status >= 500
            ? AsmApiExceptionType.server
            : status == 404
            ? AsmApiExceptionType.notFound
            : AsmApiExceptionType.badResponse,
        message: 'failure',
        statusCode: status,
        cause: body,
      ),
    );

ApiResponse<Object?> _ok(Object? body) =>
    ApiResponse<Object?>.success(body, statusCode: 200);

Future<MemoryAuthTokenStore> _tokenStore() async {
  final store = MemoryAuthTokenStore();
  String encode(Object value) =>
      base64UrlEncode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  final exp = DateTime.utc(2100).millisecondsSinceEpoch ~/ 1000;
  await store.saveTokens(
    AuthTokens(
      accessToken:
          '${encode({'alg': 'none'})}.${encode({'exp': exp})}.signature',
      refreshToken: 'driver-refresh',
    ),
  );
  return store;
}

final class _ScriptedOfferApi implements DriverOfferResponseApiGateway {
  _ScriptedOfferApi(this.responses);

  final List<ApiResponse<DriverOfferResponseReceipt>> responses;
  final keys = <String>[];
  var _index = 0;

  @override
  Future<ApiResponse<T>> post<T>(
    String path, {
    Object? data,
    Map<String, String>? headers,
    JsonDecoder<T>? decoder,
  }) async {
    keys.add(headers?['Idempotency-Key'] ?? '');
    final response =
        responses[_index < responses.length ? _index : responses.length - 1];
    _index += 1;
    return response as ApiResponse<T>;
  }
}

final class _ScriptedClient extends AsmApiClient {
  _ScriptedClient(this.responses) : super(baseUrl: 'https://alanteh.test');

  final List<ApiResponse<Object?>> responses;
  final paths = <String>[];
  var _index = 0;

  @override
  Future<ApiResponse<T>> request<T>({
    required String method,
    required String path,
    Object? data,
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
    JsonDecoder<T>? decoder,
  }) async {
    paths.add(path);
    final response =
        responses[_index < responses.length ? _index : responses.length - 1];
    _index += 1;
    return response as ApiResponse<T>;
  }
}

final class _ManualClock implements DriverMonotonicClock {
  _ManualClock(this.value);

  Duration value;

  @override
  Duration get now => value;
}

final class _ControlledSource implements DriverPendingOffersSource {
  Completer<DriverPendingOffersFetch>? _pending;
  var calls = 0;

  @override
  Future<DriverPendingOffersFetch> fetch() {
    calls += 1;
    _pending = Completer<DriverPendingOffersFetch>();
    return _pending!.future;
  }

  void complete(Object? json) =>
      _pending!.complete(DriverPendingOffersFetched(json));

  void fail() => _pending!.complete(const DriverPendingOffersUnavailable());

  void endSession() =>
      _pending!.complete(const DriverPendingOffersSessionExpired());
}

final class _DutyGateway implements DriverDutyGateway {
  _DutyGateway(this.summary);

  final DriverDutySummary? summary;

  @override
  Future<DriverDutySummary> fetchDuty() async =>
      summary ?? (throw StateError('duty unavailable'));

  @override
  Future<List<DriverAssignedTrip>> fetchTrips() async => const [];

  @override
  Future<DriverAssignedTrip> fetchTripDetail(String tripReference) =>
      throw UnimplementedError();
}

final class _StatusDutyGateway extends _DutyGateway
    implements DriverDutyStatusGateway {
  _StatusDutyGateway() : super(null);

  final updates = <DriverOperationalDutyStatus>[];

  @override
  Future<DriverDutyTransition> updateDutyStatus(
    DriverOperationalDutyStatus status,
  ) async {
    updates.add(status);
    return DriverDutyTransition(
      dutyStatus: status.wireValue,
      since: DateTime.utc(2026, 10, 30),
    );
  }
}

final class _MemoryQueue implements DriverTripActionPersistentQueue {
  final _events = <String, QueuedEvent>{};

  @override
  Future<QueuedEvent> enqueue(QueuedEvent event) async =>
      _events.putIfAbsent(event.id, () => event);

  @override
  Future<QueuedEvent?> eventById(String id) async => _events[id];

  @override
  Future<List<QueuedEvent>> pendingEvents() async => _events.values.toList();

  @override
  Future<void> markSynced(String id) async => _events.remove(id);

  @override
  Future<void> markFailed(String id) async {}

  @override
  Future<void> markPermanentlyFailed(String id) async => _events.remove(id);
}
