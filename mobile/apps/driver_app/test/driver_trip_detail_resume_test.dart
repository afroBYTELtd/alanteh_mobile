import 'package:driver_app/driver_duty_trips.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The Assigned trip screen reloads the trip when the app comes back to the
// front. Seen on the test phone (10 Oct): the passenger cancelled while the
// app was away, and on return the screen still said "Driver accepted" with
// "Continue live trip".
void main() {
  late _Gateway gateway;

  setUp(() => gateway = _Gateway('driver_accepted'));

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Column(
              children: [
                const Text('Work', key: Key('work')),
                TextButton(
                  key: const Key('open'),
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => DriverTripDetailScreen(
                        gateway: gateway,
                        tripReference: 'TRIP-1',
                      ),
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
  }

  Future<void> awayAndBack(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
  }

  testWidgets('cancelled while the app was away: on return it says "Trip '
      'cancelled" and offers a way back to Work', (tester) async {
    await open(tester);
    expect(find.text('Driver accepted'), findsOneWidget);

    gateway.status = 'cancelled_by_passenger';
    await awayAndBack(tester);

    expect(find.text('Trip cancelled'), findsOneWidget);
    expect(find.text('Continue live trip'), findsNothing);
    expect(find.text('Driver accepted'), findsNothing);

    await tester.tap(find.byKey(const Key('driver-trip-cancelled-back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('work')), findsOneWidget);
    expect(find.byType(DriverTripDetailScreen), findsNothing);
  });

  testWidgets('cancelled by operations reads the same', (tester) async {
    await open(tester);
    gateway.status = 'cancelled_by_operations';
    await awayAndBack(tester);

    expect(find.text('Trip cancelled'), findsOneWidget);
  });

  testWidgets('on return the trip is reloaded once', (tester) async {
    await open(tester);
    final loads = gateway.calls;

    await awayAndBack(tester);

    expect(gateway.calls, loads + 1);
    expect(find.text('Driver accepted'), findsOneWidget);
  });

  testWidgets('a reload that fails on return keeps what is on screen', (
    tester,
  ) async {
    await open(tester);
    gateway.fail = true;

    await awayAndBack(tester);

    expect(find.text('Driver accepted'), findsOneWidget);
    expect(find.text('Trip detail could not be loaded.'), findsNothing);
  });

  testWidgets('a trip already cancelled when opened says so too', (
    tester,
  ) async {
    gateway.status = 'cancelled_by_passenger';
    await open(tester);

    expect(find.text('Trip cancelled'), findsOneWidget);
    expect(find.text('Continue live trip'), findsNothing);
  });
}

final class _Gateway implements DriverDutyGateway {
  _Gateway(this.status);

  String status;
  bool fail = false;
  var calls = 0;

  @override
  Future<DriverAssignedTrip> fetchTripDetail(String tripReference) async {
    calls += 1;
    if (fail) {
      throw const DriverDutyApiException(
        DriverDutyApiFailureType.unavailable,
        'Cannot reach the server.',
      );
    }
    return DriverAssignedTrip(
      reference: tripReference,
      status: status,
      pickupLocation: 'Pinned location',
      destination: 'Osu Test D2',
      passengerCount: 1,
      vehicleReference: 'ALANTEH-DEMO-VEH-01',
    );
  }

  @override
  Future<DriverDutySummary> fetchDuty() => throw UnimplementedError();

  @override
  Future<List<DriverAssignedTrip>> fetchTrips() async => const [];
}
