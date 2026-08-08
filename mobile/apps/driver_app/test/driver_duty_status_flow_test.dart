import 'dart:async';

import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_app_config/asm_app_config.dart';
import 'package:asm_auth/asm_auth.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:asm_offline_queue/asm_offline_queue.dart';
import 'package:driver_app/driver_duty_trips.dart';
import 'package:driver_app/driver_home.dart';
import 'package:driver_app/driver_shell.dart';
import 'package:driver_app/network/driver_trip_action_gateway.dart';
import 'package:driver_app/network/driver_trip_action_resilience.dart';
import 'package:driver_app/readiness/driver_readiness_check.dart';
import 'package:driver_app/readiness/driver_shift_check_submission.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 8, 7, 8);

  test('test_nested_offline_no_check_decodes_correctly', () {
    final summary = DriverDutySummary.fromJson(const <String, Object?>{
      'duty': <String, Object?>{
        'duty_status': 'offline',
        'shift_check_today': false,
      },
    });

    expect(summary.dutyStatus, 'offline');
    expect(summary.shiftCheckToday, isFalse);
  });

  test('test_nested_online_with_check_decodes_correctly', () {
    final summary = DriverDutySummary.fromJson(const <String, Object?>{
      'duty': <String, Object?>{
        'duty_status': 'online',
        'shift_check_today': true,
        'shift_check_today_reference': 'SC-QA-DRV-001-20260807',
      },
    });

    expect(summary.dutyStatus, 'online');
    expect(summary.shiftCheckToday, isTrue);
    expect(summary.shiftCheckTodayReference, 'SC-QA-DRV-001-20260807');
  });

  test('test_nested_duty_since_decodes_correctly', () {
    final summary = DriverDutySummary.fromJson(const <String, Object?>{
      'duty': <String, Object?>{
        'duty_since': '2026-08-07T23:35:37Z',
      },
    });

    expect(summary.dutySince, DateTime.parse('2026-08-07T23:35:37Z'));
  });

  test('test_top_level_duty_status_not_used', () {
    final summary = DriverDutySummary.fromJson(const <String, Object?>{
      'duty_status': 'online',
      'duty': <String, Object?>{
        'duty_status': 'offline',
      },
    });

    expect(summary.dutyStatus, 'offline');
  });

  test('test_null_duty_object_produces_safe_defaults', () {
    final summary = DriverDutySummary.fromJson(const <String, Object?>{
      'duty': null,
    });

    expect(summary.dutyStatus, isNull);
    expect(summary.shiftCheckToday, isFalse);
  });

  testWidgets(
    'test_offline_no_check_does_not_render_home_before_shift_check_route',
    (tester) async {
      final firstDuty = Completer<DriverDutySummary>();
      final summary = DriverDutySummary(
        dutyStatus: 'offline',
        dutySince: now.subtract(const Duration(days: 1)),
        shiftCheckToday: false,
      );
      final gateway = _MutableDutyGateway(
        summary,
        firstDutyCompleter: firstDuty,
      );

      await tester.pumpWidget(
        _testApp(DriverShell(driverDutyGateway: gateway, deviceNow: () => now)),
      );

      expect(
        find.byKey(const Key('driver-duty-startup-loading')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('driver-home-assigned-trips-card')),
        findsNothing,
      );

      firstDuty.complete(summary);
      await tester.pump();

      expect(
        find.byKey(const Key('driver-duty-startup-loading')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('driver-home-assigned-trips-card')),
        findsNothing,
        reason:
            'DriverHome must not render in the frame before required '
            'startup shift-check navigation.',
      );
      expect(find.text('START SHIFT CHECK'), findsNothing);
      expect(gateway.dutyCalls, 1);
    },
  );

  testWidgets(
    'test_offline_no_check_shift_check_is_first_duty_flow_destination',
    (tester) async {
      final firstDuty = Completer<DriverDutySummary>();
      final summary = DriverDutySummary(
        dutyStatus: 'offline',
        dutySince: now.subtract(const Duration(days: 1)),
        shiftCheckToday: false,
      );
      final gateway = _MutableDutyGateway(
        summary,
        firstDutyCompleter: firstDuty,
      );

      await tester.pumpWidget(
        _testApp(DriverShell(driverDutyGateway: gateway, deviceNow: () => now)),
      );

      firstDuty.complete(summary);
      await tester.pump();

      expect(
        find.byKey(const Key('driver-home-assigned-trips-card')),
        findsNothing,
      );

      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const Key('driver-shift-readiness-screen')),
        findsOneWidget,
      );
      expect(
        find.text(
          'Complete these checks once before your first trip of the day.',
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('driver-home-assigned-trips-card')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'test_offline_check_done_preserves_existing_offline_home_startup',
    (tester) async {
      final gateway = _MutableDutyGateway(
        DriverDutySummary(
          dutyStatus: 'offline',
          dutySince: now.subtract(const Duration(hours: 1)),
          shiftCheckToday: true,
        ),
      );

      await tester.pumpWidget(
        _testApp(DriverShell(driverDutyGateway: gateway, deviceNow: () => now)),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('driver-shift-readiness-screen')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('driver-home-assigned-trips-card')),
        findsOneWidget,
      );
      expect(find.text("Today's shift · offline"), findsOneWidget);
      expect(find.text('GO ONLINE'), findsOneWidget);
    },
  );

  testWidgets(
    'test_online_startup_preserves_existing_online_home_without_shift_check',
    (tester) async {
      final gateway = _MutableDutyGateway(
        DriverDutySummary(
          dutyStatus: 'online',
          dutySince: now.subtract(const Duration(minutes: 5)),
          shiftCheckToday: true,
        ),
      );

      await tester.pumpWidget(
        _testApp(DriverShell(driverDutyGateway: gateway, deviceNow: () => now)),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('driver-shift-readiness-screen')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('driver-home-assigned-trips-card')),
        findsOneWidget,
      );
      expect(find.text("You're online"), findsOneWidget);
      expect(find.text('GO OFFLINE'), findsOneWidget);
    },
  );

  testWidgets('test_first_shift_check_today_transitions_to_online_directly', (
    tester,
  ) async {
    final dutyGateway = _MutableDutyGateway(
      DriverDutySummary(
        driverReference: 'DRV-001',
        dutyStatus: 'offline',
        dutySince: DateTime(2026, 8, 6, 8),
        shiftCheckToday: false,
      ),
    );
    final queue = _MemoryQueue();
    final shiftGateway = _SuccessfulShiftCheckGateway(
      onSubmit: () {
        dutyGateway.current = DriverDutySummary(
          driverReference: 'DRV-001',
          dutyStatus: 'online',
          dutySince: now,
          shiftCheckToday: true,
          shiftCheckTodayReference: 'SC-QA-DRV-001-20260807',
        );
      },
    );
    final controller = DriverShiftCheckSubmissionController(
      queue: queue,
      gateway: shiftGateway,
      isOnline: () async => true,
    );

    await tester.pumpWidget(
      _testApp(
        DriverShell(
          driverDutyGateway: dutyGateway,
          driverShiftCheckController: controller,
          deviceNow: () => now,
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('driver-shift-readiness-screen')),
      findsOneWidget,
    );
    expect(
      find.text(
        'Complete these checks once before your first trip of the day.',
      ),
      findsOneWidget,
    );

    await _completeReadiness(tester);
    await tester.tap(find.byKey(const Key('readiness-ready')));
    await tester.pump();
    await tester.pump();

    expect(shiftGateway.calls, 1);

    await tester.pump(const Duration(milliseconds: 350));
    expect(dutyGateway.dutyCalls, greaterThanOrEqualTo(2));

    expect(find.byKey(const Key('driver-online-transition')), findsOneWidget);
    expect(find.text('Shift check submitted.'), findsOneWidget);
    expect(find.text('You are now online.'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(find.text("Today's shift · online now"), findsOneWidget);
    expect(find.text("You're online"), findsOneWidget);
    expect(find.text("Today's shift · offline"), findsNothing);
    expect(dutyGateway.dutyCalls, greaterThanOrEqualTo(2));

    await controller.stopAutomaticSync();
  });

  testWidgets('test_shift_check_today_true_skips_shift_check_screen', (
    tester,
  ) async {
    final gateway = _MutableDutyGateway(
      DriverDutySummary(
        dutyStatus: 'offline',
        dutySince: now.subtract(const Duration(hours: 1)),
        shiftCheckToday: true,
      ),
    );

    await tester.pumpWidget(
      _testApp(DriverShell(driverDutyGateway: gateway, deviceNow: () => now)),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('driver-shift-readiness-screen')),
      findsNothing,
    );
    expect(find.text('GO ONLINE'), findsOneWidget);
    expect(find.text('START SHIFT CHECK'), findsNothing);
  });

  testWidgets('test_shift_check_today_false_shows_shift_check_screen', (
    tester,
  ) async {
    final gateway = _MutableDutyGateway(
      DriverDutySummary(
        dutyStatus: 'offline',
        dutySince: now.subtract(const Duration(days: 1)),
        shiftCheckToday: false,
      ),
    );

    await tester.pumpWidget(
      _testApp(DriverShell(driverDutyGateway: gateway, deviceNow: () => now)),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('driver-shift-readiness-screen')),
      findsOneWidget,
    );
  });

  testWidgets('test_duty_since_not_used_for_shift_check_inference', (
    tester,
  ) async {
    final gateway = _MutableDutyGateway(
      DriverDutySummary(
        dutyStatus: 'offline',
        dutySince: now,
        shiftCheckToday: false,
      ),
    );

    await tester.pumpWidget(
      _testApp(DriverShell(driverDutyGateway: gateway, deviceNow: () => now)),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('driver-shift-readiness-screen')),
      findsOneWidget,
      reason:
          "Today's duty_since must not imply that today's shift check exists.",
    );
  });

  testWidgets('test_go_offline_calls_duty_endpoint_with_offline', (
    tester,
  ) async {
    final gateway = _MutableDutyGateway(
      DriverDutySummary(
        dutyStatus: 'online',
        dutySince: now.subtract(const Duration(minutes: 30)),
        shiftCheckToday: true,
      ),
      transitionNow: now,
    );

    await tester.pumpWidget(
      _testApp(DriverShell(driverDutyGateway: gateway, deviceNow: () => now)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('driver-go-offline')));
    await tester.pumpAndSettle();

    expect(gateway.transitionStatuses, <DriverOperationalDutyStatus>[
      DriverOperationalDutyStatus.offline,
    ]);
    expect(find.text("Today's shift · offline"), findsOneWidget);
    expect(find.text('GO ONLINE'), findsOneWidget);
  });

  testWidgets('test_go_online_calls_duty_endpoint_with_online', (tester) async {
    final gateway = _MutableDutyGateway(
      DriverDutySummary(
        dutyStatus: 'offline',
        dutySince: now.subtract(const Duration(minutes: 30)),
        shiftCheckToday: true,
      ),
      transitionNow: now,
    );

    await tester.pumpWidget(
      _testApp(DriverShell(driverDutyGateway: gateway, deviceNow: () => now)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('driver-go-online')));
    await tester.pumpAndSettle();

    expect(gateway.transitionStatuses, <DriverOperationalDutyStatus>[
      DriverOperationalDutyStatus.online,
    ]);
    expect(find.text("Today's shift · online now"), findsOneWidget);
    expect(find.text('GO OFFLINE'), findsOneWidget);
  });

  testWidgets(
    'test_complete_readiness_check_not_visible_after_shift_check_done',
    (tester) async {
      final gateway = _MutableDutyGateway(
        DriverDutySummary(
          dutyStatus: 'offline',
          dutySince: now.subtract(const Duration(hours: 2)),
          shiftCheckToday: true,
        ),
      );

      await tester.pumpWidget(
        _testApp(DriverShell(driverDutyGateway: gateway, deviceNow: () => now)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Complete readiness check'), findsNothing);
      expect(find.text('START SHIFT CHECK'), findsNothing);
      expect(find.text('GO ONLINE'), findsOneWidget);
    },
  );

  testWidgets('test_shift_check_screen_not_shown_if_already_done_today', (
    tester,
  ) async {
    final gateway = _MutableDutyGateway(
      DriverDutySummary(
        dutyStatus: 'offline',
        dutySince: now.subtract(const Duration(minutes: 10)),
        shiftCheckToday: true,
      ),
    );

    await tester.pumpWidget(
      _testApp(DriverShell(driverDutyGateway: gateway, deviceNow: () => now)),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('driver-shift-readiness-screen')),
      findsNothing,
    );
    expect(find.text('Shift check'), findsNothing);
  });

  testWidgets('test_online_state_shows_correct_wording', (tester) async {
    final gateway = _MutableDutyGateway(
      DriverDutySummary(
        dutyStatus: 'online',
        dutySince: now.subtract(const Duration(minutes: 5)),
        shiftCheckToday: true,
      ),
    );

    await tester.pumpWidget(
      _testApp(DriverShell(driverDutyGateway: gateway, deviceNow: () => now)),
    );
    await tester.pumpAndSettle();

    for (final text in <String>[
      "Today's shift · online now",
      "You're online",
      'Ready to receive nearby ride offers.',
      'Waiting for offers',
      'WAITING FOR A RIDE OFFER NEARBY',
      'Stay in your zone for faster matches.',
      'GO OFFLINE',
    ]) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
  });

  testWidgets('test_offline_state_post_check_shows_correct_wording', (
    tester,
  ) async {
    final gateway = _MutableDutyGateway(
      DriverDutySummary(
        dutyStatus: 'offline',
        dutySince: now.subtract(const Duration(hours: 3)),
        shiftCheckToday: true,
      ),
    );

    await tester.pumpWidget(
      _testApp(DriverShell(driverDutyGateway: gateway, deviceNow: () => now)),
    );
    await tester.pumpAndSettle();

    expect(find.text("Today's shift · offline"), findsOneWidget);
    expect(find.text("You're offline"), findsOneWidget);
    expect(find.text('GO ONLINE'), findsOneWidget);
    expect(find.text('START SHIFT CHECK'), findsNothing);
    expect(find.text('Complete readiness check'), findsNothing);
  });

  testWidgets('test_offline_state_no_check_shows_correct_wording', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        DriverHome(
          market: MarketConfig.ghanaAccra,
          isOnShift: false,
          shiftCheckCompletedToday: false,
          dutyActionInFlight: false,
          onOpenReadiness: () {},
          onGoOnline: null,
          onGoOffline: null,
          onRecordConcern: () {},
          onPreviewIncomingRequest: () {},
          localQaEnabled: false,
          dutyGateway: null,
          onOpenAssignedTrips: () {},
          onOpenShiftSummary: () {},
        ),
      ),
    );

    expect(find.text("Today's shift · not yet started"), findsOneWidget);
    expect(find.text("You're offline"), findsOneWidget);
    expect(
      find.text('Complete your pre-shift check to go online.'),
      findsOneWidget,
    );
    expect(find.text('START SHIFT CHECK'), findsOneWidget);
    expect(
      find.text('Complete readiness before starting your shift.'),
      findsNothing,
    );
  });

  test('test_token_refreshed_before_duty_post', () async {
    const expiredToken = 'e30.eyJleHAiOjF9.';
    const refreshedToken = 'e30.eyJleHAiOjQxMDI0NDQ4MDB9.';

    final tokenStore = _MutableTokenStore(expiredToken);
    final apiClient = _RecordingDutyApiClient();
    var refreshCalls = 0;

    final gateway = AsmDriverDutyGateway.withApiClient(
      apiClient: apiClient,
      tokenStore: tokenStore,
      refreshAccessToken: () async {
        refreshCalls += 1;
        tokenStore.accessToken = refreshedToken;
        return DriverTokenRefreshOutcome.refreshed;
      },
      dutyRetryDelay: (_) async {},
    );

    final transition = await gateway.updateDutyStatus(
      DriverOperationalDutyStatus.online,
    );

    expect(transition.dutyStatus, 'online');
    expect(refreshCalls, 1);
    expect(apiClient.postCalls, 1);
    expect(apiClient.paths.single, driverDutyStatusPath);
    expect(apiClient.headers.single['Authorization'], 'Bearer $refreshedToken');
    expect(apiClient.bodies.single, <String, Object?>{'status': 'online'});
  });

  test('test_duty_call_not_queued_on_failure', () async {
    const validToken = 'e30.eyJleHAiOjQxMDI0NDQ4MDB9.';

    final tokenStore = _MutableTokenStore(validToken);
    final apiClient = _FailingDutyApiClient();

    final gateway = AsmDriverDutyGateway.withApiClient(
      apiClient: apiClient,
      tokenStore: tokenStore,
      refreshAccessToken: () async => DriverTokenRefreshOutcome.sessionExpired,
      dutyRetryDelay: (_) async {},
    );

    await expectLater(
      gateway.updateDutyStatus(DriverOperationalDutyStatus.online),
      throwsA(isA<DriverDutyApiException>()),
    );

    expect(apiClient.postCalls, 4);

    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(
      apiClient.postCalls,
      4,
      reason: 'No deferred queue or later duty delivery may remain.',
    );
  });
}

