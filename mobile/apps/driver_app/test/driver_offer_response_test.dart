import 'dart:async';

import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_auth/asm_auth.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:asm_offline_queue/asm_offline_queue.dart';
import 'package:driver_app/driver_duty_trips.dart';
import 'package:driver_app/network/driver_offer_response_gateway.dart';
import 'package:driver_app/network/driver_offer_response_resilience.dart';
import 'package:driver_app/network/driver_trip_action_gateway.dart';
import 'package:driver_app/network/driver_trip_action_resilience.dart';
import 'package:driver_app/network/ghana_network_resilience.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Driver offer-response gateway', () {
    test(
      'uses exact endpoint, bearer token, stable key, and exact body',
      () async {
        final store = MemoryAuthTokenStore();
        await store.saveTokens(
          AuthTokens(
            accessToken: 'driver-access',
            refreshToken: 'driver-refresh',
          ),
        );
        final api = _RecordingOfferApi(
          responses: <ApiResponse<DriverOfferResponseReceipt>>[
            _offerSuccess(statusCode: 201, tripReference: 'TRIP-GHANA/001'),
          ],
        );
        final gateway = ApiDriverOfferResponseGateway(
          apiGateway: api,
          tokenStore: store,
        );

        final receipt = await gateway.accept(
          tripReference: 'TRIP-GHANA/001',
          idempotencyKey:
              'DRIVER-OFFER-TRIP-GHANA/001-11111111-1111-4111-8111-111111111111',
          deviceTimestamp: '2026-07-23T17:00:00.000Z',
        );

        expect(receipt.tripStatus, 'driver_accepted');
        expect(receipt.duplicate, isFalse);
        expect(api.paths, <String>[
          '/api/driver/trips/TRIP-GHANA%2F001/response/',
        ]);
        expect(api.headers.single['Authorization'], 'Bearer driver-access');
        expect(
          api.headers.single['Idempotency-Key'],
          'DRIVER-OFFER-TRIP-GHANA/001-'
          '11111111-1111-4111-8111-111111111111',
        );
        expect(api.headers.single['Content-Type'], 'application/json');
        expect(api.bodies.single, <String, Object?>{
          'response': 'accept',
          'device_timestamp': '2026-07-23T17:00:00.000Z',
        });
      },
    );

    test('accepts only 200 duplicate true as replay success', () async {
      final store = await _tokenStore();
      final api = _RecordingOfferApi(
        responses: <ApiResponse<DriverOfferResponseReceipt>>[
          _offerSuccess(statusCode: 200, duplicate: true),
        ],
      );
      final gateway = ApiDriverOfferResponseGateway(
        apiGateway: api,
        tokenStore: store,
      );

      final receipt = await gateway.accept(
        tripReference: 'TRIP-001',
        idempotencyKey: 'DRIVER-OFFER-TRIP-001-uuid',
        deviceTimestamp: '2026-07-23T17:00:00.000Z',
      );

      expect(receipt.duplicate, isTrue);
      expect(receipt.tripStatus, 'driver_accepted');
    });

    test(
      'rejects invalid success combinations and mismatched references',
      () async {
        final store = await _tokenStore();
        final api = _RecordingOfferApi(
          responses: <ApiResponse<DriverOfferResponseReceipt>>[
            _offerSuccess(statusCode: 201, duplicate: true),
            ApiResponse.success(
              const DriverOfferResponseReceipt(
                tripReference: 'OTHER-TRIP',
                tripStatus: 'driver_accepted',
                duplicate: false,
              ),
              statusCode: 201,
            ),
          ],
        );
        final gateway = ApiDriverOfferResponseGateway(
          apiGateway: api,
          tokenStore: store,
        );

        await expectLater(
          gateway.accept(
            tripReference: 'TRIP-001',
            idempotencyKey: 'DRIVER-OFFER-TRIP-001-first',
            deviceTimestamp: '2026-07-23T17:00:00.000Z',
          ),
          throwsA(
            isA<DriverOfferResponseException>().having(
              (error) => error.type,
              'type',
              DriverOfferResponseFailureType.badResponse,
            ),
          ),
        );

        await expectLater(
          gateway.accept(
            tripReference: 'TRIP-001',
            idempotencyKey: 'DRIVER-OFFER-TRIP-001-second',
            deviceTimestamp: '2026-07-23T17:00:01.000Z',
          ),
          throwsA(
            isA<DriverOfferResponseException>().having(
              (error) => error.type,
              'type',
              DriverOfferResponseFailureType.badResponse,
            ),
          ),
        );
      },
    );

    test('retries transient failures at 2s, 4s, and 8s unchanged', () async {
      final store = await _tokenStore();
      final delays = <Duration>[];
      final api = _RecordingOfferApi(
        responses: <ApiResponse<DriverOfferResponseReceipt>>[
          _offerFailure(503),
          _offerFailure(502),
          _offerFailure(504),
          _offerSuccess(statusCode: 201),
        ],
      );
      final gateway = ApiDriverOfferResponseGateway(
        apiGateway: api,
        tokenStore: store,
        retryPolicy: GhanaRetryPolicy(
          delay: (duration) async => delays.add(duration),
        ),
      );

      await gateway.accept(
        tripReference: 'TRIP-RETRY',
        idempotencyKey: 'DRIVER-OFFER-TRIP-RETRY-stable',
        deviceTimestamp: '2026-07-23T17:10:00.000Z',
      );

      expect(api.paths, hasLength(4));
      expect(
        api.headers.map((headers) => headers['Idempotency-Key']),
        everyElement('DRIVER-OFFER-TRIP-RETRY-stable'),
      );
      expect(
        api.bodies,
        everyElement(<String, Object?>{
          'response': 'accept',
          'device_timestamp': '2026-07-23T17:10:00.000Z',
        }),
      );
      expect(delays, <Duration>[
        const Duration(seconds: 2),
        const Duration(seconds: 4),
        const Duration(seconds: 8),
      ]);
    });

    test(
      'exhausted transient retries use the exact required message',
      () async {
        final store = await _tokenStore();
        final api = _RecordingOfferApi(
          responses: List<ApiResponse<DriverOfferResponseReceipt>>.generate(
            4,
            (_) => _offerFailure(503),
          ),
        );
        final gateway = ApiDriverOfferResponseGateway(
          apiGateway: api,
          tokenStore: store,
          retryPolicy: GhanaRetryPolicy(delay: (_) async {}),
        );

        await expectLater(
          gateway.accept(
            tripReference: 'TRIP-EXHAUST',
            idempotencyKey: 'DRIVER-OFFER-TRIP-EXHAUST-stable',
            deviceTimestamp: '2026-07-23T17:20:00.000Z',
          ),
          throwsA(
            isA<DriverOfferResponseException>()
                .having(
                  (error) => error.type,
                  'type',
                  DriverOfferResponseFailureType.temporarilyUnavailable,
                )
                .having(
                  (error) => error.message,
                  'message',
                  driverOfferAcceptanceFailureMessage,
                ),
          ),
        );

        expect(api.paths, hasLength(4));
      },
    );

    test('401 refreshes once and preserves key, timestamp, and body', () async {
      final store = await _tokenStore(accessToken: 'expired-access');
      final api = _RecordingOfferApi(
        responses: <ApiResponse<DriverOfferResponseReceipt>>[
          ApiResponse.apiFailure(
            const AsmApiException(
              type: AsmApiExceptionType.authentication,
              message: 'Unauthorized.',
              statusCode: 401,
            ),
          ),
          _offerSuccess(statusCode: 201),
        ],
      );
      var refreshCalls = 0;
      final gateway = ApiDriverOfferResponseGateway(
        apiGateway: api,
        tokenStore: store,
        refreshAccessToken: () async {
          refreshCalls += 1;
          await store.saveTokens(
            AuthTokens(
              accessToken: 'refreshed-access',
              refreshToken: 'driver-refresh',
            ),
          );
          return DriverTokenRefreshOutcome.refreshed;
        },
      );

      await gateway.accept(
        tripReference: 'TRIP-401',
        idempotencyKey: 'DRIVER-OFFER-TRIP-401-stable',
        deviceTimestamp: '2026-07-23T17:30:00.000Z',
      );

      expect(refreshCalls, 1);
      expect(api.headers, hasLength(2));
      expect(
        api.headers.map((headers) => headers['Idempotency-Key']),
        everyElement('DRIVER-OFFER-TRIP-401-stable'),
      );
      expect(api.headers.map((headers) => headers['Authorization']), <String?>[
        'Bearer expired-access',
        'Bearer refreshed-access',
      ]);
      expect(api.bodies[0], api.bodies[1]);
    });

    test('409 does not retry and uses exact conflict message', () async {
      final store = await _tokenStore();
      final api = _RecordingOfferApi(
        responses: <ApiResponse<DriverOfferResponseReceipt>>[
          _offerFailure(409),
        ],
      );
      final gateway = ApiDriverOfferResponseGateway(
        apiGateway: api,
        tokenStore: store,
      );

      await expectLater(
        gateway.accept(
          tripReference: 'TRIP-CONFLICT',
          idempotencyKey: 'DRIVER-OFFER-TRIP-CONFLICT-stable',
          deviceTimestamp: '2026-07-23T17:40:00.000Z',
        ),
        throwsA(
          isA<DriverOfferResponseException>()
              .having(
                (error) => error.type,
                'type',
                DriverOfferResponseFailureType.conflict,
              )
              .having(
                (error) => error.message,
                'message',
                driverOfferConflictMessage,
              )
              .having(
                (error) => error.permitsManualRetry,
                'permitsManualRetry',
                isFalse,
              ),
        ),
      );

      expect(api.paths, hasLength(1));
    });

    test(
      'other 4xx is safe, exposes no raw detail, and permits manual retry',
      () async {
        final store = await _tokenStore();
        final api = _RecordingOfferApi(
          responses: <ApiResponse<DriverOfferResponseReceipt>>[
            ApiResponse.apiFailure(
              const AsmApiException(
                type: AsmApiExceptionType.badResponse,
                message: 'Raw backend private detail.',
                statusCode: 400,
                cause: <String, Object?>{
                  'detail': 'Raw backend private detail.',
                },
              ),
            ),
          ],
        );
        final gateway = ApiDriverOfferResponseGateway(
          apiGateway: api,
          tokenStore: store,
        );

        await expectLater(
          gateway.accept(
            tripReference: 'TRIP-400',
            idempotencyKey: 'DRIVER-OFFER-TRIP-400-stable',
            deviceTimestamp: '2026-07-23T17:50:00.000Z',
          ),
          throwsA(
            isA<DriverOfferResponseException>()
                .having(
                  (error) => error.type,
                  'type',
                  DriverOfferResponseFailureType.clientFailure,
                )
                .having(
                  (error) => error.message,
                  'message',
                  driverOfferSafeClientFailureMessage,
                )
                .having(
                  (error) => error.permitsManualRetry,
                  'permitsManualRetry',
                  isTrue,
                ),
          ),
        );
      },
    );
  });

  group('Driver persistent offer acceptance', () {
    test('first display creates one stable UUID4-prefixed record', () async {
      final queue = _MemoryOfferQueue();
      final controller = _controller(
        queue: queue,
        gateway: _RecordingOfferGateway(),
      );

      final first = await controller.prepareWhenOfferDisplayed();
      final second = await controller.prepareWhenOfferDisplayed();

      expect(queue.events, hasLength(1));
      expect(second.id, first.id);
      expect(second.idempotencyKey, first.idempotencyKey);
      expect(
        first.idempotencyKey,
        matches(
          RegExp(
            r'^DRIVER-OFFER-TRIP-OFFER-001-'
            r'[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-'
            r'[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
      expect(first.payloadJson, <String, Object?>{'response': 'accept'});
      expect(first.payloadJson.containsKey('device_timestamp'), isFalse);
    });

    test('first tap persists UTC timestamp before any network call', () async {
      final queue = _MemoryOfferQueue();
      final fixedTime = DateTime.utc(2026, 7, 23, 18, 0);
      late _RecordingOfferGateway gateway;
      gateway = _RecordingOfferGateway(
        beforeSuccess: () {
          final stored = queue.events.single;
          expect(
            stored.payloadJson['device_timestamp'],
            fixedTime.toIso8601String(),
          );
          expect(gateway.deviceTimestamps, <String>[
            fixedTime.toIso8601String(),
          ]);
        },
      );
      final controller = _controller(
        queue: queue,
        gateway: gateway,
        utcNow: () => fixedTime,
      );

      final result = await controller.accept();

      expect(result.accepted, isTrue);
      expect(queue.events.single.syncStatus, QueueSyncStatus.synced);
      expect(gateway.calls, 1);
    });

    test(
      'repeat taps share one in-flight request and one queue record',
      () async {
        final queue = _MemoryOfferQueue();
        final pending = Completer<DriverOfferResponseReceipt>();
        final gateway = _RecordingOfferGateway(pending: pending);
        final controller = _controller(queue: queue, gateway: gateway);

        final first = controller.accept();
        final second = controller.accept();

        expect(identical(first, second), isTrue);

        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(gateway.calls, 1);
        expect(queue.events, hasLength(1));

        pending.complete(_receipt());
        final results = await Future.wait(<Future<DriverOfferAcceptanceResult>>[
          first,
          second,
        ]);

        expect(results, everyElement(isA<DriverOfferAcceptanceResult>()));
        expect(
          results,
          everyElement(
            predicate<DriverOfferAcceptanceResult>((result) => result.accepted),
          ),
        );
        expect(gateway.calls, 1);
      },
    );

    test(
      'manual retry reuses the same key and exact persisted timestamp',
      () async {
        final queue = _MemoryOfferQueue();
        final gateway = _RecordingOfferGateway(
          errors: <DriverOfferResponseException>[
            const DriverOfferResponseException(
              type: DriverOfferResponseFailureType.temporarilyUnavailable,
              message: driverOfferAcceptanceFailureMessage,
            ),
          ],
        );
        final controller = _controller(
          queue: queue,
          gateway: gateway,
          utcNow: () => DateTime.utc(2026, 7, 23, 18, 10),
        );

        final first = await controller.accept();
        final second = await controller.retry();

        expect(first.accepted, isFalse);
        expect(first.permitsManualRetry, isTrue);
        expect(second.accepted, isTrue);
        expect(gateway.idempotencyKeys, hasLength(2));
        expect(gateway.idempotencyKeys.toSet(), hasLength(1));
        expect(gateway.deviceTimestamps.toSet(), hasLength(1));
        expect(queue.events, hasLength(1));
        expect(queue.events.single.syncStatus, QueueSyncStatus.synced);
      },
    );

    test('duplicate replay requires refreshed driver_accepted truth', () async {
      final queue = _MemoryOfferQueue();
      final gateway = _RecordingOfferGateway(
        receipts: <DriverOfferResponseReceipt>[_receipt(duplicate: true)],
      );
      var refreshCalls = 0;
      final controller = DriverOfferResponseResilienceController(
        queue: queue,
        gateway: gateway,
        tripReference: 'TRIP-OFFER-001',
        driverId: 'DRIVER-001',
        verifyServerState: (receipt) async {
          refreshCalls += 1;
          return const DriverOfferVerifiedTrip(
            tripReference: 'TRIP-OFFER-001',
            status: 'driver_accepted',
          );
        },
      );

      final result = await controller.accept();

      expect(
        result.disposition,
        DriverOfferAcceptanceDisposition.duplicateRecovered,
      );
      expect(refreshCalls, 1);
      expect(queue.events.single.syncStatus, QueueSyncStatus.synced);
    });

    test(
      'validated POST stays synchronized when refreshed status is delayed',
      () async {
        final queue = _MemoryOfferQueue();
        final gateway = _RecordingOfferGateway();
        final controller = DriverOfferResponseResilienceController(
          queue: queue,
          gateway: gateway,
          tripReference: 'TRIP-OFFER-001',
          driverId: 'DRIVER-001',
          verifyServerState: (_) async => const DriverOfferVerifiedTrip(
            tripReference: 'TRIP-OFFER-001',
            status: 'driver_offer_sent',
          ),
        );

        final result = await controller.accept();

        expect(result.accepted, isFalse);
        expect(
          result.disposition,
          DriverOfferAcceptanceDisposition.retryableFailure,
        );
        expect(result.permitsManualRetry, isTrue);
        expect(gateway.calls, 1);
        expect(queue.events.single.syncStatus, QueueSyncStatus.synced);
      },
    );

    test('validated POST is synchronized before refresh and Retry only '
        'rechecks the live GET', () async {
      final queue = _MemoryOfferQueue();
      final gateway = _RecordingOfferGateway();
      var verifyCalls = 0;

      final controller = DriverOfferResponseResilienceController(
        queue: queue,
        gateway: gateway,
        tripReference: 'TRIP-OFFER-001',
        driverId: 'DRIVER-001',
        verifyServerState: (_) async {
          verifyCalls += 1;

          if (verifyCalls == 1) {
            expect(queue.events.single.syncStatus, QueueSyncStatus.synced);
            throw StateError('Temporary refresh failure.');
          }

          return const DriverOfferVerifiedTrip(
            tripReference: 'TRIP-OFFER-001',
            status: 'driver_accepted',
          );
        },
      );

      final first = await controller.accept();

      expect(first.accepted, isFalse);
      expect(first.permitsManualRetry, isTrue);
      expect(gateway.calls, 1);
      expect(verifyCalls, 1);

      final second = await controller.retry();

      expect(second.accepted, isTrue);
      expect(gateway.calls, 1);
      expect(verifyCalls, 2);
      expect(queue.events.single.syncStatus, QueueSyncStatus.synced);
    });

    test(
      'controller restoration reuses the synchronized key and timestamp',
      () async {
        final queue = _MemoryOfferQueue();
        final firstGateway = _RecordingOfferGateway();
        final fixedTime = DateTime.utc(2026, 7, 23, 18, 20);

        final firstController = _controller(
          queue: queue,
          gateway: firstGateway,
          utcNow: () => fixedTime,
        );

        final firstResult = await firstController.accept();
        final persisted = queue.events.single;

        expect(firstResult.accepted, isTrue);
        expect(persisted.syncStatus, QueueSyncStatus.synced);

        final restoredGateway = _RecordingOfferGateway(
          receipts: <DriverOfferResponseReceipt>[_receipt(duplicate: true)],
        );
        final restoredController = _controller(
          queue: queue,
          gateway: restoredGateway,
          utcNow: () => DateTime.utc(2026, 7, 23, 19),
        );

        final restoredResult = await restoredController.accept();

        expect(restoredResult.accepted, isTrue);
        expect(
          restoredResult.disposition,
          DriverOfferAcceptanceDisposition.duplicateRecovered,
        );
        expect(queue.events, hasLength(1));
        expect(
          restoredGateway.idempotencyKeys.single,
          persisted.idempotencyKey,
        );
        expect(
          restoredGateway.deviceTimestamps.single,
          persisted.payloadJson['device_timestamp'],
        );
        expect(queue.events.single.syncStatus, QueueSyncStatus.synced);
      },
    );

    test(
      'conflict preserves record and does not permit manual retry',
      () async {
        final queue = _MemoryOfferQueue();
        final controller = _controller(
          queue: queue,
          gateway: _RecordingOfferGateway(
            errors: <DriverOfferResponseException>[
              const DriverOfferResponseException(
                type: DriverOfferResponseFailureType.conflict,
                message: driverOfferConflictMessage,
              ),
            ],
          ),
        );

        final result = await controller.accept();

        expect(result.disposition, DriverOfferAcceptanceDisposition.conflict);
        expect(result.permitsManualRetry, isFalse);
        expect(result.message, driverOfferConflictMessage);
        expect(queue.events.single.syncStatus, QueueSyncStatus.pending);
      },
    );
  });

  group('Driver offer UI and status gating', () {
    test('only approved backend statuses unlock live trip actions', () {
      expect(driverCanOpenLiveTripActions('assigned'), isTrue);
      expect(driverCanOpenLiveTripActions('driver_accepted'), isTrue);
      expect(driverCanOpenLiveTripActions('driver_en_route'), isTrue);
      expect(driverCanOpenLiveTripActions('dispatched'), isTrue);

      expect(driverCanOpenLiveTripActions('driver_offer_sent'), isFalse);
      expect(driverCanOpenLiveTripActions('accepted_for_trip'), isFalse);
      expect(driverCanOpenLiveTripActions('arrived_at_pickup'), isTrue);
      expect(driverIsOfferPending('driver_offer_sent'), isTrue);
      expect(driverIsOfferPending('driver_accepted'), isFalse);
    });

    testWidgets('pending offer shows Accept, disabled Decline, blocks Arrived, '
        'and ignores repeat taps', (tester) async {
      tester.view.physicalSize = const Size(430, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final queue = _MemoryOfferQueue();
      final pending = Completer<DriverOfferResponseReceipt>();
      final offerGateway = _RecordingOfferGateway(pending: pending);
      final dutyGateway = _SequenceDutyGateway(
        details: <DriverAssignedTrip>[
          _trip(status: 'driver_offer_sent'),
          _trip(status: 'driver_accepted'),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AsmThemes.driver,
          home: DriverTripDetailScreen(
            gateway: dutyGateway,
            tripReference: 'TRIP-OFFER-001',
            offerResponseControllerFactory: (_) async =>
                DriverOfferResponseResilienceController(
                  queue: queue,
                  gateway: offerGateway,
                  tripReference: 'TRIP-OFFER-001',
                  driverId: 'DRIVER-001',
                  verifyServerState: (_) async {
                    final refreshed = await dutyGateway.fetchTripDetail(
                      'TRIP-OFFER-001',
                    );
                    return DriverOfferVerifiedTrip(
                      tripReference: refreshed.reference,
                      status: refreshed.status?.trim() ?? '',
                      source: refreshed,
                    );
                  },
                ),
            actionControllerFactory: (_) async =>
                DriverTripActionResilienceController(
                  queue: _NoopTripActionQueue(),
                  tripReference: 'TRIP-OFFER-001',
                  driverId: 'DRIVER-001',
                ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('driver-accept-offer')), findsOneWidget);
      expect(
        find.byKey(const Key('driver-decline-offer-disabled')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const Key('driver-decline-offer-disabled')),
            )
            .onPressed,
        isNull,
      );
      expect(
        find.byKey(const Key('driver-open-live-trip-actions')),
        findsNothing,
      );
      expect(queue.events, hasLength(1));
      expect(offerGateway.calls, 0);

      await tester.tap(find.byKey(const Key('driver-accept-offer')));
      await tester.pump();

      expect(find.text('Confirming acceptance...'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('driver-accept-offer')))
            .onPressed,
        isNull,
      );

      await tester.tap(
        find.byKey(const Key('driver-accept-offer')),
        warnIfMissed: false,
      );
      await tester.pump();

      expect(offerGateway.calls, 1);
      expect(queue.events, hasLength(1));

      pending.complete(_receipt());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('driver-accept-offer')), findsNothing);
      expect(
        find.byKey(const Key('driver-open-live-trip-actions')),
        findsOneWidget,
      );
      expect(dutyGateway.detailCalls, 2);
      expect(queue.events.single.syncStatus, QueueSyncStatus.synced);
    });
  });
}

Future<MemoryAuthTokenStore> _tokenStore({
  String accessToken = 'driver-access',
}) async {
  final store = MemoryAuthTokenStore();
  await store.saveTokens(
    AuthTokens(accessToken: accessToken, refreshToken: 'driver-refresh'),
  );
  return store;
}

ApiResponse<DriverOfferResponseReceipt> _offerSuccess({
  required int statusCode,
  bool duplicate = false,
  String? tripReference,
}) {
  return ApiResponse.success(
    DriverOfferResponseReceipt(
      tripReference: tripReference,
      tripStatus: 'driver_accepted',
      duplicate: duplicate,
    ),
    statusCode: statusCode,
  );
}

ApiResponse<DriverOfferResponseReceipt> _offerFailure(int statusCode) {
  return ApiResponse.apiFailure(
    AsmApiException(
      type: statusCode >= 500
          ? AsmApiExceptionType.server
          : AsmApiExceptionType.badResponse,
      message: 'Raw backend failure.',
      statusCode: statusCode,
    ),
  );
}

DriverOfferResponseReceipt _receipt({bool duplicate = false}) {
  return DriverOfferResponseReceipt(
    tripReference: 'TRIP-OFFER-001',
    tripStatus: 'driver_accepted',
    duplicate: duplicate,
  );
}

DriverAssignedTrip _trip({required String status}) {
  return DriverAssignedTrip(
    reference: 'TRIP-OFFER-001',
    status: status,
    pickupLocation: 'Accra Mall',
    destination: 'Accra Market',
    vehicleReference: 'VEH-001',
    passengerCount: 1,
  );
}

DriverOfferResponseResilienceController _controller({
  required _MemoryOfferQueue queue,
  required DriverOfferResponseGateway gateway,
  DateTime Function()? utcNow,
}) {
  return DriverOfferResponseResilienceController(
    queue: queue,
    gateway: gateway,
    tripReference: 'TRIP-OFFER-001',
    driverId: 'DRIVER-001',
    utcNow: utcNow,
    verifyServerState: (_) async => const DriverOfferVerifiedTrip(
      tripReference: 'TRIP-OFFER-001',
      status: 'driver_accepted',
    ),
  );
}

final class _RecordingOfferApi implements DriverOfferResponseApiGateway {
  _RecordingOfferApi({required this.responses});

  final List<ApiResponse<DriverOfferResponseReceipt>> responses;
  final paths = <String>[];
  final bodies = <Object?>[];
  final headers = <Map<String, String>>[];
  int _index = 0;

  @override
  Future<ApiResponse<T>> post<T>(
    String path, {
    Object? data,
    Map<String, String>? headers,
    JsonDecoder<T>? decoder,
  }) async {
    paths.add(path);
    bodies.add(data);
    this.headers.add(Map<String, String>.of(headers ?? const {}));

    final response =
        responses[_index < responses.length ? _index : responses.length - 1];
    _index += 1;
    return response as ApiResponse<T>;
  }
}

final class _MemoryOfferQueue implements DriverTripActionPersistentQueue {
  final events = <QueuedEvent>[];

  @override
  Future<QueuedEvent> enqueue(QueuedEvent event) async {
    final index = events.indexWhere((candidate) => candidate.id == event.id);
    if (index < 0) {
      events.add(event);
    } else {
      events[index] = event;
    }
    return event;
  }

  @override
  Future<QueuedEvent?> eventById(String id) async {
    for (final event in events) {
      if (event.id == id) {
        return event;
      }
    }
    return null;
  }

  @override
  Future<List<QueuedEvent>> pendingEvents() async {
    return events
        .where(
          (event) =>
              event.syncStatus == QueueSyncStatus.pending ||
              event.syncStatus == QueueSyncStatus.failed,
        )
        .toList(growable: false);
  }

  @override
  Future<void> markFailed(String id) async {}

  @override
  Future<void> markPermanentlyFailed(String id) async {}

  @override
  Future<void> markSynced(String id) async {
    final event = await eventById(id);
    if (event == null) {
      return;
    }
    await enqueue(event.copyWith(syncStatus: QueueSyncStatus.synced));
  }
}

final class _RecordingOfferGateway implements DriverOfferResponseGateway {
  _RecordingOfferGateway({
    List<DriverOfferResponseReceipt>? receipts,
    List<DriverOfferResponseException>? errors,
    this.pending,
    this.beforeSuccess,
  }) : receipts = receipts ?? <DriverOfferResponseReceipt>[_receipt()],
       errors = errors ?? <DriverOfferResponseException>[];

  final List<DriverOfferResponseReceipt> receipts;
  final List<DriverOfferResponseException> errors;
  final Completer<DriverOfferResponseReceipt>? pending;
  final void Function()? beforeSuccess;

  final idempotencyKeys = <String>[];
  final deviceTimestamps = <String>[];
  int calls = 0;

  @override
  Future<DriverOfferResponseReceipt> accept({
    required String tripReference,
    required String idempotencyKey,
    required String deviceTimestamp,
  }) async {
    calls += 1;
    idempotencyKeys.add(idempotencyKey);
    deviceTimestamps.add(deviceTimestamp);

    final pendingResponse = pending;
    if (pendingResponse != null) {
      return pendingResponse.future;
    }

    if (errors.isNotEmpty) {
      throw errors.removeAt(0);
    }

    beforeSuccess?.call();
    if (receipts.isEmpty) {
      return _receipt();
    }
    return receipts.removeAt(0);
  }
}

final class _SequenceDutyGateway implements DriverDutyGateway {
  _SequenceDutyGateway({required this.details});

  final List<DriverAssignedTrip> details;
  int detailCalls = 0;

  @override
  Future<DriverDutySummary> fetchDuty() async {
    return const DriverDutySummary(driverReference: 'DRIVER-001');
  }

  @override
  Future<List<DriverAssignedTrip>> fetchTrips() async => details;

  @override
  Future<DriverAssignedTrip> fetchTripDetail(String tripReference) async {
    final index = detailCalls < details.length
        ? detailCalls
        : details.length - 1;
    detailCalls += 1;
    return details[index];
  }
}

final class _NoopTripActionQueue implements DriverTripActionQueue {
  @override
  Future<QueuedEvent> enqueue(QueuedEvent event) async => event;
}
