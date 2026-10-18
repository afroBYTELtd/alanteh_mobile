import 'package:asm_design_system/asm_design_system.dart';
import 'package:asm_maps/testing.dart';
import 'package:asm_offline_queue/asm_offline_queue.dart';
import 'package:driver_app/driver_duty_trips.dart';
import 'package:driver_app/driver_shell.dart';
import 'package:driver_app/network/driver_trip_action_gateway.dart';
import 'package:driver_app/network/driver_trip_action_resilience.dart';
import 'package:driver_app/trip_progress/driver_trip_visual_sequence.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Seen on the test phone (18 Oct, check 4): a trip opened from the Trips
// tab, cancelled by dispatch; "Back to Work" left the driver on Trips. It
// now shows Work whichever tab the trip was opened from.
void main() {
  const reference = 'TRIP-BTW-1';

  Future<_Gateway> pumpShell(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final gateway = _Gateway('driver_accepted');
    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.driver,
        home: DriverShell(
          driverDutyGateway: gateway,
          driverTripActionControllerFactory: _controllerFactory,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Waiting for offers'), findsOneWidget);
    return gateway;
  }

  Future<void> openFromTrips(WidgetTester tester) async {
    await tester.tap(find.text('Trips'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(reference));
    await tester.pumpAndSettle();
  }

  Future<void> openFromWork(WidgetTester tester, _Gateway gateway) async {
    // As the app opens an accepted offer or a push: the trip detail pushed
    // over the shell while Work is selected.
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push<void>(
      MaterialPageRoute<void>(
        builder: (_) => DriverTripDetailScreen(
          gateway: gateway,
          tripReference: reference,
          actionControllerFactory: _controllerFactory,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> cancelOnLiveScreen(WidgetTester tester, _Gateway gateway) async {
    final open = find.byKey(const Key('driver-open-live-trip-actions'));
    await tester.ensureVisible(open);
    await tester.pumpAndSettle();
    await tester.tap(open);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(asmFakeMapAnimationDuration);
    gateway.status = 'cancelled_by_operations';
    await tester.pump(driverLiveTripCheckInterval);
    await tester.pump();
    await tester.pump(asmFakeMapAnimationDuration);
    expect(find.byKey(const Key('driver-live-trip-cancelled')), findsOneWidget);
  }

  Future<void> expectWork(WidgetTester tester) async {
    await tester.pumpAndSettle();
    expect(find.text('Waiting for offers'), findsOneWidget);
    expect(find.byType(DriverAssignedTripsScreen), findsNothing);
    expect(find.byType(DriverTripDetailScreen), findsNothing);
  }

  testWidgets('from the Trips tab, Back to Work on the live card shows Work', (
    tester,
  ) async {
    final gateway = await pumpShell(tester);
    await openFromTrips(tester);
    await cancelOnLiveScreen(tester, gateway);

    await tester.tap(find.byKey(const Key('driver-live-trip-ended-back')));
    await expectWork(tester);
  });

  testWidgets('from Work, Back to Work on the live card shows Work', (
    tester,
  ) async {
    final gateway = await pumpShell(tester);
    await openFromWork(tester, gateway);
    await cancelOnLiveScreen(tester, gateway);

    await tester.tap(find.byKey(const Key('driver-live-trip-ended-back')));
    await expectWork(tester);
  });

  testWidgets('from the Trips tab, Back to Work on the trip detail card shows '
      'Work', (tester) async {
    final gateway = await pumpShell(tester);
    gateway.status = 'cancelled_by_passenger';
    await openFromTrips(tester);
    expect(find.byKey(const Key('driver-trip-cancelled')), findsOneWidget);

    await tester.tap(find.byKey(const Key('driver-trip-cancelled-back')));
    await expectWork(tester);
  });
}

Future<DriverTripActionResilienceController> _controllerFactory(
  String tripReference,
) async => DriverTripActionResilienceController(
  queue: _Queue(),
  gateway: _NoActions(),
  tripReference: tripReference,
  driverId: 'DRV-BTW',
);

final class _Gateway implements DriverDutyGateway {
  _Gateway(this.status);

  String status;

  @override
  Future<DriverDutySummary> fetchDuty() async => DriverDutySummary(
    driverReference: 'DRV-BTW',
    dutyStatus: 'online',
    dutySince: DateTime(2026, 10, 18, 8),
    shiftCheckToday: true,
  );

  @override
  Future<List<DriverAssignedTrip>> fetchTrips() async => [_trip()];

  @override
  Future<DriverAssignedTrip> fetchTripDetail(String tripReference) async =>
      _trip();

  DriverAssignedTrip _trip() => DriverAssignedTrip(
    reference: 'TRIP-BTW-1',
    status: status,
    pickupLocation: 'Near Accra Mall',
    destination: 'Airport, Terminal 3',
  );
}

final class _NoActions implements DriverTripActionGateway {
  @override
  Future<DriverTripActionReceipt> submit({
    required DriverTripAction action,
    required String tripReference,
    required String idempotencyKey,
    Map<String, Object?> body = const <String, Object?>{},
    String? pickupVerificationCode,
  }) => throw UnimplementedError();
}

final class _Queue implements DriverTripActionPersistentQueue {
  @override
  Future<QueuedEvent> enqueue(QueuedEvent event) async => event;

  @override
  Future<QueuedEvent?> eventById(String id) async => null;

  @override
  Future<List<QueuedEvent>> pendingEvents() async => const [];

  @override
  Future<void> markFailed(String id) async {}

  @override
  Future<void> markPermanentlyFailed(String id) async {}

  @override
  Future<void> markSynced(String id) async {}
}