Widget _testApp(Widget home) {
  return MaterialApp(theme: AsmThemes.driver, home: home);
}

Future<void> _completeReadiness(WidgetTester tester) async {
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

final class _MutableDutyGateway
    implements DriverDutyGateway, DriverDutyStatusGateway {
  _MutableDutyGateway(
    this.current, {
    DateTime? transitionNow,
    this._firstDutyCompleter,
  }) : transitionNow = transitionNow ?? DateTime(2026, 8, 7, 8);

  DriverDutySummary current;
  final DateTime transitionNow;
  final Completer<DriverDutySummary>? _firstDutyCompleter;

  int dutyCalls = 0;
  final List<DriverOperationalDutyStatus> transitionStatuses =
      <DriverOperationalDutyStatus>[];

  @override
  Future<DriverDutySummary> fetchDuty() async {
    dutyCalls += 1;
    if (dutyCalls == 1 && _firstDutyCompleter != null) {
      return _firstDutyCompleter.future;
    }
    return current;
  }

  @override
  Future<List<DriverAssignedTrip>> fetchTrips() async {
    return const <DriverAssignedTrip>[];
  }

  @override
  Future<DriverAssignedTrip> fetchTripDetail(String tripReference) async {
    throw StateError('Trip detail not used in duty-status tests.');
  }

  @override
  Future<DriverDutyTransition> updateDutyStatus(
    DriverOperationalDutyStatus status,
  ) async {
    transitionStatuses.add(status);

    final transition = DriverDutyTransition(
      dutyStatus: status.wireValue,
      since: transitionNow,
    );

    current = current.withDutyTransition(transition);
    return transition;
  }
}

final class _SuccessfulShiftCheckGateway implements DriverShiftCheckGateway {
  _SuccessfulShiftCheckGateway({this.onSubmit});

  final VoidCallback? onSubmit;
  int calls = 0;

  @override
  Future<ApiResponse<Object?>> submit({
    required Map<String, Object?> body,
    required String idempotencyKey,
  }) async {
    calls += 1;
    onSubmit?.call();

    return ApiResponse<Object?>.success(const <String, Object?>{
      'ok': true,
    }, statusCode: 201);
  }
}

final class _MemoryQueue implements DriverTripActionPersistentQueue {
  final Map<String, QueuedEvent> _events = <String, QueuedEvent>{};

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
    final event = _events[id];
    if (event != null) {
      _events[id] = event.copyWith(syncStatus: QueueSyncStatus.synced);
    }
  }

  @override
  Future<void> markFailed(String id) async {
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
    final event = _events[id];
    if (event != null) {
      _events[id] = event.copyWith(
        syncStatus: QueueSyncStatus.permanentlyFailed,
      );
    }
  }
}

