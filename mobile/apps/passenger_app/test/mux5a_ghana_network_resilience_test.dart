import 'dart:async';

import 'package:asm_api_client/asm_api_client.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passenger_app/network/ghana_network_resilience.dart';

void main() {
  test('Ghana request profile matches the exact Ghana retry baseline', () {
    final client = GhanaResilientApiClient(baseUrl: 'https://example.test');

    expect(client.requestTimeout, const Duration(seconds: 15));
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
    expect(GhanaRequestPolicy.isSafeToRetry('GET', const {}), isTrue);
    expect(GhanaRequestPolicy.isSafeToRetry('HEAD', const {}), isTrue);
    expect(GhanaRequestPolicy.isSafeToRetry('POST', const {}), isFalse);
    expect(
      GhanaRequestPolicy.isSafeToRetry('POST', const {
        'Idempotency-Key': 'APP-safe-key',
      }),
      isTrue,
    );
  });

  test('safe failure waits 2s 4s 8s before the fourth attempt', () async {
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
              type: AsmApiExceptionType.network,
              message: 'offline',
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

  test('exhausted safe request returns failure for manual retry', () async {
    var attempts = 0;
    final delays = <Duration>[];
    final policy = GhanaRetryPolicy(
      delay: (duration) async => delays.add(duration),
    );

    final response = await policy.execute<String>(
      safeToRetry: true,
      operation: () async {
        attempts += 1;
        return ApiResponse.clientException(
          const AsmApiException(
            type: AsmApiExceptionType.timeout,
            message: 'timeout',
          ),
        );
      },
    );

    expect(response.error?.type, AsmApiExceptionType.timeout);
    expect(attempts, 4);
    expect(delays, GhanaRequestPolicy.retryBackoffs);
    expect(GhanaRequestPolicy.manualRetryMessage, contains('try again'));
  });

  test('unsafe POST-style work is not retried automatically', () async {
    var attempts = 0;
    final policy = GhanaRetryPolicy(delay: (_) async {});

    final response = await policy.execute<String>(
      safeToRetry: false,
      operation: () async {
        attempts += 1;
        return ApiResponse.clientException(
          const AsmApiException(
            type: AsmApiExceptionType.timeout,
            message: 'timeout',
          ),
        );
      },
    );

    expect(response.error?.type, AsmApiExceptionType.timeout);
    expect(attempts, 1);
  });

  test(
    'connectivity state combines cellular or Wi-Fi with API reachability',
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

      expect(monitor.state.status, GhanaNetworkStatus.online);
      expect(monitor.state.transport, GhanaNetworkTransport.wifi);

      monitor.dispose();
      await source.close();
    },
  );

  testWidgets('offline connectivity shows the Ghana network banner', (
    tester,
  ) async {
    final source = _FakeGhanaConnectivitySource(const <ConnectivityResult>[
      ConnectivityResult.none,
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: GhanaNetworkStatusBanner(
          baseUrl: 'https://example.test',
          offlineMessage: 'Poor or no connection.',
          connectivitySource: source,
          probe: (_, _) async => true,
          checkInterval: const Duration(hours: 1),
          child: const Scaffold(body: Text('Passenger content')),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const Key('ghana-network-offline-banner')),
      findsOneWidget,
    );
    expect(find.text('Poor or no connection.'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await source.close();
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
