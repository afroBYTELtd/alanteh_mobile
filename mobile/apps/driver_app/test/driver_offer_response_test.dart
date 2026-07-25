import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_auth/asm_auth.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:asm_offline_queue/asm_offline_queue.dart';
import 'package:driver_app/driver_duty_trips.dart';
import 'package:driver_app/main.dart' as driver_main;
import 'package:driver_app/network/driver_offer_response_gateway.dart';
import 'package:driver_app/network/driver_offer_response_resilience.dart';
import 'package:driver_app/network/driver_trip_action_gateway.dart';
import 'package:driver_app/network/driver_trip_action_resilience.dart';
import 'package:driver_app/network/ghana_network_resilience.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('test_valid_session_reaches_request_sent', () async {
    final store = MemoryAuthTokenStore();
    await store.saveTokens(
      AuthTokens(
        accessToken: 'diagnostic-access-token',
        refreshToken: 'diagnostic-refresh-token',
      ),
    );
    final api = _ArrivedDiagnosticsActionApi(
      response: ApiResponse.success(
        const DriverTripActionReceipt(
          tripReference: 'TRIP-DIAGNOSTICS-VALID',
          status: 'arrived_at_pickup',
          message: 'Arrival confirmed.',
          duplicate: false,
        ),
        statusCode: 201,
      ),
    );
    final events = <DriverTripActionTelemetryEvent>[];
    final gateway = ApiDriverTripActionGateway(
      apiGateway: api,
      tokenStore: store,
    )..attachSubmissionTelemetrySink(events.add);

    final receipt = await gateway.submit(
      action: DriverTripAction.arrivedPickup,
      tripReference: 'TRIP-DIAGNOSTICS-VALID',
      idempotencyKey: 'DIAGNOSTIC-IDEMPOTENCY-KEY',
    );

    expect(receipt.status, 'arrived_at_pickup');
    expect(api.calls, 1);
    expect(api.paths, <String>[
      '/api/driver/trips/TRIP-DIAGNOSTICS-VALID/'
          'actions/arrived-pickup/',
    ]);
    expect(
      events.map((event) => event.stage).toList(),
      <DriverTripActionTelemetryStage>[
        DriverTripActionTelemetryStage.tokenCheck,
        DriverTripActionTelemetryStage.requestSent,
        DriverTripActionTelemetryStage.httpStatusClass,
      ],
    );
    expect(events[0].qaDisplayText, 'TOKEN_CHECK: TOKEN_PRESENT');
    expect(events[1].qaDisplayText, 'REQUEST_SENT');
    expect(events[2].qaDisplayText, 'HTTP_STATUS_CLASS: 2xx');

    final display = events.map((event) => event.qaDisplayText).join('|');
    for (final forbidden in const <String>[
      'TRIP-DIAGNOSTICS-VALID',
      'diagnostic-access-token',
      'diagnostic-refresh-token',
      'DIAGNOSTIC-IDEMPOTENCY-KEY',
      'Authorization',
      'Bearer ',
      'https://',
      'http://',
    ]) {
      expect(display, isNot(contains(forbidden)));
    }
  });

  test('test_in_flight_guard_resets_after_offer_response', () async {
    final offerQueue = _MemoryOfferQueue();
    final offerGateway = _RecordingOfferGateway();
    final offerController = _controller(
      queue: offerQueue,
      gateway: offerGateway,
    );

    final offerResult = await offerController.accept();

    expect(offerResult.accepted, isTrue);
    expect(offerGateway.calls, 1);

    final actionQueue = _ArrivedDiagnosticsOfferActionQueue();
    final actionGateway = _ArrivedDiagnosticsOfferActionGateway();
    final actionController = DriverTripActionResilienceController(
      queue: actionQueue,
      gateway: actionGateway,
      tripReference: 'TRIP-DIAGNOSTICS-AFTER-OFFER',
      driverId: 'DRIVER-DIAGNOSTICS-AFTER-OFFER',
    );

    final actionResult = await actionController.recordAction(
      eventType: 'arrived-pickup',
      payload: const <String, Object?>{},
    );

    expect(actionResult.canAdvance, isTrue);
    expect(actionGateway.calls, 1);
    expect(actionQueue.events, hasLength(1));
    expect(actionQueue.events.single.syncStatus, QueueSyncStatus.synced);
  });

  group('Driver offer-response gateway', () {
    test(
      'uses exact endpoint, bearer token, stable key, and exact body',
      () async {
        final accessToken = _jwtExpiringAt(DateTime.utc(2100));
        final store = await _tokenStore(accessToken: accessToken);
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
        expect(api.headers.single['Authorization'], 'Bearer $accessToken');
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
      final initialAccessToken = _jwtExpiringAt(DateTime.utc(2100));
      final store = await _tokenStore(accessToken: initialAccessToken);
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
        'Bearer $initialAccessToken',
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

  group('MOBILE-DRIVER-TOKEN-REFRESH-BEFORE-OFFER', () {
    final now = DateTime.utc(2026, 7, 25, 5);

    test('test_valid_token_proceeds_without_refresh', () async {
      final store = await _tokenStore(
        accessToken: _jwtExpiringAt(now.add(const Duration(seconds: 61))),
      );
      final api = _RecordingOfferApi(
        responses: <ApiResponse<DriverOfferResponseReceipt>>[
          _offerSuccess(statusCode: 201),
        ],
      );
      var refreshCalls = 0;
      final events = <DriverOfferSubmissionTelemetryEvent>[];
      final gateway = ApiDriverOfferResponseGateway(
        apiGateway: api,
        tokenStore: store,
        utcNow: () => now,
        refreshAccessToken: () async {
          refreshCalls += 1;
          return DriverTokenRefreshOutcome.refreshed;
        },
      );

      await gateway.accept(
        tripReference: 'TRIP-TOKEN-VALID',
        idempotencyKey: 'DRIVER-OFFER-TRIP-TOKEN-VALID-stable',
        deviceTimestamp: '2026-07-25T05:00:00.000Z',
        telemetrySink: events.add,
      );

      expect(refreshCalls, 0);
      expect(api.paths, hasLength(1));
      expect(_telemetryTexts(events), <String>[
        'TOKEN_CHECK: TOKEN_VALID',
        'REQUEST_SENT',
        'HTTP_STATUS_CLASS: 2xx',
      ]);
    });

    test('test_expired_token_triggers_refresh', () async {
      final store = await _tokenStore(
        accessToken: _jwtExpiringAt(now.subtract(const Duration(seconds: 1))),
      );
      final api = _RecordingOfferApi(
        responses: <ApiResponse<DriverOfferResponseReceipt>>[
          _offerSuccess(statusCode: 201),
        ],
      );
      var refreshCalls = 0;
      final events = <DriverOfferSubmissionTelemetryEvent>[];
      final gateway = ApiDriverOfferResponseGateway(
        apiGateway: api,
        tokenStore: store,
        utcNow: () => now,
        refreshAccessToken: () async {
          refreshCalls += 1;
          await store.saveTokens(
            AuthTokens(
              accessToken: _jwtExpiringAt(now.add(const Duration(hours: 1))),
              refreshToken: 'driver-refresh',
            ),
          );
          return DriverTokenRefreshOutcome.refreshed;
        },
      );

      await gateway.accept(
        tripReference: 'TRIP-TOKEN-EXPIRED',
        idempotencyKey: 'DRIVER-OFFER-TRIP-TOKEN-EXPIRED-stable',
        deviceTimestamp: '2026-07-25T05:01:00.000Z',
        telemetrySink: events.add,
      );

      expect(refreshCalls, 1);
      expect(api.paths, hasLength(1));
      expect(_telemetryTexts(events).first, 'TOKEN_CHECK: TOKEN_REFRESHED');
    });

    test('test_near_expiry_token_triggers_refresh', () async {
      final store = await _tokenStore(
        accessToken: _jwtExpiringAt(now.add(const Duration(seconds: 60))),
      );
      final api = _RecordingOfferApi(
        responses: <ApiResponse<DriverOfferResponseReceipt>>[
          _offerSuccess(statusCode: 201),
        ],
      );
      var refreshCalls = 0;
      final gateway = ApiDriverOfferResponseGateway(
        apiGateway: api,
        tokenStore: store,
        utcNow: () => now,
        refreshAccessToken: () async {
          refreshCalls += 1;
          await store.saveTokens(
            AuthTokens(
              accessToken: _jwtExpiringAt(now.add(const Duration(hours: 1))),
              refreshToken: 'driver-refresh',
            ),
          );
          return DriverTokenRefreshOutcome.refreshed;
        },
      );

      await gateway.accept(
        tripReference: 'TRIP-TOKEN-NEAR-EXPIRY',
        idempotencyKey: 'DRIVER-OFFER-TRIP-TOKEN-NEAR-EXPIRY-stable',
        deviceTimestamp: '2026-07-25T05:02:00.000Z',
      );

      expect(refreshCalls, 1);
      expect(api.paths, hasLength(1));
    });

    test('test_refresh_failure_blocks_post', () async {
      final store = await _tokenStore(accessToken: _jwtExpiringAt(now));
      final api = _RecordingOfferApi(
        responses: <ApiResponse<DriverOfferResponseReceipt>>[
          _offerSuccess(statusCode: 201),
        ],
      );
      final events = <DriverOfferSubmissionTelemetryEvent>[];
      final gateway = ApiDriverOfferResponseGateway(
        apiGateway: api,
        tokenStore: store,
        utcNow: () => now,
        refreshAccessToken: () async =>
            DriverTokenRefreshOutcome.sessionExpired,
      );

      await expectLater(
        gateway.accept(
          tripReference: 'TRIP-REFRESH-FAILURE',
          idempotencyKey: 'DRIVER-OFFER-TRIP-REFRESH-FAILURE-stable',
          deviceTimestamp: '2026-07-25T05:03:00.000Z',
          telemetrySink: events.add,
        ),
        throwsA(
          isA<DriverOfferResponseException>()
              .having(
                (error) => error.type,
                'type',
                DriverOfferResponseFailureType.signInRequired,
              )
              .having(
                (error) => error.message,
                'message',
                driverOfferSessionExpiredMessage,
              ),
        ),
      );

      expect(api.paths, isEmpty);
      expect(_telemetryTexts(events), <String>[
        'TOKEN_CHECK: TOKEN_REFRESH_FAILED',
      ]);
    });

    test('test_refresh_network_failure_blocks_post', () async {
      final store = await _tokenStore(accessToken: _jwtExpiringAt(now));
      final api = _RecordingOfferApi(
        responses: <ApiResponse<DriverOfferResponseReceipt>>[
          _offerSuccess(statusCode: 201),
        ],
      );
      final events = <DriverOfferSubmissionTelemetryEvent>[];
      final gateway = ApiDriverOfferResponseGateway(
        apiGateway: api,
        tokenStore: store,
        utcNow: () => now,
        refreshAccessToken: () async {
          throw const AsmApiException(
            type: AsmApiExceptionType.network,
            message: 'Private network detail.',
          );
        },
      );

      await expectLater(
        gateway.accept(
          tripReference: 'TRIP-REFRESH-NETWORK-FAILURE',
          idempotencyKey: 'DRIVER-OFFER-TRIP-REFRESH-NETWORK-FAILURE-stable',
          deviceTimestamp: '2026-07-25T05:04:00.000Z',
          telemetrySink: events.add,
        ),
        throwsA(
          isA<DriverOfferResponseException>()
              .having(
                (error) => error.type,
                'type',
                DriverOfferResponseFailureType.signInRequired,
              )
              .having(
                (error) => error.message,
                'message',
                driverOfferSessionExpiredMessage,
              ),
        ),
      );

      expect(api.paths, isEmpty);
      expect(_telemetryTexts(events), <String>[
        'TOKEN_CHECK: TOKEN_REFRESH_FAILED',
      ]);
    });

    test('test_persistent_record_preserved_after_refresh_failure', () async {
      final store = await _tokenStore(accessToken: _jwtExpiringAt(now));
      final api = _RecordingOfferApi(
        responses: <ApiResponse<DriverOfferResponseReceipt>>[
          _offerSuccess(statusCode: 201),
        ],
      );
      final queue = _MemoryOfferQueue();
      final controller = _controller(
        queue: queue,
        gateway: ApiDriverOfferResponseGateway(
          apiGateway: api,
          tokenStore: store,
          utcNow: () => now,
          refreshAccessToken: () async =>
              DriverTokenRefreshOutcome.sessionExpired,
        ),
        utcNow: () => now,
      );
      final events = <DriverOfferSubmissionTelemetryEvent>[];
      final sessionMessages = <String>[];
      controller.attachSubmissionTelemetrySink(events.add);
      controller.attachSessionExpiredHandler((message) async {
        sessionMessages.add(message);
      });

      final result = await controller.accept();

      expect(result.accepted, isFalse);
      expect(result.permitsManualRetry, isFalse);
      expect(result.message, driverOfferSessionExpiredMessage);
      expect(api.paths, isEmpty);
      expect(queue.events, hasLength(1));
      expect(queue.events.single.syncStatus, QueueSyncStatus.pending);
      expect(queue.markSyncedCalls, 0);
      expect(sessionMessages, <String>[driverOfferSessionExpiredMessage]);
      expect(_telemetryTexts(events), <String>[
        'SUBMIT_START',
        'TOKEN_CHECK: TOKEN_REFRESH_FAILED',
        'QUEUE_STATE: pending',
      ]);
    });

    test(
      'malformed missing nonnumeric and invalid exp trigger refresh',
      () async {
        final invalidTokens = <String>[
          'not-a-jwt',
          _jwtWithPayload(const <String, Object?>{}),
          _jwtWithPayload(const <String, Object?>{'exp': 'later'}),
          _jwtWithPayload(const <String, Object?>{'exp': null}),
          _jwtWithPayload(const <String, Object?>{'exp': -1}),
        ];

        for (final invalidToken in invalidTokens) {
          final store = await _tokenStore(accessToken: invalidToken);
          final api = _RecordingOfferApi(
            responses: <ApiResponse<DriverOfferResponseReceipt>>[
              _offerSuccess(statusCode: 201),
            ],
          );
          var refreshCalls = 0;
          final gateway = ApiDriverOfferResponseGateway(
            apiGateway: api,
            tokenStore: store,
            utcNow: () => now,
            refreshAccessToken: () async {
              refreshCalls += 1;
              await store.saveTokens(
                AuthTokens(
                  accessToken: _jwtExpiringAt(
                    now.add(const Duration(hours: 1)),
                  ),
                  refreshToken: 'driver-refresh',
                ),
              );
              return DriverTokenRefreshOutcome.refreshed;
            },
          );

          await gateway.accept(
            tripReference: 'TRIP-INVALID-EXP',
            idempotencyKey: 'DRIVER-OFFER-TRIP-INVALID-EXP-stable',
            deviceTimestamp: '2026-07-25T05:05:00.000Z',
          );

          expect(refreshCalls, 1, reason: invalidToken);
          expect(api.paths, hasLength(1), reason: invalidToken);
        }
      },
    );
  });

  group('Sanitized offer submission telemetry', () {
    test(
      'initialization-only registers all seven hooks with no side effects',
      () {
        final tokenStore = _CountingAuthTokenStore();
        final api = _RecordingOfferApi(
          responses: <ApiResponse<DriverOfferResponseReceipt>>[
            _offerSuccess(statusCode: 201),
          ],
        );
        final queue = _MemoryOfferQueue();

        final initialization = initializeDriverOfferSubmissionTelemetryHooks();

        expect(initialization.allHooksRegistered, isTrue);
        expect(initialization.hookCodes, <String>[
          'SUBMIT_START',
          'TOKEN_CHECK',
          'REQUEST_SENT',
          'HTTP_STATUS_CLASS',
          'RETRY_ATTEMPT_N',
          'QUEUE_STATE',
          'RECEIPT_CHECK',
        ]);
        expect(
          initialization.qaDisplayText,
          'TELEMETRY_INIT_ONLY: ALL_7_HOOKS_REGISTERED '
          '[SUBMIT_START, TOKEN_CHECK, REQUEST_SENT, '
          'HTTP_STATUS_CLASS, RETRY_ATTEMPT_N, QUEUE_STATE, '
          'RECEIPT_CHECK]',
        );
        expect(tokenStore.accessTokenReads, 0);
        expect(tokenStore.refreshTokenReads, 0);
        expect(tokenStore.saveCalls, 0);
        expect(tokenStore.clearCalls, 0);
        expect(api.paths, isEmpty);
        expect(queue.events, isEmpty);
        expect(queue.enqueueCalls, 0);
        expect(queue.eventByIdCalls, 0);
        expect(queue.pendingEventsCalls, 0);
        expect(queue.markSyncedCalls, 0);
      },
    );

    test('ordered 201 telemetry follows persistent synchronization', () async {
      final store = await _tokenStore();
      final api = _RecordingOfferApi(
        responses: <ApiResponse<DriverOfferResponseReceipt>>[
          _offerSuccess(statusCode: 201),
        ],
      );
      final queue = _MemoryOfferQueue();
      final gateway = ApiDriverOfferResponseGateway(
        apiGateway: api,
        tokenStore: store,
      );
      final controller = _controller(
        queue: queue,
        gateway: gateway,
        utcNow: () => DateTime.utc(2026, 7, 25, 4),
      );
      final events = <DriverOfferSubmissionTelemetryEvent>[];

      controller.attachSubmissionTelemetrySink((event) {
        if (event.stage == DriverOfferSubmissionTelemetryStage.receiptCheck) {
          expect(queue.events.single.syncStatus, QueueSyncStatus.synced);
        }
        events.add(event);
      });

      final result = await controller.accept();

      expect(result.accepted, isTrue);
      expect(_telemetryTexts(events), <String>[
        'SUBMIT_START',
        'QUEUE_STATE: queued',
        'TOKEN_CHECK: TOKEN_VALID',
        'REQUEST_SENT',
        'HTTP_STATUS_CLASS: 2xx',
        'QUEUE_STATE: dequeued',
        'RECEIPT_CHECK',
      ]);
      expect(api.paths, hasLength(1));
      expect(queue.markSyncedCalls, 1);
      expect(queue.events.single.syncStatus, QueueSyncStatus.synced);
    });

    test('ordered valid 200 duplicate telemetry is accepted', () async {
      final store = await _tokenStore();
      final api = _RecordingOfferApi(
        responses: <ApiResponse<DriverOfferResponseReceipt>>[
          _offerSuccess(statusCode: 200, duplicate: true),
        ],
      );
      final queue = _MemoryOfferQueue();
      final controller = _controller(
        queue: queue,
        gateway: ApiDriverOfferResponseGateway(
          apiGateway: api,
          tokenStore: store,
        ),
      );
      final events = <DriverOfferSubmissionTelemetryEvent>[];
      controller.attachSubmissionTelemetrySink(events.add);

      final result = await controller.accept();

      expect(
        result.disposition,
        DriverOfferAcceptanceDisposition.duplicateRecovered,
      );
      expect(_telemetryTexts(events), <String>[
        'SUBMIT_START',
        'QUEUE_STATE: queued',
        'TOKEN_CHECK: TOKEN_VALID',
        'REQUEST_SENT',
        'HTTP_STATUS_CLASS: 2xx',
        'QUEUE_STATE: dequeued',
        'RECEIPT_CHECK',
      ]);
      expect(api.paths, hasLength(1));
      expect(queue.markSyncedCalls, 1);
    });

    test('4xx emits class once, does not retry, and stays pending', () async {
      final store = await _tokenStore();
      final api = _RecordingOfferApi(
        responses: <ApiResponse<DriverOfferResponseReceipt>>[
          _offerFailure(400),
        ],
      );
      final queue = _MemoryOfferQueue();
      final controller = _controller(
        queue: queue,
        gateway: ApiDriverOfferResponseGateway(
          apiGateway: api,
          tokenStore: store,
        ),
        utcNow: () => DateTime.utc(2026, 7, 25, 4, 5),
      );
      final events = <DriverOfferSubmissionTelemetryEvent>[];
      controller.attachSubmissionTelemetrySink(events.add);

      final result = await controller.accept();

      expect(result.accepted, isFalse);
      expect(_telemetryTexts(events), <String>[
        'SUBMIT_START',
        'QUEUE_STATE: queued',
        'TOKEN_CHECK: TOKEN_VALID',
        'REQUEST_SENT',
        'HTTP_STATUS_CLASS: 4xx',
        'QUEUE_STATE: pending',
      ]);
      expect(api.paths, hasLength(1));
      expect(queue.enqueueCalls, 2);
      expect(queue.markSyncedCalls, 0);
      expect(queue.events.single.syncStatus, QueueSyncStatus.pending);
    });

    test(
      '5xx retries preserve 2s 4s 8s, key, timestamp, and event order',
      () async {
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
        final queue = _MemoryOfferQueue();
        final controller = _controller(
          queue: queue,
          gateway: ApiDriverOfferResponseGateway(
            apiGateway: api,
            tokenStore: store,
            retryPolicy: GhanaRetryPolicy(
              delay: (duration) async => delays.add(duration),
            ),
          ),
          utcNow: () => DateTime.utc(2026, 7, 25, 4, 10),
        );
        final events = <DriverOfferSubmissionTelemetryEvent>[];
        controller.attachSubmissionTelemetrySink(events.add);

        final result = await controller.accept();

        expect(result.accepted, isTrue);
        expect(delays, <Duration>[
          const Duration(seconds: 2),
          const Duration(seconds: 4),
          const Duration(seconds: 8),
        ]);
        expect(_telemetryTexts(events), <String>[
          'SUBMIT_START',
          'QUEUE_STATE: queued',
          'TOKEN_CHECK: TOKEN_VALID',
          'REQUEST_SENT',
          'HTTP_STATUS_CLASS: 5xx',
          'RETRY_ATTEMPT_N: 1',
          'REQUEST_SENT',
          'HTTP_STATUS_CLASS: 5xx',
          'RETRY_ATTEMPT_N: 2',
          'REQUEST_SENT',
          'HTTP_STATUS_CLASS: 5xx',
          'RETRY_ATTEMPT_N: 3',
          'REQUEST_SENT',
          'HTTP_STATUS_CLASS: 2xx',
          'QUEUE_STATE: dequeued',
          'RECEIPT_CHECK',
        ]);
        expect(api.paths, hasLength(4));
        expect(
          api.headers.map((value) => value['Idempotency-Key']).toSet(),
          hasLength(1),
        );
        expect(
          api.bodies
              .map(
                (value) => (value as Map<String, Object?>)['device_timestamp'],
              )
              .toSet(),
          hasLength(1),
        );
      },
    );

    test('proven timeout emits only timeout HTTP classes', () async {
      final store = await _tokenStore();
      final api = _RecordingOfferApi(
        responses: List<ApiResponse<DriverOfferResponseReceipt>>.generate(
          4,
          (_) => _offerClientException(AsmApiExceptionType.timeout),
        ),
      );
      final queue = _MemoryOfferQueue();
      final controller = _controller(
        queue: queue,
        gateway: ApiDriverOfferResponseGateway(
          apiGateway: api,
          tokenStore: store,
          retryPolicy: GhanaRetryPolicy(delay: (_) async {}),
        ),
      );
      final events = <DriverOfferSubmissionTelemetryEvent>[];
      controller.attachSubmissionTelemetrySink(events.add);

      final result = await controller.accept();
      final texts = _telemetryTexts(events);

      expect(result.accepted, isFalse);
      expect(
        texts.where((value) => value == 'HTTP_STATUS_CLASS: timeout'),
        hasLength(4),
      );
      expect(texts, isNot(contains('HTTP_STATUS_CLASS: 4xx')));
      expect(texts, isNot(contains('HTTP_STATUS_CLASS: 5xx')));
      expect(texts.last, 'QUEUE_STATE: pending');
    });

    test(
      'non-timeout transport failure fabricates no HTTP status class',
      () async {
        final store = await _tokenStore();
        final api = _RecordingOfferApi(
          responses: List<ApiResponse<DriverOfferResponseReceipt>>.generate(
            4,
            (_) => _offerClientException(AsmApiExceptionType.network),
          ),
        );
        final queue = _MemoryOfferQueue();
        final controller = _controller(
          queue: queue,
          gateway: ApiDriverOfferResponseGateway(
            apiGateway: api,
            tokenStore: store,
            retryPolicy: GhanaRetryPolicy(delay: (_) async {}),
          ),
        );
        final events = <DriverOfferSubmissionTelemetryEvent>[];
        controller.attachSubmissionTelemetrySink(events.add);

        final result = await controller.accept();
        final texts = _telemetryTexts(events);

        expect(result.accepted, isFalse);
        expect(api.paths, hasLength(4));
        expect(
          texts.where((value) => value.startsWith('HTTP_STATUS_CLASS')),
          isEmpty,
        );
        expect(texts.where((value) => value == 'REQUEST_SENT'), hasLength(4));
        expect(texts.last, 'QUEUE_STATE: pending');
      },
    );

    test('REQUEST_SENT is present before every transport invocation', () async {
      final store = await _tokenStore();
      final events = <DriverOfferSubmissionTelemetryEvent>[];
      final api = _RecordingOfferApi(
        responses: <ApiResponse<DriverOfferResponseReceipt>>[
          _offerFailure(503),
          _offerSuccess(statusCode: 201),
        ],
        beforePost: (_) {
          expect(events.last.qaDisplayText, 'REQUEST_SENT');
        },
      );
      final queue = _MemoryOfferQueue();
      final controller = _controller(
        queue: queue,
        gateway: ApiDriverOfferResponseGateway(
          apiGateway: api,
          tokenStore: store,
          retryPolicy: GhanaRetryPolicy(delay: (_) async {}),
        ),
      );
      controller.attachSubmissionTelemetrySink(events.add);

      await controller.accept();

      expect(api.paths, hasLength(2));
      expect(
        _telemetryTexts(events).where((value) => value == 'REQUEST_SENT'),
        hasLength(2),
      );
    });

    test(
      'receipt persistence failure emits pending and no receipt check',
      () async {
        final store = await _tokenStore();
        final api = _RecordingOfferApi(
          responses: <ApiResponse<DriverOfferResponseReceipt>>[
            _offerSuccess(statusCode: 201),
          ],
        );
        final queue = _MemoryOfferQueue(throwOnMarkSynced: true);
        final controller = _controller(
          queue: queue,
          gateway: ApiDriverOfferResponseGateway(
            apiGateway: api,
            tokenStore: store,
          ),
        );
        final events = <DriverOfferSubmissionTelemetryEvent>[];
        controller.attachSubmissionTelemetrySink(events.add);

        await expectLater(controller.accept(), throwsStateError);

        final texts = _telemetryTexts(events);
        expect(texts, contains('HTTP_STATUS_CLASS: 2xx'));
        expect(texts, isNot(contains('QUEUE_STATE: dequeued')));
        expect(texts, isNot(contains('RECEIPT_CHECK')));
        expect(texts.last, 'QUEUE_STATE: pending');
        expect(queue.markSyncedCalls, 1);
        expect(queue.events.single.syncStatus, QueueSyncStatus.pending);
      },
    );

    test('telemetry display values are closed-set and privacy safe', () {
      const sensitiveMarkers = <String>[
        'TRIP-PRIVATE-001',
        'DRIVER-PRIVATE-001',
        '233000000000',
        '1234',
        'private-token',
        'Authorization',
        'Idempotency-Key',
        'device_timestamp',
        'private-exception',
        '/private/database/path',
      ];
      final events = <DriverOfferSubmissionTelemetryEvent>[
        const DriverOfferSubmissionTelemetryEvent.submitStart(),
        const DriverOfferSubmissionTelemetryEvent.tokenCheck(
          DriverOfferSubmissionTokenCheckOutcome.tokenValid,
        ),
        const DriverOfferSubmissionTelemetryEvent.requestSent(),
        const DriverOfferSubmissionTelemetryEvent.httpStatusClass(
          DriverOfferSubmissionHttpStatusClass.success2xx,
        ),
        const DriverOfferSubmissionTelemetryEvent.httpStatusClass(
          DriverOfferSubmissionHttpStatusClass.client4xx,
        ),
        const DriverOfferSubmissionTelemetryEvent.httpStatusClass(
          DriverOfferSubmissionHttpStatusClass.server5xx,
        ),
        const DriverOfferSubmissionTelemetryEvent.httpStatusClass(
          DriverOfferSubmissionHttpStatusClass.timeout,
        ),
        const DriverOfferSubmissionTelemetryEvent.retryAttempt(
          DriverOfferSubmissionRetryAttempt.one,
        ),
        const DriverOfferSubmissionTelemetryEvent.retryAttempt(
          DriverOfferSubmissionRetryAttempt.two,
        ),
        const DriverOfferSubmissionTelemetryEvent.retryAttempt(
          DriverOfferSubmissionRetryAttempt.three,
        ),
        const DriverOfferSubmissionTelemetryEvent.queueState(
          DriverOfferSubmissionQueueState.queued,
        ),
        const DriverOfferSubmissionTelemetryEvent.queueState(
          DriverOfferSubmissionQueueState.dequeued,
        ),
        const DriverOfferSubmissionTelemetryEvent.queueState(
          DriverOfferSubmissionQueueState.pending,
        ),
        const DriverOfferSubmissionTelemetryEvent.queueState(
          DriverOfferSubmissionQueueState.failed,
        ),
        const DriverOfferSubmissionTelemetryEvent.receiptCheck(),
      ];

      final text = _telemetryTexts(events).join('\n');

      for (final marker in sensitiveMarkers) {
        expect(text, isNot(contains(marker)));
      }
      expect(
        _telemetryTexts(events),
        everyElement(
          matches(
            RegExp(
              r'^(SUBMIT_START|TOKEN_CHECK: (TOKEN_VALID|'
              r'TOKEN_REFRESHED|TOKEN_REFRESH_FAILED)|REQUEST_SENT|'
              r'HTTP_STATUS_CLASS: (2xx|4xx|5xx|timeout)|'
              r'RETRY_ATTEMPT_N: [123]|'
              r'QUEUE_STATE: (queued|dequeued|pending|failed)|'
              r'RECEIPT_CHECK)$',
            ),
          ),
        ),
      );
    });
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

  group('Driver duty production response parser', () {
    test('test_exact_production_response_shape', () {
      final summary = DriverDutySummary.fromJson(const <String, Object?>{
        'driver': <String, Object?>{'driver_reference': 'QA-DRV-001'},
        'duty': <String, Object?>{
          'can_receive_assignments': true,
          'active_trip_count': 1,
          'assigned_trip_count': 2,
        },
      });

      expect(summary.driverReference, 'QA-DRV-001');
      expect(summary.canReceiveAssignments, isTrue);
      expect(summary.activeTripCount, 1);
      expect(summary.assignedTripCount, 2);
    });

    test('test_valid_nested_driver_reference', () {
      final summary = DriverDutySummary.fromJson(const <String, Object?>{
        'driver': <String, Object?>{'driver_reference': '  QA-DRV-001  '},
      });

      expect(summary.driverReference, 'QA-DRV-001');
    });

    test('test_missing_driver_object', () {
      final summary = DriverDutySummary.fromJson(const <String, Object?>{});

      expect(summary.driverReference, isNull);
    });

    test('test_null_driver_reference_value', () {
      final summary = DriverDutySummary.fromJson(const <String, Object?>{
        'driver': <String, Object?>{'driver_reference': null},
      });

      expect(summary.driverReference, isNull);
    });

    test('test_blank_driver_reference_value', () {
      for (final value in <String>['', '   ']) {
        final summary = DriverDutySummary.fromJson(<String, Object?>{
          'driver': <String, Object?>{'driver_reference': value},
        });

        expect(summary.driverReference, isNull, reason: 'value=<$value>');
      }
    });

    test('test_wrong_value_type', () {
      for (final value in <Object?>[
        42,
        true,
        const <String, Object?>{'unexpected': 'map'},
        const <Object?>['unexpected', 'list'],
      ]) {
        final summary = DriverDutySummary.fromJson(<String, Object?>{
          'driver': <String, Object?>{'driver_reference': value},
        });

        expect(summary.driverReference, isNull, reason: 'value=$value');
      }
    });

    test('test_nested_duty_fields', () {
      final summary = DriverDutySummary.fromJson(const <String, Object?>{
        'duty': <String, Object?>{
          'can_receive_assignments': true,
          'active_trip_count': 3,
          'assigned_trip_count': 4,
        },
      });

      expect(summary.canReceiveAssignments, isTrue);
      expect(summary.activeTripCount, 3);
      expect(summary.assignedTripCount, 4);
    });

    test('test_duty_does_not_supply_driver_reference', () {
      final summary = DriverDutySummary.fromJson(const <String, Object?>{
        'duty': <String, Object?>{
          'driver_reference': 'DUTY-MUST-NOT-BE-USED',
          'can_receive_assignments': true,
          'active_trip_count': 1,
          'assigned_trip_count': 1,
        },
      });

      expect(summary.driverReference, isNull);
    });

    test('test_root_level_legacy_fields_do_not_populate_driver_reference', () {
      final summary = DriverDutySummary.fromJson(const <String, Object?>{
        'driver_reference': 'ROOT-DRIVER-REFERENCE',
        'driver_code': 'ROOT-DRIVER-CODE',
        'reference': 'ROOT-REFERENCE',
        'code': 'ROOT-CODE',
      });

      expect(summary.driverReference, isNull);
    });

    test('test_production_factory_receives_mapped_reference', () async {
      final summary = DriverDutySummary.fromJson(const <String, Object?>{
        'driver': <String, Object?>{'driver_reference': '  QA-DRV-001  '},
        'duty': <String, Object?>{
          'can_receive_assignments': true,
          'active_trip_count': 0,
          'assigned_trip_count': 1,
        },
      });
      final queue = _MemoryOfferQueue();
      final offerGateway = _RecordingOfferGateway();
      final dutyGateway = _DiagnosticDutyGateway(
        onFetchDuty: () async => summary,
        detail: _trip(status: 'driver_offer_sent'),
      );

      final controller = await _diagnosticProductionFactory(
        dutyGateway: dutyGateway,
        queue: queue,
        offerGateway: offerGateway,
      )('TRIP-OFFER-001');

      final prepared = await controller.prepareWhenOfferDisplayed();

      expect(prepared.driverId, 'QA-DRV-001');
      expect(offerGateway.calls, 0);
      expect(await queue.pendingEvents(), hasLength(1));
    });
  });

  group('Typed offer-preparation diagnostics', () {
    test('exact sanitized preparation codes remain stable', () {
      expect(
        DriverOfferPreparationFailureCode.values.map((code) => code.value),
        <String>[
          'factory_unavailable',
          'driver_duty_fetch_failed',
          'driver_reference_missing',
          'persistent_queue_open_or_read_failed',
          'conflicting_offer_record',
          'invalid_offer_record',
          'queue_enqueue_failed',
        ],
      );
    });

    testWidgets(
      'production-style preparation enables Accept only after persistence',
      (tester) async {
        final queue = _MemoryOfferQueue();

        final dutyGateway = _DiagnosticDutyGateway(
          onFetchDuty: () async =>
              const DriverDutySummary(driverReference: 'DRIVER-001'),
          detail: _trip(status: 'driver_offer_sent'),
        );
        final offerGateway = _RecordingOfferGateway();

        await _pumpDiagnosticOffer(
          tester,
          dutyGateway: dutyGateway,
          factory: _diagnosticProductionFactory(
            dutyGateway: dutyGateway,
            queue: queue,
            offerGateway: offerGateway,
          ),
        );

        expect(find.text('PREP_READY'), findsOneWidget);
        expect(_acceptButton(tester).onPressed, isNotNull);
        expect(offerGateway.calls, 0);
        expect(queue.events, hasLength(1));
      },
    );

    testWidgets(
      'factory unavailable is exact and preserves all fail-closed gates',
      (tester) async {
        final dutyGateway = _DiagnosticDutyGateway(
          onFetchDuty: () async =>
              const DriverDutySummary(driverReference: 'DRIVER-001'),
          detail: _trip(status: 'driver_offer_sent'),
        );

        await _pumpDiagnosticOffer(
          tester,
          dutyGateway: dutyGateway,
          factory: null,
        );

        expect(find.text('PREP_FAILED: factory_unavailable'), findsOneWidget);
        expect(_acceptButton(tester).onPressed, isNull);
        expect(
          find.byKey(const Key('driver-offer-preparation-retry')),
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
      },
    );

    testWidgets('Driver duty failure exposes only driver_duty_fetch_failed', (
      tester,
    ) async {
      final queue = _MemoryOfferQueue();

      final dutyGateway = _DiagnosticDutyGateway(
        onFetchDuty: () async {
          throw StateError('PRIVATE token header phone database path');
        },
        detail: _trip(status: 'driver_offer_sent'),
      );

      await _pumpDiagnosticOffer(
        tester,
        dutyGateway: dutyGateway,
        factory: _diagnosticProductionFactory(
          dutyGateway: dutyGateway,
          queue: queue,
          offerGateway: _RecordingOfferGateway(),
        ),
      );

      final seam = _preparationStatusText(tester);

      expect(seam, 'PREP_FAILED: driver_duty_fetch_failed');
      expect(seam, matches(RegExp(r'^PREP_FAILED: [a-z_]+$')));
      expect(find.textContaining('PRIVATE'), findsNothing);
      expect(_acceptButton(tester).onPressed, isNull);
    });

    testWidgets('blank Driver reference produces driver_reference_missing', (
      tester,
    ) async {
      final queue = _MemoryOfferQueue();

      final dutyGateway = _DiagnosticDutyGateway(
        onFetchDuty: () async =>
            const DriverDutySummary(driverReference: '   '),
        detail: _trip(status: 'driver_offer_sent'),
      );

      await _pumpDiagnosticOffer(
        tester,
        dutyGateway: dutyGateway,
        factory: _diagnosticProductionFactory(
          dutyGateway: dutyGateway,
          queue: queue,
          offerGateway: _RecordingOfferGateway(),
        ),
      );

      expect(
        _preparationStatusText(tester),
        'PREP_FAILED: driver_reference_missing',
      );
      expect(_acceptButton(tester).onPressed, isNull);
    });

    testWidgets('persistent queue open failure is classified safely', (
      tester,
    ) async {
      final queue = PersistentDriverTripActionQueue(
        managerFactory: () async {
          throw StateError('PRIVATE file path and database contents');
        },
      );
      final dutyGateway = _DiagnosticDutyGateway(
        onFetchDuty: () async =>
            const DriverDutySummary(driverReference: 'DRIVER-001'),
        detail: _trip(status: 'driver_offer_sent'),
      );

      await _pumpDiagnosticOffer(
        tester,
        dutyGateway: dutyGateway,
        factory: _diagnosticProductionFactory(
          dutyGateway: dutyGateway,
          queue: queue,
          offerGateway: _RecordingOfferGateway(),
        ),
      );

      expect(
        _preparationStatusText(tester),
        'PREP_FAILED: persistent_queue_open_or_read_failed',
      );
      expect(find.textContaining('PRIVATE'), findsNothing);
      expect(_acceptButton(tester).onPressed, isNull);
    });

    test(
      'persistent file-backed queue read failure is classified safely',
      () async {
        final harness = await _FileBackedQueueHarness.create(
          initializeDatabase: (path) =>
              _createQueueDatabase(path, createTable: false),
        );
        addTearDown(harness.close);

        final dutyGateway = _DiagnosticDutyGateway(
          onFetchDuty: () async =>
              const DriverDutySummary(driverReference: 'DRIVER-001'),
          detail: _trip(status: 'driver_offer_sent'),
        );

        final controller = await _diagnosticProductionFactory(
          dutyGateway: dutyGateway,
          queue: harness.queue,
          offerGateway: _RecordingOfferGateway(),
        )('TRIP-OFFER-001');

        await expectLater(
          controller.prepareWhenOfferDisplayed(),
          throwsA(
            _preparationFailure(
              DriverOfferPreparationFailureCode.persistentQueueOpenOrReadFailed,
            ),
          ),
        );
      },
    );
    test('conflicting pending record is retained and classified', () async {
      final harness = await _FileBackedQueueHarness.create();
      addTearDown(harness.close);

      await harness.queue.enqueue(
        _preparedDiagnosticEvent(id: 'older-conflicting-record'),
      );

      final controller = await _diagnosticProductionFactory(
        dutyGateway: _DiagnosticDutyGateway(
          onFetchDuty: () async =>
              const DriverDutySummary(driverReference: 'DRIVER-001'),
          detail: _trip(status: 'driver_offer_sent'),
        ),
        queue: harness.queue,
        offerGateway: _RecordingOfferGateway(),
      )('TRIP-OFFER-001');

      await expectLater(
        controller.prepareWhenOfferDisplayed(),
        throwsA(
          _preparationFailure(
            DriverOfferPreparationFailureCode.conflictingOfferRecord,
          ),
        ),
      );

      expect(await harness.queue.pendingEvents(), hasLength(1));
    });

    test('invalid deterministic record is retained and classified', () async {
      final harness = await _FileBackedQueueHarness.create();
      addTearDown(harness.close);

      await harness.queue.enqueue(
        _preparedDiagnosticEvent(
          id: 'driver-offer-accept:trip-offer-001',
          idempotencyKey: 'invalid-key',
        ),
      );

      final controller = await _diagnosticProductionFactory(
        dutyGateway: _DiagnosticDutyGateway(
          onFetchDuty: () async =>
              const DriverDutySummary(driverReference: 'DRIVER-001'),
          detail: _trip(status: 'driver_offer_sent'),
        ),
        queue: harness.queue,
        offerGateway: _RecordingOfferGateway(),
      )('TRIP-OFFER-001');

      await expectLater(
        controller.prepareWhenOfferDisplayed(),
        throwsA(
          _preparationFailure(
            DriverOfferPreparationFailureCode.invalidOfferRecord,
          ),
        ),
      );

      expect(await harness.queue.pendingEvents(), hasLength(1));
    });

    test('file-backed enqueue failure produces queue_enqueue_failed', () async {
      final harness = await _FileBackedQueueHarness.create(
        initializeDatabase: (path) =>
            _createQueueDatabase(path, failInserts: true),
      );
      addTearDown(harness.close);

      final controller = await _diagnosticProductionFactory(
        dutyGateway: _DiagnosticDutyGateway(
          onFetchDuty: () async =>
              const DriverDutySummary(driverReference: 'DRIVER-001'),
          detail: _trip(status: 'driver_offer_sent'),
        ),
        queue: harness.queue,
        offerGateway: _RecordingOfferGateway(),
      )('TRIP-OFFER-001');

      await expectLater(
        controller.prepareWhenOfferDisplayed(),
        throwsA(
          _preparationFailure(
            DriverOfferPreparationFailureCode.queueEnqueueFailed,
          ),
        ),
      );
    });

    test('prepared record survives close/reopen without duplication', () async {
      final harness = await _FileBackedQueueHarness.create();
      addTearDown(harness.close);

      final dutyGateway = _DiagnosticDutyGateway(
        onFetchDuty: () async =>
            const DriverDutySummary(driverReference: 'DRIVER-001'),
        detail: _trip(status: 'driver_offer_sent'),
      );

      final firstController = await _diagnosticProductionFactory(
        dutyGateway: dutyGateway,
        queue: harness.queue,
        offerGateway: _RecordingOfferGateway(),
      )('TRIP-OFFER-001');

      final first = await firstController.prepareWhenOfferDisplayed();

      expect(first.payloadJson.containsKey('device_timestamp'), isFalse);

      await harness.reopen();

      final restoredController = await _diagnosticProductionFactory(
        dutyGateway: dutyGateway,
        queue: harness.queue,
        offerGateway: _RecordingOfferGateway(),
      )('TRIP-OFFER-001');

      final restored = await restoredController.prepareWhenOfferDisplayed();

      expect(restored.id, first.id);
      expect(restored.idempotencyKey, first.idempotencyKey);
      expect(restored.payloadJson.containsKey('device_timestamp'), isFalse);
      expect(await harness.queue.pendingEvents(), hasLength(1));
    });

    test(
      'retained older prepared fixture remains readable after reopen',
      () async {
        final prior = _preparedDiagnosticEvent(
          id: 'driver-offer-accept:trip-offer-001',
          idempotencyKey: 'DRIVER-OFFER-TRIP-OFFER-001-prior-fixture',
        );

        final harness = await _FileBackedQueueHarness.create(
          initializeDatabase: (path) async {
            await _createQueueDatabase(path);
            await _insertQueueFixture(path, prior);
          },
        );
        addTearDown(harness.close);

        final dutyGateway = _DiagnosticDutyGateway(
          onFetchDuty: () async =>
              const DriverDutySummary(driverReference: 'DRIVER-001'),
          detail: _trip(status: 'driver_offer_sent'),
        );

        final firstController = await _diagnosticProductionFactory(
          dutyGateway: dutyGateway,
          queue: harness.queue,
          offerGateway: _RecordingOfferGateway(),
        )('TRIP-OFFER-001');

        final first = await firstController.prepareWhenOfferDisplayed();

        expect(first.idempotencyKey, prior.idempotencyKey);
        expect(first.payloadJson.containsKey('device_timestamp'), isFalse);

        await harness.reopen();

        final reopenedController = await _diagnosticProductionFactory(
          dutyGateway: dutyGateway,
          queue: harness.queue,
          offerGateway: _RecordingOfferGateway(),
        )('TRIP-OFFER-001');

        final reopened = await reopenedController.prepareWhenOfferDisplayed();

        expect(reopened.idempotencyKey, prior.idempotencyKey);
        expect(await harness.queue.pendingEvents(), hasLength(1));
      },
    );

    testWidgets('rapid Retry taps serialize preparation and send no POST', (
      tester,
    ) async {
      final queue = _MemoryOfferQueue();

      final unrelated = QueuedEvent(
        id: 'unrelated-retained-record',
        eventType: 'unrelated-event',
        tripReference: 'TRIP-OTHER',
        driverId: 'DRIVER-OTHER',
        payloadJson: const <String, Object?>{'state': 'retained'},
        idempotencyKey: 'unrelated-retained-key',
        deviceTimestamp: DateTime.utc(2026, 7, 24, 3),
      );
      await queue.enqueue(unrelated);

      var dutyCalls = 0;
      final retryCompleter = Completer<DriverDutySummary>();

      final dutyGateway = _DiagnosticDutyGateway(
        onFetchDuty: () {
          dutyCalls += 1;
          if (dutyCalls == 1) {
            throw StateError('PRIVATE first failure');
          }
          return retryCompleter.future;
        },
        detail: _trip(status: 'driver_offer_sent'),
      );
      final offerGateway = _RecordingOfferGateway();

      await _pumpDiagnosticOffer(
        tester,
        dutyGateway: dutyGateway,
        factory: _diagnosticProductionFactory(
          dutyGateway: dutyGateway,
          queue: queue,
          offerGateway: offerGateway,
        ),
      );

      expect(
        _preparationStatusText(tester),
        'PREP_FAILED: driver_duty_fetch_failed',
      );
      expect(_acceptButton(tester).onPressed, isNull);

      final retry = find.byKey(const Key('driver-offer-preparation-retry'));

      await tester.tap(retry);
      await tester.tap(retry, warnIfMissed: false);
      await tester.pump();

      expect(dutyCalls, 2);
      expect(tester.widget<TextButton>(retry).onPressed, isNull);
      expect(_acceptButton(tester).onPressed, isNull);
      expect(offerGateway.calls, 0);

      retryCompleter.complete(
        const DriverDutySummary(driverReference: 'DRIVER-001'),
      );
      await tester.pumpAndSettle();

      expect(dutyCalls, 2);
      expect(find.text('PREP_READY'), findsOneWidget);
      expect(retry, findsNothing);
      expect(_acceptButton(tester).onPressed, isNotNull);
      expect(offerGateway.calls, 0);

      final retained = await queue.eventById(unrelated.id);
      expect(retained?.idempotencyKey, unrelated.idempotencyKey);

      final pending = await queue.pendingEvents();
      expect(pending, hasLength(2));
      expect(
        pending
            .where((event) => event.id == 'driver-offer-accept:trip-offer-001')
            .length,
        1,
      );
    });

    testWidgets('failed Retry keeps Accept disabled and creates no record', (
      tester,
    ) async {
      final queue = _MemoryOfferQueue();

      var dutyCalls = 0;
      final dutyGateway = _DiagnosticDutyGateway(
        onFetchDuty: () async {
          dutyCalls += 1;
          throw StateError('PRIVATE repeat failure');
        },
        detail: _trip(status: 'driver_offer_sent'),
      );
      final offerGateway = _RecordingOfferGateway();

      await _pumpDiagnosticOffer(
        tester,
        dutyGateway: dutyGateway,
        factory: _diagnosticProductionFactory(
          dutyGateway: dutyGateway,
          queue: queue,
          offerGateway: offerGateway,
        ),
      );

      await tester.tap(find.byKey(const Key('driver-offer-preparation-retry')));
      await tester.pumpAndSettle();

      expect(dutyCalls, 2);
      expect(
        _preparationStatusText(tester),
        'PREP_FAILED: driver_duty_fetch_failed',
      );
      expect(_acceptButton(tester).onPressed, isNull);
      expect(offerGateway.calls, 0);
      expect(await queue.pendingEvents(), isEmpty);
    });
  });
}

Future<MemoryAuthTokenStore> _tokenStore({String? accessToken}) async {
  final store = MemoryAuthTokenStore();
  await store.saveTokens(
    AuthTokens(
      accessToken: accessToken ?? _jwtExpiringAt(DateTime.utc(2100)),
      refreshToken: 'driver-refresh',
    ),
  );
  return store;
}

String _jwtExpiringAt(DateTime expiry) {
  return _jwtWithPayload(<String, Object?>{
    'exp':
        expiry.toUtc().millisecondsSinceEpoch ~/ Duration.millisecondsPerSecond,
  });
}

String _jwtWithPayload(Map<String, Object?> payload) {
  String encode(Object value) {
    return base64UrlEncode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  }

  return '${encode(const <String, Object?>{'alg': 'none', 'typ': 'JWT'})}.${encode(payload)}.signature';
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

ApiResponse<DriverOfferResponseReceipt> _offerClientException(
  AsmApiExceptionType type,
) {
  return ApiResponse.clientException(
    AsmApiException(type: type, message: 'Private transport detail.'),
  );
}

List<String> _telemetryTexts(
  Iterable<DriverOfferSubmissionTelemetryEvent> events,
) {
  return events.map((event) => event.qaDisplayText).toList(growable: false);
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

final class _CountingAuthTokenStore implements AuthTokenStore {
  int accessTokenReads = 0;
  int refreshTokenReads = 0;
  int saveCalls = 0;
  int clearCalls = 0;

  @override
  Future<void> saveTokens(AuthTokens tokens) async {
    saveCalls += 1;
  }

  @override
  Future<String?> readAccessToken() async {
    accessTokenReads += 1;
    return null;
  }

  @override
  Future<String?> readRefreshToken() async {
    refreshTokenReads += 1;
    return null;
  }

  @override
  Future<void> clearTokens() async {
    clearCalls += 1;
  }
}

final class _RecordingOfferApi implements DriverOfferResponseApiGateway {
  _RecordingOfferApi({required this.responses, this.beforePost});

  final List<ApiResponse<DriverOfferResponseReceipt>> responses;
  final void Function(int invocation)? beforePost;
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
    beforePost?.call(_index + 1);
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
  _MemoryOfferQueue({this.throwOnMarkSynced = false});

  final bool throwOnMarkSynced;
  final events = <QueuedEvent>[];
  int enqueueCalls = 0;
  int eventByIdCalls = 0;
  int pendingEventsCalls = 0;
  int markSyncedCalls = 0;

  @override
  Future<QueuedEvent> enqueue(QueuedEvent event) async {
    enqueueCalls += 1;
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
    eventByIdCalls += 1;
    for (final event in events) {
      if (event.id == id) {
        return event;
      }
    }
    return null;
  }

  @override
  Future<List<QueuedEvent>> pendingEvents() async {
    pendingEventsCalls += 1;
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
    markSyncedCalls += 1;
    if (throwOnMarkSynced) {
      throw StateError('Sanitized queue synchronization failure.');
    }

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
    DriverOfferSubmissionTelemetrySink? telemetrySink,
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

Matcher _preparationFailure(DriverOfferPreparationFailureCode code) {
  return isA<DriverOfferPreparationException>().having(
    (error) => error.code,
    'code',
    code,
  );
}

DriverOfferResponseControllerFactory _diagnosticProductionFactory({
  required DriverDutyGateway dutyGateway,
  required DriverTripActionPersistentQueue queue,
  required DriverOfferResponseGateway offerGateway,
}) {
  final factory = driver_main.driverOfferResponseControllerFactoryFor(
    baseUrl: 'https://diagnostic.invalid',
    tokenStore: MemoryAuthTokenStore(),
    dutyGateway: dutyGateway,
    persistentQueue: queue,
    offerGateway: offerGateway,
  );

  expect(factory, isNotNull);
  return factory!;
}

Future<void> _pumpDiagnosticOffer(
  WidgetTester tester, {
  required DriverDutyGateway dutyGateway,
  required DriverOfferResponseControllerFactory? factory,
}) async {
  tester.view.physicalSize = const Size(430, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: AsmThemes.driver,
      home: DriverTripDetailScreen(
        gateway: dutyGateway,
        tripReference: 'TRIP-OFFER-001',
        offerResponseControllerFactory: factory,
      ),
    ),
  );

  for (var attempt = 0; attempt < 200; attempt += 1) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();

    final hasPreparationStatus = find
        .byKey(const Key('driver-offer-preparation-status'))
        .evaluate()
        .isNotEmpty;

    if (hasPreparationStatus) {
      return;
    }
  }

  throw StateError('Offer preparation did not reach a typed result.');
}

FilledButton _acceptButton(WidgetTester tester) {
  return tester.widget<FilledButton>(
    find.byKey(const Key('driver-accept-offer')),
  );
}

String? _preparationStatusText(WidgetTester tester) {
  return tester
      .widget<Text>(find.byKey(const Key('driver-offer-preparation-status')))
      .data;
}

QueuedEvent _preparedDiagnosticEvent({
  required String id,
  String? idempotencyKey,
}) {
  return QueuedEvent(
    id: id,
    eventType:
        '${driverOfferResponsePath('TRIP-OFFER-001')}'
        '$driverOfferAcceptanceEventIdentity',
    tripReference: 'TRIP-OFFER-001',
    driverId: 'DRIVER-001',
    payloadJson: const <String, Object?>{'response': 'accept'},
    idempotencyKey:
        idempotencyKey ??
        'DRIVER-OFFER-TRIP-OFFER-001-'
            '11111111-1111-4111-8111-111111111111',
    deviceTimestamp: DateTime.utc(2026, 7, 24, 3),
    createdAt: DateTime.utc(2026, 7, 24, 3),
    updatedAt: DateTime.utc(2026, 7, 24, 3),
  );
}

final class _FileBackedQueueHarness {
  _FileBackedQueueHarness._({
    required this.directory,
    required this.databasePath,
    required this.queue,
  });

  final Directory directory;
  final String databasePath;
  PersistentDriverTripActionQueue queue;

  static Future<_FileBackedQueueHarness> create({
    Future<void> Function(String path)? initializeDatabase,
  }) async {
    final directory = await Directory.systemTemp.createTemp(
      'driver_offer_diagnostics_',
    );
    final databasePath = '${directory.path}/asm_offline_queue.sqlite';

    if (initializeDatabase != null) {
      await initializeDatabase(databasePath);
    }

    return _FileBackedQueueHarness._(
      directory: directory,
      databasePath: databasePath,
      queue: _queueFor(databasePath),
    );
  }

  static PersistentDriverTripActionQueue _queueFor(String databasePath) {
    return PersistentDriverTripActionQueue(
      managerFactory: () => QueueManager.open(databasePath: databasePath),
    );
  }

  Future<void> reopen() async {
    await queue.close();
    queue = _queueFor(databasePath);
  }

  Future<void> close() async {
    try {
      await queue.close();
    } on Object {
      // Deliberately failed opens have no live database.
    }

    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }
}

Future<void> _createQueueDatabase(
  String path, {
  bool createTable = true,
  bool failInserts = false,
}) async {
  final database = await databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: 1,
      onCreate: (database, version) async {
        if (!createTable) {
          return;
        }

        await database.execute('''
CREATE TABLE queued_events (
  id TEXT PRIMARY KEY,
  event_type TEXT NOT NULL,
  trip_reference TEXT NOT NULL,
  driver_id TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  idempotency_key TEXT NOT NULL,
  device_timestamp TEXT NOT NULL,
  sync_status TEXT NOT NULL,
  retry_count INTEGER NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
)
''');

        await database.execute(
          'CREATE INDEX idx_queued_events_created_at '
          'ON queued_events(created_at)',
        );
      },
    ),
  );

  if (failInserts) {
    await database.execute('''
CREATE TRIGGER fail_queued_event_insert
BEFORE INSERT ON queued_events
BEGIN
  SELECT RAISE(ABORT, 'diagnostic enqueue failure');
END
''');
  }

  await database.close();
}

Future<void> _insertQueueFixture(String path, QueuedEvent event) async {
  final database = await databaseFactoryFfi.openDatabase(path);

  await database.rawInsert(
    '''
INSERT INTO queued_events (
  id,
  event_type,
  trip_reference,
  driver_id,
  payload_json,
  idempotency_key,
  device_timestamp,
  sync_status,
  retry_count,
  created_at,
  updated_at
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
''',
    <Object?>[
      event.id,
      event.eventType,
      event.tripReference,
      event.driverId,
      jsonEncode(event.payloadJson),
      event.idempotencyKey,
      event.deviceTimestamp.toIso8601String(),
      event.syncStatus.name,
      event.retryCount,
      event.createdAt.toIso8601String(),
      event.updatedAt.toIso8601String(),
    ],
  );

  await database.close();
}

final class _DiagnosticDutyGateway implements DriverDutyGateway {
  _DiagnosticDutyGateway({required this.onFetchDuty, required this.detail});

  final Future<DriverDutySummary> Function() onFetchDuty;
  final DriverAssignedTrip detail;
  int detailCalls = 0;

  @override
  Future<DriverDutySummary> fetchDuty() => onFetchDuty();

  @override
  Future<List<DriverAssignedTrip>> fetchTrips() async => <DriverAssignedTrip>[
    detail,
  ];

  @override
  Future<DriverAssignedTrip> fetchTripDetail(String tripReference) async {
    detailCalls += 1;
    return detail;
  }
}

final class _NoopTripActionQueue implements DriverTripActionQueue {
  @override
  Future<QueuedEvent> enqueue(QueuedEvent event) async => event;
}

final class _ArrivedDiagnosticsActionApi implements DriverTripActionApiGateway {
  _ArrivedDiagnosticsActionApi({required this.response});

  final ApiResponse<DriverTripActionReceipt> response;
  final paths = <String>[];
  int calls = 0;

  @override
  Future<ApiResponse<T>> post<T>(
    String path, {
    Object? data,
    Map<String, String>? headers,
    JsonDecoder<T>? decoder,
  }) async {
    calls += 1;
    paths.add(path);
    return response as ApiResponse<T>;
  }
}

final class _ArrivedDiagnosticsOfferActionQueue
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

final class _ArrivedDiagnosticsOfferActionGateway
    implements DriverTripActionGateway {
  int calls = 0;

  @override
  Future<DriverTripActionReceipt> submit({
    required DriverTripAction action,
    required String tripReference,
    required String idempotencyKey,
    Map<String, Object?> body = const <String, Object?>{},
  }) async {
    calls += 1;
    return DriverTripActionReceipt(
      tripReference: tripReference,
      status: action.expectedStatus,
      message: 'Action confirmed.',
      duplicate: false,
    );
  }
}
