import 'dart:async';

import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_app_config/asm_app_config.dart';
import 'package:asm_offline_queue/asm_offline_queue.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:driver_app/network/driver_trip_action_resilience.dart';
import 'package:driver_app/readiness/driver_readiness_check.dart';
import 'package:driver_app/readiness/driver_readiness_page.dart';
import 'package:driver_app/readiness/driver_shift_check_submission.dart';

void main() {
  test('test_shift_check_submits_to_backend_on_completion', () async {
    final queue = _MemoryShiftCheckQueue();
    final apiClient = _RecordingShiftCheckApiClient();
    final controller = DriverShiftCheckSubmissionController(
      queue: queue,
      gateway: ApiDriverShiftCheckGateway(apiClient),
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
    return _completer.future;
  }
}
