import 'package:driver_app/notifications/trip_offer_channel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// Trip offer pushes name the Android channel trip_offers_v1 (backend
// TRIP_OFFER_CHANNEL_ID). The app creates it with high importance, so an
// offer shows as a banner, before Firebase can hand the app any push.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const platform = MethodChannel('io.alanteh.driver/notification_channels');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(platform, null));

  test('creates the high-importance trip offers channel', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(platform, (call) async {
      calls.add(call);
      return null;
    });

    await ensureTripOfferChannel();

    expect(calls, hasLength(1));
    expect(calls.single.method, 'createChannel');
    expect(calls.single.arguments, {
      'id': 'trip_offers_v1',
      'name': 'Trip offers',
      'description': 'New trip requests. Each one is open for a short time.',
      'importance': 'high',
    });
  });

  test('a platform without the channel does not stop the app', () async {
    // No handler: as on iOS, where the channel does not exist.
    await expectLater(ensureTripOfferChannel(), completes);
  });

  test('a channel error does not stop the app', () async {
    messenger.setMockMethodCallHandler(platform, (call) async {
      throw PlatformException(code: 'failed');
    });

    await expectLater(ensureTripOfferChannel(), completes);
  });

  test('the channel exists before Firebase starts', () async {
    final order = <String>[];

    await prepareAndroidPush(
      createOfferChannel: () async => order.add('channel'),
      startFirebase: () async => order.add('firebase'),
    );

    expect(order, ['channel', 'firebase']);
  });
}