final class _MutableTokenStore implements AuthTokenStore {
  _MutableTokenStore(this.accessToken);

  String? accessToken;

  @override
  Future<void> saveTokens(AuthTokens tokens) async {
    accessToken = tokens.accessToken;
  }

  @override
  Future<String?> readAccessToken() async => accessToken;

  @override
  Future<String?> readRefreshToken() async => null;

  @override
  Future<void> clearTokens() async {
    accessToken = null;
  }
}

final class _RecordingDutyApiClient
    implements DriverDutyApiClient, DriverDutyPostApiClient {
  int postCalls = 0;
  final List<String> paths = <String>[];
  final List<Object?> bodies = <Object?>[];
  final List<Map<String, String>> headers = <Map<String, String>>[];

  @override
  Future<ApiResponse<T>> get<T>(String path, {JsonDecoder<T>? decoder}) async {
    throw StateError('GET not used by this gateway test.');
  }

  @override
  Future<ApiResponse<T>> post<T>(
    String path, {
    Object? data,
    Map<String, String>? headers,
    JsonDecoder<T>? decoder,
  }) async {
    postCalls += 1;
    paths.add(path);
    bodies.add(data);
    this.headers.add(<String, String>{...?headers});

    final decoded = decoder!(<String, Object?>{
      'duty_status': 'online',
      'since': '2026-08-07T08:00:00Z',
    });

    return ApiResponse<T>.success(decoded, statusCode: 200);
  }
}

final class _FailingDutyApiClient
    implements DriverDutyApiClient, DriverDutyPostApiClient {
  int postCalls = 0;

  @override
  Future<ApiResponse<T>> get<T>(String path, {JsonDecoder<T>? decoder}) async {
    throw StateError('GET not used by this gateway test.');
  }

  @override
  Future<ApiResponse<T>> post<T>(
    String path, {
    Object? data,
    Map<String, String>? headers,
    JsonDecoder<T>? decoder,
  }) async {
    postCalls += 1;

    return ApiResponse<T>.apiFailure(
      const AsmApiException(
        type: AsmApiExceptionType.network,
        message: 'Network unavailable.',
      ),
    );
  }
}
