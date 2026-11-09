// B8: six driver server actions through the whole app (DriverApp, signed in
// through its own sign-in screen). Each uses the production gateway or
// repository class over an AsmApiClient whose transport records the request,
// so the path, body and Bearer token are the ones production sends. Seen
// 30 Oct: none of these had a whole-app test; B7.2 showed why that matters.

import 'dart:async';
import 'dart:convert';

import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_auth/asm_auth.dart';
import 'package:asm_offline_queue/asm_offline_queue.dart';
import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:driver_app/driver_duty_trips.dart';
import 'package:driver_app/main.dart';
import 'package:driver_app/network/driver_rating_gateway.dart';
import 'package:driver_app/network/driver_trip_action_gateway.dart';
import 'package:driver_app/network/driver_trip_action_resilience.dart';
import 'package:driver_app/notifications/push_device_registration.dart';
import 'package:driver_app/notifications/push_notification_runtime.dart';
import 'package:driver_app/offers/driver_pending_offer_store.dart';
import 'package:driver_app/readiness/driver_readiness_check.dart';
import 'package:driver_app/readiness/driver_shift_check_submission.dart';
import 'package:driver_app/safety/driver_trip_safety.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _trip = 'TRIP-B8';

/// A real-shaped access token, valid until 2099: the app refreshes any
/// token it cannot read before sending.
final _access =
    'header.${base64Url.encode(utf8.encode('{"exp":4102444800}')).replaceAll('=', '')}.signature';

