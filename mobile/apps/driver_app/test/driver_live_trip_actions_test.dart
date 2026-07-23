import 'dart:async';

import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_auth/asm_auth.dart';
import 'package:asm_offline_queue/asm_offline_queue.dart';
import 'package:driver_app/driver_duty_trips.dart';
import 'package:driver_app/main.dart' as driver_main;
import 'package:driver_app/network/driver_trip_action_gateway.dart';
import 'package:driver_app/network/ghana_network_resilience.dart';
import 'package:driver_app/network/driver_trip_action_resilience.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Driver live trip-action gateway', () {
    test(
      'uses the accepted paths, empty body, and idempotency header',
      () async {
        final store = MemoryAuthTokenStore();
        await store.saveTokens(
          AuthTokens(
            accessToken: 'driver-access',
            refreshToken: 'driver-refresh',
          ),
        );
        final api = _RecordingActionApiGateway(
          responses: <ApiResponse<DriverTripActionReceipt>>[
            _successReceipt(
              action: DriverTripAction.arrivedPickup,
              statusCode: 201,
            ),
            _successReceipt(
              action: DriverTripAction.startTrip,
              statusCode: 201,
            ),
            _successReceipt(
              action: DriverTripAction.completeTrip,
              statusCode: 201,
            ),
          ],
        );
        final gateway = ApiDriverTripActionGateway(
          apiGateway: api,
          tokenStore: store,
        );

        for (final action in DriverTripAction.values) {
          final receipt = await gateway.submit(
            action: action,
            tripReference: 'TRIP-GHANA-001',
            idempotencyKey: 'ACTION-${action.eventType}',
          );
          expect(receipt.status, action.expectedStatus);
        }

        expect(api.paths, <String>[
          '/api/driver/trips/TRIP-GHANA-001/actions/arrived-pickup/',
          '/api/driver/trips/TRIP-GHANA-001/actions/start-trip/',
          '/api/driver/trips/TRIP-GHANA-001/actions/complete-trip/',
        ]);
        expect(api.bodies, everyElement(<String, Object?>{}));
        expect(
          api.headers.map((value) => value['Authorization']),
          everyElement('Bearer driver-access'),
        );
        expect(
          api.headers.map((value) => value['Content-Type']),
          everyElement('application/json'),
        );
        expect(api.headers.map((value) => value['Idempotency-Key']), <String>[
          'ACTION-arrived-pickup',
          'ACTION-start-trip',
          'ACTION-complete-trip',
        ]);
      },
    );

    test(
      'discards caller metadata and always transmits exact empty JSON',
      () async {
        final store = MemoryAuthTokenStore();
        await store.saveTokens(
          AuthTokens(
            accessToken: 'driver-access',
            refreshToken: 'driver-refresh',
          ),
        );
        final api = _RecordingActionApiGateway(
          responses: <ApiResponse<DriverTripActionReceipt>>[
            _successReceipt(
              action: DriverTripAction.arrivedPickup,
              statusCode: 201,
            ),
          ],
        );
        final gateway = ApiDriverTripActionGateway(
          apiGateway: api,
          tokenStore: store,
        );

        await gateway.submit(
          action: DriverTripAction.arrivedPickup,
          tripReference: 'TRIP-GHANA-001',
          idempotencyKey: 'ACTION-exact-empty-body',
          body: const <String, Object?>{
            'device_timestamp': '2026-07-23T08:00:00Z',
            'action': 'arrived-pickup',
          },
        );

        expect(api.bodies, <Object?>[<String, Object?>{}]);
      },
    );

    test('accepts only 200 duplicate true as duplicate success', () async {
      final store = MemoryAuthTokenStore();
      await store.saveTokens(
        AuthTokens(
          accessToken: 'driver-access',
          refreshToken: 'driver-refresh',
        ),
      );
      final api = _RecordingActionApiGateway(
        responses: <ApiResponse<DriverTripActionReceipt>>[
          _successReceipt(
            action: DriverTripAction.arrivedPickup,
            statusCode: 200,
            duplicate: true,
          ),
        ],
      );
      final gateway = ApiDriverTripActionGateway(
        apiGateway: api,
        tokenStore: store,
      );

      final receipt = await gateway.submit(
        action: DriverTripAction.arrivedPickup,
        tripReference: 'TRIP-GHANA-001',
        idempotencyKey: 'ACTION-duplicate',
      );

      expect(receipt.duplicate, isTrue);
    });

    test('rejects 201 responses incorrectly marked duplicate', () async {
      final store = MemoryAuthTokenStore();
      await store.saveTokens(
        AuthTokens(
          accessToken: 'driver-access',
          refreshToken: 'driver-refresh',
        ),
      );
      final api = _RecordingActionApiGateway(
        responses: <ApiResponse<DriverTripActionReceipt>>[
          _successReceipt(
            action: DriverTripAction.arrivedPickup,
            statusCode: 201,
            duplicate: true,
          ),
        ],
      );
      final gateway = ApiDriverTripActionGateway(
        apiGateway: api,
        tokenStore: store,
      );

      await expectLater(
        gateway.submit(
          action: DriverTripAction.arrivedPickup,
          tripReference: 'TRIP-GHANA-001',
          idempotencyKey: 'ACTION-invalid-first-duplicate',
        ),
        throwsA(
          isA<DriverTripActionException>().having(
            (error) => error.type,
            'type',
            DriverTripActionFailureType.badResponse,
          ),
        ),
      );
    });

    test('rejects malformed or mismatched successful receipt', () async {
      final store = MemoryAuthTokenStore();
      await store.saveTokens(
        AuthTokens(
          accessToken: 'driver-access',
          refreshToken: 'driver-refresh',
        ),
      );
      final api = _RecordingActionApiGateway(
        responses: <ApiResponse<DriverTripActionReceipt>>[
          ApiResponse.success(
            const DriverTripActionReceipt(
              tripReference: 'OTHER-TRIP',
              status: 'arrived_at_pickup',
              message: 'Arrived.',
              duplicate: false,
            ),
            statusCode: 201,
          ),
        ],
      );
      final gateway = ApiDriverTripActionGateway(
        apiGateway: api,
        tokenStore: store,
      );

      await expectLater(
        gateway.submit(
          action: DriverTripAction.arrivedPickup,
          tripReference: 'TRIP-GHANA-001',
          idempotencyKey: 'ACTION-mismatch',
        ),
        throwsA(
          isA<DriverTripActionException>().having(
            (error) => error.type,
            'type',
            DriverTripActionFailureType.badResponse,
          ),
        ),
      );
    });

    test('rejects an unexpected successful action status', () async {
      final store = MemoryAuthTokenStore();
      await store.saveTokens(
        AuthTokens(
          accessToken: 'driver-access',
          refreshToken: 'driver-refresh',
        ),
      );
      final api = _RecordingActionApiGateway(
        responses: <ApiResponse<DriverTripActionReceipt>>[
          ApiResponse.success(
            const DriverTripActionReceipt(
              tripReference: 'TRIP-GHANA-001',
              status: 'completed_confirmed',
              message: 'Unexpected status.',
              duplicate: false,
            ),
            statusCode: 201,
          ),
        ],
      );
      final gateway = ApiDriverTripActionGateway(
        apiGateway: api,
        tokenStore: store,
      );

      await expectLater(
        gateway.submit(
          action: DriverTripAction.completeTrip,
          tripReference: 'TRIP-GHANA-001',
          idempotencyKey: 'ACTION-unexpected-status',
        ),
        throwsA(
          isA<DriverTripActionException>().having(
            (error) => error.type,
            'type',
            DriverTripActionFailureType.badResponse,
          ),
        ),
      );
    });

    test('requires every accepted success-response field', () {
      expect(
        () => DriverTripActionReceipt.fromJson(const <String, Object?>{
          'trip_reference': 'TRIP-GHANA-001',
          'status': 'in_progress',
          'message': 'Trip started.',
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('uses truthful accepted completion status', () {
      expect(
        DriverTripAction.completeTrip.expectedStatus,
        'completed_pending_review',
      );
      expect(DriverTripAction.startTrip.expectedStatus, 'in_progress');
      expect(
        driverStatusLabel('completed_pending_review'),
        'Trip completed — awaiting operations review',
      );
      expect(
        driverStatusLabel('completed_confirmed'),
        isNot(contains('confirmed')),
      );
      expect(
        DriverTripAction.completeTrip.expectedStatus,
        isNot('completed_confirmed'),
      );
    });

    test('refreshes once and retries with the same idempotency key', () async {
      final store = MemoryAuthTokenStore();
      await store.saveTokens(
        AuthTokens(accessToken: 'expired-access', refreshToken: 'refresh-one'),
      );
      final api = _RecordingActionApiGateway(
        responses: <ApiResponse<DriverTripActionReceipt>>[
          ApiResponse.apiFailure(
            const AsmApiException(
              type: AsmApiExceptionType.authentication,
              message: 'Unauthorized.',
              statusCode: 401,
            ),
          ),
          _successReceipt(action: DriverTripAction.startTrip, statusCode: 201),
        ],
      );
      var refreshCalls = 0;
      final gateway = ApiDriverTripActionGateway(
        apiGateway: api,
        tokenStore: store,
        refreshAccessToken: () async {
          refreshCalls += 1;
          await store.saveTokens(
            AuthTokens(
              accessToken: 'refreshed-access',
              refreshToken: 'refresh-one',
            ),
          );
          return DriverTokenRefreshOutcome.refreshed;
        },
      );

      await gateway.submit(
        action: DriverTripAction.startTrip,
        tripReference: 'TRIP-GHANA-001',
        idempotencyKey: 'ACTION-stable-key',
      );

      expect(refreshCalls, 1);
      expect(api.headers, hasLength(2));
      expect(
        api.headers.map((value) => value['Idempotency-Key']),
        everyElement('ACTION-stable-key'),
      );
      expect(api.headers.map((value) => value['Authorization']), <String?>[
        'Bearer expired-access',
        'Bearer refreshed-access',
      ]);
    });

    test('404 does not retry or replace the idempotency key', () async {
      final store = MemoryAuthTokenStore();
      await store.saveTokens(
        AuthTokens(
          accessToken: 'driver-access',
          refreshToken: 'driver-refresh',
        ),
      );
      final api = _RecordingActionApiGateway(
        responses: <ApiResponse<DriverTripActionReceipt>>[
          ApiResponse.apiFailure(
            const AsmApiException(
              type: AsmApiExceptionType.badResponse,
              message: 'Not found.',
              statusCode: 404,
              cause: <String, Object?>{'unexpected': 'non-receipt error shape'},
            ),
          ),
        ],
      );
      final gateway = ApiDriverTripActionGateway(
        apiGateway: api,
        tokenStore: store,
      );

      await expectLater(
        gateway.submit(
          action: DriverTripAction.arrivedPickup,
          tripReference: 'TRIP-GHANA-404',
          idempotencyKey: 'ACTION-404-STABLE',
        ),
        throwsA(
          isA<DriverTripActionException>().having(
            (error) => error.type,
            'type',
            DriverTripActionFailureType.notFound,
          ),
        ),
      );

      expect(api.paths, hasLength(1));
      expect(
        api.paths.single,
        '/api/driver/trips/TRIP-GHANA-404/actions/arrived-pickup/',
      );
      expect(api.headers, hasLength(1));
      expect(api.headers.single['Idempotency-Key'], 'ACTION-404-STABLE');
      expect(api.bodies.single, <String, Object?>{});
    });

    test('429 does not retry or assume a success-response schema', () async {
      final store = MemoryAuthTokenStore();
      await store.saveTokens(
        AuthTokens(
          accessToken: 'driver-access',
          refreshToken: 'driver-refresh',
        ),
      );
      final api = _RecordingActionApiGateway(
        responses: <ApiResponse<DriverTripActionReceipt>>[
          ApiResponse.apiFailure(
            const AsmApiException(
              type: AsmApiExceptionType.badResponse,
              message: 'Rate limited.',
              statusCode: 429,
              cause: <String, Object?>{
                'retry_after': 30,
                'body': 'not a DriverTripActionReceipt',
              },
            ),
          ),
        ],
      );
      final gateway = ApiDriverTripActionGateway(
        apiGateway: api,
        tokenStore: store,
      );

      await expectLater(
        gateway.submit(
          action: DriverTripAction.startTrip,
          tripReference: 'TRIP-GHANA-429',
          idempotencyKey: 'ACTION-429-STABLE',
        ),
        throwsA(
          isA<DriverTripActionException>().having(
            (error) => error.type,
            'type',
            DriverTripActionFailureType.rateLimited,
          ),
        ),
      );

      expect(api.paths, hasLength(1));
      expect(api.headers, hasLength(1));
      expect(api.headers.single['Idempotency-Key'], 'ACTION-429-STABLE');
      expect(api.bodies.single, <String, Object?>{});
    });

    test(
      'maps invalid_transition without exposing raw backend details',
      () async {
        final store = MemoryAuthTokenStore();
        await store.saveTokens(
          AuthTokens(
            accessToken: 'driver-access',
            refreshToken: 'driver-refresh',
          ),
        );
        final api = _RecordingActionApiGateway(
          responses: <ApiResponse<DriverTripActionReceipt>>[
            ApiResponse.apiFailure(
              const AsmApiException(
                type: AsmApiExceptionType.badResponse,
                message: 'Raw backend transition failure.',
                statusCode: 400,
                cause: <String, Object?>{
                  'code': 'invalid_transition',
                  'detail': 'Internal transition details.',
                },
              ),
            ),
          ],
        );
        final gateway = ApiDriverTripActionGateway(
          apiGateway: api,
          tokenStore: store,
        );

        await expectLater(
          gateway.submit(
            action: DriverTripAction.completeTrip,
            tripReference: 'TRIP-GHANA-001',
            idempotencyKey: 'ACTION-invalid-transition',
          ),
          throwsA(
            isA<DriverTripActionException>()
                .having(
                  (error) => error.type,
                  'type',
                  DriverTripActionFailureType.invalidTransition,
                )
                .having(
                  (error) => error.message,
                  'message',
                  isNot(contains('Internal transition details')),
                ),
          ),
        );
      },
    );
  });

  group('Driver persistent action coordinator', () {
    test(
      'network failure keeps one stable queued intent for safe retry',
      () async {
        final queue = _MemoryPersistentActionQueue();
        final gateway = _SequenceDriverTripActionGateway(
          failures: <DriverTripActionException>[
            const DriverTripActionException(
              type: DriverTripActionFailureType.temporarilyUnavailable,
              message: 'Temporary failure.',
            ),
          ],
        );
        final controller = DriverTripActionResilienceController(
          queue: queue,
          gateway: gateway,
          tripReference: 'TRIP-GHANA-002',
          driverId: 'DRIVER-002',
          verifyServerState: (action, receipt) async {
            return receipt.status == action.expectedStatus;
          },
        );

        final first = await controller.recordAction(
          eventType: 'arrived-pickup',
          payload: const <String, Object?>{'action': 'arrived-pickup'},
        );
        final second = await controller.recordAction(
          eventType: 'arrived-pickup',
          payload: const <String, Object?>{'action': 'arrived-pickup'},
        );

        expect(first.queuedOffline, isTrue);
        expect(second.canAdvance, isTrue);
        expect(queue.events, hasLength(1));
        expect(gateway.idempotencyKeys, hasLength(2));
        expect(gateway.idempotencyKeys.toSet(), hasLength(1));
        expect(queue.events.single.syncStatus, QueueSyncStatus.synced);
        expect(queue.events.single.retryCount, 0);
        expect(
          queue.events.single.eventType,
          '/api/driver/trips/TRIP-GHANA-002/'
          'actions/arrived-pickup/',
        );
        expect(queue.events.single.payloadJson, isEmpty);
      },
    );

    test('discards device timestamp before persistent enqueue', () async {
      final queue = _MemoryPersistentActionQueue();
      final gateway = _SequenceDriverTripActionGateway(
        failures: const <DriverTripActionException>[
          DriverTripActionException(
            type: DriverTripActionFailureType.temporarilyUnavailable,
            message: 'Temporary failure.',
          ),
        ],
      );
      final controller = DriverTripActionResilienceController(
        queue: queue,
        gateway: gateway,
        tripReference: 'TRIP-GHANA-EMPTY-BODY',
        driverId: 'DRIVER-EMPTY-BODY',
      );

      final result = await controller.recordAction(
        eventType: 'arrived-pickup',
        payload: const <String, Object?>{
          'device_timestamp': '2026-07-23T08:00:00Z',
          'action': 'arrived-pickup',
        },
      );

      expect(result.queuedOffline, isTrue);
      expect(queue.events, hasLength(1));
      expect(queue.events.single.payloadJson, isEmpty);
    });

    test(
      'pending action survives controller recreation with the same request',
      () async {
        final queue = _MemoryPersistentActionQueue();
        final firstGateway = _SequenceDriverTripActionGateway(
          failures: const <DriverTripActionException>[
            DriverTripActionException(
              type: DriverTripActionFailureType.temporarilyUnavailable,
              message: 'Temporary network failure.',
            ),
          ],
        );
        final firstController = DriverTripActionResilienceController(
          queue: queue,
          gateway: firstGateway,
          tripReference: 'TRIP-GHANA-RECREATE',
          driverId: 'DRIVER-RECREATE',
        );

        final firstResult = await firstController.recordAction(
          eventType: 'complete-trip',
          payload: const <String, Object?>{
            'device_timestamp': '2026-07-23T08:00:00Z',
          },
        );

        expect(firstResult.queuedOffline, isTrue);
        expect(queue.events, hasLength(1));

        final persistedBeforeRecreation = queue.events.single;
        expect(
          persistedBeforeRecreation.eventType,
          '/api/driver/trips/TRIP-GHANA-RECREATE/'
          'actions/complete-trip/',
        );
        expect(persistedBeforeRecreation.payloadJson, isEmpty);
        expect(persistedBeforeRecreation.syncStatus, QueueSyncStatus.pending);

        final secondGateway = _SequenceDriverTripActionGateway();
        final recreatedController = DriverTripActionResilienceController(
          queue: queue,
          gateway: secondGateway,
          tripReference: 'TRIP-GHANA-RECREATE',
          driverId: 'DRIVER-RECREATE',
        );

        final recovered = await recreatedController.recoverPendingActions();

        expect(recovered, hasLength(1));
        expect(recovered.single.status, 'completed_pending_review');
        expect(secondGateway.idempotencyKeys, hasLength(1));
        expect(
          secondGateway.idempotencyKeys.single,
          persistedBeforeRecreation.idempotencyKey,
        );

        expect(queue.events, hasLength(1));
        final persistedAfterRecreation = queue.events.single;
        expect(persistedAfterRecreation.id, persistedBeforeRecreation.id);
        expect(
          persistedAfterRecreation.eventType,
          persistedBeforeRecreation.eventType,
        );
        expect(
          persistedAfterRecreation.idempotencyKey,
          persistedBeforeRecreation.idempotencyKey,
        );
        expect(persistedAfterRecreation.payloadJson, isEmpty);
        expect(persistedAfterRecreation.syncStatus, QueueSyncStatus.synced);
      },
    );

    test('concurrent duplicate taps share one in-flight submission', () async {
      final queue = _MemoryPersistentActionQueue();
      final gateway = _PendingDriverTripActionGateway();
      final controller = DriverTripActionResilienceController(
        queue: queue,
        gateway: gateway,
        tripReference: 'TRIP-GHANA-003',
        driverId: 'DRIVER-003',
      );

      final first = controller.recordAction(
        eventType: 'start-trip',
        payload: const <String, Object?>{},
      );
      final second = controller.recordAction(
        eventType: 'start-trip',
        payload: const <String, Object?>{},
      );

      await Future<void>.delayed(Duration.zero);
      expect(gateway.calls, 1);
      expect(queue.events, hasLength(1));

      gateway.complete();
      final results = await Future.wait(<Future<DriverTripActionRecordResult>>[
        first,
        second,
      ]);

      expect(results, everyElement(isA<DriverTripActionRecordResult>()));
      expect(gateway.calls, 1);
      expect(queue.events.single.syncStatus, QueueSyncStatus.synced);
    });
  });

  test(
    'duplicate success waits for refreshed trip-state verification',
    () async {
      final queue = _MemoryPersistentActionQueue();
      final gateway = _SequenceDriverTripActionGateway(
        forceDuplicateSuccess: true,
      );
      var verified = false;
      var verificationCalls = 0;
      final controller = DriverTripActionResilienceController(
        queue: queue,
        gateway: gateway,
        tripReference: 'TRIP-GHANA-004',
        driverId: 'DRIVER-004',
        verifyServerState: (action, receipt) async {
          verificationCalls += 1;
          expect(receipt.status, action.expectedStatus);
          return verified;
        },
      );

      final unverified = await controller.recordAction(
        eventType: 'start-trip',
        payload: const <String, Object?>{},
      );

      expect(unverified.canAdvance, isFalse);
      expect(unverified.disposition, DriverTripActionDisposition.rejected);
      expect(queue.events, hasLength(1));
      expect(queue.events.single.syncStatus, QueueSyncStatus.pending);
      expect(queue.events.single.retryCount, 0);

      verified = true;
      final verifiedResult = await controller.recordAction(
        eventType: 'start-trip',
        payload: const <String, Object?>{},
      );

      expect(verifiedResult.canAdvance, isTrue);
      expect(
        verifiedResult.disposition,
        DriverTripActionDisposition.duplicateAcknowledged,
      );
      expect(verificationCalls, 2);
      expect(gateway.idempotencyKeys, hasLength(2));
      expect(gateway.idempotencyKeys.toSet(), hasLength(1));
      expect(queue.events.single.syncStatus, QueueSyncStatus.synced);
    },
  );

  test('idempotency conflict preserves the same pending intent', () async {
    final queue = _MemoryPersistentActionQueue();
    final gateway = _SequenceDriverTripActionGateway(
      failures: const <DriverTripActionException>[
        DriverTripActionException(
          type: DriverTripActionFailureType.idempotencyConflict,
          message: 'Conflict.',
        ),
      ],
    );
    final controller = DriverTripActionResilienceController(
      queue: queue,
      gateway: gateway,
      tripReference: 'TRIP-GHANA-005',
      driverId: 'DRIVER-005',
    );

    final result = await controller.recordAction(
      eventType: 'complete-trip',
      payload: const <String, Object?>{},
    );

    expect(result.canAdvance, isFalse);
    expect(result.disposition, DriverTripActionDisposition.rejected);
    expect(queue.events, hasLength(1));
    expect(queue.events.single.syncStatus, QueueSyncStatus.pending);
    expect(queue.events.single.retryCount, 0);
    expect(
      queue.events.single.eventType,
      '/api/driver/trips/TRIP-GHANA-005/'
      'actions/complete-trip/',
    );
  });

  group('Driver Ghana authentication parity', () {
    test('login retries network failures using 2s 4s 8s', () async {
      var attempts = 0;
      final delays = <Duration>[];

      final state = await driver_main.driverLoginWithGhanaRetry(
        delay: (duration) async => delays.add(duration),
        attempt: () async {
          attempts += 1;

          if (attempts < GhanaRequestPolicy.maxAttempts) {
            return AuthState.unauthenticated(
              AuthException(
                type: AuthExceptionType.apiFailure,
                message: 'Temporary login failure.',
                cause: const AsmApiException(
                  type: AsmApiExceptionType.network,
                  message: 'offline',
                ),
              ),
            );
          }

          return AuthState.authenticated(
            AuthSession(
              tokens: AuthTokens(
                accessToken: 'driver-access',
                refreshToken: 'driver-refresh',
              ),
              accountType: AuthAccountType.driver,
            ),
          );
        },
      );

      expect(state.isAuthenticated, isTrue);
      expect(attempts, GhanaRequestPolicy.maxAttempts);
      expect(delays, GhanaRequestPolicy.retryBackoffs);
    });

    test('invalid login credentials are not retried', () async {
      var attempts = 0;
      final delays = <Duration>[];

      final state = await driver_main.driverLoginWithGhanaRetry(
        delay: (duration) async => delays.add(duration),
        attempt: () async {
          attempts += 1;
          return const AuthState.unauthenticated(
            AuthException(
              type: AuthExceptionType.apiFailure,
              message: 'Invalid credentials.',
              cause: AsmApiException(
                type: AsmApiExceptionType.authentication,
                message: 'Unauthorized.',
                statusCode: 401,
              ),
            ),
          );
        },
      );

      expect(state.isUnauthenticated, isTrue);
      expect(attempts, 1);
      expect(delays, isEmpty);
    });

    test(
      'transient startup refresh exhaustion preserves stored tokens',
      () async {
        final store = MemoryAuthTokenStore();
        await store.saveTokens(
          AuthTokens(
            accessToken: 'stored-driver-access',
            refreshToken: 'stored-driver-refresh',
          ),
        );
        final delays = <Duration>[];
        final api = _SequenceDriverSessionRefreshApiGateway(
          List<ApiResponse<Map<String, Object?>>>.generate(
            GhanaRequestPolicy.maxAttempts,
            (_) => ApiResponse.clientException(
              const AsmApiException(
                type: AsmApiExceptionType.timeout,
                message: 'timeout',
              ),
            ),
          ),
        );
        final controller = driver_main.DriverSessionRefreshController(
          apiGateway: api,
          tokenStore: store,
          retryPolicy: GhanaRetryPolicy(
            delay: (duration) async => delays.add(duration),
          ),
        );

        final outcome = await controller.refresh();

        expect(outcome, DriverTokenRefreshOutcome.temporarilyUnavailable);
        expect(api.calls, GhanaRequestPolicy.maxAttempts);
        expect(delays, GhanaRequestPolicy.retryBackoffs);
        expect(await store.readAccessToken(), 'stored-driver-access');
        expect(await store.readRefreshToken(), 'stored-driver-refresh');
      },
    );

    test('definitive refresh rejection clears stored tokens', () async {
      final store = MemoryAuthTokenStore();
      await store.saveTokens(
        AuthTokens(
          accessToken: 'expired-driver-access',
          refreshToken: 'expired-driver-refresh',
        ),
      );
      final api = _SequenceDriverSessionRefreshApiGateway(
        <ApiResponse<Map<String, Object?>>>[
          ApiResponse.apiFailure(
            const AsmApiException(
              type: AsmApiExceptionType.authentication,
              message: 'Unauthorized.',
              statusCode: 401,
            ),
          ),
        ],
      );
      final controller = driver_main.DriverSessionRefreshController(
        apiGateway: api,
        tokenStore: store,
        retryPolicy: GhanaRetryPolicy(delay: (_) async {}),
      );

      final outcome = await controller.refresh();

      expect(outcome, DriverTokenRefreshOutcome.sessionExpired);
      expect(api.calls, 1);
      expect(await store.readAccessToken(), isNull);
      expect(await store.readRefreshToken(), isNull);
    });
  });

  group('Driver authenticated read recovery', () {
    test(
      'trip list first 401 refreshes once and retries unchanged GET',
      () async {
        final api = _SequenceDriverDutyApiClient(<ApiResponse<Object?>>[
          ApiResponse.apiFailure(
            const AsmApiException(
              type: AsmApiExceptionType.authentication,
              message: 'Unauthorized.',
              statusCode: 401,
            ),
          ),
          ApiResponse.success(<DriverAssignedTrip>[
            const DriverAssignedTrip(reference: 'TRIP-READ-001'),
          ], statusCode: 200),
        ]);
        var refreshCalls = 0;
        final gateway = AsmDriverDutyGateway.withApiClient(
          apiClient: api,
          refreshAccessToken: () async {
            refreshCalls += 1;
            return DriverTokenRefreshOutcome.refreshed;
          },
        );

        final trips = await gateway.fetchTrips();

        expect(refreshCalls, 1);
        expect(api.paths, <String>[driverTripsPath, driverTripsPath]);
        expect(trips.single.reference, 'TRIP-READ-001');
      },
    );

    test('trip detail does not loop refresh after a second 401', () async {
      final api = _SequenceDriverDutyApiClient(<ApiResponse<Object?>>[
        ApiResponse.apiFailure(
          const AsmApiException(
            type: AsmApiExceptionType.authentication,
            message: 'Unauthorized.',
            statusCode: 401,
          ),
        ),
        ApiResponse.apiFailure(
          const AsmApiException(
            type: AsmApiExceptionType.authentication,
            message: 'Unauthorized again.',
            statusCode: 401,
          ),
        ),
      ]);
      var refreshCalls = 0;
      final gateway = AsmDriverDutyGateway.withApiClient(
        apiClient: api,
        refreshAccessToken: () async {
          refreshCalls += 1;
          return DriverTokenRefreshOutcome.refreshed;
        },
      );

      await expectLater(
        gateway.fetchTripDetail('TRIP-READ-002'),
        throwsA(
          isA<DriverDutyApiException>().having(
            (error) => error.type,
            'type',
            DriverDutyApiFailureType.sessionExpired,
          ),
        ),
      );

      expect(refreshCalls, 1);
      expect(api.paths, hasLength(2));
      expect(api.paths[0], api.paths[1]);
    });
  });
}

ApiResponse<DriverTripActionReceipt> _successReceipt({
  required DriverTripAction action,
  required int statusCode,
  bool duplicate = false,
}) {
  return ApiResponse.success(
    DriverTripActionReceipt(
      tripReference: 'TRIP-GHANA-001',
      status: action.expectedStatus,
      message: 'Action confirmed.',
      duplicate: duplicate,
    ),
    statusCode: statusCode,
  );
}

final class _RecordingActionApiGateway implements DriverTripActionApiGateway {
  _RecordingActionApiGateway({
    required List<ApiResponse<DriverTripActionReceipt>> responses,
  }) : _responses = List<ApiResponse<DriverTripActionReceipt>>.from(responses);

  final List<ApiResponse<DriverTripActionReceipt>> _responses;
  final paths = <String>[];
  final bodies = <Object?>[];
  final headers = <Map<String, String>>[];

  @override
  Future<ApiResponse<T>> post<T>(
    String path, {
    Object? data,
    Map<String, String>? headers,
    JsonDecoder<T>? decoder,
  }) async {
    paths.add(path);
    bodies.add(data);
    this.headers.add(Map<String, String>.from(headers ?? const {}));
    return _responses.removeAt(0) as ApiResponse<T>;
  }
}

final class _MemoryPersistentActionQueue
    implements DriverTripActionPersistentQueue {
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
              (event.syncStatus == QueueSyncStatus.failed &&
                  event.retryCount < QueueManager.maxRetryCount),
        )
        .toList(growable: false);
  }

  @override
  Future<void> markFailed(String id) async {
    final event = await eventById(id);
    if (event == null) {
      return;
    }
    final nextRetry = event.retryCount + 1;
    await enqueue(
      event.copyWith(
        retryCount: nextRetry,
        syncStatus: nextRetry >= QueueManager.maxRetryCount
            ? QueueSyncStatus.permanentlyFailed
            : QueueSyncStatus.failed,
      ),
    );
  }

  @override
  Future<void> markPermanentlyFailed(String id) async {
    final event = await eventById(id);
    if (event != null) {
      await enqueue(
        event.copyWith(syncStatus: QueueSyncStatus.permanentlyFailed),
      );
    }
  }

  @override
  Future<void> markSynced(String id) async {
    final event = await eventById(id);
    if (event != null) {
      await enqueue(event.copyWith(syncStatus: QueueSyncStatus.synced));
    }
  }
}

final class _SequenceDriverTripActionGateway
    implements DriverTripActionGateway {
  _SequenceDriverTripActionGateway({
    List<DriverTripActionException> failures = const [],
    this.forceDuplicateSuccess = false,
  }) : _failures = List<DriverTripActionException>.from(failures);

  final List<DriverTripActionException> _failures;
  final bool forceDuplicateSuccess;
  final idempotencyKeys = <String>[];

  @override
  Future<DriverTripActionReceipt> submit({
    required DriverTripAction action,
    required String tripReference,
    required String idempotencyKey,
    Map<String, Object?> body = const <String, Object?>{},
  }) async {
    idempotencyKeys.add(idempotencyKey);
    if (_failures.isNotEmpty) {
      throw _failures.removeAt(0);
    }
    return DriverTripActionReceipt(
      tripReference: tripReference,
      status: action.expectedStatus,
      message: 'Action confirmed.',
      duplicate: forceDuplicateSuccess || idempotencyKeys.length > 1,
    );
  }
}

final class _PendingDriverTripActionGateway implements DriverTripActionGateway {
  final _completer = Completer<DriverTripActionReceipt>();
  int calls = 0;

  @override
  Future<DriverTripActionReceipt> submit({
    required DriverTripAction action,
    required String tripReference,
    required String idempotencyKey,
    Map<String, Object?> body = const <String, Object?>{},
  }) {
    calls += 1;
    return _completer.future;
  }

  void complete() {
    _completer.complete(
      const DriverTripActionReceipt(
        tripReference: 'TRIP-GHANA-003',
        status: 'in_progress',
        message: 'Trip started.',
        duplicate: false,
      ),
    );
  }
}

final class _SequenceDriverSessionRefreshApiGateway
    implements driver_main.DriverSessionRefreshApiGateway {
  _SequenceDriverSessionRefreshApiGateway(
    List<ApiResponse<Map<String, Object?>>> responses,
  ) : _responses = List<ApiResponse<Map<String, Object?>>>.from(responses);

  final List<ApiResponse<Map<String, Object?>>> _responses;
  int calls = 0;

  @override
  Future<ApiResponse<T>> post<T>(
    String path, {
    required Map<String, Object?> body,
    JsonDecoder<T>? decoder,
  }) async {
    calls += 1;
    return _responses.removeAt(0) as ApiResponse<T>;
  }
}

final class _SequenceDriverDutyApiClient implements DriverDutyApiClient {
  _SequenceDriverDutyApiClient(List<ApiResponse<Object?>> responses)
    : _responses = List<ApiResponse<Object?>>.from(responses);

  final List<ApiResponse<Object?>> _responses;
  final paths = <String>[];

  @override
  Future<ApiResponse<T>> get<T>(String path, {JsonDecoder<T>? decoder}) async {
    paths.add(path);
    final response = _responses.removeAt(0);
    final error = response.error;

    if (error != null) {
      return ApiResponse<T>.apiFailure(error);
    }

    if (!response.isSuccess) {
      throw StateError(
        'The Driver read test response had no success data or error.',
      );
    }

    final data = response.data;
    if (data == null) {
      throw StateError('The successful Driver read test response had no data.');
    }

    return ApiResponse<T>.success(data as T, statusCode: response.statusCode);
  }
}
