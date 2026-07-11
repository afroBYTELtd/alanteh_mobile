import 'dart:async';
import 'dart:io';

import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_auth/asm_auth.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passenger_app/ride_requests/ride_request_history.dart';

void main() {
  test('history repository uses accepted list and detail endpoints', () async {
    final store = MemoryAuthTokenStore();
    await store.saveTokens(AuthTokens(accessToken: 'a', refreshToken: 'r'));

    final gateway = _FakeHistoryGateway(
      responses: <String, Object?>{
        ApiPassengerRideRequestHistoryRepository.listPath: <String, Object?>{
          'results': <Object?>[_recordJson(reference: 'RR-APP-NEWEST')],
        },
        '/api/rides/requests/RR-APP-NEWEST/': _recordJson(
          reference: 'RR-APP-NEWEST',
          controlCenterMessage: 'Passenger-safe detail update.',
        ),
      },
    );

    final repository = ApiPassengerRideRequestHistoryRepository(
      gateway,
      tokenStore: store,
    );

    final records = await repository.fetchRequests();
    final detail = await repository.fetchRequest('RR-APP-NEWEST');

    expect(records.single.requestReference, 'RR-APP-NEWEST');
    expect(detail.requestReference, 'RR-APP-NEWEST');
    expect(gateway.paths, <String>[
      '/api/rides/requests/',
      '/api/rides/requests/RR-APP-NEWEST/',
    ]);
  });

  testWidgets('request history shows loading state', (tester) async {
    final pending = Completer<List<PassengerRideRequestRecord>>();

    await _pumpHistory(
      tester,
      _FakeRepository(listLoader: () => pending.future),
    );

    expect(
      find.byKey(const Key('ride-request-history-loading')),
      findsOneWidget,
    );

    pending.complete(const <PassengerRideRequestRecord>[]);
    await tester.pumpAndSettle();
  });

  testWidgets('request history shows loaded records newest first', (
    tester,
  ) async {
    final newest = _record(
      reference: 'RR-APP-NEWEST',
      createdAt: DateTime.utc(2026, 7, 11, 13),
      pickup: 'Accra Mall',
      destination: 'Kotoka International Airport',
      latestStaffState: 'Passenger app request received.',
    );
    final older = _record(
      reference: 'RR-APP-OLDER',
      createdAt: DateTime.utc(2026, 7, 11, 12),
      pickup: 'Osu',
      destination: 'Airport City',
    );

    await _pumpHistory(
      tester,
      _FakeRepository(
        listLoader: () async => <PassengerRideRequestRecord>[older, newest],
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('ride-request-history-loaded')),
      findsOneWidget,
    );
    expect(find.text('RR-APP-NEWEST'), findsOneWidget);
    expect(find.text('RR-APP-OLDER'), findsOneWidget);
    expect(find.text('Mobile receipt confirmed'), findsWidgets);
    expect(find.text('Passenger app request received.'), findsOneWidget);

    final newestTop = tester.getTopLeft(
      find.byKey(const ValueKey<String>('ride-request-RR-APP-NEWEST')),
    );
    final olderTop = tester.getTopLeft(
      find.byKey(const ValueKey<String>('ride-request-RR-APP-OLDER')),
    );

    expect(newestTop.dy, lessThan(olderTop.dy));
  });

  testWidgets('request history shows empty state', (tester) async {
    await _pumpHistory(
      tester,
      _FakeRepository(
        listLoader: () async => const <PassengerRideRequestRecord>[],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ride-request-history-empty')), findsOneWidget);
    expect(find.text('No trips yet'), findsOneWidget);
  });

  testWidgets('request history shows safe error state', (tester) async {
    await _pumpHistory(
      tester,
      _FakeRepository(
        listLoader: () => Future<List<PassengerRideRequestRecord>>.error(
          const PassengerRideRequestHistoryException.network(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ride-request-history-error')), findsOneWidget);
    expect(
      find.text(PassengerRideRequestHistoryException.networkMessage),
      findsOneWidget,
    );
    expect(find.byKey(const Key('ride-request-history-retry')), findsOneWidget);
  });

  testWidgets('request history shows safe session expired state', (
    tester,
  ) async {
    var signInRequested = false;

    await _pumpHistory(
      tester,
      _FakeRepository(
        listLoader: () => Future<List<PassengerRideRequestRecord>>.error(
          const PassengerRideRequestHistoryException.sessionExpired(),
        ),
      ),
      onSignInRequired: () {
        signInRequested = true;
      },
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('ride-request-history-session-expired')),
      findsOneWidget,
    );
    expect(find.text('Session expired'), findsOneWidget);
    expect(
      find.text(PassengerRideRequestHistoryException.sessionExpiredMessage),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('ride-request-history-sign-in-again')),
    );

    expect(signInRequested, isTrue);
  });

  testWidgets('request detail displays only passenger-safe fields', (
    tester,
  ) async {
    final summary = _record(
      reference: 'RR-APP-DETAIL',
      pickup: 'Accra Mall',
      destination: 'Kotoka International Airport',
    );

    final detail = _record(
      reference: 'RR-APP-DETAIL',
      pickup: 'Accra Mall',
      destination: 'Kotoka International Airport',
      passengerCount: 2,
      requestedPickupTime: DateTime.utc(2026, 7, 11, 14, 30),
      status: 'under_review',
      tripCreated: false,
      controlCenterMessage: 'Your request is being reviewed.',
    );

    await _pumpHistory(
      tester,
      _FakeRepository(
        listLoader: () async => <PassengerRideRequestRecord>[summary],
        detailLoader: (_) async => detail,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('ride-request-RR-APP-DETAIL')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ride-request-detail-loaded')), findsOneWidget);
    expect(find.text('RR-APP-DETAIL'), findsOneWidget);
    expect(find.text('Accra Mall'), findsOneWidget);
    expect(find.text('Kotoka International Airport'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('Under Review'), findsOneWidget);
    expect(find.text('Confirmed'), findsOneWidget);
    expect(find.text('Not yet converted into a trip'), findsOneWidget);
    expect(find.text('Your request is being reviewed.'), findsOneWidget);
  });

  testWidgets('history screens do not render sensitive fields', (tester) async {
    final record = _record(
      reference: 'RR-APP-SAFE',
      pickup: 'Accra Mall',
      destination: 'Airport City',
      controlCenterMessage: 'Passenger-safe Control Center update.',
    );

    await _pumpHistory(
      tester,
      _FakeRepository(
        listLoader: () async => <PassengerRideRequestRecord>[record],
        detailLoader: (_) async => record,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('ride-request-RR-APP-SAFE')),
    );
    await tester.pumpAndSettle();

    for (final sensitiveText in <String>[
      'PIN',
      'access token',
      'refresh token',
      'Authorization',
      'phone',
      'email',
      'idempotency key',
      'raw payload',
    ]) {
      expect(
        find.textContaining(sensitiveText, findRichText: true),
        findsNothing,
      );
    }
  });

  testWidgets('history toolbar refresh reloads requests', (tester) async {
    var calls = 0;

    await _pumpHistory(
      tester,
      _FakeRepository(
        listLoader: () async {
          calls += 1;
          return <PassengerRideRequestRecord>[
            _record(
              reference: calls == 1 ? 'RR-APP-FIRST' : 'RR-APP-REFRESHED',
            ),
          ];
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('RR-APP-FIRST'), findsOneWidget);

    await tester.tap(find.byTooltip('Refresh requests'));
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(find.text('RR-APP-REFRESHED'), findsOneWidget);
    expect(find.text('RR-APP-FIRST'), findsNothing);
  });

  testWidgets('history pull to refresh reloads requests', (tester) async {
    var calls = 0;

    await _pumpHistory(
      tester,
      _FakeRepository(
        listLoader: () async {
          calls += 1;
          return <PassengerRideRequestRecord>[
            _record(
              reference: calls == 1
                  ? 'RR-APP-BEFORE-PULL'
                  : 'RR-APP-AFTER-PULL',
            ),
          ];
        },
      ),
    );
    await tester.pumpAndSettle();

    final refreshState = tester.state<RefreshIndicatorState>(
      find.byType(RefreshIndicator),
    );

    final refreshFuture = refreshState.show();
    await tester.pump();
    await tester.pumpAndSettle();
    await refreshFuture;

    expect(calls, 2);
    expect(find.text('RR-APP-AFTER-PULL'), findsOneWidget);
    expect(find.text('RR-APP-BEFORE-PULL'), findsNothing);
  });

  test('Passenger navigation and receipt link to request history', () {
    final homeSource = File('lib/passenger_home.dart').readAsStringSync();

    final shellSource = File('lib/passenger_shell.dart').readAsStringSync();

    final reviewSource = File(
      'lib/booking/booking_review.dart',
    ).readAsStringSync();

    expect(homeSource, contains("label: const Text('My Ride Requests')"));
    expect(homeSource, contains("Key('open-ride-request-history')"));
    expect(reviewSource, contains("label: const Text('View my requests')"));
    expect(reviewSource, isNot(contains("label: const Text('Back to home')")));
    expect(
      RegExp(
        r'if \(widget\.rideRequestHistoryRepository != null\)',
      ).allMatches(shellSource),
      hasLength(2),
    );
    expect(
      RegExp(r'await _openRideRequests\(\);').allMatches(shellSource),
      hasLength(2),
    );
    expect(shellSource, contains('1 => PassengerRideRequestHistoryPage('));
    expect(
      shellSource,
      contains('const EmptyPassengerRideRequestHistoryRepository()'),
    );
    expect(shellSource, isNot(contains("title: 'No trips yet'")));
  });

  test('Driver app remains free of Passenger history integration', () {
    final driverDirectory = Directory('../driver_app/lib');

    expect(driverDirectory.existsSync(), isTrue);

    final source = driverDirectory
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .map((file) => file.readAsStringSync())
        .join('\n');

    expect(source, isNot(contains('/api/rides/requests/')));
    expect(source, isNot(contains('PassengerRideRequestHistory')));
  });
}

Future<void> _pumpHistory(
  WidgetTester tester,
  PassengerRideRequestHistoryRepository repository, {
  VoidCallback? onSignInRequired,
}) async {
  tester.view.physicalSize = const Size(430, 900);
  tester.view.devicePixelRatio = 1;

  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: AsmThemes.passenger,
      home: PassengerRideRequestHistoryPage(
        repository: repository,
        onSignInRequired: onSignInRequired,
      ),
    ),
  );
}

PassengerRideRequestRecord _record({
  required String reference,
  String pickup = 'Pickup',
  String destination = 'Destination',
  String status = 'requested',
  int passengerCount = 1,
  DateTime? requestedPickupTime,
  bool tripCreated = false,
  String? latestStaffState,
  DateTime? createdAt,
  String? controlCenterMessage,
}) {
  return PassengerRideRequestRecord(
    requestReference: reference,
    status: status,
    pickupLocation: pickup,
    destination: destination,
    passengerCount: passengerCount,
    requestedPickupTime: requestedPickupTime,
    createdAt: createdAt ?? DateTime.utc(2026, 7, 11, 12),
    updatedAt: DateTime.utc(2026, 7, 11, 13),
    hasMobileReceipt: true,
    tripCreated: tripCreated,
    latestStaffState: latestStaffState,
    controlCenterMessage: controlCenterMessage,
  );
}

Map<String, Object?> _recordJson({
  required String reference,
  String? controlCenterMessage,
}) {
  final result = <String, Object?>{
    'request_reference': reference,
    'status': 'requested',
    'pickup_location': 'Accra Mall',
    'destination': 'Kotoka International Airport',
    'passenger_count': 1,
    'requested_pickup_time': null,
    'created_at': '2026-07-11T12:00:00Z',
    'updated_at': '2026-07-11T13:00:00Z',
    'source_channel': 'passenger_app',
    'has_mobile_receipt': true,
    'latest_staff_state': 'Passenger app request received.',
    'trip_created': false,
  };
  if (controlCenterMessage != null) {
    result['control_center_message'] = controlCenterMessage;
  }
  return result;
}

class _FakeRepository implements PassengerRideRequestHistoryRepository {
  const _FakeRepository({required this.listLoader, this.detailLoader});

  final Future<List<PassengerRideRequestRecord>> Function() listLoader;

  final Future<PassengerRideRequestRecord> Function(String requestReference)?
  detailLoader;

  @override
  Future<List<PassengerRideRequestRecord>> fetchRequests() {
    return listLoader();
  }

  @override
  Future<PassengerRideRequestRecord> fetchRequest(String requestReference) {
    final loader = detailLoader;
    if (loader == null) {
      return Future<PassengerRideRequestRecord>.error(
        const PassengerRideRequestHistoryException.notFound(),
      );
    }
    return loader(requestReference);
  }
}

class _FakeHistoryGateway implements PassengerRideRequestHistoryApiGateway {
  _FakeHistoryGateway({required this.responses});

  final Map<String, Object?> responses;
  final List<String> paths = <String>[];

  @override
  Future<ApiResponse<T>> get<T>(String path, {JsonDecoder<T>? decoder}) async {
    paths.add(path);

    final payload = responses[path];

    if (payload == null || decoder == null) {
      return ApiResponse.apiFailure(
        const AsmApiException(
          type: AsmApiExceptionType.notFound,
          message: 'Not found.',
          statusCode: 404,
        ),
      );
    }

    return ApiResponse.success(decoder(payload), statusCode: 200);
  }
}
