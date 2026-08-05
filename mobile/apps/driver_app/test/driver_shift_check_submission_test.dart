import 'dart:async';
import 'dart:convert' as convert;

import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_app_config/asm_app_config.dart';
import 'package:asm_auth/asm_auth.dart';
import 'package:asm_offline_queue/asm_offline_queue.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:driver_app/network/driver_trip_action_gateway.dart';
import 'package:driver_app/network/driver_trip_action_resilience.dart';
import 'package:driver_app/network/ghana_network_resilience.dart';
import 'package:driver_app/readiness/driver_readiness_check.dart';
import 'package:driver_app/readiness/driver_readiness_page.dart';
import 'package:driver_app/readiness/driver_shift_check_submission.dart';

void main() {
  test('test_shift_check_submits_to_backend_on_completion', () async {
    final queue = _MemoryShiftCheckQueue();
    final apiClient = _RecordingShiftCheckApiClient();
    final controller = DriverShiftCheckSubmissionController(
      queue: queue,
      gateway: ApiDriverShiftCheckGateway(
        client: apiClient,
        tokenStore: _StaticAuthTokenStore(_testValidJwt),
        refreshAccessToken: null,
      ),
      isOnline: () async => true,
    );
    final submittedAt = DateTime(2026, 8, 5, 1, 2, 3);
    final check = _completeReadinessCheck();

    final result = await controller.submit(
      DriverShiftCheckSubmission.fromReadiness(
        check: check,
        batteryNeedsAttention: false,
        submittedAt: submittedAt,
      ),
    );

    expect(result.submitted, isTrue);
    expect(result.queued, isFalse);
    expect(apiClient.paths, <String>[driverShiftCheckPath]);
    expect(apiClient.bodies.single, <String, Object?>{
      'vehicle_check': true,
      'battery_check': true,
      'battery_attention_flag': false,
      'phone_app_check': true,
      'safety_check': true,
      'submitted_at': submittedAt.toIso8601String(),
    });
    expect(
      apiClient.headers.single['Idempotency-Key'],
      startsWith('DRIVER-SHIFT-CHECK-'),
    );
    expect(queue.syncedIds, <String>[result.event.id]);
    expect(queue.failedIds, isEmpty);
  });

  test('test_battery_attention_flag_true_when_battery_flagged', () {
    final submission = DriverShiftCheckSubmission.fromReadiness(
      check: _completeReadinessCheck(),
      batteryNeedsAttention: true,
      submittedAt: DateTime(2026, 8, 5, 2, 0),
    );

    expect(submission.batteryAttentionFlag, isTrue);
    expect(submission.toJson()['battery_attention_flag'], isTrue);
  });

  test('test_battery_attention_flag_false_when_battery_clear', () {
    final submission = DriverShiftCheckSubmission.fromReadiness(
      check: _completeReadinessCheck(),
      batteryNeedsAttention: false,
      submittedAt: DateTime(2026, 8, 5, 2, 0),
    );

    expect(submission.batteryAttentionFlag, isFalse);
    expect(submission.toJson()['battery_attention_flag'], isFalse);
  });

  testWidgets('test_local_only_text_absent_from_screen', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: DriverReadinessPage(market: MarketConfig.ghanaAccra),
      ),
    );

    expect(find.text('LOCAL ONLY'), findsNothing);
    expect(find.text('Local pre-shift checklist'), findsNothing);
    expect(
      find.text('Use these checks as a local device reminder before driving.'),
      findsNothing,
    );
    expect(find.text('Shift check · LOCAL ONLY'), findsNothing);
    expect(find.text('Shift check'), findsWidgets);
  });

  testWidgets('test_local_only_banner_absent_from_screen', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: DriverReadinessPage(market: MarketConfig.ghanaAccra),
      ),
    );

    expect(find.byKey(const Key('readiness-local-only')), findsNothing);
    expect(
      find.byKey(const Key('driver-shift-readiness-screen')),
      findsOneWidget,
    );
  });

  testWidgets('test_success_state_shown_after_submission', (tester) async {
    final queue = _MemoryShiftCheckQueue();
    final gateway = _CompletingShiftCheckGateway();
    final controller = DriverShiftCheckSubmissionController(
      queue: queue,
      gateway: gateway,
      isOnline: () async => true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: DriverReadinessPage(
          market: MarketConfig.ghanaAccra,
          submissionController: controller,
          deviceNow: () => DateTime(2026, 8, 5, 3, 0),
        ),
      ),
    );

    await _completeReadinessScreen(tester);
    await tester.tap(find.byKey(const Key('readiness-ready')));
    await tester.pump();

    expect(find.text('Submitting shift check...'), findsOneWidget);

    gateway.completeSuccess();
    await tester.pump();
    await tester.pump();

    expect(find.text('Shift check submitted'), findsOneWidget);
    expect(
      find.text(
        'Your pre-shift check has been sent. '
        'You are ready to drive.',
      ),
      findsOneWidget,
    );

    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
  });

  testWidgets('test_queued_state_shown_when_offline', (tester) async {
    final queue = _MemoryShiftCheckQueue();
    final gateway = _RecordingShiftCheckGateway.success();
    final controller = DriverShiftCheckSubmissionController(
      queue: queue,
      gateway: gateway,
      isOnline: () async => false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: DriverReadinessPage(
          market: MarketConfig.ghanaAccra,
          submissionController: controller,
          deviceNow: () => DateTime(2026, 8, 5, 3, 30),
        ),
      ),
    );

    await _completeReadinessScreen(tester);
    await tester.tap(find.byKey(const Key('readiness-ready')));
    await tester.pump();
    await tester.pump();

    expect(find.text('Shift check saved'), findsOneWidget);
    expect(
      find.text(
        'Check saved on device. It will be submitted '
        'automatically when you are connected.',
      ),
      findsOneWidget,
    );
    expect(gateway.bodies, isEmpty);
    expect(queue.events, hasLength(1));

    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
  });

  test('test_submission_uses_offline_queue_on_failure', () async {
    final queue = _MemoryShiftCheckQueue();
    final gateway = _RecordingShiftCheckGateway.failure();
    final controller = DriverShiftCheckSubmissionController(
      queue: queue,
      gateway: gateway,
      isOnline: () async => true,
      retryDelay: (_) => Completer<void>().future,
    );

    final result = await controller.submit(
      DriverShiftCheckSubmission.fromReadiness(
        check: _completeReadinessCheck(),
        batteryNeedsAttention: false,
        submittedAt: DateTime(2026, 8, 5, 4, 0),
      ),
    );

    expect(result.queued, isTrue);
    expect(result.submitted, isFalse);
    expect(queue.events, hasLength(1));
    expect(queue.events.single.id, result.event.id);
    expect(queue.failedIds, <String>[result.event.id]);
    expect(queue.syncedIds, isEmpty);
    expect(gateway.bodies, hasLength(1));
  });

  test('test_submitted_at_is_device_timestamp', () {
    final deviceTimestamp = DateTime(2026, 8, 5, 4, 15, 30, 456, 789);

    final submission = DriverShiftCheckSubmission.fromReadiness(
      check: _completeReadinessCheck(),
      batteryNeedsAttention: false,
      submittedAt: deviceTimestamp,
    );

    expect(submission.submittedAt, same(deviceTimestamp));
    expect(
      submission.toJson()['submitted_at'],
      deviceTimestamp.toIso8601String(),
    );
  });

  test('test_failed_delivery_schedules_2s_retry', () async {
    final queue = _MemoryShiftCheckQueue();
    final gateway = _SequenceShiftCheckGateway(<ApiResponse<Object?>>[
      ApiResponse<Object?>.apiFailure(
        const AsmApiException(
          type: AsmApiExceptionType.server,
          message: 'Temporary failure.',
          statusCode: 503,
        ),
      ),
    ]);
    final retryDelay = _ControlledRetryDelay();
    final controller = DriverShiftCheckSubmissionController(
      queue: queue,
      gateway: gateway,
      isOnline: () async => true,
      retryDelay: retryDelay.call,
    );

    final result = await controller.submit(
      _testShiftCheckSubmission(DateTime(2026, 8, 5, 5, 0)),
    );

    expect(result.queued, isTrue);
    expect(retryDelay.scheduled, <Duration>[const Duration(seconds: 2)]);
    expect(gateway.callCount, 1);
    expect(queue.failedIds, <String>[result.event.id]);
  });

  test('test_2s_retry_failure_schedules_4s_retry', () async {
    final queue = _MemoryShiftCheckQueue();
    final gateway = _SequenceShiftCheckGateway(<ApiResponse<Object?>>[
      ApiResponse<Object?>.apiFailure(
        const AsmApiException(
          type: AsmApiExceptionType.server,
          message: 'Temporary failure.',
          statusCode: 503,
        ),
      ),
      ApiResponse<Object?>.apiFailure(
        const AsmApiException(
          type: AsmApiExceptionType.server,
          message: 'Temporary failure.',
          statusCode: 503,
        ),
      ),
    ]);
    final retryDelay = _ControlledRetryDelay();
    final controller = DriverShiftCheckSubmissionController(
      queue: queue,
      gateway: gateway,
      isOnline: () async => true,
      retryDelay: retryDelay.call,
    );

    final result = await controller.submit(
      _testShiftCheckSubmission(DateTime(2026, 8, 5, 5, 15)),
    );

    expect(result.queued, isTrue);
    expect(retryDelay.scheduled, <Duration>[const Duration(seconds: 2)]);

    retryDelay.completeNext();
    await _flushAsyncWork();

    expect(gateway.callCount, 2);
    expect(retryDelay.scheduled, <Duration>[
      const Duration(seconds: 2),
      const Duration(seconds: 4),
    ]);
    expect(queue.failedIds, <String>[result.event.id]);
  });

  test('test_4s_retry_failure_schedules_8s_retry', () async {
    final queue = _MemoryShiftCheckQueue();
    final gateway = _SequenceShiftCheckGateway(<ApiResponse<Object?>>[
      ApiResponse<Object?>.apiFailure(
        const AsmApiException(
          type: AsmApiExceptionType.server,
          message: 'Temporary failure.',
          statusCode: 503,
        ),
      ),
      ApiResponse<Object?>.apiFailure(
        const AsmApiException(
          type: AsmApiExceptionType.server,
          message: 'Temporary failure.',
          statusCode: 503,
        ),
      ),
      ApiResponse<Object?>.apiFailure(
        const AsmApiException(
          type: AsmApiExceptionType.server,
          message: 'Temporary failure.',
          statusCode: 503,
        ),
      ),
      ApiResponse<Object?>.apiFailure(
        const AsmApiException(
          type: AsmApiExceptionType.server,
          message: 'Temporary failure.',
          statusCode: 503,
        ),
      ),
    ]);
    final retryDelay = _ControlledRetryDelay();
    final controller = DriverShiftCheckSubmissionController(
      queue: queue,
      gateway: gateway,
      isOnline: () async => true,
      retryDelay: retryDelay.call,
    );

    final result = await controller.submit(
      _testShiftCheckSubmission(DateTime(2026, 8, 5, 5, 30)),
    );

    retryDelay.completeNext();
    await _flushAsyncWork();
    retryDelay.completeNext();
    await _flushAsyncWork();

    expect(result.queued, isTrue);
    expect(gateway.callCount, 3);
    expect(retryDelay.scheduled, <Duration>[
      const Duration(seconds: 2),
      const Duration(seconds: 4),
      const Duration(seconds: 8),
    ]);

    retryDelay.completeNext();
    await _flushAsyncWork();

    expect(gateway.callCount, 4);
    expect(retryDelay.scheduled, <Duration>[
      const Duration(seconds: 2),
      const Duration(seconds: 4),
      const Duration(seconds: 8),
    ]);
    expect(queue.failedIds, <String>[result.event.id]);
    expect(queue.syncedIds, isEmpty);
    expect(
      (await queue.eventById(result.event.id))?.syncStatus,
      QueueSyncStatus.failed,
    );
    expect(await queue.pendingEvents(), hasLength(1));
  });

  test('test_no_overlapping_sync_when_already_running', () async {
    final queue = _MemoryShiftCheckQueue();
    final event = await queue.enqueue(
      _testQueuedShiftCheckEvent(DateTime(2026, 8, 5, 5, 45)),
    );
    final gateway = _CompletingShiftCheckGateway();
    final controller = DriverShiftCheckSubmissionController(
      queue: queue,
      gateway: gateway,
      isOnline: () async => true,
      retryDelay: (_) => Completer<void>().future,
    );

    final first = controller.syncQueuedSubmissions();
    final second = controller.syncQueuedSubmissions();

    expect(identical(first, second), isTrue);
    await _flushAsyncWork();
    expect(gateway.callCount, 1);

    gateway.completeSuccess();
    await Future.wait(<Future<void>>[first, second]);

    expect(queue.syncedIds, <String>[event.id]);
  });
  test('test_successful_retry_dequeues_item_exactly_once', () async {
    final queue = _MemoryShiftCheckQueue();
    final gateway = _SequenceShiftCheckGateway(<ApiResponse<Object?>>[
      ApiResponse<Object?>.apiFailure(
        const AsmApiException(
          type: AsmApiExceptionType.server,
          message: 'Temporary failure.',
          statusCode: 503,
        ),
      ),
      ApiResponse<Object?>.success(<String, Object?>{
        'ok': true,
      }, statusCode: 201),
    ]);
    final retryDelay = _ControlledRetryDelay();
    final controller = DriverShiftCheckSubmissionController(
      queue: queue,
      gateway: gateway,
      isOnline: () async => true,
      retryDelay: retryDelay.call,
    );

    final result = await controller.submit(
      _testShiftCheckSubmission(DateTime(2026, 8, 5, 6, 0)),
    );

    expect(result.queued, isTrue);
    expect(retryDelay.scheduled, <Duration>[const Duration(seconds: 2)]);

    retryDelay.completeNext();
    await _flushAsyncWork();

    expect(gateway.callCount, 2);
    expect(queue.syncedIds, <String>[result.event.id]);
    expect(queue.syncedIds.where((id) => id == result.event.id), hasLength(1));
    expect(await queue.pendingEvents(), isEmpty);
    expect(
      (await queue.eventById(result.event.id))?.syncStatus,
      QueueSyncStatus.synced,
    );
    expect(retryDelay.scheduled, <Duration>[const Duration(seconds: 2)]);
  });

  test('test_existing_startup_sync_still_fires', () async {
    final queue = _MemoryShiftCheckQueue();
    final event = await queue.enqueue(
      _testQueuedShiftCheckEvent(DateTime(2026, 8, 5, 6, 15)),
    );
    final gateway = _RecordingShiftCheckGateway.success();
    final controller = DriverShiftCheckSubmissionController(
      queue: queue,
      gateway: gateway,
      isOnline: () async => true,
      retryDelay: (_) => Completer<void>().future,
    );

    await controller.startAutomaticSync();

    expect(gateway.bodies, hasLength(1));
    expect(queue.syncedIds, <String>[event.id]);
    expect(await queue.pendingEvents(), isEmpty);

    await controller.stopAutomaticSync();
  });

  test('test_existing_connectivity_sync_still_fires', () async {
    final queue = _MemoryShiftCheckQueue();
    final event = await queue.enqueue(
      _testQueuedShiftCheckEvent(DateTime(2026, 8, 5, 6, 30)),
    );
    final gateway = _RecordingShiftCheckGateway.success();
    final connectivity = _TestGhanaConnectivitySource();
    var online = false;
    final controller = DriverShiftCheckSubmissionController(
      queue: queue,
      gateway: gateway,
      isOnline: () async => online,
      connectivitySource: connectivity,
      retryDelay: (_) => Completer<void>().future,
    );

    await controller.startAutomaticSync();

    expect(gateway.bodies, isEmpty);
    expect(queue.syncedIds, isEmpty);

    online = true;
    connectivity.emit(<ConnectivityResult>[ConnectivityResult.wifi]);
    await _flushAsyncWork();

    expect(gateway.bodies, hasLength(1));
    expect(queue.syncedIds, <String>[event.id]);
    expect(await queue.pendingEvents(), isEmpty);

    await controller.stopAutomaticSync();
    await connectivity.close();
  });
  test('test_token_refreshed_before_shift_check_post', () async {
    final now = DateTime.utc(2026, 8, 5, 7);
    final expiringToken = _jwtWithExpiry(now.add(const Duration(seconds: 30)));
    final refreshedToken = _jwtWithExpiry(now.add(const Duration(hours: 1)));
    final tokenStore = _StaticAuthTokenStore(expiringToken);
    final apiClient = _ScriptedShiftCheckApiClient(<ApiResponse<Object?>>[
      ApiResponse<Object?>.success(<String, Object?>{
        'ok': true,
      }, statusCode: 201),
    ]);
    var refreshCalls = 0;
    final gateway = ApiDriverShiftCheckGateway(
      client: apiClient,
      tokenStore: tokenStore,
      refreshAccessToken: () async {
        refreshCalls += 1;
        tokenStore.setAccessToken(refreshedToken);
        return DriverTokenRefreshOutcome.refreshed;
      },
      utcNow: () => now,
    );

    final response = await gateway.submit(
      body: const <String, Object?>{'vehicle_check': true},
      idempotencyKey: 'SHIFT-CHECK-TOKEN-REFRESH',
    );

    expect(response.isSuccess, isTrue);
    expect(refreshCalls, 1);
    expect(apiClient.callCount, 1);
    expect(apiClient.headers.single['Authorization'], 'Bearer $refreshedToken');
    expect(
      apiClient.headers.single['Authorization'],
      isNot('Bearer $expiringToken'),
    );
  });

  test('test_expired_token_triggers_refresh_before_retry', () async {
    var now = DateTime.utc(2026, 8, 5, 7, 15);
    final initialToken = _jwtWithExpiry(now.add(const Duration(seconds: 120)));
    final refreshedToken = _jwtWithExpiry(now.add(const Duration(hours: 2)));
    final tokenStore = _StaticAuthTokenStore(initialToken);
    final apiClient = _ScriptedShiftCheckApiClient(<ApiResponse<Object?>>[
      ApiResponse<Object?>.apiFailure(
        const AsmApiException(
          type: AsmApiExceptionType.server,
          message: 'Temporary failure.',
          statusCode: 503,
        ),
      ),
      ApiResponse<Object?>.success(<String, Object?>{
        'ok': true,
      }, statusCode: 201),
    ]);
    var refreshCalls = 0;
    final retryDelay = _ControlledRetryDelay();
    final controller = DriverShiftCheckSubmissionController(
      queue: _MemoryShiftCheckQueue(),
      gateway: ApiDriverShiftCheckGateway(
        client: apiClient,
        tokenStore: tokenStore,
        refreshAccessToken: () async {
          refreshCalls += 1;
          tokenStore.setAccessToken(refreshedToken);
          return DriverTokenRefreshOutcome.refreshed;
        },
        utcNow: () => now,
      ),
      isOnline: () async => true,
      retryDelay: retryDelay.call,
    );

    final result = await controller.submit(
      _testShiftCheckSubmission(DateTime(2026, 8, 5, 7, 15)),
    );

    expect(result.queued, isTrue);
    expect(refreshCalls, 0);
    expect(apiClient.headers.first['Authorization'], 'Bearer $initialToken');

    now = now.add(const Duration(seconds: 70));
    retryDelay.completeNext();
    await _flushAsyncWork();

    expect(refreshCalls, 1);
    expect(apiClient.callCount, 2);
    expect(apiClient.headers.last['Authorization'], 'Bearer $refreshedToken');
  });

  test('test_401_response_schedules_retry_with_token_refresh', () async {
    final now = DateTime.utc(2026, 8, 5, 7, 30);
    final initialToken = _jwtWithExpiry(now.add(const Duration(hours: 1)));
    final refreshedToken = _jwtWithExpiry(now.add(const Duration(hours: 2)));
    final tokenStore = _StaticAuthTokenStore(initialToken);
    final apiClient = _ScriptedShiftCheckApiClient(<ApiResponse<Object?>>[
      ApiResponse<Object?>.apiFailure(
        const AsmApiException(
          type: AsmApiExceptionType.server,
          message: 'Unauthenticated.',
          statusCode: 401,
        ),
      ),
      ApiResponse<Object?>.success(<String, Object?>{
        'ok': true,
      }, statusCode: 201),
    ]);
    final queue = _MemoryShiftCheckQueue();
    final retryDelay = _ControlledRetryDelay();
    var refreshCalls = 0;
    final controller = DriverShiftCheckSubmissionController(
      queue: queue,
      gateway: ApiDriverShiftCheckGateway(
        client: apiClient,
        tokenStore: tokenStore,
        refreshAccessToken: () async {
          refreshCalls += 1;
          tokenStore.setAccessToken(refreshedToken);
          return DriverTokenRefreshOutcome.refreshed;
        },
        utcNow: () => now,
      ),
      isOnline: () async => true,
      retryDelay: retryDelay.call,
    );

    final result = await controller.submit(
      _testShiftCheckSubmission(DateTime(2026, 8, 5, 7, 30)),
    );

    expect(result.queued, isTrue);
    expect(apiClient.callCount, 1);
    expect(refreshCalls, 0);
    expect(retryDelay.scheduled, <Duration>[const Duration(seconds: 2)]);

    retryDelay.completeNext();
    await _flushAsyncWork();

    expect(apiClient.callCount, 2);
    expect(refreshCalls, 1);
    expect(apiClient.headers, hasLength(2));
    expect(apiClient.headers.first['Authorization'], 'Bearer $initialToken');
    expect(apiClient.headers.last['Authorization'], 'Bearer $refreshedToken');
    expect(queue.syncedIds, <String>[result.event.id]);
    expect(await queue.pendingEvents(), isEmpty);
    expect(retryDelay.scheduled, <Duration>[const Duration(seconds: 2)]);
  });

  testWidgets('test_refresh_failure_queues_item_and_shows_queued_state', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 8, 5, 7, 45);
    final tokenStore = _StaticAuthTokenStore(
      _jwtWithExpiry(now.subtract(const Duration(seconds: 1))),
    );
    final apiClient = _ScriptedShiftCheckApiClient(<ApiResponse<Object?>>[
      ApiResponse<Object?>.success(<String, Object?>{
        'ok': true,
      }, statusCode: 201),
    ]);
    final queue = _MemoryShiftCheckQueue();
    var refreshCalls = 0;
    final controller = DriverShiftCheckSubmissionController(
      queue: queue,
      gateway: ApiDriverShiftCheckGateway(
        client: apiClient,
        tokenStore: tokenStore,
        refreshAccessToken: () async {
          refreshCalls += 1;
          return DriverTokenRefreshOutcome.sessionExpired;
        },
        utcNow: () => now,
      ),
      isOnline: () async => true,
      retryDelay: (_) => Completer<void>().future,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: DriverReadinessPage(
          market: MarketConfig.ghanaAccra,
          submissionController: controller,
          deviceNow: () => now,
        ),
      ),
    );

    await _completeReadinessScreen(tester);
    await tester.tap(find.byKey(const Key('readiness-ready')));
    await tester.pump();
    await tester.pump();

    expect(refreshCalls, 1);
    expect(apiClient.callCount, 0);
    expect(queue.events, hasLength(1));
    expect(queue.failedIds, <String>[queue.events.single.id]);
    expect(queue.events.single.syncStatus, QueueSyncStatus.failed);
    expect(find.text('Shift check saved'), findsOneWidget);
    expect(
      find.text(
        'Check saved on device. It will be submitted '
        'automatically when you are connected.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Session expired'), findsNothing);
    expect(find.textContaining('Authentication'), findsNothing);
    expect(find.textContaining('sign in again'), findsNothing);

    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
  });
}

