import 'package:asm_app_config/asm_app_config.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:passenger_app/booking/booking_page.dart';
import 'package:passenger_app/booking/passenger_fare_estimate.dart';
import 'package:passenger_app/map/osrm_route.dart';
import 'package:passenger_app/map/passenger_map.dart';

// The route behind the review's route card and fare estimate is always
// between two fixed Accra points (the destination has no coordinates yet),
// so every booking showed the same route and estimate. Both stay off until
// real destination coordinates exist.
void main() {
  testWidgets('the review shows no fare estimate and asks for none', (
    tester,
  ) async {
    final fares = _RecordingFareRepository();
    await _pumpBookingReview(tester, fares: fares);

    expect(fares.tripKilometres, isEmpty);
    // Nothing derived from the fixed points: no route card, drawn route,
    // pins or distance, and no route request at all.
    expect(_FixedRouteService.calls, 0);
    expect(find.byKey(const Key('osrm-route-preview-card')), findsNothing);
    expect(find.byKey(const Key('route-distance-duration')), findsNothing);
    expect(find.textContaining('km ·'), findsNothing);
    expect(find.byKey(const Key('passenger-fare-estimate')), findsNothing);
    expect(find.text('Estimated total'), findsNothing);
    expect(find.textContaining('km ×'), findsNothing);
    expect(
      find.byKey(const Key('fare-confirmed-before-payment')),
      findsOneWidget,
    );
    expect(
      find.text('Your fare will be confirmed before you pay.'),
      findsOneWidget,
    );
  });

  testWidgets('the estimate path still works when switched on', (
    tester,
  ) async {
    final fares = _RecordingFareRepository();
    await _pumpBookingReview(tester, fares: fares, showFareEstimate: true);

    expect(fares.tripKilometres, <double>[10.2]);
    expect(find.text('Estimated total'), findsOneWidget);
    expect(find.byKey(const Key('osrm-route-preview-card')), findsOneWidget);
    expect(
      find.byKey(const Key('fare-confirmed-before-payment')),
      findsNothing,
    );
  });
}

Future<void> _pumpBookingReview(
  WidgetTester tester, {
  required _RecordingFareRepository fares,
  bool? showFareEstimate,
}) async {
  tester.view.physicalSize = const Size(430, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  _FixedRouteService.calls = 0;
  await tester.pumpWidget(
    MaterialApp(
      theme: AsmThemes.passenger,
      home: showFareEstimate == null
          ? BookingPage(
              market: MarketConfig.ghanaAccra,
              fareEstimateRepository: fares,
              routeService: const _FixedRouteService(),
            )
          : BookingPage(
              market: MarketConfig.ghanaAccra,
              fareEstimateRepository: fares,
              routeService: const _FixedRouteService(),
              showRouteAndFareEstimate: showFareEstimate,
            ),
    ),
  );

  await tester.enterText(find.byKey(const Key('booking-pickup')), 'Osu');
  await tester.enterText(
    find.byKey(const Key('booking-destination')),
    'Airport',
  );
  await tester.ensureVisible(find.byKey(const Key('request-ride')));
  await tester.tap(find.byKey(const Key('request-ride')));
  await tester.pumpAndSettle();
}

class _RecordingFareRepository implements PassengerFareEstimateRepository {
  final tripKilometres = <double>[];

  @override
  Future<PassengerBookingFareEstimate> fetchEstimate(
    double tripKilometres,
  ) async {
    this.tripKilometres.add(tripKilometres);
    return PassengerBookingFareEstimate.fromJson(<String, Object?>{
      'currency': 'GHS',
      'trip_km': '10.2',
      'pickup_km': '0',
      'trip_rate': '3.50',
      'trip_fare': '35.70',
      'pickup_fee': '0.00',
      'estimated_total': '35.70',
      'minimum_fare': '20.00',
    });
  }
}

class _FixedRouteService implements PassengerRouteService {
  const _FixedRouteService();

  static int calls = 0;

  @override
  Future<PassengerRouteEstimate> route({
    LatLng pickup = accraPickup,
    LatLng destination = accraDestination,
  }) async {
    calls += 1;
    return const PassengerRouteEstimate(
      points: <LatLng>[accraPickup, accraDestination],
      distanceKilometres: 10.2,
      durationMinutes: 22,
    );
  }
}
