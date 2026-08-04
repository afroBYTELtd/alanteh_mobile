import 'package:asm_design_system/asm_design_system.dart';
import 'package:asm_offline_queue/asm_offline_queue.dart';
import 'package:driver_app/driver_duty_trips.dart';
import 'package:driver_app/network/driver_trip_action_gateway.dart';
import 'package:driver_app/network/driver_trip_action_resilience.dart';
import 'package:driver_app/trip_progress/driver_trip_visual_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('test_completed_pending_review_appears_in_driver_trip_list', (
    tester,
  ) async {
    final trip = _completedTrip(
      reference: 'TRIP-PENDING',
      status: 'completed_pending_review',
    );

    await _pumpTripsList(tester, _ArchivalDriverDutyGateway(trips: [trip]));

    expect(find.byKey(const Key('driver-trip-TRIP-PENDING')), findsOneWidget);
    expect(find.text('Accra Mall → Ghana University'), findsOneWidget);
    expect(find.text('Awaiting review'), findsOneWidget);
  });

  testWidgets('test_completed_confirmed_appears_in_driver_trip_list', (
    tester,
  ) async {
    final trip = _completedTrip(
      reference: 'TRIP-CONFIRMED',
      status: 'completed_confirmed',
    );

    await _pumpTripsList(tester, _ArchivalDriverDutyGateway(trips: [trip]));

    expect(find.byKey(const Key('driver-trip-TRIP-CONFIRMED')), findsOneWidget);
    expect(find.text('Confirmed'), findsOneWidget);
  });

  testWidgets('test_completed_trip_card_shows_correct_review_status_label', (
    tester,
  ) async {
    final trips = <DriverAssignedTrip>[
      _completedTrip(
        reference: 'TRIP-MAP-PENDING',
        status: 'completed_pending_review',
      ),
      _completedTrip(
        reference: 'TRIP-MAP-CONFIRMED',
        status: 'completed_confirmed',
      ),
      _completedTrip(reference: 'TRIP-MAP-OVERDUE', status: 'review_overdue'),
    ];

    await _pumpTripsList(
      tester,
      _ArchivalDriverDutyGateway(trips: trips),
      size: const Size(430, 1800),
    );

    expect(find.text('Awaiting review'), findsOneWidget);
    expect(find.text('Confirmed'), findsOneWidget);
    expect(find.text('Review overdue'), findsOneWidget);
    expect(find.text('2026-08-01 15:45 UTC'), findsNWidgets(3));
  });

  testWidgets('test_completed_trip_detail_is_read_only', (tester) async {
    final trip = _completedTrip(
      reference: 'TRIP-READ-ONLY',
      status: 'completed_pending_review',
      assignmentReleased: false,
    );

    await _pumpTripDetail(
      tester,
      _ArchivalDriverDutyGateway(trips: [trip]),
      trip,
    );

    expect(find.text('Completed trip summary'), findsOneWidget);
    expect(find.text('Accra Mall → Ghana University'), findsOneWidget);
    expect(find.text('2026-08-01 15:45 UTC'), findsOneWidget);
    expect(find.text('Passengers'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Awaiting review'), findsOneWidget);
    expect(find.text('Assignment closed'), findsNothing);
    _expectNoLifecycleActions();
  });

  testWidgets('test_no_action_buttons_on_completed_trip', (tester) async {
    for (final status in driverTerminalTripStatuses) {
      var actionFactoryCalls = 0;
      final trip = _completedTrip(
        reference: 'TRIP-NO-ACTIONS-$status',
        status: status,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      tester.view.physicalSize = const Size(430, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: AsmThemes.driver,
          home: DriverTripDetailScreen(
            gateway: _ArchivalDriverDutyGateway(trips: [trip]),
            tripReference: trip.reference,
            actionControllerFactory: (reference) async {
              actionFactoryCalls += 1;
              return DriverTripActionResilienceController(
                queue: _RecordingQueue(),
                tripReference: reference,
                driverId: 'DRV-TERMINAL',
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      _expectNoLifecycleActions();
      expect(
        find.byKey(const Key('driver-open-live-trip-actions')),
        findsNothing,
      );
      expect(actionFactoryCalls, 0);
    }
  });

  testWidgets('test_completed_trip_reopens_after_relaunch', (tester) async {
    final trip = _completedTrip(
      reference: 'TRIP-RELAUNCH',
      status: 'completed_confirmed',
      assignmentReleased: true,
    );
    final gateway = _ArchivalDriverDutyGateway(trips: [trip]);

    await _pumpTripsList(tester, gateway);
    await tester.tap(find.byKey(const Key('driver-trip-TRIP-RELAUNCH')));
    await tester.pumpAndSettle();

    expect(find.text('Completed trip summary'), findsOneWidget);
    expect(find.text('Confirmed'), findsOneWidget);
    expect(gateway.detailCalls, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    await _pumpTripsList(tester, gateway);
    expect(gateway.tripsCalls, 2);

    await tester.tap(find.byKey(const Key('driver-trip-TRIP-RELAUNCH')));
    await tester.pumpAndSettle();

    expect(find.text('Completed trip summary'), findsOneWidget);
    expect(find.text('Assignment closed'), findsOneWidget);
    expect(gateway.detailCalls, 2);
  });

  testWidgets('test_raw_backend_status_not_visible_on_completed_card', (
    tester,
  ) async {
    final terminalStatuses = driverTerminalTripStatuses.toList(growable: false);
    final trips = List<DriverAssignedTrip>.generate(
      terminalStatuses.length,
      (index) => _completedTrip(
        reference: 'TRIP-RAW-${index + 1}',
        status: terminalStatuses[index],
      ),
      growable: false,
    );

    await _pumpTripsList(
      tester,
      _ArchivalDriverDutyGateway(trips: trips),
      size: const Size(430, 1800),
    );

    for (final rawStatus in driverTerminalTripStatuses) {
      expect(find.text(rawStatus), findsNothing);
      expect(find.textContaining(rawStatus), findsNothing);
    }
  });

  testWidgets('test_assignment_released_state_shown_correctly', (tester) async {
    final released = _completedTrip(
      reference: 'TRIP-RELEASED',
      status: 'completed_confirmed',
      assignmentReleased: true,
    );

    await _pumpTripDetail(
      tester,
      _ArchivalDriverDutyGateway(trips: [released]),
      released,
    );

    expect(find.text('Assignment closed'), findsOneWidget);
    expect(find.text('released'), findsNothing);
    expect(find.text('active'), findsNothing);

    final active = _completedTrip(
      reference: 'TRIP-ACTIVE-ASSIGNMENT',
      status: 'completed_pending_review',
      assignmentReleased: false,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    await _pumpTripDetail(
      tester,
      _ArchivalDriverDutyGateway(trips: [active]),
      active,
    );

    expect(find.text('Assignment closed'), findsNothing);
    expect(find.text('Assignment'), findsNothing);
    expect(find.text('active'), findsNothing);
  });

  testWidgets('test_review_overdue_is_presented_explicitly', (tester) async {
    final trip = _completedTrip(
      reference: 'TRIP-OVERDUE',
      status: 'review_overdue',
    );

    await _pumpTripDetail(
      tester,
      _ArchivalDriverDutyGateway(trips: [trip]),
      trip,
    );

    expect(find.text('Review overdue'), findsOneWidget);
    expect(find.text('review_overdue'), findsNothing);
    _expectNoLifecycleActions();
  });

  test('test_terminal_actions_programmatically_guarded', () async {
    for (final status in driverTerminalTripStatuses) {
      final queue = _RecordingQueue();
      final gateway = _RecordingTripActionGateway();
      final controller = DriverTripActionResilienceController(
        queue: queue,
        gateway: gateway,
        tripReference: 'TRIP-GUARDED',
        driverId: 'DRV-GUARDED',
        readCurrentTripStatus: () async => status,
      );

      final result = await controller.recordAction(
        eventType: 'arrived-pickup',
        payload: const <String, Object?>{},
      );

      expect(result.canAdvance, isFalse);
      expect(result.disposition, DriverTripActionDisposition.rejected);
      expect(result.error?.type, DriverTripActionFailureType.invalidTransition);
      expect(queue.events, isEmpty);
      expect(gateway.calls, 0);
    }
  });

  test('test_terminal_visual_state_is_completed_for_all_review_states', () {
    for (final status in driverTerminalTripStatuses) {
      expect(
        DriverTripVisualState.fromBackendStatus(status).stage,
        DriverTripVisualStage.completed,
      );
    }
  });

  test('test_released_assignment_sets_assignment_released_true', () {
    final trip = DriverAssignedTrip.fromJson(const <String, Object?>{
      'trip_reference': 'TRIP-PARSER-RELEASED',
      'status': 'completed_confirmed',
      'assignment': <String, Object?>{
        'status': 'released',
        'released_at': '2026-08-01T16:00:00Z',
      },
    });

    expect(trip.assignmentReleased, isTrue);
  });

  test('test_active_assignment_sets_assignment_released_false', () {
    final trip = DriverAssignedTrip.fromJson(const <String, Object?>{
      'trip_reference': 'TRIP-PARSER-ACTIVE',
      'status': 'completed_pending_review',
      'assignment': <String, Object?>{'status': 'active'},
    });

    expect(trip.assignmentReleased, isFalse);
  });

  test('test_null_assignment_sets_assignment_released_false', () {
    final trip = DriverAssignedTrip.fromJson(const <String, Object?>{
      'trip_reference': 'TRIP-PARSER-UNASSIGNED',
      'status': 'completed_confirmed',
      'assignment': null,
    });

    expect(trip.assignmentReleased, isFalse);
  });

  testWidgets('test_assignment_closed_visible_when_assignment_released', (
    tester,
  ) async {
    final trip = DriverAssignedTrip.fromJson(const <String, Object?>{
      'trip_reference': 'TRIP-UI-RELEASED',
      'status': 'completed_confirmed',
      'pickup_location': 'Accra Mall',
      'destination': 'Ghana University',
      'completed_at': '2026-08-01T15:45:00Z',
      'passenger_count': 3,
      'assignment': <String, Object?>{
        'status': 'released',
        'released_at': '2026-08-01T16:00:00Z',
      },
    });

    await _pumpTripDetail(
      tester,
      _ArchivalDriverDutyGateway(trips: <DriverAssignedTrip>[trip]),
      trip,
    );

    expect(find.text('Assignment closed'), findsOneWidget);
    expect(find.text('completed_confirmed'), findsNothing);
  });

  testWidgets('test_assignment_closed_hidden_when_assignment_active', (
    tester,
  ) async {
    final trip = DriverAssignedTrip.fromJson(const <String, Object?>{
      'trip_reference': 'TRIP-UI-ACTIVE',
      'status': 'completed_pending_review',
      'pickup_location': 'Accra Mall',
      'destination': 'Ghana University',
      'completed_at': '2026-08-01T15:45:00Z',
      'passenger_count': 3,
      'assignment': <String, Object?>{'status': 'active'},
    });

    await _pumpTripDetail(
      tester,
      _ArchivalDriverDutyGateway(trips: <DriverAssignedTrip>[trip]),
      trip,
    );

    expect(find.text('Assignment closed'), findsNothing);
    expect(find.text('Assignment'), findsNothing);
  });

  testWidgets('test_assignment_closed_hidden_when_unassigned', (tester) async {
    final trip = DriverAssignedTrip.fromJson(const <String, Object?>{
      'trip_reference': 'TRIP-UI-UNASSIGNED',
      'status': 'completed_confirmed',
      'pickup_location': 'Accra Mall',
      'destination': 'Ghana University',
      'completed_at': '2026-08-01T15:45:00Z',
      'passenger_count': 3,
      'assignment': null,
    });

    await _pumpTripDetail(
      tester,
      _ArchivalDriverDutyGateway(trips: <DriverAssignedTrip>[trip]),
      trip,
    );

    expect(find.text('Assignment closed'), findsNothing);
    expect(find.text('Assignment'), findsNothing);
  });

  test('test_existing_trip_detail_payload_decodes_archival_fields', () {
    final trip = DriverAssignedTrip.fromJson(const <String, Object?>{
      'trip_reference': 'TRIP-DECODED',
      'status': 'completed_confirmed',
      'pickup_location': 'Accra Mall',
      'destination': 'Ghana University',
      'completed_at': '2026-08-01T15:45:00Z',
      'passenger_count': 3,
      'assignment': <String, Object?>{
        'assignment_status': 'released',
        'released_at': '2026-08-01T16:00:00Z',
      },
    });

    expect(trip.completedTime, '2026-08-01T15:45:00Z');
    expect(trip.assignmentReleased, isTrue);
    expect(driverTripCompletionDateTimeLabel(trip), '2026-08-01 15:45 UTC');
  });
}

Future<void> _pumpTripsList(
  WidgetTester tester,
  _ArchivalDriverDutyGateway gateway, {
  Size size = const Size(430, 1400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: AsmThemes.driver,
      home: DriverAssignedTripsScreen(gateway: gateway),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpTripDetail(
  WidgetTester tester,
  _ArchivalDriverDutyGateway gateway,
  DriverAssignedTrip trip,
) async {
  tester.view.physicalSize = const Size(430, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: AsmThemes.driver,
      home: DriverTripDetailScreen(
        gateway: gateway,
        tripReference: trip.reference,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void _expectNoLifecycleActions() {
  for (final text in const <String>[
    'Arrived at pickup',
    "I've arrived",
    'Start trip',
    'Arrived at destination',
    'Complete trip',
    'Continue live trip',
  ]) {
    expect(find.text(text), findsNothing);
  }

  for (final key in const <Key>[
    Key('driver-mark-arrived-pickup'),
    Key('driver-confirm-onboard'),
    Key('driver-mark-arrived-destination'),
    Key('driver-complete-trip'),
    Key('driver-open-live-trip-actions'),
  ]) {
    expect(find.byKey(key), findsNothing);
  }
}

DriverAssignedTrip _completedTrip({
  required String reference,
  required String status,
  bool? assignmentReleased,
}) {
  return DriverAssignedTrip(
    reference: reference,
    status: status,
    pickupLocation: 'Accra Mall',
    destination: 'Ghana University',
    requestedPickupTime: '2026-08-01T14:00:00Z',
    createdTime: '2026-08-01T13:30:00Z',
    updatedTime: '2026-08-01T16:00:00Z',
    completedTime: '2026-08-01T15:45:00Z',
    passengerCount: 3,
    controlCenterMessage: 'Internal message must not appear.',
    assignmentReleased: assignmentReleased,
  );
}

final class _ArchivalDriverDutyGateway implements DriverDutyGateway {
  _ArchivalDriverDutyGateway({required this.trips});

  final List<DriverAssignedTrip> trips;
  int tripsCalls = 0;
  int detailCalls = 0;

  @override
  Future<DriverDutySummary> fetchDuty() async {
    return const DriverDutySummary(driverReference: 'DRV-ARCHIVAL');
  }

  @override
  Future<List<DriverAssignedTrip>> fetchTrips() async {
    tripsCalls += 1;
    return List<DriverAssignedTrip>.unmodifiable(trips);
  }

  @override
  Future<DriverAssignedTrip> fetchTripDetail(String tripReference) async {
    detailCalls += 1;
    return trips.singleWhere((trip) => trip.reference == tripReference);
  }
}

final class _RecordingQueue implements DriverTripActionPersistentQueue {
  final List<QueuedEvent> events = <QueuedEvent>[];

  @override
  Future<QueuedEvent> enqueue(QueuedEvent event) async {
    events.add(event);
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
    return List<QueuedEvent>.unmodifiable(events);
  }

  @override
  Future<void> markSynced(String id) async {}

  @override
  Future<void> markFailed(String id) async {}

  @override
  Future<void> markPermanentlyFailed(String id) async {}
}

final class _RecordingTripActionGateway implements DriverTripActionGateway {
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
      message: 'Recorded.',
      duplicate: false,
    );
  }
}
