import 'package:asm_app_config/asm_app_config.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:driver_app/ride_offer/driver_ride_offer_page.dart';
import 'package:driver_app/trip_progress/driver_trip_route.dart';
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
    expect(find.text('Trip completed'), findsWidgets);
    expect(find.text('Accra Mall → Accra Market'), findsOneWidget);
    expect(find.text('9.5 km'), findsOneWidget);
    expect(find.text('23 min'), findsOneWidget);
    expect(find.text('Passengers'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(
      find.text('This completed trip is ready for shift review.'),
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

Future<void> _pumpTripSequence(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AsmThemes.driver,
      home: const DriverTripVisualSequencePage(),
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

void _useSurface(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(430, 1000);

  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });
}
