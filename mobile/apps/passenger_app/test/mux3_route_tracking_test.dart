import 'dart:async';
import 'dart:io';

import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:passenger_app/booking/route_preview_card.dart';
import 'package:passenger_app/map/osrm_route.dart';
import 'package:passenger_app/map/passenger_map.dart';
import 'package:passenger_app/network/passenger_cancellation_gateway.dart';
import 'package:passenger_app/payment_rating/passenger_payment_rating_contract.dart';
import 'package:passenger_app/payment_rating/passenger_payment_rating_page.dart';
import 'package:passenger_app/ride_requests/ride_request_history.dart';
import 'package:passenger_app/safety/passenger_trip_safety.dart';
import 'package:passenger_app/tracking/ride_tracking_screen.dart';

const _testVehiclePosition = LatLng(5.5980, -0.1795);

void main() {
  test('OSRM GeoJSON parser returns route geometry and statistics', () {
    final estimate = parseOsrmRouteResponse(<String, Object?>{
      'routes': <Object?>[
        <String, Object?>{
          'distance': 12345.0,
          'duration': 1500.0,
          'geometry': <String, Object?>{
            'coordinates': <Object?>[
              <Object?>[-0.1737, 5.6037],
              <Object?>[-0.1903, 5.5766],
              <Object?>[-0.2069, 5.5495],
            ],
          },
        },
      ],
    });

    expect(estimate.usedFallback, isFalse);
    expect(estimate.points, hasLength(3));
    expect(estimate.points.first.latitude, 5.6037);
    expect(estimate.points.first.longitude, -0.1737);
    expect(estimate.points.last.latitude, 5.5495);
    expect(estimate.points.last.longitude, -0.2069);
    expect(estimate.distanceKilometres, 12.345);
    expect(estimate.durationMinutes, 25);
  });

  test('OSRM parser rejects malformed geometry safely', () {
    expect(
      () => parseOsrmRouteResponse(<String, Object?>{
        'routes': <Object?>[
          <String, Object?>{
            'distance': 1000,
            'duration': 300,
            'geometry': <String, Object?>{
              'coordinates': <Object?>[
                <Object?>[-0.1737],
              ],
            },
          },
        ],
      }),
      throwsFormatException,
    );
  });

  test('direct-line fallback uses only pickup and destination', () {
    const pickup = LatLng(5.6037, -0.1737);
    const destination = LatLng(5.5495, -0.2069);

    final estimate = safeDirectRouteFallback(
      pickup: pickup,
      destination: destination,
    );

    expect(estimate.usedFallback, isTrue);
    expect(estimate.points, const <LatLng>[pickup, destination]);
    expect(estimate.distanceKilometres, greaterThan(0));
    expect(estimate.durationMinutes, greaterThan(0));
  });

  testWidgets('route preview renders OSRM geometry statistics', (tester) async {
    const estimate = PassengerRouteEstimate(
      points: <LatLng>[accraPickup, LatLng(5.5766, -0.1903), accraDestination],
      distanceKilometres: 12.3,
      durationMinutes: 25,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RoutePreviewCard(
            routeService: _FakeRouteService(estimate: estimate),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.byKey(const Key('osrm-route-preview-card')), findsOneWidget);
    expect(find.byKey(const Key('route-distance-duration')), findsOneWidget);
    expect(find.text('12.3 km · about 25 min'), findsOneWidget);

    final map = tester.widget<AsmPassengerMap>(find.byType(AsmPassengerMap));

    expect(map.pickup, accraPickup);
    expect(map.destination, accraDestination);
    expect(map.route, hasLength(3));
  });

  testWidgets('route preview falls back without inventing geometry', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoutePreviewCard(
            routeService: _FakeRouteService(error: StateError('offline')),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(
      find.byTooltip(
        'Route service unavailable. '
        'Showing a direct-line estimate.',
      ),
      findsOneWidget,
    );

    final map = tester.widget<AsmPassengerMap>(find.byType(AsmPassengerMap));

    expect(map.route, const <LatLng>[accraPickup, accraDestination]);
  });

  testWidgets('tracking renders every passenger-safe ride state', (
    tester,
  ) async {
    _useSurface(tester);

    final cases =
        <({PassengerRideRequestRecord record, String key, String title})>[
          (
            record: _record(status: 'requested'),
            key: 'looking-for-driver-state',
            title: 'Looking for a driver',
          ),
          (
            record: _record(status: 'assigned'),
            key: 'driver-assigned-state',
            title: 'Driver assigned',
          ),
          (
            record: _record(status: 'driver_offer_sent'),
            key: 'looking-for-driver-state',
            title: 'Looking for a driver',
          ),
          (
            record: _record(status: 'driver_accepted'),
            key: 'vehicle-en-route-state',
            title: 'Your vehicle is on the way',
          ),
          (
            record: _record(status: 'arrived_at_pickup'),
            key: 'driver-arrived-state',
            title: 'Your driver is outside',
          ),
          (
            record: _record(status: 'in_progress'),
            key: 'trip-in-progress-state',
            title: 'Trip in progress',
          ),
          (
            record: _record(status: 'completed_pending_review'),
            key: 'arrived-at-destination-state',
            title: 'You’ve arrived',
          ),
          (
            record: _record(latestStaffState: 'vehicle reassigned'),
            key: 'vehicle-reassigned-state',
            title: 'New vehicle assigned',
          ),
          (
            record: _record(status: 'rejected'),
            key: 'request-rejected-state',
            title: 'No vehicles available right now',
          ),
        ];

    for (final rideCase in cases) {
      final repository = _SequenceRepository(<Object>[rideCase.record]);

      await _pumpTracking(
        tester,
        repository,
        pollInterval: const Duration(hours: 1),
      );

      expect(find.byKey(Key(rideCase.key)), findsWidgets);
      expect(find.text(rideCase.title), findsOneWidget);
    }

    await _disposeTracking(tester);
  });

  testWidgets('test_under_review_shows_reviewing_your_request_heading', (
    tester,
  ) async {
    _useSurface(tester);

    final repository = _SequenceRepository(<Object>[
      _record(
        status: 'under_review',
        latestStaffState: 'Trip in progress',
        controlCenterMessage: 'Your request is being reviewed by staff.',
      ),
    ]);

    await _pumpTracking(
      tester,
      repository,
      pollInterval: const Duration(hours: 1),
    );

    expect(find.text('Reviewing your request'), findsOneWidget);
    expect(
      find.text('Your request is being reviewed by staff.'),
      findsOneWidget,
    );

    await _disposeTracking(tester);
  });

  testWidgets('test_under_review_does_not_show_trip_in_progress', (
    tester,
  ) async {
    _useSurface(tester);

    final repository = _SequenceRepository(<Object>[
      _record(
        status: 'under_review',
        latestStaffState: 'Trip in progress',
        controlCenterMessage: 'Your request is being reviewed by staff.',
      ),
    ]);

    await _pumpTracking(
      tester,
      repository,
      pollInterval: const Duration(hours: 1),
    );

    expect(find.text('Reviewing your request'), findsOneWidget);
    expect(find.text('Trip in progress'), findsNothing);

    await _disposeTracking(tester);
  });

  testWidgets('test_in_progress_still_shows_trip_in_progress', (tester) async {
    _useSurface(tester);

    final repository = _SequenceRepository(<Object>[
      _record(
        status: 'in_progress',
        controlCenterMessage: 'Your trip is in progress.',
      ),
    ]);

    await _pumpTracking(
      tester,
      repository,
      pollInterval: const Duration(hours: 1),
    );

    expect(find.byKey(const Key('trip-in-progress-state')), findsOneWidget);
    expect(find.text('Trip in progress'), findsOneWidget);

    await _disposeTracking(tester);
  });

  testWidgets('test_no_pre_trip_status_shows_trip_in_progress', (tester) async {
    _useSurface(tester);

    final cases = <PassengerRideRequestRecord>[
      _record(
        status: 'requested',
        controlCenterMessage: 'Your ride request was received.',
      ),
      _record(
        status: 'under_review',
        latestStaffState: 'Trip in progress',
        controlCenterMessage: 'Your request is being reviewed by staff.',
      ),
      _record(
        status: 'accepted_for_trip',
        controlCenterMessage: 'Your ride is being prepared.',
      ),
    ];

    for (final record in cases) {
      final repository = _SequenceRepository(<Object>[record]);

      await _pumpTracking(
        tester,
        repository,
        pollInterval: const Duration(hours: 1),
      );

      expect(
        find.text('Trip in progress'),
        findsNothing,
        reason: 'Pre-trip status ${record.status} must not use trip heading.',
      );

      await _disposeTracking(tester);
    }
  });

  testWidgets(
    'tracking never creates a vehicle marker without CC5C coordinates',
    (tester) async {
      _useSurface(tester);

      final repository = _SequenceRepository(<Object>[
        _record(latestStaffState: 'driver assigned'),
      ]);

      await _pumpTracking(
        tester,
        repository,
        pollInterval: const Duration(hours: 1),
      );

      final map = tester.widget<AsmPassengerMap>(find.byType(AsmPassengerMap));

      expect(map.vehicle, isNull);
      expect(map.route, isEmpty);
      expect(
        find.byKey(const Key('passenger-map-static-vehicle-marker')),
        findsNothing,
      );

      await _disposeTracking(tester);
    },
  );

  group('converted-status placeholder never renders as a real state', () {
    testWidgets(
      'a raw "converted" initialRecord shows a neutral checking-status '
      'view, not "Looking for a driver", before the trip fetch resolves',
      (tester) async {
        _useSurface(tester);

        final tripCompleter = Completer<PassengerTripRecord>();
        final requestRepository = _SequenceRepository(<Object>[
          _record(status: 'converted', tripReference: 'TRIP-FIRSTFRAME-001'),
        ]);
        final tripRepository = _CompleterTripRepository(
          tripCompleter.future,
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: AsmThemes.passenger,
            home: RideTrackingScreen(
              repository: requestRepository,
              requestReference: 'RR-APP-MUX3-TEST',
              tripRepository: tripRepository,
              initialRecord: _record(
                status: 'converted',
                tripReference: 'TRIP-FIRSTFRAME-001',
              ),
              pollInterval: const Duration(hours: 1),
            ),
          ),
        );
        await tester.pump();

        // The trip fetch is deliberately held open (via the Completer)
        // so this frame is guaranteed to be pre-resolution - exactly
        // the frame a passenger opening a historical trip card actually
        // sees first.
        expect(
          find.byKey(const Key('checking-trip-status-state')),
          findsOneWidget,
        );
        expect(find.text('Checking your trip'), findsOneWidget);
        expect(find.text('Looking for a driver'), findsNothing);
        expect(
          find.byKey(const Key('looking-for-driver-state')),
          findsNothing,
        );

        tripCompleter.complete(
          _trip(status: 'cancelled_by_operations'),
        );
        await tester.pumpAndSettle();

        // Once the fetch resolves, the real (here: terminal) status
        // takes over and the placeholder is gone.
        expect(find.text('Trip cancelled'), findsOneWidget);
        expect(
          find.byKey(const Key('checking-trip-status-state')),
          findsNothing,
        );

        await _disposeTracking(tester);
      },
    );

    testWidgets(
      'a reconnect attempt on a not-yet-enriched record still shows the '
      'reconnecting banner, not a blank spinner screen',
      (tester) async {
        _useSurface(tester);

        final requestRepository = _SequenceRepository(<Object>[
          _record(status: 'converted', tripReference: 'TRIP-RECONNECT-001'),
        ]);
        final tripRepository = _TripSequenceRepository(<Object>[
          const PassengerRideRequestHistoryException.network(),
          _trip(status: 'arrived_at_pickup'),
        ]);

        await _pumpTracking(
          tester,
          requestRepository,
          tripRepository: tripRepository,
          pollInterval: const Duration(milliseconds: 100),
        );

        expect(find.text('Reconnecting…'), findsOneWidget);
        expect(find.text('Checking your trip'), findsOneWidget);
        expect(find.text('Looking for a driver'), findsNothing);

        await tester.pump(const Duration(milliseconds: 110));
        await tester.pump();

        expect(find.byKey(const Key('driver-arrived-state')), findsOneWidget);
        expect(find.text('Reconnecting…'), findsNothing);

        await _disposeTracking(tester);
      },
    );
  });

  testWidgets('tracking shows only static last-known CC5C GPS data', (
    tester,
  ) async {
    _useSurface(tester);

    final repository = _SequenceRepository(<Object>[
      _record(
        latestStaffState: 'driver assigned',
        plateNumber: 'GT 1234-26',
        vehiclePosition: _testVehiclePosition,
      ),
    ]);

    await _pumpTracking(
      tester,
      repository,
      pollInterval: const Duration(hours: 1),
    );

    final map = tester.widget<AsmPassengerMap>(find.byType(AsmPassengerMap));

    expect(map.vehicle, _testVehiclePosition);
    expect(
      find.byKey(const Key('passenger-map-static-vehicle-marker')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('tracking-safe-plate-number')), findsOneWidget);
    expect(find.text('GT 1234-26'), findsOneWidget);

    await _disposeTracking(tester);
  });

  testWidgets('pickup verification code is shown when present', (
    tester,
  ) async {
    _useSurface(tester);

    final repository = _SequenceRepository(<Object>[
      _record(
        latestStaffState: 'driver assigned',
        plateNumber: 'GT 1234-26',
        pickupVerificationCode: '4821',
      ),
    ]);

    await _pumpTracking(
      tester,
      repository,
      pollInterval: const Duration(hours: 1),
    );

    expect(
      find.byKey(const Key('tracking-pickup-verification-code-badge')),
      findsOneWidget,
    );
    expect(find.text('4821'), findsOneWidget);
    expect(find.text('Pickup code'), findsOneWidget);
    // Must never be confused with the plate number, both of which are
    // now rendered as prominent digit badges on the same screen.
    expect(find.text('GT 1234-26'), findsOneWidget);

    await _disposeTracking(tester);
  });

  testWidgets(
    'pickup verification code badge is absent when the trip has no code',
    (tester) async {
      _useSurface(tester);

      final repository = _SequenceRepository(<Object>[
        _record(latestStaffState: 'driver assigned', plateNumber: 'GT 1234-26'),
      ]);

      await _pumpTracking(
        tester,
        repository,
        pollInterval: const Duration(hours: 1),
      );

      expect(
        find.byKey(const Key('tracking-pickup-verification-code-badge')),
        findsNothing,
      );

      await _disposeTracking(tester);
    },
  );

  testWidgets(
    'pickup verification code carries over once a trip is converted',
    (tester) async {
      _useSurface(tester);

      final requestRepository = _SequenceRepository(<Object>[
        _record(status: 'converted', tripReference: 'TRIP-SWITCH-001'),
      ]);
      final tripRepository = _TripSequenceRepository(<Object>[
        _trip(status: 'driver_accepted', pickupVerificationCode: '9034'),
      ]);

      await _pumpTracking(
        tester,
        requestRepository,
        tripRepository: tripRepository,
        pollInterval: const Duration(hours: 1),
      );

      expect(
        find.byKey(const Key('tracking-pickup-verification-code-badge')),
        findsOneWidget,
      );
      expect(find.text('9034'), findsOneWidget);

      await _disposeTracking(tester);
    },
  );

  testWidgets('test_driver_name_displayed_when_present', (tester) async {
    _useSurface(tester);

    final requestRepository = _SequenceRepository(<Object>[
      _record(status: 'converted', tripReference: 'TRIP-SWITCH-001'),
    ]);
    final tripRepository = _TripSequenceRepository(<Object>[
      _trip(status: 'driver_accepted', driverName: '  Kwame Mensah  '),
    ]);

    await _pumpTracking(
      tester,
      requestRepository,
      tripRepository: tripRepository,
      pollInterval: const Duration(hours: 1),
    );

    expect(find.byKey(const Key('tracking-driver-first-name')), findsOneWidget);
    expect(find.text('Kwame'), findsOneWidget);
    expect(find.textContaining('Mensah'), findsNothing);

    final avatar = tester.widget<CircleAvatar>(
      find.byKey(const Key('tracking-driver-avatar')),
    );
    expect(avatar.backgroundColor, AsmColors.brandDeepGreen);
    expect(find.text('K'), findsOneWidget);

    final driverName = tester.widget<Text>(
      find.byKey(const Key('tracking-driver-first-name')),
    );
    expect(driverName.style?.fontWeight, FontWeight.w900);

    await _disposeTracking(tester);
  });

  testWidgets('test_vehicle_info_displayed_when_present', (tester) async {
    _useSurface(tester);

    final repository = _SequenceRepository(<Object>[
      _record(
        latestStaffState: 'driver assigned',
        vehicleColour: 'Blue',
        vehicleType: 'Solar Taxi',
      ),
    ]);

    await _pumpTracking(
      tester,
      repository,
      pollInterval: const Duration(hours: 1),
    );

    expect(find.byKey(const Key('tracking-vehicle-info')), findsOneWidget);
    expect(find.text('Blue · Solar Taxi'), findsOneWidget);

    final vehicleInfo = tester.widget<Text>(
      find.byKey(const Key('tracking-vehicle-info')),
    );
    expect(vehicleInfo.style?.fontWeight, FontWeight.w600);

    await _disposeTracking(tester);
  });

  testWidgets('test_distance_displayed_when_present_with_correct_km_label', (
    tester,
  ) async {
    _useSurface(tester);

    final repository = _SequenceRepository(<Object>[
      _record(latestStaffState: 'driver assigned', driverDistanceKm: 2.34),
    ]);

    await _pumpTracking(
      tester,
      repository,
      pollInterval: const Duration(hours: 1),
    );

    expect(find.byKey(const Key('tracking-driver-distance')), findsOneWidget);
    expect(
      find.byKey(const Key('tracking-driver-distance-icon')),
      findsOneWidget,
    );
    expect(find.text('Driver is approximately 2.3 km away'), findsOneWidget);

    final distanceIcon = tester.widget<Icon>(
      find.byKey(const Key('tracking-driver-distance-icon')),
    );
    expect(distanceIcon.icon, Icons.location_on_outlined);
    expect(distanceIcon.color, AsmColors.brandDeepGreen);
    expect(find.textContaining('ETA'), findsNothing);

    await _disposeTracking(tester);
  });

  testWidgets('test_distance_row_absent_when_null', (tester) async {
    _useSurface(tester);

    final repository = _SequenceRepository(<Object>[
      _record(latestStaffState: 'driver assigned', driverDistanceKm: null),
    ]);

    await _pumpTracking(
      tester,
      repository,
      pollInterval: const Duration(hours: 1),
    );

    expect(find.byKey(const Key('tracking-driver-distance')), findsNothing);
    expect(
      find.byKey(const Key('tracking-driver-distance-icon')),
      findsNothing,
    );
    expect(find.textContaining('Driver is approximately'), findsNothing);
    expect(find.textContaining('Distance unavailable'), findsNothing);

    await _disposeTracking(tester);
  });

  testWidgets('test_no_phone_number_ever_rendered', (tester) async {
    _useSurface(tester);

    final parsedTrip = PassengerTripRecord.fromJson(<String, Object?>{
      'trip_reference': 'TRIP-SWITCH-001',
      'trip_status': 'driver_accepted',
      'driver_name': 'Kwame Mensah',
      'driver_phone': '+233 00 000 0000',
      'driver_phone_number': '+233 11 111 1111',
      'phone_number': '+233 22 222 2222',
    }, expectedTripReference: 'TRIP-SWITCH-001');

    final requestRepository = _SequenceRepository(<Object>[
      _record(status: 'converted', tripReference: 'TRIP-SWITCH-001'),
    ]);
    final tripRepository = _TripSequenceRepository(<Object>[parsedTrip]);

    await _pumpTracking(
      tester,
      requestRepository,
      tripRepository: tripRepository,
      pollInterval: const Duration(hours: 1),
    );

    expect(find.textContaining('+233 00 000 0000'), findsNothing);
    expect(find.textContaining('+233 11 111 1111'), findsNothing);
    expect(find.textContaining('+233 22 222 2222'), findsNothing);

    await _disposeTracking(tester);
  });

  testWidgets('test_existing_plate_display_unchanged', (tester) async {
    _useSurface(tester);

    final repository = _SequenceRepository(<Object>[
      _record(
        latestStaffState: 'driver assigned',
        driverName: 'Kwame Mensah',
        vehicleColour: 'Blue',
        vehicleType: 'Solar Taxi',
        plateNumber: 'GT 1234-26',
        driverDistanceKm: 2.34,
      ),
    ]);

    await _pumpTracking(
      tester,
      repository,
      pollInterval: const Duration(hours: 1),
    );

    final plateFinder = find.byKey(const Key('tracking-safe-plate-number'));

    expect(plateFinder, findsOneWidget);
    expect(find.byKey(const Key('tracking-plate-badge')), findsOneWidget);
    expect(find.text('GT 1234-26'), findsOneWidget);

    final plate = tester.widget<Text>(plateFinder);
    expect(plate.data, 'GT 1234-26');
    expect(plate.style?.fontSize, 24);
    expect(plate.style?.fontWeight, FontWeight.w900);

    await _disposeTracking(tester);
  });

  testWidgets('tracking polls and moves to the latest CC5C state', (
    tester,
  ) async {
    _useSurface(tester);

    final repository = _SequenceRepository(<Object>[
      _record(status: 'requested'),
      _record(
        latestStaffState: 'driver assigned',
        vehiclePosition: _testVehiclePosition,
      ),
    ]);

    await _pumpTracking(
      tester,
      repository,
      pollInterval: const Duration(milliseconds: 100),
    );

    expect(find.byKey(const Key('looking-for-driver-state')), findsOneWidget);
    expect(repository.detailCalls, 1);

    await tester.pump(const Duration(milliseconds: 110));
    await tester.pump();

    expect(find.byKey(const Key('driver-assigned-state')), findsOneWidget);
    expect(repository.detailCalls, 2);

    await _disposeTracking(tester);
  });

  testWidgets(
    'tracking switches once from converted request polling to trip polling',
    (tester) async {
      _useSurface(tester);

      final requestRepository = _SequenceRepository(<Object>[
        _record(status: 'converted', tripReference: 'TRIP-SWITCH-001'),
      ]);
      final tripRepository = _TripSequenceRepository(<Object>[
        _trip(status: 'driver_accepted', message: 'Your driver is on the way.'),
        _trip(status: 'arrived_at_pickup', message: 'Your driver has arrived.'),
        _trip(status: 'in_progress', message: 'Your trip is in progress.'),
      ]);

      await _pumpTracking(
        tester,
        requestRepository,
        tripRepository: tripRepository,
        pollInterval: const Duration(milliseconds: 100),
      );

      expect(requestRepository.detailCalls, 1);
      expect(tripRepository.tripCalls, 1);
      expect(find.byKey(const Key('vehicle-en-route-state')), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 110));
      await tester.pump();

      expect(requestRepository.detailCalls, 1);
      expect(tripRepository.tripCalls, 2);
      expect(find.byKey(const Key('driver-arrived-state')), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 110));
      await tester.pump();

      expect(requestRepository.detailCalls, 1);
      expect(tripRepository.tripCalls, 3);
      expect(find.byKey(const Key('trip-in-progress-state')), findsOneWidget);

      await _disposeTracking(tester);
    },
  );

  testWidgets(
    'converted request without trip reference keeps request polling',
    (tester) async {
      _useSurface(tester);

      final requestRepository = _SequenceRepository(<Object>[
        _record(status: 'converted'),
        _record(status: 'converted'),
      ]);
      final tripRepository = _TripSequenceRepository(<Object>[]);

      await _pumpTracking(
        tester,
        requestRepository,
        tripRepository: tripRepository,
        pollInterval: const Duration(milliseconds: 100),
      );

      expect(requestRepository.detailCalls, 1);
      expect(tripRepository.tripCalls, 0);

      await tester.pump(const Duration(milliseconds: 110));
      await tester.pump();

      expect(requestRepository.detailCalls, 2);
      expect(tripRepository.tripCalls, 0);

      await _disposeTracking(tester);
    },
  );

  testWidgets(
    'trip switch failure auto-recovers trip without returning to request polling',
    (tester) async {
      _useSurface(tester);

      final requestRepository = _SequenceRepository(<Object>[
        _record(status: 'converted', tripReference: 'TRIP-RETRY-001'),
      ]);
      final tripRepository = _TripSequenceRepository(<Object>[
        const PassengerRideRequestHistoryException.network(),
        _trip(status: 'arrived_at_pickup', message: 'Your driver has arrived.'),
      ]);

      await _pumpTracking(
        tester,
        requestRepository,
        tripRepository: tripRepository,
        pollInterval: const Duration(milliseconds: 100),
      );

      expect(requestRepository.detailCalls, 1);
      expect(tripRepository.tripCalls, 1);
      expect(find.text('Reconnecting…'), findsOneWidget);
      expect(find.byKey(const Key('tracking-connection-retry')), findsNothing);

      await tester.pump(const Duration(milliseconds: 110));
      await tester.pump();

      expect(requestRepository.detailCalls, 1);
      expect(tripRepository.tripCalls, 2);
      expect(find.byKey(const Key('driver-arrived-state')), findsOneWidget);
      expect(find.text('Reconnecting…'), findsNothing);

      await _disposeTracking(tester);
    },
  );

  testWidgets(
    'test_poll_failure_after_request_retries_shows_reconnecting_not_manual_retry_immediately',
    (tester) async {
      _useSurface(tester);

      final requestRepository = _SequenceRepository(<Object>[
        _record(status: 'converted', tripReference: 'TRIP-RECOVER-001'),
      ]);
      final tripRepository = _TripSequenceRepository(<Object>[
        _trip(status: 'driver_accepted'),
        const PassengerRideRequestHistoryException.network(),
        _trip(status: 'arrived_at_pickup'),
      ]);

      await _pumpTracking(
        tester,
        requestRepository,
        tripRepository: tripRepository,
        pollInterval: const Duration(milliseconds: 100),
      );

      expect(tripRepository.tripCalls, 1);

      await tester.pump(const Duration(milliseconds: 110));
      await tester.pump();

      expect(tripRepository.tripCalls, 2);
      expect(
        find.byKey(const Key('tracking-reconnecting-banner')),
        findsOneWidget,
      );
      expect(find.text('Reconnecting…'), findsOneWidget);
      expect(find.byKey(const Key('tracking-connection-retry')), findsNothing);

      await _disposeTracking(tester);
    },
  );

  testWidgets('test_reconnecting_state_preserves_last_safe_trip_data', (
    tester,
  ) async {
    _useSurface(tester);

    final requestRepository = _SequenceRepository(<Object>[
      _record(status: 'converted', tripReference: 'TRIP-RECOVER-002'),
    ]);
    final tripRepository = _TripSequenceRepository(<Object>[
      _trip(
        status: 'driver_accepted',
        message: 'Your driver is on the way.',
        driverName: 'Kwame',
        vehicleType: 'SUV',
      ),
      const PassengerRideRequestHistoryException.network(),
    ]);

    await _pumpTracking(
      tester,
      requestRepository,
      tripRepository: tripRepository,
      pollInterval: const Duration(milliseconds: 100),
    );

    expect(find.byKey(const Key('vehicle-en-route-state')), findsOneWidget);
    expect(find.text('Your driver is on the way.'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 110));
    await tester.pump();

    expect(tripRepository.tripCalls, 2);
    expect(
      find.byKey(const Key('tracking-reconnecting-banner')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('vehicle-en-route-state')), findsOneWidget);
    expect(find.text('Your driver is on the way.'), findsOneWidget);

    await _disposeTracking(tester);
  });

  testWidgets('test_successful_recovery_poll_resumes_normal_10s_interval', (
    tester,
  ) async {
    _useSurface(tester);

    final requestRepository = _SequenceRepository(<Object>[
      _record(status: 'converted', tripReference: 'TRIP-RECOVER-003'),
    ]);
    final tripRepository = _TripSequenceRepository(<Object>[
      _trip(status: 'driver_accepted'),
      const PassengerRideRequestHistoryException.network(),
      _trip(status: 'arrived_at_pickup'),
      _trip(status: 'in_progress'),
    ]);

    await _pumpTracking(
      tester,
      requestRepository,
      tripRepository: tripRepository,
      pollInterval: const Duration(seconds: 10),
    );

    expect(tripRepository.tripCalls, 1);

    await tester.pump(const Duration(seconds: 10));
    await tester.pump();

    expect(tripRepository.tripCalls, 2);
    expect(find.text('Reconnecting…'), findsOneWidget);

    await tester.pump(const Duration(seconds: 9));
    expect(tripRepository.tripCalls, 2);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(tripRepository.tripCalls, 3);
    expect(find.byKey(const Key('driver-arrived-state')), findsOneWidget);
    expect(find.text('Reconnecting…'), findsNothing);

    await tester.pump(const Duration(seconds: 9));
    expect(tripRepository.tripCalls, 3);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(tripRepository.tripCalls, 4);
    expect(find.byKey(const Key('trip-in-progress-state')), findsOneWidget);

    await _disposeTracking(tester);
  });

  testWidgets('test_second_consecutive_poll_failure_shows_manual_retry', (
    tester,
  ) async {
    _useSurface(tester);

    final requestRepository = _SequenceRepository(<Object>[
      _record(status: 'converted', tripReference: 'TRIP-RECOVER-004'),
    ]);
    final tripRepository = _TripSequenceRepository(<Object>[
      _trip(status: 'driver_accepted'),
      const PassengerRideRequestHistoryException.network(),
      const PassengerRideRequestHistoryException.network(),
    ]);

    await _pumpTracking(
      tester,
      requestRepository,
      tripRepository: tripRepository,
      pollInterval: const Duration(milliseconds: 100),
    );

    await tester.pump(const Duration(milliseconds: 110));
    await tester.pump();

    expect(tripRepository.tripCalls, 2);
    expect(find.text('Reconnecting…'), findsOneWidget);
    expect(find.byKey(const Key('tracking-connection-retry')), findsNothing);

    await tester.pump(const Duration(milliseconds: 110));
    await tester.pump();

    expect(tripRepository.tripCalls, 3);
    expect(find.text('Reconnecting…'), findsNothing);
    expect(
      find.byKey(const Key('tracking-connection-interrupted-banner')),
      findsOneWidget,
    );
    expect(find.text('Connection interrupted'), findsOneWidget);
    expect(find.byKey(const Key('tracking-connection-retry')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 500));
    expect(tripRepository.tripCalls, 3);

    await _disposeTracking(tester);
  });

  testWidgets('test_manual_retry_after_exhausted_auto_recovery_still_works', (
    tester,
  ) async {
    _useSurface(tester);

    final requestRepository = _SequenceRepository(<Object>[
      _record(status: 'converted', tripReference: 'TRIP-RECOVER-005'),
    ]);
    final tripRepository = _TripSequenceRepository(<Object>[
      _trip(status: 'driver_accepted'),
      const PassengerRideRequestHistoryException.network(),
      const PassengerRideRequestHistoryException.network(),
      _trip(status: 'arrived_at_pickup'),
      _trip(status: 'in_progress'),
    ]);

    await _pumpTracking(
      tester,
      requestRepository,
      tripRepository: tripRepository,
      pollInterval: const Duration(milliseconds: 100),
    );

    await tester.pump(const Duration(milliseconds: 110));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 110));
    await tester.pump();

    expect(tripRepository.tripCalls, 3);
    expect(find.byKey(const Key('tracking-connection-retry')), findsOneWidget);

    await tester.tap(find.byKey(const Key('tracking-connection-retry')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(tripRepository.tripCalls, 4);
    expect(find.byKey(const Key('driver-arrived-state')), findsOneWidget);
    expect(
      find.byKey(const Key('tracking-connection-interrupted-banner')),
      findsNothing,
    );

    await tester.pump(const Duration(milliseconds: 110));
    await tester.pump();

    expect(tripRepository.tripCalls, 5);
    expect(find.byKey(const Key('trip-in-progress-state')), findsOneWidget);

    await _disposeTracking(tester);
  });

  test('test_no_stacked_or_duplicate_backoff_introduced_at_screen_level', () {
    final source = File(
      'lib/tracking/ride_tracking_screen.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('Duration(seconds: 2)')));
    expect(source, isNot(contains('Duration(seconds: 4)')));
    expect(source, isNot(contains('Duration(seconds: 8)')));
    expect(source, isNot(contains('GhanaRequestPolicy.retryBackoffs')));
    expect(source, isNot(contains('GhanaRetryPolicy')));
    expect(source, contains('_timer = Timer(widget.pollInterval, _load);'));
    expect(source, contains('this.pollInterval = const Duration(seconds: 10)'));
  });

  testWidgets('offline tracking retries safely', (tester) async {
    _useSurface(tester);

    final repository = _SequenceRepository(<Object>[
      const PassengerRideRequestHistoryException.network(),
      _record(status: 'requested'),
    ]);

    await _pumpTracking(
      tester,
      repository,
      pollInterval: const Duration(hours: 1),
    );

    expect(find.byKey(const Key('offline-state')), findsOneWidget);
    expect(find.text('You’re offline'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.byKey(const Key('looking-for-driver-state')), findsOneWidget);
    expect(repository.detailCalls, 2);

    await _disposeTracking(tester);
  });

  testWidgets('test_cancelled_by_operations_stops_polling', (tester) async {
    _useSurface(tester);

    final requestRepository = _SequenceRepository(<Object>[
      _record(status: 'converted', tripReference: 'TRIP-CANCELLED-OPS-POLLING'),
    ]);
    final tripRepository = _TripSequenceRepository(<Object>[
      _trip(status: 'cancelled_by_operations'),
    ]);

    await _pumpTracking(
      tester,
      requestRepository,
      tripRepository: tripRepository,
      pollInterval: const Duration(milliseconds: 10),
    );

    expect(find.byKey(const Key('trip-cancelled-state')), findsOneWidget);
    expect(requestRepository.detailCalls, 1);
    expect(tripRepository.tripCalls, 1);

    await tester.pump(const Duration(milliseconds: 50));

    expect(requestRepository.detailCalls, 1);
    expect(tripRepository.tripCalls, 1);

    await _disposeTracking(tester);
  });

  testWidgets('test_cancelled_by_operations_shows_correct_message', (
    tester,
  ) async {
    _useSurface(tester);

    final requestRepository = _SequenceRepository(<Object>[
      _record(status: 'converted', tripReference: 'TRIP-CANCELLED-OPS-MESSAGE'),
    ]);
    final tripRepository = _TripSequenceRepository(<Object>[
      _trip(
        status: 'cancelled_by_operations',
        message: 'Your driver is on the way.',
      ),
    ]);

    await _pumpTracking(
      tester,
      requestRepository,
      tripRepository: tripRepository,
      pollInterval: const Duration(hours: 1),
    );

    expect(find.text('Trip cancelled'), findsOneWidget);
    expect(
      find.text('Your trip was cancelled by ALANTEH support.'),
      findsOneWidget,
    );
    expect(find.text('Looking for a driver'), findsNothing);
    expect(find.text('Your driver is on the way.'), findsNothing);

    await _disposeTracking(tester);
  });

  testWidgets('test_cancelled_by_operations_cancel_request_action_absent', (
    tester,
  ) async {
    _useSurface(tester);

    final requestRepository = _SequenceRepository(<Object>[
      _record(status: 'converted', tripReference: 'TRIP-CANCELLED-OPS-ACTIONS'),
    ]);
    final tripRepository = _TripSequenceRepository(<Object>[
      _trip(status: 'cancelled_by_operations'),
    ]);

    await _pumpTracking(
      tester,
      requestRepository,
      tripRepository: tripRepository,
      pollInterval: const Duration(hours: 1),
    );

    expect(find.byKey(const Key('trip-cancelled-state')), findsOneWidget);
    expect(find.byKey(const Key('open-cancel-confirmation')), findsNothing);
    expect(find.text('Cancel request'), findsNothing);
    expect(
      find.byKey(const Key('cancelled-by-operations-book-again')),
      findsOneWidget,
    );

    await _disposeTracking(tester);
  });

  testWidgets(
    'completed pending review stops trip polling and not request polling',
    (tester) async {
      _useSurface(tester);

      final requestRepository = _SequenceRepository(<Object>[
        _record(status: 'converted', tripReference: 'TRIP-TERMINAL-001'),
      ]);
      final tripRepository = _TripSequenceRepository(<Object>[
        _trip(status: 'completed_pending_review'),
      ]);

      await _pumpTracking(
        tester,
        requestRepository,
        tripRepository: tripRepository,
        pollInterval: const Duration(milliseconds: 10),
      );

      expect(
        find.byKey(const Key('arrived-at-destination-state')),
        findsOneWidget,
      );
      expect(requestRepository.detailCalls, 1);
      expect(tripRepository.tripCalls, 1);

      await tester.pump(const Duration(milliseconds: 50));

      expect(requestRepository.detailCalls, 1);
      expect(tripRepository.tripCalls, 1);

      await _disposeTracking(tester);
    },
  );

  testWidgets('reassigned and rejected states expose safe actions', (
    tester,
  ) async {
    _useSurface(tester);

    await _pumpTracking(
      tester,
      _SequenceRepository(<Object>[
        _record(
          latestStaffState: 'vehicle reassigned',
          vehiclePosition: _testVehiclePosition,
        ),
      ]),
      pollInterval: const Duration(hours: 1),
    );

    expect(find.byKey(const Key('vehicle-reassigned-state')), findsWidgets);
    expect(find.text('Your vehicle has been reassigned.'), findsOneWidget);

    await _pumpTracking(
      tester,
      _SequenceRepository(<Object>[_record(status: 'rejected')]),
      pollInterval: const Duration(hours: 1),
    );

    expect(find.byKey(const Key('request-rejected-state')), findsOneWidget);
    expect(find.byKey(const Key('rejected-book-again')), findsOneWidget);
    expect(find.byKey(const Key('rejected-contact-support')), findsOneWidget);

    await _disposeTracking(tester);
  });

  testWidgets(
    'cancel button opens the reason sheet and submits a ride-request '
    'cancellation',
    (tester) async {
      _useSurface(tester);

      final repository = _SequenceRepository(<Object>[
        _record(status: 'requested'),
        _record(status: 'cancelled'),
      ]);
      final gateway = _FakeCancellationGateway();

      await _pumpTracking(
        tester,
        repository,
        pollInterval: const Duration(hours: 1),
        cancellationGateway: gateway,
      );

      await tester.tap(find.byKey(const Key('open-cancel-confirmation')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('passenger-cancel-reason-sheet')),
        findsOneWidget,
      );
      for (final reason in PassengerCancellationReason.values) {
        if (reason == PassengerCancellationReason.priceOrFareConcern) {
          // No fare exists pre-conversion; excluded below.
          continue;
        }
        expect(
          find.byKey(Key('passenger-cancel-reason-option-${reason.code}')),
          findsOneWidget,
        );
      }
      expect(
        find.byKey(
          const Key(
            'passenger-cancel-reason-option-price_or_fare_concern',
          ),
        ),
        findsNothing,
      );

      await tester.tap(
        find.byKey(
          const Key('passenger-cancel-reason-option-no_longer_needed'),
        ),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const Key('passenger-cancel-reason-confirm')),
      );
      await tester.pumpAndSettle();

      expect(gateway.rideRequestCalls, 1);
      expect(gateway.tripCalls, 0);
      expect(gateway.rideRequestReasons, <PassengerCancellationReason>[
        PassengerCancellationReason.noLongerNeeded,
      ]);
      expect(gateway.rideRequestNotes, <String?>[null]);
      expect(find.byKey(const Key('trip-cancelled-by-passenger-state')), findsOneWidget);
      expect(find.byKey(const Key('open-cancel-confirmation')), findsNothing);

      await _disposeTracking(tester);
    },
  );

  testWidgets(
    'vehicle-en-route notice shows in the reason sheet, and Never mind '
    'submits nothing',
    (tester) async {
      _useSurface(tester);

      final repository = _SequenceRepository(<Object>[
        _record(
          latestStaffState: 'dispatched',
          vehiclePosition: _testVehiclePosition,
        ),
      ]);
      final gateway = _FakeCancellationGateway();

      await _pumpTracking(
        tester,
        repository,
        pollInterval: const Duration(hours: 1),
        cancellationGateway: gateway,
      );

      await tester.tap(find.byKey(const Key('open-cancel-confirmation')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('cancel-vehicle-en-route-notice')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const Key('passenger-cancel-reason-cancel')),
      );
      await tester.pumpAndSettle();

      expect(gateway.rideRequestCalls, 0);
      expect(gateway.tripCalls, 0);
      expect(
        find.byKey(const Key('passenger-cancel-reason-sheet')),
        findsNothing,
      );

      await _disposeTracking(tester);
    },
  );

  testWidgets(
    'other requires a note, and a Trip-linked cancellation calls the '
    'trip endpoint with the fare-concern reason available',
    (tester) async {
      _useSurface(tester);

      final repository = _SequenceRepository(<Object>[
        _record(status: 'converted', tripReference: 'TRIP-SWITCH-001'),
      ]);
      final tripRepository = _TripSequenceRepository(<Object>[
        _trip(status: 'fare_confirmed', fareAmount: '55.00'),
      ]);
      final gateway = _FakeCancellationGateway();

      await _pumpTracking(
        tester,
        repository,
        tripRepository: tripRepository,
        pollInterval: const Duration(hours: 1),
        cancellationGateway: gateway,
      );

      await tester.tap(find.byKey(const Key('open-cancel-confirmation')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(
          const Key(
            'passenger-cancel-reason-option-price_or_fare_concern',
          ),
        ),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const Key('passenger-cancel-reason-option-other')),
      );
      await tester.pump();

      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('passenger-cancel-reason-confirm')),
            )
            .onPressed,
        isNull,
      );

      await tester.enterText(
        find.byKey(const Key('passenger-cancel-reason-other-note')),
        'Driver asked me to cancel and rebook at a lower fare.',
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const Key('passenger-cancel-reason-confirm')),
      );
      await tester.pumpAndSettle();

      expect(gateway.tripCalls, 1);
      expect(gateway.rideRequestCalls, 0);
      expect(gateway.tripReasons, <PassengerCancellationReason>[
        PassengerCancellationReason.other,
      ]);
      expect(gateway.tripNotes, <String?>[
        'Driver asked me to cancel and rebook at a lower fare.',
      ]);

      await _disposeTracking(tester);
    },
  );

  // KNOWN GAP (deliberately accepted, logged 2026-09-19): this proves the
  // client-side render path via a fabricated PassengerCancellationException,
  // not a live 400 from a trip actually progressed to PASSENGER_ONBOARD or
  // later. The boundary itself is confirmed from backend code + backend
  // tests (TRIP_PASSENGER_CANCEL_ELIGIBLE_STATUSES), and this handler is the
  // same shared "render this message for this stable error code" path
  // already live-verified end-to-end on the pre-conversion RideRequest case.
  // Risk is low given the shared code path; revisit live-triggering this
  // specific transition if a future trip-lifecycle live test makes it cheap,
  // rather than manufacturing one for this alone.
  testWidgets(
    'a not-eligible cancellation shows the friendly message with a '
    'separate contact-support action, not appended to the same sentence',
    (tester) async {
      _useSurface(tester);

      final repository = _SequenceRepository(<Object>[
        _record(status: 'converted', tripReference: 'TRIP-SWITCH-001'),
      ]);
      final tripRepository = _TripSequenceRepository(<Object>[
        _trip(status: 'arrived_at_pickup'),
      ]);
      final gateway = _FakeCancellationGateway(
        error: const PassengerCancellationException.notEligible(),
      );

      await _pumpTracking(
        tester,
        repository,
        tripRepository: tripRepository,
        pollInterval: const Duration(hours: 1),
        cancellationGateway: gateway,
      );

      await tester.tap(find.byKey(const Key('open-cancel-confirmation')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const Key('passenger-cancel-reason-option-no_longer_needed'),
        ),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const Key('passenger-cancel-reason-confirm')),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          'This trip has already started and can no longer be cancelled here.',
        ),
        findsOneWidget,
      );
      // The message itself must not also carry the support framing - that's
      // a separate SnackBarAction, not part of the same sentence.
      expect(
        find.textContaining('if something'),
        findsNothing,
      );
      expect(find.text('Contact support'), findsOneWidget);

      await _disposeTracking(tester);
    },
  );

  testWidgets(
    'the reason sheet does not overflow when the on-screen keyboard opens '
    'for the other note field',
    (tester) async {
      // Same lesson as the driver-app decline sheet: WidgetTester.view.viewInsets
      // simulates the keyboard opening (widget tests don't open a real one).
      _useSurface(tester);

      final repository = _SequenceRepository(<Object>[
        _record(status: 'requested'),
      ]);
      final gateway = _FakeCancellationGateway();

      await _pumpTracking(
        tester,
        repository,
        pollInterval: const Duration(hours: 1),
        cancellationGateway: gateway,
      );

      await tester.tap(find.byKey(const Key('open-cancel-confirmation')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('passenger-cancel-reason-option-other')),
      );
      await tester.pump();

      tester.view.viewInsets = const FakeViewPadding(bottom: 500);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      await tester.enterText(
        find.byKey(const Key('passenger-cancel-reason-other-note')),
        'Driver asked me to cancel and rebook at a lower fare.',
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const Key('passenger-cancel-reason-confirm')),
        findsOneWidget,
      );

      await _disposeTracking(tester);
    },
  );

  testWidgets('history card title uses From to To and Book again callback', (
    tester,
  ) async {
    _useSurface(tester);

    PassengerRideRequestRecord? selectedRecord;

    final record = _record(
      status: 'completed',
      pickup: 'Solar Hotel',
      destination: 'Accra Airport',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: PassengerRideRequestHistoryPage(
          repository: _SequenceRepository(
            <Object>[record],
            listRecords: <PassengerRideRequestRecord>[record],
          ),
          onBookAgain: (record) {
            selectedRecord = record;
          },
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    final title = tester.widget<Text>(
      find.byKey(const Key('trip-card-route-title')),
    );

    expect(title.data, 'Solar Hotel → Accra Airport');
    expect(title.data, isNot('RR-APP-MUX3-TEST'));

    expect(find.text('Book again'), findsOneWidget);

    await tester.tap(find.byKey(const Key('history-card-book-again')));
    await tester.pump();

    expect(selectedRecord, same(record));
  });

  testWidgets('tracking filters internal and sensitive messages', (
    tester,
  ) async {
    _useSurface(tester);

    await _pumpTracking(
      tester,
      _SequenceRepository(<Object>[
        _record(
          status: 'requested',
          controlCenterMessage:
              'Access token authorization received '
              'by Control Center.',
        ),
      ]),
      pollInterval: const Duration(hours: 1),
    );

    expect(find.textContaining('Access token'), findsNothing);
    expect(find.textContaining('authorization'), findsNothing);
    expect(find.textContaining('Control Center'), findsNothing);
    expect(
      find.text(
        'We are reviewing your request and '
        'matching a nearby vehicle.',
      ),
      findsOneWidget,
    );

    await _disposeTracking(tester);
  });

  testWidgets(
    'completed tracking opens backend payment and rating by exact reference',
    (tester) async {
      _useSurface(tester);

      final paymentRepository = _TrackingPaymentRatingRepository();

      await _pumpTracking(
        tester,
        _SequenceRepository(<Object>[_record(status: 'completed')]),
        pollInterval: const Duration(hours: 1),
        paymentRatingRepository: paymentRepository,
      );

      expect(
        find.byKey(const Key('open-payment-rating-from-tracking')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const Key('open-payment-rating-from-tracking')),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byType(PassengerPaymentRatingPage), findsOneWidget);
      expect(paymentRepository.references, <String>[
        'RR-APP-MUX3-TEST',
        'RR-APP-MUX3-TEST',
        'RR-APP-MUX3-TEST',
      ]);
      expect(
        find.byKey(const Key('payment-not-available-state')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('payment-confirmed-state')), findsNothing);
      expect(find.byKey(const Key('payment-receipt-state')), findsNothing);

      await _disposeTracking(tester);
    },
  );

  test('tracking source forbids fake GPS and live animation', () {
    final source = File(
      'lib/tracking/ride_tracking_screen.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('accraVehicleFixture')));
    expect(source, isNot(contains('accraTripMidpointFixture')));
    expect(source, isNot(contains('WebSocket')));
    expect(source, isNot(contains('AnimationController')));
    expect(source, isNot(contains('StreamBuilder')));
    expect(source, contains('this.pollInterval = const Duration(seconds: 10)'));
  });

  testWidgets('test_emergency_action_opens_tel_191_dialer', (tester) async {
    _useSurface(tester);
    final repository = _SequenceRepository(<Object>[
      _record(
        latestStaffState: 'driver assigned',
        driverName: 'Kwame Mensah',
        vehicleColour: 'Blue',
        vehicleType: 'Solar Taxi',
      ),
    ]);
    final launcher = _RecordingSafetyUriLauncher();

    await _pumpTracking(
      tester,
      repository,
      pollInterval: const Duration(hours: 1),
      safetyUriLauncher: launcher,
    );

    await tester.ensureVisible(
      find.byKey(const Key('tracking-safety-emergency')),
    );
    await tester.tap(find.byKey(const Key('tracking-safety-emergency')));
    await tester.pump();

    expect(launcher.canLaunchUris, <Uri>[passengerEmergency191Uri]);
    expect(launcher.launchedUris, <Uri>[passengerEmergency191Uri]);
    expect(launcher.launchedUris.single.toString(), 'tel:191');

    await _disposeTracking(tester);
  });

  testWidgets('test_emergency_action_does_not_place_call_directly', (
    tester,
  ) async {
    _useSurface(tester);
    final repository = _SequenceRepository(<Object>[
      _record(latestStaffState: 'driver assigned'),
    ]);
    final launcher = _RecordingSafetyUriLauncher();

    await _pumpTracking(
      tester,
      repository,
      pollInterval: const Duration(hours: 1),
      safetyUriLauncher: launcher,
    );

    await tester.ensureVisible(
      find.byKey(const Key('tracking-safety-emergency')),
    );
    await tester.tap(find.byKey(const Key('tracking-safety-emergency')));
    await tester.pump();

    expect(launcher.launchedUris, hasLength(1));
    expect(launcher.launchedUris.single.scheme, 'tel');
    expect(launcher.launchedUris.single.path, '191');

    await _disposeTracking(tester);
  });

  testWidgets('test_sms_share_disabled_or_prompts_when_no_trusted_contact_set', (
    tester,
  ) async {
    _useSurface(tester);
    final repository = _SequenceRepository(<Object>[
      _record(
        latestStaffState: 'driver assigned',
        driverName: 'Kwame Mensah',
        vehicleColour: 'Blue',
        vehicleType: 'Solar Taxi',
      ),
    ]);
    final contacts = _TrackingTrustedContactRepository(
      const PassengerTrustedContact.empty(),
    );
    final launcher = _RecordingSafetyUriLauncher();

    await _pumpTracking(
      tester,
      repository,
      pollInterval: const Duration(hours: 1),
      trustedContactRepository: contacts,
      safetyUriLauncher: launcher,
    );

    expect(
      find.byKey(const Key('tracking-safety-message-contact')),
      findsNothing,
    );

    final shareFinder = find.byKey(const Key('tracking-safety-share'));
    await tester.ensureVisible(shareFinder);
    await tester.tap(shareFinder);
    await tester.pumpAndSettle();

    final finder = find.byKey(const Key('tracking-safety-message-contact'));
    expect(finder, findsOneWidget);

    await tester.tap(finder);
    await tester.pumpAndSettle();

    expect(contacts.fetchCalls, 1);
    expect(find.byType(SnackBar), findsOneWidget);

    final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(snackBar.content, isA<Text>());

    final guidance = snackBar.content as Text;
    expect(
      guidance.data,
      'Add a trusted contact in Safety & emergency settings to send this trip by message.',
    );

    expect(launcher.launchedUris, isEmpty);

    await _disposeTracking(tester);
  });

  testWidgets('test_os_share_sheet_available_independent_of_trusted_contact', (
    tester,
  ) async {
    _useSurface(tester);
    final repository = _SequenceRepository(<Object>[
      _record(
        latestStaffState: 'driver assigned',
        driverName: 'Kwame Mensah',
        vehicleColour: 'Blue',
        vehicleType: 'Solar Taxi',
        plateNumber: 'GT 1234-26',
      ),
    ]);
    final share = _RecordingSafetyShareGateway();

    await _pumpTracking(
      tester,
      repository,
      pollInterval: const Duration(hours: 1),
      safetyShareGateway: share,
    );

    final finder = find.byKey(const Key('tracking-safety-share'));
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();

    final anotherWay = find.byKey(
      const Key('tracking-safety-share-another-way'),
    );
    expect(anotherWay, findsOneWidget);

    await tester.tap(anotherWay);
    await tester.pumpAndSettle();

    expect(share.sharedTexts, hasLength(1));
    expect(share.sharedTexts.single, contains('Driver first name: Kwame'));
    expect(share.sharedTexts.single, contains('Vehicle type: Solar Taxi'));
    expect(share.sharedTexts.single, contains('Vehicle colour: Blue'));
    expect(share.sharedTexts.single, contains('Plate: GT 1234-26'));

    await _disposeTracking(tester);
  });

  testWidgets(
    'test_shared_summary_uses_actual_trip_reference_not_request_reference',
    (tester) async {
      _useSurface(tester);
      final repository = _SequenceRepository(<Object>[
        _record(
          status: 'driver_accepted',
          tripReference: 'TRIP-MUX3-SAFETY',
          latestStaffState: 'driver assigned',
          driverName: 'Kwame Mensah',
          vehicleColour: 'Blue',
          vehicleType: 'Solar Taxi',
          plateNumber: 'GT 1234-26',
        ),
      ]);
      final share = _RecordingSafetyShareGateway();

      await _pumpTracking(
        tester,
        repository,
        pollInterval: const Duration(hours: 1),
        safetyShareGateway: share,
      );

      final shareFinder = find.byKey(const Key('tracking-safety-share'));
      await tester.ensureVisible(shareFinder);
      await tester.tap(shareFinder);
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('tracking-safety-share-another-way')),
      );
      await tester.pumpAndSettle();

      expect(share.sharedTexts, hasLength(1));
      expect(
        share.sharedTexts.single,
        contains('Trip reference: TRIP-MUX3-SAFETY'),
      );
      expect(
        share.sharedTexts.single,
        isNot(contains('Trip reference: RR-APP-MUX3-TEST')),
      );

      await _disposeTracking(tester);
    },
  );

  testWidgets('test_share_trip_opens_two_choice_surface', (tester) async {
    _useSurface(tester);
    final repository = _SequenceRepository(<Object>[
      _record(
        status: 'driver_accepted',
        tripReference: 'TRIP-MUX3-SAFETY',
        latestStaffState: 'driver assigned',
      ),
    ]);
    final contacts = _TrackingTrustedContactRepository(
      const PassengerTrustedContact(
        name: 'Trusted Person',
        phone: '+233555000111',
      ),
    );

    await _pumpTracking(
      tester,
      repository,
      pollInterval: const Duration(hours: 1),
      trustedContactRepository: contacts,
    );

    final shareFinder = find.byKey(const Key('tracking-safety-share'));
    await tester.ensureVisible(shareFinder);
    await tester.tap(shareFinder);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('tracking-safety-share-choice-surface')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('tracking-safety-message-contact')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('tracking-safety-share-another-way')),
      findsOneWidget,
    );
    expect(find.text('Message trusted contact'), findsOneWidget);
    expect(find.text('Share another way'), findsOneWidget);

    await _disposeTracking(tester);
  });

  testWidgets(
    'test_message_trusted_contact_not_rendered_as_separate_top_level_action',
    (tester) async {
      _useSurface(tester);
      final repository = _SequenceRepository(<Object>[
        _record(
          status: 'driver_accepted',
          tripReference: 'TRIP-MUX3-SAFETY',
          latestStaffState: 'driver assigned',
        ),
      ]);
      final contacts = _TrackingTrustedContactRepository(
        const PassengerTrustedContact(
          name: 'Trusted Person',
          phone: '+233555000111',
        ),
      );

      await _pumpTracking(
        tester,
        repository,
        pollInterval: const Duration(hours: 1),
        trustedContactRepository: contacts,
      );

      expect(
        find.byKey(const Key('tracking-safety-message-contact')),
        findsNothing,
      );
      expect(find.text('Message trusted contact'), findsNothing);
      expect(find.byKey(const Key('tracking-safety-share')), findsOneWidget);

      await _disposeTracking(tester);
    },
  );

  testWidgets('test_sms_and_os_share_use_same_canonical_summary', (
    tester,
  ) async {
    _useSurface(tester);
    final repository = _SequenceRepository(<Object>[
      _record(
        status: 'driver_accepted',
        tripReference: 'TRIP-MUX3-SAFETY',
        latestStaffState: 'driver assigned',
        pickup: '5.60500, -0.16680',
        destination: 'Ghana Sea Port',
        driverName: 'Kwame Mensah',
        vehicleColour: 'Blue',
        vehicleType: 'Solar Taxi',
        plateNumber: 'GT 1234-26',
      ),
    ]);
    final contacts = _TrackingTrustedContactRepository(
      const PassengerTrustedContact(
        name: 'Trusted Person',
        phone: '+233555000111',
      ),
    );
    final launcher = _RecordingSafetyUriLauncher();
    final share = _RecordingSafetyShareGateway();

    await _pumpTracking(
      tester,
      repository,
      pollInterval: const Duration(hours: 1),
      trustedContactRepository: contacts,
      safetyUriLauncher: launcher,
      safetyShareGateway: share,
    );

    final shareFinder = find.byKey(const Key('tracking-safety-share'));
    await tester.ensureVisible(shareFinder);
    await tester.tap(shareFinder);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('tracking-safety-message-contact')));
    await tester.pumpAndSettle();

    expect(launcher.launchedUris, hasLength(1));
    final smsBody = launcher.launchedUris.single.queryParameters['body'];
    expect(smsBody, isNotNull);
    expect(smsBody, contains('Trip reference: TRIP-MUX3-SAFETY'));
    expect(smsBody, contains('Pickup: Not shared for privacy'));
    expect(smsBody, isNot(contains('5.60500')));
    expect(smsBody, isNot(contains('-0.16680')));

    await tester.ensureVisible(shareFinder);
    await tester.tap(shareFinder);
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('tracking-safety-share-another-way')),
    );
    await tester.pumpAndSettle();

    expect(share.sharedTexts, hasLength(1));
    expect(share.sharedTexts.single, smsBody);

    await _disposeTracking(tester);
  });

  testWidgets('test_safety_card_visual_placement_after_driver_vehicle_info', (
    tester,
  ) async {
    _useSurface(tester);
    final repository = _SequenceRepository(<Object>[
      _record(
        latestStaffState: 'driver assigned',
        driverName: 'Kwame Mensah',
        vehicleColour: 'Blue',
        vehicleType: 'Solar Taxi',
        plateNumber: 'GT 1234-26',
      ),
    ]);

    await _pumpTracking(
      tester,
      repository,
      pollInterval: const Duration(hours: 1),
    );

    final vehicle = find.byKey(const Key('tracking-vehicle-info'));
    final safety = find.byKey(const Key('tracking-safety-card'));

    expect(vehicle, findsOneWidget);
    expect(safety, findsOneWidget);
    expect(
      tester.getTopLeft(safety).dy,
      greaterThan(tester.getBottomLeft(vehicle).dy),
    );

    await _disposeTracking(tester);
  });
}