void main() {
  // Location services off, as on a phone with them turned off: the alert
  // goes without a position. (No plugin answers in a test.)
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter.baseflow.com/geolocator'),
          (call) async =>
              call.method == 'isLocationServiceEnabled' ? false : null,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter.baseflow.com/geolocator'),
          null,
        );
  });

  testWidgets('1. shift check: the check opens at sign-in, I am ready posts '
      'it, and Work says online', (tester) async {
    final app = _App()
      ..duty.dutyStatus = 'offline'
      ..duty.shiftCheckToday = false;
    await app.pumpSignedIn(tester);
    expect(
      find.byKey(const Key('driver-shift-readiness-screen')),
      findsOneWidget,
    );

    await _completeReadiness(tester);
    await tester.tap(find.byKey(const Key('readiness-ready')));
    await _settle(tester);
    // "Shift check submitted. You are now online." shows for 2 s.
    await tester.pump(const Duration(seconds: 2));
    await _settle(tester);

    final request = app.server.only('POST', '/api/driver/shift-check/');
    expect(request.bearer, _access);
    expect(request.headers['idempotency-key'], startsWith('DRIVER-SHIFT-'));
    expect(request.json, containsPair('vehicle_check', true));
    expect(request.json, containsPair('battery_check', true));
    expect(request.json, containsPair('phone_app_check', true));
    expect(request.json, containsPair('safety_check', true));
    expect(request.json['submitted_at'], isA<String>());
    expect(find.text("Today's shift · online now"), findsOneWidget);
    await app.dispose(tester);
  });

  testWidgets('2. trip actions: arrived, start, at destination and complete '
      'on the trip screen post the three actions, in order', (tester) async {
    final app = _App()..duty.tripStatus = 'driver_accepted';
    await app.pumpSignedIn(tester);
    await app.openLiveTrip(tester);

    await app.tapAndSettle(tester, 'driver-mark-arrived-pickup');
    await app.tapAndSettle(tester, 'driver-open-onboard-confirmation');
    await app.tapAndSettle(tester, 'driver-confirm-onboard');
    await app.tapAndSettle(tester, 'driver-mark-arrived-destination');
    final beforeComplete = app.server.requests.length;
    await app.tapAndSettle(tester, 'driver-complete-trip');

    final actions = app.server.requests
        .where((request) => request.path.contains('/actions/'))
        .toList();
    expect(actions.map((request) => '${request.method} ${request.path}'), [
      'POST /api/driver/trips/$_trip/actions/arrived-pickup/',
      'POST /api/driver/trips/$_trip/actions/start-trip/',
      'POST /api/driver/trips/$_trip/actions/complete-trip/',
    ]);
    for (final request in actions) {
      expect(request.bearer, _access);
      expect(request.headers['idempotency-key'], isNotEmpty);
    }
    expect(
      app.server.requests.length,
      beforeComplete + 1,
      reason: '"Arrived at destination" sends nothing; Complete sends one',
    );
    expect(find.byKey(const Key('driver-trip-completed')), findsOneWidget);
    await app.dispose(tester);
  });

  testWidgets('3. push registration: sign-in registers the phone', (
    tester,
  ) async {
    final app = _App();
    await app.pumpSignedIn(tester);

    final request = app.server.only('POST', '/api/push/devices/');
    expect(request.bearer, _access);
    expect(request.json, <String, Object?>{
      'device_token': 'fcm-b8-token',
      'platform': 'android',
    });
    await app.dispose(tester);
  });

  testWidgets('4. rating: a confirmed trip is rated from its detail screen', (
    tester,
  ) async {
    final app = _App()..duty.tripStatus = 'completed_confirmed';
    await app.pumpSignedIn(tester);
    await app.openTripDetail(tester);

    await app.tapAndSettle(tester, 'driver-rate-passenger-button');
    for (final key in const [
      'Overall-5',
      'Comfort-4',
      'Conduct-5',
      'Cleanliness-4',
    ]) {
      await app.tapAndSettle(tester, key);
    }
    await tester.enterText(
      find.byKey(const Key('driver-rating-feedback')),
      'Polite passenger',
    );
    await app.tapAndSettle(tester, 'submit-driver-rating');

    expect(
      app.server.only('GET', '/api/driver/trips/$_trip/rating/').bearer,
      _access,
    );
    final request = app.server.only('POST', '/api/driver/trips/$_trip/rating/');
    expect(request.bearer, _access);
    expect(request.json, <String, Object?>{
      'overall_score': 5,
      'comfort_score': 4,
      'conduct_score': 5,
      'cleanliness_score': 4,
      'feedback_note': 'Polite passenger',
    });
    expect(find.byKey(const Key('driver-rating-submitted')), findsOneWidget);
    await app.dispose(tester);
  });

  testWidgets('5. trusted contact: Account, Safety & emergency, Save', (
    tester,
  ) async {
    final app = _App();
    await app.pumpSignedIn(tester);
    await _selectTab(tester, 'Account');
    await app.tapAndSettle(tester, 'driver-account-safety-emergency');

    await tester.enterText(
      find.byKey(const Key('driver-trusted-contact-name')),
      'B8 Contact',
    );
    await tester.enterText(
      find.byKey(const Key('driver-trusted-contact-phone')),
      '+233200000008',
    );
    await app.tapAndSettle(tester, 'driver-trusted-contact-save');

    expect(app.server.only('GET', '/api/driver/profile/').bearer, isNotNull);
    final request = app.server.only('PATCH', '/api/driver/profile/');
    expect(request.bearer, _access);
    expect(request.json, <String, Object?>{
      'emergency_contact_name': 'B8 Contact',
      'emergency_contact_phone': '+233200000008',
    });
    await app.dispose(tester);
  });

  testWidgets('6. safety alert: one tap on Alert dispatch during a trip '
      'posts it, with the trip', (tester) async {
    final app = _App()..duty.tripStatus = 'in_progress';
    await app.pumpSignedIn(tester);
    await app.openLiveTrip(tester);

    await app.tapAndSettle(tester, 'driver-trip-safety-alert-dispatch');

    final request = app.server.only('POST', '/api/driver/safety-alert/');
    expect(request.bearer, _access);
    expect(request.json, containsPair('trip_reference', _trip));
    expect(find.text('Your alert has been sent to dispatch.'), findsOneWidget);
    await app.dispose(tester);
  });
}

final class _App {
  final tokens = MemoryAuthTokenStore();
  final duty = _Duty();
  late final server = _Server(duty);
  late final _client = AsmApiClient(
    baseUrl: 'https://b8.alanteh.invalid',
    tokenProvider: DriverStoredAccessTokenProvider(tokens),
    dio: Dio()..httpClientAdapter = server,
  );

