import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The Android channel trip offer pushes name (backend
/// TRIP_OFFER_CHANNEL_ID). A new id, because Android never lets an app
/// raise an existing channel's importance.
const tripOfferChannelId = 'trip_offers_v1';

const _channels = MethodChannel('io.alanteh.driver/notification_channels');

/// Creates the trip offers channel with high importance, so an offer shows
/// as a banner. Creating it again changes nothing. Never throws: without it
/// (iOS, or a failure) pushes still arrive on the default channel.
Future<void> ensureTripOfferChannel() async {
  try {
    await _channels.invokeMethod<void>('createChannel', <String, String>{
      'id': tripOfferChannelId,
      'name': 'Trip offers',
      'description': 'New trip requests. Each one is open for a short time.',
      'importance': 'high',
    });
  } on MissingPluginException {
    // No such channel on this platform.
  } on PlatformException catch (error) {
    debugPrint('Trip offers channel not created: ${error.code}');
  }
}

/// Android start-up for pushes: the offer channel exists before Firebase
/// starts, so no push can arrive before it.
Future<void> prepareAndroidPush({
  required Future<void> Function() createOfferChannel,
  required Future<void> Function() startFirebase,
}) async {
  await createOfferChannel();
  await startFirebase();
}