PassengerRideRequestRecord _record({
  String status = 'requested',
  String? latestStaffState,
  String? controlCenterMessage,
  String? tripReference,
  String pickup = 'Solar Hotel',
  String destination = 'Accra Airport',
  String? plateNumber,
  String? pickupVerificationCode,
  LatLng? vehiclePosition,
  String? driverName,
  String? vehicleType,
  String? vehicleColour,
  double? driverDistanceKm,
}) {
  return PassengerRideRequestRecord(
    requestReference: 'RR-APP-MUX3-TEST',
    status: status,
    pickupLocation: pickup,
    destination: destination,
    passengerCount: 1,
    createdAt: DateTime.utc(2026, 7, 14, 9),
    updatedAt: DateTime.utc(2026, 7, 14, 9, 5),
    hasMobileReceipt: true,
    tripCreated: false,
    latestStaffState: latestStaffState,
    controlCenterMessage: controlCenterMessage,
    tripReference: tripReference,
    plateNumber: plateNumber,
    pickupVerificationCode: pickupVerificationCode,
    vehicleLatitude: vehiclePosition?.latitude,
    vehicleLongitude: vehiclePosition?.longitude,
    driverName: driverName,
    vehicleType: vehicleType,
    vehicleColour: vehicleColour,
    driverDistanceKm: driverDistanceKm,
  );
}