DriverShiftCheckSubmission _testShiftCheckSubmission(DateTime submittedAt) {
  return DriverShiftCheckSubmission.fromReadiness(
    check: _completeReadinessCheck(),
    batteryNeedsAttention: false,
    submittedAt: submittedAt,
  );
}

QueuedEvent _testQueuedShiftCheckEvent(DateTime timestamp) {
  final identity = timestamp.toUtc().microsecondsSinceEpoch;
  return QueuedEvent(
    id: 'driver-shift-check:$identity',
    eventType: driverShiftCheckPath,
    tripReference: driverShiftCheckQueueReference,
    driverId: driverShiftCheckQueueDriverIdentity,
    payloadJson: _testShiftCheckSubmission(timestamp).toJson(),
    idempotencyKey: 'DRIVER-SHIFT-CHECK-$identity',
    deviceTimestamp: timestamp,
  );
}

Future<void> _flushAsyncWork() async {
  for (var index = 0; index < 8; index += 1) {
    await Future<void>.delayed(Duration.zero);
  }
}

final class _TestGhanaConnectivitySource implements GhanaConnectivitySource {
  final StreamController<List<ConnectivityResult>> _controller =
      StreamController<List<ConnectivityResult>>.broadcast();

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async {
    return const <ConnectivityResult>[ConnectivityResult.none];
  }

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged {
    return _controller.stream;
  }

