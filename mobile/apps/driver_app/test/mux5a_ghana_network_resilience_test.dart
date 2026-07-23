import 'dart:async';

import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_offline_queue/asm_offline_queue.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:driver_app/network/driver_trip_action_resilience.dart';
import 'package:driver_app/network/ghana_network_resilience.dart';
import 'package:driver_app/trip_progress/driver_trip_visual_sequence.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Ghana request profile uses exact retry and gzip settings', () {
    expect(GhanaRequestPolicy.connectTimeout, const Duration(seconds: 15));
    expect(GhanaRequestPolicy.sendTimeout, const Duration(seconds: 15));
    expect(GhanaRequestPolicy.receiveTimeout, const Duration(seconds: 15));
    expect(GhanaRequestPolicy.requestTimeout, const Duration(seconds: 15));
    expect(GhanaRequestPolicy.retryBackoffs, const <Duration>[
      Duration(seconds: 2),
      Duration(seconds: 4),
      Duration(seconds: 8),
    ]);
    expect(GhanaRequestPolicy.maxAttempts, 4);
    expect(GhanaRequestPolicy.headersFor(null)['Accept-Encoding'], 'gzip');
  });

  test('safe Driver read waits 2s 4s 8s before the fourth attempt', () async {
    var attempts = 0;
    final delays = <Duration>[];
    final policy = GhanaRetryPolicy(
      delay: (duration) async => delays.add(duration),
    );
    final response = await policy.execute<String>(
      safeToRetry: true,
      operation: () async {
        attempts += 1;
        if (attempts < GhanaRequestPolicy.maxAttempts) {
          return ApiResponse.clientException(
            const AsmApiException(
              type: AsmApiExceptionType.timeout,
              message: 'timeout',
            ),
          );
        }
        return ApiResponse.success('ok');
      },
    );

    expect(response.data, 'ok');
    expect(attempts, 4);
    expect(delays, GhanaRequestPolicy.retryBackoffs);
  });

  test('unsafe Driver POST-style work is not retried', () async {
    var attempts = 0;
    final policy = GhanaRetryPolicy(delay: (_) async {});

    final response = await policy.execute<String>(
      safeToRetry: false,
      operation: () async {
        attempts += 1;
        return ApiResponse.clientException(
          const AsmApiException(
            type: AsmApiExceptionType.network,
            message: 'offline',
          ),
        );
      },
    );

    expect(response.error?.type, AsmApiExceptionType.network);
    expect(attempts, 1);
  });

  test(
    'Driver connectivity state combines cellular with API reachability',
    () async {
      final source = _FakeGhanaConnectivitySource(const <ConnectivityResult>[
        ConnectivityResult.mobile,
      ]);
      final monitor = GhanaReachabilityMonitor(
        reachability: GhanaApiReachability(
          baseUrl: 'https://example.test',
          probe: (_, _) async => true,
        ),
        connectivitySource: source,
        checkInterval: const Duration(hours: 1),
      );

      await monitor.start();

      expect(monitor.state.status, GhanaNetworkStatus.online);
      expect(monitor.state.transport, GhanaNetworkTransport.cellular);
      expect(monitor.state.apiReachable, isTrue);

      source.emit(const <ConnectivityResult>[ConnectivityResult.wifi]);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(monitor.state.transport, GhanaNetworkTransport.wifi);

      monitor.dispose();
      await source.close();
    },
  );

  test('offline Driver trip actions are queued with safe metadata', () async {
    final queue = _RecordingDriverTripActionQueue();
    final controller = DriverTripActionResilienceController(
      isOnline: () async => false,
      queue: queue,
      tripReference: 'TRIP-GHANA-001',
      driverId: 'DRIVER-001',
    );

    final result = await controller.recordAction(
      eventType: 'arrived-pickup',
      payload: const <String, Object?>{'action': 'arrived-pickup'},
    );

    expect(result.queuedOffline, isTrue);
    expect(queue.events, hasLength(1));
    expect(queue.events.single.tripReference, 'TRIP-GHANA-001');
    expect(queue.events.single.driverId, 'DRIVER-001');
    expect(queue.events.single.idempotencyKey, isNotEmpty);
    expect(queue.events.single.syncStatus, QueueSyncStatus.pending);
  });

  testWidgets('queued Driver visual action shows an honest notice', (
    tester,
  ) async {
    final queue = _RecordingDriverTripActionQueue();
    final controller = DriverTripActionResilienceController(
      isOnline: () async => false,
      queue: queue,
      tripReference: 'TRIP-GHANA-002',
      driverId: 'DRIVER-002',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: DriverTripVisualSequencePage(actionRecorder: controller),
      ),
    );

    final action = find.byKey(const Key('driver-mark-arrived-pickup'));
    await tester.ensureVisible(action);
    await tester.pumpAndSettle();
    await tester.tap(action);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('driver-trip-action-queued-snackbar')),
      findsOneWidget,
    );
    expect(find.textContaining('Saved on this device'), findsOneWidget);
    expect(
      queue.events.single.eventType,
      '/api/driver/trips/TRIP-GHANA-002/actions/arrived-pickup/',
    );
    expect(queue.events.single.payloadJson, isEmpty);
  });
}

final class _FakeGhanaConnectivitySource implements GhanaConnectivitySource {
  _FakeGhanaConnectivitySource(this.current);

  List<ConnectivityResult> current;
  final StreamController<List<ConnectivityResult>> _controller =
      StreamController<List<ConnectivityResult>>.broadcast();

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => current;

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      _controller.stream;

  void emit(List<ConnectivityResult> results) {
    current = results;
    _controller.add(results);
  }

  Future<void> close() => _controller.close();
}

final class _RecordingDriverTripActionQueue implements DriverTripActionQueue {
  final events = <QueuedEvent>[];

  @override
  Future<QueuedEvent> enqueue(QueuedEvent event) async {
    events.add(event);
    return event;
  }
}