void _useSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(430, 1000);
  tester.view.devicePixelRatio = 1;

  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pumpTracking(
  WidgetTester tester,
  PassengerRideRequestHistoryRepository repository, {
  required Duration pollInterval,
  PassengerTripLifecycleRepository? tripRepository,
  PassengerPaymentRatingRepository? paymentRatingRepository,
  PassengerTrustedContactRepository? trustedContactRepository,
  PassengerSafetyUriLauncher safetyUriLauncher =
      const PlatformPassengerSafetyUriLauncher(),
  PassengerSafetyShareGateway safetyShareGateway =
      const PlatformPassengerSafetyShareGateway(),
  PassengerCancellationGateway? cancellationGateway,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AsmThemes.passenger,
      home: RideTrackingScreen(
        repository: repository,
        requestReference: 'RR-APP-MUX3-TEST',
        tripRepository: tripRepository,
        pollInterval: pollInterval,
        paymentRatingRepository: paymentRatingRepository,
        trustedContactRepository: trustedContactRepository,
        safetyUriLauncher: safetyUriLauncher,
        safetyShareGateway: safetyShareGateway,
        cancellationGateway: cancellationGateway,
      ),
    ),
  );

  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
}

Future<void> _disposeTracking(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
  await tester.pump();
}

class _RecordingSafetyUriLauncher implements PassengerSafetyUriLauncher {
  final List<Uri> canLaunchUris = <Uri>[];
  final List<Uri> launchedUris = <Uri>[];