  void emit(List<ConnectivityResult> results) {
    _controller.add(results);
  }

  Future<void> close() {
    return _controller.close();
  }
}

final class _ControlledRetryDelay {
  final List<Duration> scheduled = <Duration>[];
  final List<Completer<void>> _pending = <Completer<void>>[];

  Future<void> call(Duration delay) {
    scheduled.add(delay);
    final completer = Completer<void>();
    _pending.add(completer);
    return completer.future;
  }

  void completeNext() {
    final completer = _pending.removeAt(0);
    completer.complete();
  }
}

final class _SequenceShiftCheckGateway implements DriverShiftCheckGateway {
  _SequenceShiftCheckGateway(List<ApiResponse<Object?>> responses)
    : _responses = List<ApiResponse<Object?>>.of(responses);

  final List<ApiResponse<Object?>> _responses;
  int callCount = 0;

  @override
  Future<ApiResponse<Object?>> submit({
    required Map<String, Object?> body,
    required String idempotencyKey,
  }) async {
    callCount += 1;
    if (_responses.isEmpty) {
      throw StateError('No scripted shift-check response remains.');
    }
    return _responses.removeAt(0);
  }
}

DriverReadinessCheck _completeReadinessCheck() {
  var check = DriverReadinessCheck.empty();

  for (final item in DriverReadinessItem.values) {
    check = check.toggle(item);
  }

  return check;
}