  Widget _app() => DriverApp(
    showLoginShell: true,
    authService: AuthService(
      apiGateway: _AuthApi(),
      tokenStore: tokens,
      appContext: AuthAppContext.driver,
    ),
    authTokenStore: tokens,
    driverDutyGateway: duty,
    driverShiftCheckController: DriverShiftCheckSubmissionController(
      queue: _MemoryQueue(),
      gateway: ApiDriverShiftCheckGateway(
        client: _client,
        tokenStore: tokens,
        refreshAccessToken: null,
      ),
      isOnline: () async => true,
    ),
    driverTripActionControllerFactory: (reference) async =>
        DriverTripActionResilienceController(
          queue: _MemoryQueue(),
          gateway: ApiDriverTripActionGateway(
            apiGateway: AsmDriverTripActionApiGateway(_client),
            tokenStore: tokens,
          ),
          tripReference: reference,
          driverId: 'DRV-1',
          readCurrentTripStatus: () async => duty.tripStatus,
          verifyServerState: (action, receipt) async =>
              duty.tripStatus == action.expectedStatus,
        ),
    driverRatingGateway: ApiDriverRatingGateway(
      apiGateway: AsmDriverRatingApiGateway(_client),
    ),
    driverTrustedContactRepository: ApiDriverTrustedContactRepository(
      apiGateway: AsmDriverTrustedContactApiGateway(_client),
      tokenStore: tokens,
      connectionConfigured: true,
    ),
    driverSafetyAlertRepository: ApiDriverSafetyAlertRepository(
      apiGateway: AsmDriverSafetyAlertApiGateway(_client),
      tokenStore: tokens,
      connectionConfigured: true,
    ),
    pushMessageSource: _NoPushes(),
    pushDeviceRegistrarFactory: (_, {refreshSession}) =>
        FirebasePushDeviceRegistrar(
          tokenSource: _TokenSource(),
          apiGateway: AsmPushDeviceRegistrationApiGateway(_client),
        ),
  );

  Future<void> pumpSignedIn(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app());
    await _settle(tester);
    await tester.enterText(
      find.byKey(const Key('driver-phone-field')),
      '+233000000001',
    );
    await tester.enterText(find.byKey(const Key('driver-pin-field')), '9876');
    await tester.tap(find.byKey(const Key('driver-sign-in')));
    await _settle(tester);
  }

  Future<void> openTripDetail(WidgetTester tester) async {
    await _selectTab(tester, 'Trips');
    await tester.tap(find.text(_trip));
    await _settle(tester);
  }

  Future<void> openLiveTrip(WidgetTester tester) async {
    await openTripDetail(tester);
    await tapAndSettle(tester, 'driver-open-live-trip-actions');
  }

  Future<void> tapAndSettle(WidgetTester tester, String key) async {
    final finder = find.byKey(Key(key));
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await _settle(tester);
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }
}

Future<void> _selectTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i += 1) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _completeReadiness(WidgetTester tester) async {
  final list = find.byType(Scrollable).last;
  for (final item in DriverReadinessItem.values) {
    final finder = find.byKey(ValueKey<String>('readiness-${item.name}'));
    await tester.scrollUntilVisible(finder, 200, scrollable: list);
    await tester.pump();
    await tester.tap(finder);
    await tester.pump();
  }
  await tester.scrollUntilVisible(
    find.byKey(const Key('readiness-ready')),
    200,
    scrollable: list,
  );
  await tester.pump();
}

final class _Request {
  _Request(this.method, this.path, this.headers, this.body);

  final String method;
  final String path;
  final Map<String, String> headers;
  final String body;

  Map<String, Object?> get json =>
      (jsonDecode(body) as Map).cast<String, Object?>();

  String? get bearer {
    final header = headers['authorization'];
    return header != null && header.startsWith('Bearer ')
        ? header.substring('Bearer '.length)
        : null;
  }
}

/// The server: records each request at the transport and answers it.
final class _Server implements HttpClientAdapter {
  _Server(this.duty);

  final _Duty duty;
  final requests = <_Request>[];