  @override
  Future<bool> canLaunch(Uri uri) async {
    canLaunchUris.add(uri);
    return true;
  }

  @override
  Future<bool> launch(Uri uri) async {
    launchedUris.add(uri);
    return true;
  }
}

class _RecordingSafetyShareGateway implements PassengerSafetyShareGateway {
  final List<String> sharedTexts = <String>[];

  @override
  Future<void> shareText(String text) async {
    sharedTexts.add(text);
  }
}

class _TrackingTrustedContactRepository
    implements PassengerTrustedContactRepository {
  _TrackingTrustedContactRepository(this.contact);

  PassengerTrustedContact contact;
  int fetchCalls = 0;

  @override
  Future<PassengerTrustedContact> fetch() async {
    fetchCalls += 1;
    return contact;
  }

  @override
  Future<PassengerTrustedContact> save({
    required String name,
    required String phone,
  }) async {
    contact = PassengerTrustedContact(name: name, phone: phone);
    return contact;
  }
}

class _FakeRouteService implements PassengerRouteService {
  const _FakeRouteService({this.estimate, this.error});

  final PassengerRouteEstimate? estimate;
  final Object? error;

  @override
  Future<PassengerRouteEstimate> route({
    LatLng pickup = accraPickup,
    LatLng destination = accraDestination,
  }) {
    final failure = error;

    if (failure != null) {
      return Future<PassengerRouteEstimate>.error(failure);
    }

    final value = estimate;

    if (value == null) {
      return Future<PassengerRouteEstimate>.error(
        StateError('No route result configured.'),
      );
    }

    return Future<PassengerRouteEstimate>.value(value);
  }
}