Future<void> _completeReadinessScreen(WidgetTester tester) async {
  for (final item in DriverReadinessItem.values) {
    final finder = find.byKey(ValueKey<String>('readiness-${item.name}'));
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pump();
    await tester.tap(finder);
    await tester.pump();
  }

  final ready = find.byKey(const Key('readiness-ready'));
  await tester.scrollUntilVisible(
    ready,
    200,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.pump();

  expect(tester.widget<FilledButton>(ready).onPressed, isNotNull);
}

final class _MemoryShiftCheckQueue implements DriverTripActionPersistentQueue {
  final Map<String, QueuedEvent> _events = <String, QueuedEvent>{};
  final List<String> syncedIds = <String>[];
  final List<String> failedIds = <String>[];
  final List<String> permanentlyFailedIds = <String>[];

  List<QueuedEvent> get events =>
      List<QueuedEvent>.unmodifiable(_events.values);

  @override
  Future<QueuedEvent> enqueue(QueuedEvent event) async {
    _events[event.id] = event;
    return event;
  }

  @override
  Future<QueuedEvent?> eventById(String id) async {
    return _events[id];
  }

  @override
  Future<List<QueuedEvent>> pendingEvents() async {
    return _events.values
        .where(
          (event) =>
              event.syncStatus == QueueSyncStatus.pending ||
              event.syncStatus == QueueSyncStatus.failed,
        )
        .toList(growable: false);
  }

  @override
  Future<void> markSynced(String id) async {
    syncedIds.add(id);
    final event = _events[id];
    if (event != null) {
      _events[id] = event.copyWith(syncStatus: QueueSyncStatus.synced);
    }
  }

  @override
  Future<void> markFailed(String id) async {
    failedIds.add(id);
    final event = _events[id];
    if (event != null) {
      _events[id] = event.copyWith(
        syncStatus: QueueSyncStatus.failed,
        retryCount: event.retryCount + 1,
      );
    }
  }

  @override
  Future<void> markPermanentlyFailed(String id) async {
    permanentlyFailedIds.add(id);
    final event = _events[id];
    if (event != null) {
      _events[id] = event.copyWith(
        syncStatus: QueueSyncStatus.permanentlyFailed,
      );
    }
  }
}

final class _RecordingShiftCheckApiClient extends AsmApiClient {
  _RecordingShiftCheckApiClient() : super(baseUrl: 'https://example.invalid');

  final List<String> paths = <String>[];
  final List<Map<String, Object?>> bodies = <Map<String, Object?>>[];
  final List<Map<String, String>> headers = <Map<String, String>>[];

  @override
  Future<ApiResponse<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
    JsonDecoder<T>? decoder,
  }) async {
    paths.add(path);
    bodies.add(Map<String, Object?>.from(data! as Map<String, Object?>));
    this.headers.add(
      Map<String, String>.from(headers ?? const <String, String>{}),
    );

    return ApiResponse<T>.success(
      <String, Object?>{'ok': true} as T,
      statusCode: 201,
    );
  }
}

