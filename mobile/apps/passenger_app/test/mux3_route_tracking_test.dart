import 'dart:io';

import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:passenger_app/booking/route_preview_card.dart';
import 'package:passenger_app/map/osrm_route.dart';
import 'package:passenger_app/map/passenger_map.dart';
import 'package:passenger_app/payment_rating/passenger_payment_rating_contract.dart';
import 'package:passenger_app/payment_rating/passenger_payment_rating_page.dart';
import 'package:passenger_app/ride_requests/ride_request_history.dart';
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
            record: _record(latestStaffState: 'driver assigned'),
            key: 'driver-assigned-state',
            title: 'Driver assigned',
          ),
          (
            record: _record(latestStaffState: 'dispatched'),
            key: 'vehicle-en-route-state',
            title: 'Your vehicle is on the way',
          ),
          (
            record: _record(latestStaffState: 'driver arrived'),
            key: 'driver-arrived-state',
            title: 'Your driver is outside',
          ),
          (
            record: _record(status: 'in progress'),
            key: 'trip-in-progress-state',
            title: 'Trip in progress',
          ),
          (
            record: _record(status: 'completed'),
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

  testWidgets('terminal arrival stops tracking polling', (tester) async {
    _useSurface(tester);

    final repository = _SequenceRepository(<Object>[
      _record(status: 'completed'),
    ]);

    await _pumpTracking(
      tester,
      repository,
      pollInterval: const Duration(milliseconds: 10),
    );

    expect(
      find.byKey(const Key('arrived-at-destination-state')),
      findsOneWidget,
    );

    await tester.pump(const Duration(milliseconds: 50));

    expect(repository.detailCalls, 1);

    await _disposeTracking(tester);
  });

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

  testWidgets('cancel dialog performs no backend mutation', (tester) async {
    _useSurface(tester);

    final repository = _SequenceRepository(<Object>[
      _record(status: 'requested'),
    ]);

    await _pumpTracking(
      tester,
      repository,
      pollInterval: const Duration(hours: 1),
    );

    final callsBeforeDialog = repository.detailCalls;

    await tester.tap(find.byKey(const Key('open-cancel-confirmation')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('cancel-confirmation-dialog')), findsOneWidget);
    expect(repository.detailCalls, callsBeforeDialog);

    await tester.tap(
      find.byKey(const Key('cancel-dialog-no-backend-mutation')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(repository.detailCalls, callsBeforeDialog);

    await _disposeTracking(tester);
  });

  testWidgets('vehicle-en-route cancel dialog stays local only', (
    tester,
  ) async {
    _useSurface(tester);

    final repository = _SequenceRepository(<Object>[
      _record(
        latestStaffState: 'dispatched',
        vehiclePosition: _testVehiclePosition,
      ),
    ]);

    await _pumpTracking(
      tester,
      repository,
      pollInterval: const Duration(hours: 1),
    );

    final callsBeforeDialog = repository.detailCalls;

    await tester.tap(find.byKey(const Key('open-cancel-confirmation')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.byKey(const Key('cancel-vehicle-en-route-dialog')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('cancel-dialog-no-backend-mutation')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(repository.detailCalls, callsBeforeDialog);

    await _disposeTracking(tester);
  });

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
}

PassengerRideRequestRecord _record({
  String status = 'requested',
  String? latestStaffState,
  String? controlCenterMessage,
  String pickup = 'Solar Hotel',
  String destination = 'Accra Airport',
  String? plateNumber,
  LatLng? vehiclePosition,
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
    plateNumber: plateNumber,
    vehicleLatitude: vehiclePosition?.latitude,
    vehicleLongitude: vehiclePosition?.longitude,
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
  PassengerPaymentRatingRepository? paymentRatingRepository,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AsmThemes.passenger,
      home: RideTrackingScreen(
        repository: repository,
        requestReference: 'RR-APP-MUX3-TEST',
        pollInterval: pollInterval,
        paymentRatingRepository: paymentRatingRepository,
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