class _SequenceRepository implements PassengerRideRequestHistoryRepository {
  _SequenceRepository(
    this.detailResults, {
    this.listRecords = const <PassengerRideRequestRecord>[],
  });

  final List<Object> detailResults;
  final List<PassengerRideRequestRecord> listRecords;

  int detailCalls = 0;

  @override
  Future<List<PassengerRideRequestRecord>> fetchRequests() async {
    return listRecords;
  }

  @override
  Future<PassengerRideRequestRecord> fetchRequest(
    String requestReference,
  ) async {
    if (detailResults.isEmpty) {
      throw const PassengerRideRequestHistoryException.notFound();
    }

    final index = detailCalls < detailResults.length
        ? detailCalls
        : detailResults.length - 1;

    final result = detailResults[index];
    detailCalls += 1;

    if (result is PassengerRideRequestRecord) {
      return result;
    }

    throw result;
  }
}

PassengerTripRecord _trip({
  required String status,
  String message = 'Passenger-safe trip update.',
  String? driverName,
  String? vehicleType,
  String? vehicleColour,
  double? driverDistanceKm,
  String? fareAmount,
  String? plateNumber,
  String? pickupVerificationCode,
}) {
  return PassengerTripRecord(
    tripReference: 'TRIP-SWITCH-001',
    status: status,
    controlCenterMessage: message,
    driverName: driverName,
    vehicleType: vehicleType,
    vehicleColour: vehicleColour,
    driverDistanceKm: driverDistanceKm,
    fareAmount: fareAmount,
    plateNumber: plateNumber,
    pickupVerificationCode: pickupVerificationCode,
  );
}

