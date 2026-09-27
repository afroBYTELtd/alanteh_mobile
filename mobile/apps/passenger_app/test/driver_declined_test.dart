import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passenger_app/ride_requests/ride_request_history.dart';
import 'package:passenger_app/tracking/ride_tracking_screen.dart';

// Since auto-retry, a trip in driver_declined goes back to waiting and is
// offered to other drivers: it is still being filled, not a dead end. The
// backend's own passenger message for it is "Still finding you a driver."
void main() {
  test('a declined offer is still a driver search; a rejection is not', () {
    expect(
      PassengerRideState.fromStatus('driver_declined'),
      PassengerRideState.looking,
    );
    expect(PassengerRideState.hasCanonicalStatus('driver_declined'), isTrue);
    expect(
      PassengerRideState.fromStatus('rejected'),
      PassengerRideState.rejected,
    );
  });

  testWidgets('tracking keeps looking after a driver declines', (tester) async {
    await _pumpTracking(
      tester,
      _record(
        status: 'driver_declined',
        controlCenterMessage: 'Still finding you a driver.',
      ),
      now: DateTime.now,
    );

    expect(find.byKey(const Key('looking-for-driver-state')), findsOneWidget);
    expect(find.byKey(const Key('request-rejected-state')), findsNothing);
    expect(find.text('No vehicles available right now'), findsNothing);
    expect(find.text('Still finding you a driver.'), findsOneWidget);
    await _disposeTracking(tester);
  });

  testWidgets('a real rejection still shows no vehicles available', (
    tester,
  ) async {
    await _pumpTracking(tester, _record(status: 'rejected'), now: DateTime.now);

    expect(find.byKey(const Key('request-rejected-state')), findsOneWidget);
    await _disposeTracking(tester);
  });

  testWidgets('my ride requests show a declined offer as active', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: PassengerRideRequestHistoryPage(
          repository: _StaticHistoryRepository(<PassengerRideRequestRecord>[
            _record(status: 'driver_declined'),
          ]),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final chip = find.byKey(
      const ValueKey<String>('ride-request-status-driver_declined'),
    );
    expect(chip, findsOneWidget);
    expect(
      find.descendant(of: chip, matching: find.text('Active')),
      findsOneWidget,
    );
    expect(find.text('Could not be accepted'), findsNothing);
  });

  group('a scheduled ride inside its last hour', () {
    // Pickup 09:00; offers start at 08:00.
    final pickup = DateTime(2026, 10, 1, 9, 0);

    test('is a driver search, not "scheduled", once offers have started', () {
      final waiting = _record(status: 'requested', requestedPickupTime: pickup);

      expect(
        scheduledPickupAwaitingDriver(waiting, DateTime(2026, 10, 1, 7, 59)),
        pickup,
      );
      expect(
        scheduledPickupAwaitingDriver(waiting, DateTime(2026, 10, 1, 8, 0)),
        isNull,
      );
      expect(
        scheduledPickupAwaitingDriver(
          _record(status: 'driver_declined', requestedPickupTime: pickup),
          DateTime(2026, 10, 1, 8, 30),
        ),
        isNull,
      );
    });

    testWidgets('tracking shows the driver search after a decline', (
      tester,
    ) async {
      await _pumpTracking(
        tester,
        _record(
          status: 'driver_declined',
          requestedPickupTime: pickup,
          controlCenterMessage: 'Still finding you a driver.',
        ),
        now: () => DateTime(2026, 10, 1, 8, 30),
      );

      expect(find.byKey(const Key('looking-for-driver-state')), findsOneWidget);
      expect(find.byKey(const Key('ride-scheduled-state')), findsNothing);
      expect(find.byKey(const Key('request-rejected-state')), findsNothing);
      await _disposeTracking(tester);
    });
  });
}

PassengerRideRequestRecord _record({
  required String status,
  DateTime? requestedPickupTime,
  String? controlCenterMessage,
}) {
  return PassengerRideRequestRecord(
    requestReference: 'RR-APP-DECLINED01',
    status: status,
    pickupLocation: 'Osu Oxford Street',
    destination: 'Kotoka International Airport',
    passengerCount: 1,
    createdAt: DateTime(2026, 9, 29, 12),
    updatedAt: DateTime(2026, 9, 29, 12),
    hasMobileReceipt: true,
    tripCreated: true,
    requestedPickupTime: requestedPickupTime,
    controlCenterMessage: controlCenterMessage,
  );
}

Future<void> _pumpTracking(
  WidgetTester tester,
  PassengerRideRequestRecord record, {
  required DateTime Function() now,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AsmThemes.passenger,
      home: RideTrackingScreen(
        repository: _StaticHistoryRepository(<PassengerRideRequestRecord>[
          record,
        ]),
        requestReference: record.requestReference,
        initialRecord: record,
        pollInterval: const Duration(hours: 1),
        clock: now,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _disposeTracking(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
  await tester.pump();
}

class _StaticHistoryRepository
    implements PassengerRideRequestHistoryRepository {
  _StaticHistoryRepository(this.records);

  final List<PassengerRideRequestRecord> records;

  @override
  Future<List<PassengerRideRequestRecord>> fetchRequests() async => records;

  @override
  Future<PassengerRideRequestRecord> fetchRequest(
    String requestReference,
  ) async {
    return records.firstWhere(
      (record) => record.requestReference == requestReference,
    );
  }
}
