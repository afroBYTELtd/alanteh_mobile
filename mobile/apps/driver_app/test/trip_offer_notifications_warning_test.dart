import 'package:driver_app/notifications/trip_offer_channel.dart';
import 'package:driver_app/notifications/trip_offer_notifications_warning.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _channel = MethodChannel('io.alanteh.driver/notification_channels');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('reading the state from Android', () {
    final calls = <MethodCall>[];

    void answer(Object? Function(MethodCall call) reply) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async {
            calls.add(call);
            return reply(call);
          });
    }

    tearDown(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, null);
    });

    test('app on and channel at high importance: ok', () async {
      answer((_) => {'appEnabled': true, 'channelImportance': 4});
      expect(
        await readTripOfferNotificationState(),
        TripOfferNotificationState.ok,
      );
      expect(calls.single.method, 'channelState');
      expect(calls.single.arguments, {'id': 'trip_offers_v1'});
    });

    test('app notifications off', () async {
      answer((_) => {'appEnabled': false, 'channelImportance': 4});
      expect(
        await readTripOfferNotificationState(),
        TripOfferNotificationState.appNotificationsOff,
      );
    });

    test('channel lowered to default, or blocked', () async {
      for (final importance in [3, 0]) {
        answer((_) => {'appEnabled': true, 'channelImportance': importance});
        expect(
          await readTripOfferNotificationState(),
          TripOfferNotificationState.channelLowered,
        );
      }
    });

    test('channel missing on Android 8+ counts as lowered', () async {
      answer(
        (_) => {
          'appEnabled': true,
          'channelImportance': null,
          'channels': true,
        },
      );
      expect(
        await readTripOfferNotificationState(),
        TripOfferNotificationState.channelLowered,
      );
    });

    test(
      'before Android 8 (no channels): only the app switch counts',
      () async {
        answer(
          (_) => {
            'appEnabled': true,
            'channelImportance': null,
            'channels': false,
          },
        );
        expect(
          await readTripOfferNotificationState(),
          TripOfferNotificationState.ok,
        );
      },
    );

    test('no handler (not Android) or an error: unknown, no warning', () async {
      expect(
        await readTripOfferNotificationState(),
        TripOfferNotificationState.unknown,
      );
      answer((_) => throw PlatformException(code: 'boom'));
      expect(
        await readTripOfferNotificationState(),
        TripOfferNotificationState.unknown,
      );
    });

    test(
      'Turn on opens the channel page, or the app page when the app is off',
      () async {
        answer((_) => true);
        await openTripOfferNotificationSettings(
          TripOfferNotificationState.channelLowered,
        );
        await openTripOfferNotificationSettings(
          TripOfferNotificationState.appNotificationsOff,
        );
        expect(calls.map((c) => c.method), [
          'openChannelSettings',
          'openChannelSettings',
        ]);
        expect(calls.first.arguments, {
          'id': 'trip_offers_v1',
          'appLevel': false,
        });
        expect(calls.last.arguments, {
          'id': 'trip_offers_v1',
          'appLevel': true,
        });
      },
    );
  });

  group('the banner', () {
    Future<List<TripOfferNotificationState>> pump(
      WidgetTester tester,
      List<TripOfferNotificationState> states,
    ) async {
      final opened = <TripOfferNotificationState>[];
      var index = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TripOfferNotificationsWarning(
              readState: () async =>
                  states[index < states.length ? index++ : states.length - 1],
              openSettings: (state) async => opened.add(state),
            ),
          ),
        ),
      );
      await tester.pump();
      return opened;
    }

    testWidgets(
      'shows when notifications are off, and Turn on opens settings',
      (tester) async {
        final opened = await pump(tester, [
          TripOfferNotificationState.appNotificationsOff,
        ]);
        expect(
          find.text(
            'Notifications are off. You will miss trip offers when the app '
            'is closed.',
          ),
          findsOneWidget,
        );
        await tester.tap(
          find.byKey(const Key('trip-offer-notifications-turn-on')),
        );
        await tester.pump();
        expect(opened, [TripOfferNotificationState.appNotificationsOff]);
      },
    );

    testWidgets('shows when the channel was lowered', (tester) async {
      await pump(tester, [TripOfferNotificationState.channelLowered]);
      expect(
        find.byKey(const Key('trip-offer-notifications-off')),
        findsOneWidget,
      );
    });

    testWidgets('hidden when all is well or unknown', (tester) async {
      await pump(tester, [TripOfferNotificationState.ok]);
      expect(
        find.byKey(const Key('trip-offer-notifications-off')),
        findsNothing,
      );
      await pump(tester, [TripOfferNotificationState.unknown]);
      expect(
        find.byKey(const Key('trip-offer-notifications-off')),
        findsNothing,
      );
    });

    testWidgets('checks again when the app comes back', (tester) async {
      await pump(tester, [
        TripOfferNotificationState.appNotificationsOff,
        TripOfferNotificationState.ok,
      ]);
      expect(
        find.byKey(const Key('trip-offer-notifications-off')),
        findsOneWidget,
      );

      // Away and back, through the states a phone really passes.
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pump();
      await tester.pump();
      expect(
        find.byKey(const Key('trip-offer-notifications-off')),
        findsNothing,
      );
    });
  });
}
