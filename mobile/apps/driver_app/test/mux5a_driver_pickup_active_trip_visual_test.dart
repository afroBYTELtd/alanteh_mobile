import 'dart:async';

import 'package:asm_app_config/asm_app_config.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:asm_offline_queue/asm_offline_queue.dart';
import 'package:driver_app/ride_offer/driver_ride_offer_page.dart';
import 'package:driver_app/trip_progress/driver_trip_route.dart';
import 'package:driver_app/network/driver_trip_action_gateway.dart';
import 'package:driver_app/network/driver_trip_action_resilience.dart';
import 'package:driver_app/trip_progress/driver_trip_visual_sequence.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('pickup route renders map, static pin, and details sheet', (
    tester,
  ) async {
    _useSurface(tester);

    await _pumpTripSequence(tester);

    expect(find.byKey(const Key('driver-navigate-to-pickup')), findsOneWidget);
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.byType(PolylineLayer), findsOneWidget);
    expect(find.byKey(const Key('driver-static-position-pin')), findsOneWidget);
    expect(find.byKey(const Key('driver-pickup-position-pin')), findsOneWidget);
    expect(
      find.byKey(const Key('driver-destination-position-pin')),
      findsNothing,
    );
    expect(find.text('Heading to pickup'), findsOneWidget);
    expect(find.text('Accra Mall'), findsWidgets);
    expect(find.textContaining('1.2 km'), findsOneWidget);
    expect(find.textContaining('about 5 min'), findsOneWidget);
  });

  testWidgets('pickup arrival and passenger-onboard confirmation work', (
    tester,
  ) async {
    _useSurface(tester);

    await _pumpTripSequence(tester);

    await _tapVisible(
      tester,
      find.byKey(const Key('driver-mark-arrived-pickup')),
    );

    expect(find.byKey(const Key('driver-arrived-at-pickup')), findsOneWidget);
    expect(find.text("You've arrived"), findsOneWidget);
    expect(find.text('Confirm passenger onboard'), findsOneWidget);

    await _tapVisible(
      tester,
      find.byKey(const Key('driver-open-onboard-confirmation')),
    );

    expect(
      find.byKey(const Key('driver-confirm-passenger-onboard')),
      findsOneWidget,
    );
    expect(find.text('Confirm passenger onboard'), findsOneWidget);
    expect(find.text('Start trip'), findsOneWidget);
    expect(find.text('Back'), findsOneWidget);

    await _tapVisible(
      tester,
      find.byKey(const Key('driver-cancel-onboard-confirmation')),
    );

    expect(find.byKey(const Key('driver-arrived-at-pickup')), findsOneWidget);
  });

  testWidgets('confirmed passenger opens active trip destination map', (
    tester,
  ) async {
    _useSurface(tester);

    await _openActiveTrip(tester);

    expect(find.byKey(const Key('driver-active-trip')), findsOneWidget);
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.byKey(const Key('driver-static-position-pin')), findsOneWidget);
    expect(
      find.byKey(const Key('driver-destination-position-pin')),
      findsOneWidget,
    );
    expect(find.text('Trip in progress'), findsOneWidget);
    expect(find.text('Heading to Accra Market'), findsOneWidget);
    expect(find.textContaining('9.5 km'), findsOneWidget);
    expect(find.textContaining('about 23 min'), findsOneWidget);
    expect(find.text('Arrived at destination'), findsOneWidget);
  });

  testWidgets('destination arrival completes the local visual sequence', (
    tester,
  ) async {
    _useSurface(tester);

    await _openActiveTrip(tester);

    await _tapVisible(
      tester,
      find.byKey(const Key('driver-mark-arrived-destination')),
    );

    expect(
      find.byKey(const Key('driver-arrived-at-destination')),
      findsOneWidget,
    );
    expect(find.text('Arrived at destination'), findsWidgets);
    expect(find.text('Complete trip'), findsOneWidget);

    await _tapVisible(tester, find.byKey(const Key('driver-complete-trip')));

    expect(find.byKey(const Key('driver-trip-completed')), findsOneWidget);
    expect(
      find.text('Trip completed — awaiting operations review'),
      findsWidgets,
    );
    expect(find.text('Accra Mall → Accra Market'), findsOneWidget);
    expect(find.text('9.5 km'), findsOneWidget);
    expect(find.text('23 min'), findsOneWidget);
    expect(find.text('Passengers'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(
      find.text(
        'Completion is not confirmed until ALANTEH operations reviews the trip.',
      ),
      findsOneWidget,
    );
    expect(find.text('Back to home'), findsOneWidget);
  });

  testWidgets('accepted ride offer opens Navigate to pickup sequence', (
    tester,
  ) async {
    _useSurface(tester);

    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.driver,
        home: const DriverRideOfferPage(market: MarketConfig.ghanaAccra),
      ),
    );

    await _tapVisible(tester, find.byKey(const Key('view-ride-offer-details')));
    await _tapVisible(
      tester,
      find.byKey(const Key('accept-ride-offer-preview')),
    );

    expect(find.text('Ride accepted'), findsOneWidget);
    expect(find.text('Navigate to pickup'), findsOneWidget);

    await _tapVisible(
      tester,
      find.byKey(const Key('navigate-to-pickup-from-accepted')),
    );
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('driver-trip-sequence-page')), findsOneWidget);
    expect(find.byKey(const Key('driver-navigate-to-pickup')), findsOneWidget);
  });

  testWidgets(
    'live action disables immediately, ignores rapid taps, and advances only '
    'after confirmation',
    (tester) async {
      _useSurface(tester);
      final queue = _VisualPersistentQueue();
      final gateway = _PendingVisualActionGateway();
      final recorder = DriverTripActionResilienceController(
        queue: queue,
        gateway: gateway,
        tripReference: 'TRIP-VISUAL-001',
        driverId: 'DRIVER-VISUAL-001',
      );

      await _pumpTripSequence(tester, actionRecorder: recorder);

      final action = find.byKey(const Key('driver-mark-arrived-pickup'));
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.tap(action);
      await tester.pump();

      expect(gateway.calls, 1);
      expect(queue.events, hasLength(1));
      expect(tester.widget<FilledButton>(action).onPressed, isNull);
      expect(find.text('Confirming...'), findsOneWidget);
      expect(
        find.byKey(const Key('driver-navigate-to-pickup')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('driver-arrived-at-pickup')), findsNothing);

      gateway.complete();
      await tester.pumpAndSettle();

      expect(gateway.calls, 1);
      expect(find.byKey(const Key('driver-arrived-at-pickup')), findsOneWidget);
    },
  );

  testWidgets(
    'retryable live action failure never advances and re-enables manual retry',
    (tester) async {
      _useSurface(tester);
      final queue = _VisualPersistentQueue();
      final gateway = _FailingVisualActionGateway();
      final recorder = DriverTripActionResilienceController(
        queue: queue,
        gateway: gateway,
        tripReference: 'TRIP-VISUAL-002',
        driverId: 'DRIVER-VISUAL-002',
      );

      await _pumpTripSequence(tester, actionRecorder: recorder);

      final action = find.byKey(const Key('driver-mark-arrived-pickup'));
      await _tapVisible(tester, action);
      await tester.pumpAndSettle();

      expect(gateway.calls, 1);
      expect(queue.events, hasLength(1));
      expect(
        find.byKey(const Key('driver-navigate-to-pickup')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('driver-arrived-at-pickup')), findsNothing);
      expect(tester.widget<FilledButton>(action).onPressed, isNotNull);
      expect(
        find.byKey(const Key('driver-trip-action-queued-snackbar')),
        findsOneWidget,
      );
    },
  );

  test('route fallback exposes stable map coordinates', () {
    final pickup = safeDriverPickupRouteFallback();
    final destination = safeDriverDestinationRouteFallback();

    expect(pickup.usedFallback, isTrue);
    expect(destination.usedFallback, isTrue);
    expect(pickup.points.first, driverPickupStaticPosition);
    expect(destination.points.last, driverDestinationPosition);
  });
}

