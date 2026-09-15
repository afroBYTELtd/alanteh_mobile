import 'dart:async';

import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_auth/asm_auth.dart';
import 'package:driver_app/driver_duty_trips.dart';
import 'package:driver_app/main.dart';
import 'package:driver_app/notifications/push_notification_runtime.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'driver push parser accepts driver_assigned with exact trip reference',
    () {
      final intent = driverPushNavigationIntentFromMessage(
        RemoteMessage(
          data: const <String, dynamic>{
            'event_type': 'driver_assigned',
            'trip_reference': 'TRIP-EXACT-ABC123',
          },
        ),
      );

      expect(intent, isNotNull);
      expect(intent!.eventType, 'driver_assigned');
      expect(intent.tripReference, 'TRIP-EXACT-ABC123');
    },
  );

  test('driver push parser safely ignores missing trip_reference', () {
    final intent = driverPushNavigationIntentFromMessage(
      RemoteMessage(
        data: const <String, dynamic>{'event_type': 'driver_assigned'},
      ),
    );

    expect(intent, isNull);
  });

  test('driver push parser safely ignores missing event_type', () {
    final intent = driverPushNavigationIntentFromMessage(
      RemoteMessage(
        data: const <String, dynamic>{'trip_reference': 'TRIP-MISSING-EVENT'},
      ),
    );

    expect(intent, isNull);
  });

  test('driver push parser safely ignores unsupported event_type', () {
    final intent = driverPushNavigationIntentFromMessage(
      RemoteMessage(
        data: const <String, dynamic>{
          'event_type': 'trip_completed',
          'trip_reference': 'TRIP-UNSUPPORTED',
        },
      ),
    );

    expect(intent, isNull);
  });

  testWidgets('opened message source dispatches Driver navigation intent', (
    tester,
  ) async {
    final source = _FakeDriverPushMessageSource();
    addTearDown(source.dispose);

    DriverPushNavigationIntent? received;

    await tester.pumpWidget(
      MaterialApp(
        home: FirebaseForegroundPushListener(
          messageSource: source,
          onNavigationIntent: (intent) async {
            received = intent;
          },
          child: const Scaffold(body: Text('Driver')),
        ),
      ),
    );

    source.emitOpened(
      RemoteMessage(
        data: const <String, dynamic>{
          'event_type': 'driver_assigned',
          'trip_reference': 'TRIP-LISTENER-OPENED-001',
        },
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(received?.eventType, 'driver_assigned');
    expect(received?.tripReference, 'TRIP-LISTENER-OPENED-001');
  });

  testWidgets(
    'onMessageOpenedApp driver_assigned opens exact Driver trip detail',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final source = _FakeDriverPushMessageSource();
      addTearDown(source.dispose);

      final gateway = _RecordingDriverDutyGateway();

      await _pumpSignedInDriverApp(tester, source: source, gateway: gateway);

      source.emitOpened(
        RemoteMessage(
          data: const <String, dynamic>{
            'event_type': 'driver_assigned',
            'trip_reference': 'TRIP-OPENED-EXACT-001',
          },
        ),
      );

      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();

      expect(gateway.detailTripReferences, contains('TRIP-OPENED-EXACT-001'));
      expect(find.byType(DriverTripDetailScreen), findsOneWidget);
    },
  );

  testWidgets(
    'getInitialMessage driver_assigned opens exact Driver trip detail',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final source = _FakeDriverPushMessageSource(
        initialMessage: RemoteMessage(
          data: const <String, dynamic>{
            'event_type': 'driver_assigned',
            'trip_reference': 'TRIP-COLD-START-EXACT-002',
          },
        ),
      );
      addTearDown(source.dispose);

      final gateway = _RecordingDriverDutyGateway();

      await _pumpSignedInDriverApp(tester, source: source, gateway: gateway);

      await tester.pump();
      await tester.pumpAndSettle();

      expect(
        gateway.detailTripReferences,
        contains('TRIP-COLD-START-EXACT-002'),
      );
      expect(find.byType(DriverTripDetailScreen), findsOneWidget);
    },
  );
}

Future<void> _pumpSignedInDriverApp(
  WidgetTester tester, {
  required _FakeDriverPushMessageSource source,
  required _RecordingDriverDutyGateway gateway,
}) async {
  final store = MemoryAuthTokenStore();
  final authApi = _SuccessfulDriverAuthApiGateway();

  await tester.pumpWidget(
    DriverApp(
      showLoginShell: true,
      authService: AuthService(
        apiGateway: authApi,
        tokenStore: store,
        appContext: AuthAppContext.driver,
      ),
      authTokenStore: store,
      driverDutyGateway: gateway,
      pushMessageSource: source,
    ),
  );

  await tester.pumpAndSettle();

  await tester.enterText(
    find.byKey(const Key('driver-phone-field')),
    '+233000000001',
  );
  await tester.enterText(find.byKey(const Key('driver-pin-field')), '9876');
  await tester.tap(find.byKey(const Key('driver-sign-in')));
  await tester.pumpAndSettle();

  expect(find.byKey(const Key('driver-sign-in')), findsNothing);
}

final class _FakeDriverPushMessageSource implements DriverPushMessageSource {
  _FakeDriverPushMessageSource({this.initialMessage});

  final RemoteMessage? initialMessage;

  final StreamController<RemoteMessage> _foregroundController =
      StreamController<RemoteMessage>.broadcast();
  final StreamController<RemoteMessage> _openedController =
      StreamController<RemoteMessage>.broadcast();

  @override
  Stream<RemoteMessage> get foregroundMessages => _foregroundController.stream;

  @override
  Stream<RemoteMessage> get openedMessages => _openedController.stream;

  @override
  Future<RemoteMessage?> getInitialMessage() async => initialMessage;

  void emitOpened(RemoteMessage message) {
    _openedController.add(message);
  }

  Future<void> dispose() async {
    await _foregroundController.close();
    await _openedController.close();
  }
}

final class _SuccessfulDriverAuthApiGateway implements AuthApiGateway {
  @override
  Future<ApiResponse<Map<String, Object?>>> post(
    String path, {
    required Map<String, Object?> body,
  }) async {
    return ApiResponse<Map<String, Object?>>.success(<String, Object?>{
      'access': 'driver-access-token',
      'refresh': 'driver-refresh-token',
      'account_type': 'driver',
      'account': <String, Object?>{},
    }, statusCode: 200);
  }
}

final class _RecordingDriverDutyGateway implements DriverDutyGateway {
  final List<String> detailTripReferences = <String>[];

  @override
  Future<DriverDutySummary> fetchDuty() async {
    return DriverDutySummary(
      dutyStatus: 'online',
      dutySince: DateTime(2026, 9, 14, 1),
      shiftCheckToday: true,
      canReceiveAssignments: true,
    );
  }

  @override
  Future<List<DriverAssignedTrip>> fetchTrips() async {
    return const <DriverAssignedTrip>[];
  }

  @override
  Future<DriverAssignedTrip> fetchTripDetail(String tripReference) async {
    detailTripReferences.add(tripReference);

    return DriverAssignedTrip(
      reference: tripReference,
      status: 'assigned',
      pickupLocation: 'Accra Mall',
      destination: 'Independence Square',
    );
  }
}