class _FakeCancellationGateway implements PassengerCancellationGateway {
  _FakeCancellationGateway({this.error});

  final PassengerCancellationException? error;

  int rideRequestCalls = 0;
  int tripCalls = 0;
  final List<PassengerCancellationReason> rideRequestReasons =
      <PassengerCancellationReason>[];
  final List<String?> rideRequestNotes = <String?>[];
  final List<PassengerCancellationReason> tripReasons =
      <PassengerCancellationReason>[];
  final List<String?> tripNotes = <String?>[];

  @override
  Future<PassengerCancellationResult> cancelRideRequest({
    required String requestReference,
    required PassengerCancellationReason reason,
    String? reasonNote,
    required String idempotencyKey,
  }) async {
    rideRequestCalls += 1;
    rideRequestReasons.add(reason);
    rideRequestNotes.add(reasonNote);
    final currentError = error;
    if (currentError != null) {
      throw currentError;
    }
    return PassengerCancellationResult(
      reference: requestReference,
      status: 'cancelled',
      duplicate: false,
    );
  }

  @override
  Future<PassengerCancellationResult> cancelTripBooking({
    required String tripReference,
    required PassengerCancellationReason reason,
    String? reasonNote,
    required String idempotencyKey,
  }) async {
    tripCalls += 1;
    tripReasons.add(reason);
    tripNotes.add(reasonNote);
    final currentError = error;
    if (currentError != null) {
      throw currentError;
    }
    return PassengerCancellationResult(
      reference: tripReference,
      status: 'cancelled_by_passenger',
      duplicate: false,
    );
  }
}

