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

/// Whether trip offers can reach the driver when the app is closed.
enum TripOfferNotificationState {
  /// App notifications on, and the offers channel at high importance.
  ok,

  /// The app's notifications are off (on Android 13+, the permission).
  appNotificationsOff,

  /// The offers channel was lowered below high, blocked, or is missing.
  channelLowered,

  /// Could not tell (not Android, or the check failed): no warning.
  unknown,
}

/// Reads the app's notification switch and the offers channel's importance.
Future<TripOfferNotificationState> readTripOfferNotificationState() async {
  final Map<Object?, Object?>? state;
  try {
    state = await _channels.invokeMethod<Map<Object?, Object?>>(
      'channelState',
      <String, String>{'id': tripOfferChannelId},
    );
  } on MissingPluginException {
    return TripOfferNotificationState.unknown;
  } on PlatformException {
    return TripOfferNotificationState.unknown;
  }
  if (state == null) {
    return TripOfferNotificationState.unknown;
  }
  if (state['appEnabled'] == false) {
    return TripOfferNotificationState.appNotificationsOff;
  }
  // Before Android 8 there are no channels; the app switch is all there is.
  if (state['channels'] == false) {
    return TripOfferNotificationState.ok;
  }
  final importance = state['channelImportance'];
  // NotificationManager.IMPORTANCE_HIGH is 4; a missing channel is null.
  if (importance is! int || importance < 4) {
    return TripOfferNotificationState.channelLowered;
  }
  return TripOfferNotificationState.ok;
}

/// Opens the settings page that fixes [state]: the offers channel's page,
/// or the app's notification page when the app's notifications are off.
Future<void> openTripOfferNotificationSettings(
  TripOfferNotificationState state,
) async {
  try {
    await _channels.invokeMethod<bool>('openChannelSettings', <String, Object>{
      'id': tripOfferChannelId,
      'appLevel': state == TripOfferNotificationState.appNotificationsOff,
    });
  } on MissingPluginException {
    // Not Android.
  } on PlatformException catch (error) {
    debugPrint('Notification settings not opened: ${error.code}');
  }
}
