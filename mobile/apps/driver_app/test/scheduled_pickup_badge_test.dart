import 'package:asm_design_system/asm_design_system.dart';
import 'package:driver_app/driver_duty_trips.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Saturday 3 October 2026, 07:10 local time.
  final now = DateTime(2026, 10, 3, 7, 10);

  group('scheduled pickup labels', () {
    test('a ride-now trip has no badge', () {
      expect(driverScheduledPickupBadge(_trip(null), now: now), isNull);
    });

    test('a pickup later today reads as today', () {
      final pickup = DateTime(2026, 10, 3, 9, 0);

      expect(
        driverScheduledPickupBadge(_trip(pickup), now: now),
        'Scheduled pickup · 09:00 today',
      );
    });

    test('a pickup on another day names the day', () {
      final pickup = DateTime(2026, 10, 5, 9, 30);

      expect(
        driverScheduledPickupBadge(_trip(pickup), now: now),
        'Scheduled pickup · Mon 5 Oct, 09:30',
      );
    });

    test('the requested pickup row is readable, not raw ISO', () {
      final pickup = DateTime(2026, 10, 5, 9, 30);

      expect(
        driverPickupTimeLabel(pickup.toUtc().toIso8601String()),
        'Mon 5 Oct, 09:30',
      );
      expect(driverPickupTimeLabel(null), driverEmptyValue);
      expect(driverPickupTimeLabel('not a date'), 'not a date');
    });
  });

  testWidgets('the trip list and a pending offer show the badge', (
    tester,
  ) async {
    final pickup = DateTime.now().add(const Duration(days: 2));
    final trip = DriverAssignedTrip(
      reference: 'TRIP-SCHEDULED-01',
      status: 'driver_offer_sent',
      pickupLocation: 'Osu Oxford Street',
      destination: 'Kotoka International Airport',
      requestedPickupTime: pickup.toUtc().toIso8601String(),
      passengerCount: 1,
    );
    final gateway = _Gateway(trip);
    final badge = driverScheduledPickupBadge(trip)!;

    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.driver,
        home: DriverAssignedTripsScreen(gateway: gateway),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(
        const ValueKey<String>('driver-scheduled-pickup-TRIP-SCHEDULED-01'),
      ),
      findsOneWidget,
    );
    expect(find.text(badge), findsWidgets);

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
    expect(
      find.byKey(const Key('driver-offer-scheduled-pickup')),
      findsOneWidget,
    );
    expect(find.text(badge), findsWidgets);
  });
}

DriverAssignedTrip _trip(DateTime? pickup) {
  return DriverAssignedTrip(
    reference: 'TRIP-LABEL-01',
    status: 'driver_offer_sent',
    requestedPickupTime: pickup?.toUtc().toIso8601String(),
  );
}

final class _Gateway implements DriverDutyGateway {
  _Gateway(this.trip);

  final DriverAssignedTrip trip;

  @override
  Future<DriverDutySummary> fetchDuty() async {
    return const DriverDutySummary(
      displayName: 'Driver One',
      driverReference: 'DRV-001',
      phone: '+233200000001',
      status: 'active',
      assignedVehicleReference: 'VEH-009',
      canReceiveAssignments: true,
      activeTripCount: 1,
      assignedTripCount: 1,
    );
  }

  @override
  Future<List<DriverAssignedTrip>> fetchTrips() async => <DriverAssignedTrip>[
    trip,
  ];

  @override
  Future<DriverAssignedTrip> fetchTripDetail(String tripReference) async =>
      trip;
}