class _TripSequenceRepository implements PassengerTripLifecycleRepository {
  _TripSequenceRepository(this.results);

  final List<Object> results;
  int tripCalls = 0;

  @override
  Future<PassengerTripRecord> fetchTrip(String tripReference) async {
    if (results.isEmpty) {
      throw const PassengerRideRequestHistoryException.notFound();
    }

    final index = tripCalls < results.length ? tripCalls : results.length - 1;
    final result = results[index];
    tripCalls += 1;

    if (result is PassengerTripRecord) {
      return PassengerTripRecord(
        tripReference: tripReference,
        status: result.status,
        controlCenterMessage: result.controlCenterMessage,
        fareAmount: result.fareAmount,
        plateNumber: result.plateNumber,
        pickupVerificationCode: result.pickupVerificationCode,
        vehicleLatitude: result.vehicleLatitude,
        vehicleLongitude: result.vehicleLongitude,
        driverName: result.driverName,
        vehicleType: result.vehicleType,
        vehicleColour: result.vehicleColour,
        driverDistanceKm: result.driverDistanceKm,
      );
    }

    throw result;
  }
}

/// Holds a trip fetch open until the test explicitly resolves it, so a
/// pre-resolution frame can be observed deterministically rather than
/// racing the fake repository's own (near-instant) Future resolution.
class _CompleterTripRepository implements PassengerTripLifecycleRepository {
  _CompleterTripRepository(this.result);