Future<void> _openActiveTrip(WidgetTester tester) async {
  await _pumpTripSequence(tester);

  await _tapVisible(
    tester,
    find.byKey(const Key('driver-mark-arrived-pickup')),
  );
  await _tapVisible(
    tester,
    find.byKey(const Key('driver-open-onboard-confirmation')),
  );
  await _tapVisible(tester, find.byKey(const Key('driver-confirm-onboard')));
}

Future<void> _pumpTripSequence(
  WidgetTester tester, {
  DriverTripActionResilienceController? actionRecorder,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AsmThemes.driver,
      home: DriverTripVisualSequencePage(actionRecorder: actionRecorder),
    ),
  );
  await tester.pump();
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
}

final class _VisualPersistentQueue implements DriverTripActionPersistentQueue {
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

final class _PendingVisualActionGateway implements DriverTripActionGateway {
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
        tripReference: 'TRIP-VISUAL-001',
        status: 'arrived_at_pickup',
        message: 'Arrival confirmed.',
        duplicate: false,
      ),
    );
  }
}

final class _FailingVisualActionGateway implements DriverTripActionGateway {
  int calls = 0;

  @override
  Future<DriverTripActionReceipt> submit({
    required DriverTripAction action,
    required String tripReference,
    required String idempotencyKey,
    Map<String, Object?> body = const <String, Object?>{},
  }) async {
    calls += 1;
    throw const DriverTripActionException(
      type: DriverTripActionFailureType.temporarilyUnavailable,
      message: 'Cannot confirm this action right now.',
    );
  }
}

void _useSurface(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(430, 1000);

  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });
}