  _Request only(String method, String path) => requests.singleWhere(
    (request) => request.method == method && request.path == path,
  );

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final bytes = <int>[];
    if (requestStream != null) {
      await requestStream.forEach(bytes.addAll);
    }
    final request = _Request(options.method, options.uri.path, <String, String>{
      for (final entry in options.headers.entries)
        entry.key.toLowerCase(): '${entry.value}',
    }, utf8.decode(bytes));
    requests.add(request);
    final (status, body) = _answer(request);
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  (int, Map<String, Object?>) _answer(_Request request) {
    final path = request.path;
    if (path == '/api/driver/shift-check/') {
      duty
        ..dutyStatus = 'online'
        ..shiftCheckToday = true;
      return (201, <String, Object?>{'shift_check_reference': 'SC-B8'});
    }
    final action = RegExp(r'/actions/([a-z-]+)/$').firstMatch(path)?.group(1);
    if (action != null) {
      final status = switch (action) {
        'arrived-pickup' => 'arrived_at_pickup',
        'start-trip' => 'in_progress',
        _ => 'completed_pending_review',
      };
      duty.tripStatus = status;
      // A new action is answered 201; 200 only for a duplicate.
      return (
        201,
        <String, Object?>{
          'trip_reference': _trip,
          'status': status,
          'message': 'Driver trip action recorded.',
          'duplicate': false,
        },
      );
    }
    if (path.endsWith('/rating/')) {
      final posted = request.method == 'POST';
      return (
        posted ? 201 : 200,
        <String, Object?>{
          'trip_reference': _trip,
          'submitted': posted,
          if (posted)
            'rating': (jsonDecode(request.body) as Map).cast<String, Object?>(),
        },
      );
    }
    if (path == '/api/driver/profile/') {
      return (
        200,
        <String, Object?>{
          'emergency_contact_name': request.method == 'PATCH'
              ? 'B8 Contact'
              : '',
          'emergency_contact_phone': request.method == 'PATCH'
              ? '+233200000008'
              : '',
        },
      );
    }
    if (path == '/api/driver/safety-alert/') {
      return (201, <String, Object?>{'id': 1});
    }
    if (path == '/api/push/devices/') {
      return (201, <String, Object?>{'id': 1});
    }
    return (404, <String, Object?>{'detail': 'Not found.'});
  }

  @override
  void close({bool force = false}) {}
}

final class _Duty implements DriverDutyGateway, DriverDutyStatusGateway {
  String dutyStatus = 'online';
  bool shiftCheckToday = true;
  String? tripStatus;

  @override
  Future<DriverDutySummary> fetchDuty() async => DriverDutySummary(
    driverReference: 'DRV-1',
    dutyStatus: dutyStatus,
    shiftCheckToday: shiftCheckToday,
    canReceiveAssignments: true,
  );

  @override
  Future<List<DriverAssignedTrip>> fetchTrips() async =>
      tripStatus == null ? const [] : [_assigned()];

  @override
  Future<DriverAssignedTrip> fetchTripDetail(String tripReference) async =>
      _assigned();

  DriverAssignedTrip _assigned() => DriverAssignedTrip(
    reference: _trip,
    status: tripStatus,
    pickupLocation: 'Accra Mall',
    destination: 'Independence Square',
    passengerCount: 1,
  );

  @override
  Future<DriverDutyTransition> updateDutyStatus(
    DriverOperationalDutyStatus status,
  ) async {
    dutyStatus = status.wireValue;
    return DriverDutyTransition(
      dutyStatus: status.wireValue,
      since: DateTime.utc(2026, 10, 31),
    );
  }
}

/// Firebase's messages, none arriving.
final class _NoPushes implements DriverPushMessageSource {
  @override
  Stream<RemoteMessage> get foregroundMessages =>
      const Stream<RemoteMessage>.empty();

  @override
  Stream<RemoteMessage> get openedMessages =>
      const Stream<RemoteMessage>.empty();

  @override
  Future<RemoteMessage?> getInitialMessage() async => null;
}

final class _TokenSource implements PushMessagingTokenSource {
  @override
  Future<String?> getToken() async => 'fcm-b8-token';

  @override
  Stream<String> get onTokenRefresh => const Stream<String>.empty();

  @override
  Future<bool> requestNotificationPermission() async => true;
}

final class _AuthApi implements AuthApiGateway {
  @override
  Future<ApiResponse<Map<String, Object?>>> post(
    String path, {
    required Map<String, Object?> body,
  }) async => ApiResponse<Map<String, Object?>>.success(<String, Object?>{
    'access': _access,
    'refresh': 'driver-refresh',
    'account_type': 'driver',
    'account': <String, Object?>{},
  }, statusCode: 200);
}

final class _MemoryQueue implements DriverTripActionPersistentQueue {
  final _events = <String, QueuedEvent>{};

  @override
  Future<QueuedEvent> enqueue(QueuedEvent event) async =>
      _events.putIfAbsent(event.id, () => event);

  @override
  Future<QueuedEvent?> eventById(String id) async => _events[id];

  @override
  Future<List<QueuedEvent>> pendingEvents() async => _events.values.toList();

  @override
  Future<void> markSynced(String id) async => _events.remove(id);

  @override
  Future<void> markFailed(String id) async {}

  @override
  Future<void> markPermanentlyFailed(String id) async => _events.remove(id);
}