  final Future<PassengerTripRecord> result;

  @override
  Future<PassengerTripRecord> fetchTrip(String tripReference) => result;
}

class _TrackingPaymentRatingRepository
    implements PassengerPaymentRatingRepository {
  final List<String> references = <String>[];

  @override
  Future<PassengerFareSnapshot> fetchFare(String requestReference) async {
    references.add(requestReference);

    return PassengerFareSnapshot(
      requestReference: requestReference,
      fareStatus: 'fare_not_ready',
      canPay: false,
      message: 'The final fare is not ready yet.',
    );
  }

  @override
  Future<PassengerPaymentSnapshot> fetchPayment(String requestReference) async {
    references.add(requestReference);

    return PassengerPaymentSnapshot(
      requestReference: requestReference,
      paymentStatus: 'payment_not_available',
      canPay: false,
      canRetry: false,
      message: 'Payment is not available yet.',
    );
  }

  @override
  Future<PassengerRatingSnapshot> fetchRating(String requestReference) async {
    references.add(requestReference);

    return PassengerRatingSnapshot(
      requestReference: requestReference,
      ratingStatus: 'rating_not_open',
      canRate: false,
      message: 'Rating is not available yet.',
    );
  }

  @override
  Future<PassengerPaymentSnapshot> initiatePayment(
    String requestReference, {
    required String idempotencyKey,
  }) {
    throw StateError('Payment initiation was not expected.');
  }

  @override
  Future<PassengerPaymentReceiptSnapshot> fetchReceipt(
    String requestReference,
  ) {
    throw const PassengerPaymentRatingException.notFound();
  }

  @override
  Future<PassengerRatingSnapshot> submitRating(
    String requestReference,
    PassengerRatingSubmission submission,
  ) {
    throw StateError('Rating submission was not expected.');
  }
}
