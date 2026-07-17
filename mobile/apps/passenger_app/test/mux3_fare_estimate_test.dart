import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_app_config/asm_app_config.dart';
import 'package:asm_auth/asm_auth.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:passenger_app/booking/booking_page.dart';
import 'package:passenger_app/booking/passenger_fare_estimate.dart';
import 'package:passenger_app/map/osrm_route.dart';
import 'package:passenger_app/map/passenger_map.dart';

void main() {
  test(
    'fare repository sends authoritative trip_km and pickup_km zero',
    () async {
      final store = MemoryAuthTokenStore();
      await store.saveTokens(
        AuthTokens(accessToken: 'access', refreshToken: 'refresh'),
      );
      final gateway = _RecordingFareGateway.success(_farePayload());
      final repository = ApiPassengerFareEstimateRepository(
        gateway,
        tokenStore: store,
      );

      final estimate = await repository.fetchEstimate(10.2);

      expect(gateway.paths, <String>[ApiPassengerFareEstimateRepository.path]);
      expect(gateway.queries.single, <String, dynamic>{
        'trip_km': 10.2,
        'pickup_km': 0,
      });
      expect(estimate.tripKilometres, 10.2);
      expect(estimate.tripRate, 3.5);
      expect(estimate.tripFare, 35.7);
      expect(estimate.pickupFee, 0);
      expect(estimate.estimatedTotal, 35.7);
      expect(estimate.minimumFare, 20);
    },
  );

  test(
    'fare repository refreshes once after 401 and retries unchanged query',
    () async {
      final store = MemoryAuthTokenStore();
      await store.saveTokens(
        AuthTokens(
          accessToken: 'expired-access',
          refreshToken: 'stored-refresh',
        ),
      );
      final gateway = _RecordingFareGateway(
        replies: <_FareGatewayReply>[
          const _FareGatewayReply.authenticationFailure(),
          _FareGatewayReply.success(_farePayload()),
        ],
      );
      final authGateway = _RecordingAuthGateway();
      final repository = ApiPassengerFareEstimateRepository(
        gateway,
        tokenStore: store,
        authService: AuthService(apiGateway: authGateway, tokenStore: store),
      );

      final estimate = await repository.fetchEstimate(10.2);

      expect(estimate.estimatedTotal, 35.7);
      expect(gateway.paths, hasLength(2));
      expect(gateway.queries, <Map<String, dynamic>>[
        <String, dynamic>{'trip_km': 10.2, 'pickup_km': 0},
        <String, dynamic>{'trip_km': 10.2, 'pickup_km': 0},
      ]);
      expect(authGateway.paths, <String>[AuthService.refreshPath]);
      expect(await store.readAccessToken(), 'refreshed-access');
    },
  );

  test('fare response rejects nonzero booking pickup distance', () {
    final payload = _farePayload()..['pickup_km'] = '2.0';

    expect(
      () => PassengerBookingFareEstimate.fromJson(payload),
      throwsFormatException,
    );
  });

  testWidgets('fare panel displays only API-returned values', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: Scaffold(
          body: PassengerFareEstimatePanel(
            estimate: PassengerBookingFareEstimate.fromJson(_farePayload()),
          ),
        ),
      ),
    );

    expect(find.text('Fare estimate'), findsOneWidget);
    expect(find.text('Trip (10.2 km × GH₵3.50)'), findsOneWidget);
    expect(find.text('GH₵35.70'), findsNWidgets(2));
    expect(find.text('Pickup fee'), findsOneWidget);
    expect(find.text('GH₵0.00'), findsOneWidget);
    expect(find.text('Estimated total'), findsOneWidget);
    expect(find.text('Minimum fare: GH₵20.00'), findsOneWidget);
    expect(
      find.text('Final fare confirmed when driver is assigned.'),
      findsOneWidget,
    );
    expect(find.text('Payment: MTN MoMo'), findsOneWidget);
  });

  testWidgets('fare panel always has safe fallback when no fare is available', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: const Scaffold(body: PassengerFareEstimatePanel(estimate: null)),
      ),
    );

    expect(find.text('Fare estimate'), findsOneWidget);
    expect(
      find.text('Fare confirmed when driver is assigned.'),
      findsOneWidget,
    );
    expect(find.text('Payment: MTN MoMo'), findsOneWidget);
    expect(find.text('Estimated total'), findsNothing);
    expect(find.textContaining('Exception'), findsNothing);
    expect(find.textContaining('API'), findsNothing);
  });

  testWidgets('booking uses authoritative OSRM distance for fare request', (
    tester,
  ) async {
    _useSurface(tester, const Size(430, 1100));
    final repository = _RecordingFareRepository(
      PassengerBookingFareEstimate.fromJson(_farePayload()),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: BookingPage(
          market: MarketConfig.ghanaAccra,
          fareEstimateRepository: repository,
          routeService: const _FixedRouteService(
            PassengerRouteEstimate(
              points: <LatLng>[accraPickup, accraDestination],
              distanceKilometres: 10.2,
              durationMinutes: 22,
            ),
          ),
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

    expect(repository.tripKilometres, <double>[10.2]);
    expect(find.text('Trip (10.2 km × GH₵3.50)'), findsOneWidget);
    expect(find.text('Estimated total'), findsOneWidget);
  });

  testWidgets('booking keeps fallback when fare request fails', (tester) async {
    _useSurface(tester, const Size(430, 1100));

    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: const BookingPage(
          market: MarketConfig.ghanaAccra,
          fareEstimateRepository: _UnavailableFareRepository(),
          routeService: _FixedRouteService(
            PassengerRouteEstimate(
              points: <LatLng>[accraPickup, accraDestination],
              distanceKilometres: 10.2,
              durationMinutes: 22,
            ),
          ),
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

    expect(
      find.text('Fare confirmed when driver is assigned.'),
      findsOneWidget,
    );
    expect(find.text('Estimated total'), findsNothing);
    expect(find.textContaining('SocketException'), findsNothing);
    expect(find.textContaining('TimeoutException'), findsNothing);
  });
}

Map<String, Object?> _farePayload() {
  return <String, Object?>{
    'currency': 'GHS',
    'trip_km': '10.2',
    'pickup_km': '0',
    'trip_rate': '3.50',
    'trip_fare': '35.70',
    'pickup_fee': '0.00',
    'estimated_total': '35.70',
    'minimum_fare': '20.00',
  };
}

class _RecordingFareGateway implements PassengerFareEstimateApiGateway {
  _RecordingFareGateway({required List<_FareGatewayReply> replies})
    : _replies = List<_FareGatewayReply>.of(replies);

  factory _RecordingFareGateway.success(Map<String, Object?> payload) {
    return _RecordingFareGateway(
      replies: <_FareGatewayReply>[_FareGatewayReply.success(payload)],
    );
  }

  final List<_FareGatewayReply> _replies;
  final paths = <String>[];
  final queries = <Map<String, dynamic>>[];

  @override
  Future<ApiResponse<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    JsonDecoder<T>? decoder,
  }) async {
    paths.add(path);
    queries.add(Map<String, dynamic>.of(queryParameters ?? const {}));

    final reply = _replies.removeAt(0);
    if (reply.authenticationFailure) {
      return ApiResponse<T>.apiFailure(
        const AsmApiException(
          type: AsmApiExceptionType.authentication,
          message: 'Authentication required.',
          statusCode: 401,
        ),
      );
    }

    return ApiResponse<T>.success(decoder!(reply.payload), statusCode: 200);
  }
}

