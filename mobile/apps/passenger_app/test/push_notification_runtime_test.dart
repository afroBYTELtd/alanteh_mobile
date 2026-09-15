import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passenger_app/notifications/push_notification_runtime.dart';

void main() {
  RemoteMessage message({
    String eventType = 'driver_accepted',
    String tripReference = 'TRIP-PUSH-001',
  }) {
    return RemoteMessage(
      data: <String, dynamic>{
        'event_type': eventType,
        'trip_reference': tripReference,
      },
    );
  }

  test('manual RemoteMessage parses authorized push contract', () {
    final intent = passengerPushNavigationIntentFromMessage(message());

    expect(intent, isNotNull);
    expect(intent!.eventType, 'driver_accepted');
    expect(intent.tripReference, 'TRIP-PUSH-001');
  });

  test('missing or blank authorized fields are rejected', () {
    expect(
      passengerPushNavigationIntentFromMessage(
        RemoteMessage(
          data: const <String, dynamic>{
            'event_type': '',
            'trip_reference': 'TRIP-PUSH-001',
          },
        ),
      ),
      isNull,
    );

    expect(
      passengerPushNavigationIntentFromMessage(
        RemoteMessage(
          data: const <String, dynamic>{'event_type': 'driver_accepted'},
        ),
      ),
      isNull,
    );
  });

  testWidgets('foreground message dispatches parsed navigation intent', (
    tester,
  ) async {
    final source = _FakePushMessageSource();
    addTearDown(source.dispose);
    PassengerPushNavigationIntent? received;

    await tester.pumpWidget(
      MaterialApp(
        home: FirebaseForegroundPushListener(
          messageSource: source,
          onNavigationIntent: (intent) async {
            received = intent;
          },
          child: const Scaffold(body: Text('Passenger')),
        ),
      ),
    );

    source.foreground.add(message());
    await tester.pump();
    await tester.pump();

    expect(received?.eventType, 'driver_accepted');
    expect(received?.tripReference, 'TRIP-PUSH-001');
  });

  testWidgets('background notification tap dispatches navigation intent', (
    tester,
  ) async {
    final source = _FakePushMessageSource();
    addTearDown(source.dispose);
    PassengerPushNavigationIntent? received;

    await tester.pumpWidget(
      MaterialApp(
        home: FirebaseForegroundPushListener(
          messageSource: source,
          onNavigationIntent: (intent) async {
            received = intent;
          },
          child: const Scaffold(body: Text('Passenger')),
        ),
      ),
    );

    source.opened.add(message(eventType: 'arrived_at_pickup'));
    await tester.pump();
    await tester.pump();

    expect(received?.eventType, 'arrived_at_pickup');
    expect(received?.tripReference, 'TRIP-PUSH-001');
  });

  testWidgets('terminated initial message dispatches navigation intent', (
    tester,
  ) async {
    final source = _FakePushMessageSource(
      initialMessage: message(eventType: 'completed_confirmed'),
    );
    addTearDown(source.dispose);
    PassengerPushNavigationIntent? received;

    await tester.pumpWidget(
      MaterialApp(
        home: FirebaseForegroundPushListener(
          messageSource: source,
          onNavigationIntent: (intent) async {
            received = intent;
          },
          child: const Scaffold(body: Text('Passenger')),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(received?.eventType, 'completed_confirmed');
    expect(received?.tripReference, 'TRIP-PUSH-001');
  });
}

final class _FakePushMessageSource implements PassengerPushMessageSource {
  _FakePushMessageSource({this.initialMessage});

  final RemoteMessage? initialMessage;
  final StreamController<RemoteMessage> foreground =
      StreamController<RemoteMessage>.broadcast();
  final StreamController<RemoteMessage> opened =
      StreamController<RemoteMessage>.broadcast();

  @override
  Stream<RemoteMessage> get foregroundMessages => foreground.stream;

  @override
  Stream<RemoteMessage> get openedMessages => opened.stream;

  @override
  Future<RemoteMessage?> getInitialMessage() async => initialMessage;

  Future<void> dispose() async {
    await foreground.close();
    await opened.close();
  }
}