final class _RecordingShiftCheckGateway implements DriverShiftCheckGateway {
  _RecordingShiftCheckGateway.success()
    : response = ApiResponse<Object?>.success(<String, Object?>{
        'ok': true,
      }, statusCode: 201);

  _RecordingShiftCheckGateway.failure()
    : response = ApiResponse.apiFailure(
        const AsmApiException(
          type: AsmApiExceptionType.server,
          message: 'Temporary failure.',
          statusCode: 503,
        ),
      );

  final ApiResponse<Object?> response;
  final List<Map<String, Object?>> bodies = <Map<String, Object?>>[];
  final List<String> idempotencyKeys = <String>[];

  @override
  Future<ApiResponse<Object?>> submit({
    required Map<String, Object?> body,
    required String idempotencyKey,
  }) async {
    bodies.add(Map<String, Object?>.from(body));
    idempotencyKeys.add(idempotencyKey);
    return response;
  }
}

final class _CompletingShiftCheckGateway implements DriverShiftCheckGateway {
  final Completer<ApiResponse<Object?>> _completer =
      Completer<ApiResponse<Object?>>();

  int callCount = 0;

  void completeSuccess() {
    _completer.complete(
      ApiResponse<Object?>.success(<String, Object?>{
        'ok': true,
      }, statusCode: 201),
    );
  }