class _FareGatewayReply {
  const _FareGatewayReply.success(this.payload) : authenticationFailure = false;

  const _FareGatewayReply.authenticationFailure()
    : payload = null,
      authenticationFailure = true;

  final Object? payload;
  final bool authenticationFailure;
}

class _RecordingAuthGateway implements AuthApiGateway {
  final paths = <String>[];

  @override
  Future<ApiResponse<Map<String, Object?>>> post(
    String path, {
    required Map<String, Object?> body,
  }) async {
    paths.add(path);
    return ApiResponse<Map<String, Object?>>.success(const <String, Object?>{
      'access': 'refreshed-access',
    }, statusCode: 200);
  }
}

class _RecordingFareRepository implements PassengerFareEstimateRepository {
  _RecordingFareRepository(this.result);

  final PassengerBookingFareEstimate result;
  final tripKilometres = <double>[];

  @override
  Future<PassengerBookingFareEstimate> fetchEstimate(
    double tripKilometres,
  ) async {
    this.tripKilometres.add(tripKilometres);
    return result;
  }
}

class _UnavailableFareRepository implements PassengerFareEstimateRepository {
  const _UnavailableFareRepository();

  @override
  Future<PassengerBookingFareEstimate> fetchEstimate(double tripKilometres) {
    return Future<PassengerBookingFareEstimate>.error(
      StateError('Fare unavailable'),
    );
  }
}

class _FixedRouteService implements PassengerRouteService {
  const _FixedRouteService(this.estimate);

  final PassengerRouteEstimate estimate;

  @override
  Future<PassengerRouteEstimate> route({
    LatLng pickup = accraPickup,
    LatLng destination = accraDestination,
  }) async {
    return estimate;
  }
}

void _useSurface(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