  @override
  Future<ApiResponse<Object?>> submit({
    required Map<String, Object?> body,
    required String idempotencyKey,
  }) {
    callCount += 1;
    return _completer.future;
  }
}

String _jwtWithExpiry(DateTime expiry) {
  final expirySeconds =
      expiry.toUtc().millisecondsSinceEpoch ~/ Duration.millisecondsPerSecond;
  final payload = convert.base64Url
      .encode(
        convert.utf8.encode(
          convert.jsonEncode(<String, Object?>{'exp': expirySeconds}),
        ),
      )
      .replaceAll('=', '');
  return 'e30.$payload.';
}

final class _ScriptedShiftCheckApiClient extends AsmApiClient {
  _ScriptedShiftCheckApiClient(List<ApiResponse<Object?>> responses)
    : _responses = List<ApiResponse<Object?>>.of(responses),
      super(baseUrl: 'https://example.invalid');

  final List<ApiResponse<Object?>> _responses;
  final List<Map<String, String>> headers = <Map<String, String>>[];
  int callCount = 0;

  @override
  Future<ApiResponse<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
    JsonDecoder<T>? decoder,
  }) async {
    callCount += 1;
    this.headers.add(
      Map<String, String>.from(headers ?? const <String, String>{}),
    );

    if (_responses.isEmpty) {
      throw StateError('No scripted API response remains.');
    }

    return _responses.removeAt(0) as ApiResponse<T>;
  }
}

const _testValidJwt = 'e30.eyJleHAiOjQxMDI0NDQ4MDB9.';

final class _StaticAuthTokenStore implements AuthTokenStore {
  _StaticAuthTokenStore(this._accessToken);

  String? _accessToken;

  void setAccessToken(String accessToken) {
    _accessToken = accessToken;
  }

  @override
  Future<void> saveTokens(AuthTokens tokens) async {
    _accessToken = tokens.accessToken;
  }

  @override
  Future<String?> readAccessToken() async => _accessToken;

  @override
  Future<String?> readRefreshToken() async => null;

  @override
  Future<void> clearTokens() async {
    _accessToken = null;
  }
}
