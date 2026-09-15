import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

final class PassengerPushNavigationIntent {
  const PassengerPushNavigationIntent({
    required this.eventType,
    required this.tripReference,
  });

  final String eventType;
  final String tripReference;
}

PassengerPushNavigationIntent? passengerPushNavigationIntentFromMessage(
  RemoteMessage message,
) {
  final eventType = _requiredPushDataString(message.data, 'event_type');
  final tripReference = _requiredPushDataString(message.data, 'trip_reference');

  if (eventType == null || tripReference == null) {
    return null;
  }

  return PassengerPushNavigationIntent(
    eventType: eventType,
    tripReference: tripReference,
  );
}

String? _requiredPushDataString(Map<String, dynamic> data, String key) {
  final value = data[key];
  if (value is! String) {
    return null;
  }

  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}

abstract interface class PassengerPushMessageSource {
  Stream<RemoteMessage> get foregroundMessages;

  Stream<RemoteMessage> get openedMessages;

  Future<RemoteMessage?> getInitialMessage();
}

final class FirebasePassengerPushMessageSource
    implements PassengerPushMessageSource {
  const FirebasePassengerPushMessageSource();

  @override
  Stream<RemoteMessage> get foregroundMessages => FirebaseMessaging.onMessage;

  @override
  Stream<RemoteMessage> get openedMessages =>
      FirebaseMessaging.onMessageOpenedApp;

  @override
  Future<RemoteMessage?> getInitialMessage() {
    return FirebaseMessaging.instance.getInitialMessage();
  }
}

class FirebaseForegroundPushListener extends StatefulWidget {
  const FirebaseForegroundPushListener({
    required this.child,
    this.onNavigationIntent,
    this.messageSource,
    super.key,
  });

  final Widget child;
  final Future<void> Function(PassengerPushNavigationIntent intent)?
  onNavigationIntent;
  final PassengerPushMessageSource? messageSource;

  @override
  State<FirebaseForegroundPushListener> createState() =>
      _FirebaseForegroundPushListenerState();
}

class _FirebaseForegroundPushListenerState
    extends State<FirebaseForegroundPushListener> {
  late final PassengerPushMessageSource _messageSource;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _openedSubscription;

  @override
  void initState() {
    super.initState();
    _messageSource =
        widget.messageSource ?? const FirebasePassengerPushMessageSource();
    _foregroundSubscription = _messageSource.foregroundMessages.listen(
      _handleForegroundMessage,
    );
    _openedSubscription = _messageSource.openedMessages.listen(
      _handleNavigationMessage,
    );
    unawaited(_handleInitialMessage());
  }

  Future<void> _handleInitialMessage() async {
    final message = await _messageSource.getInitialMessage();
    if (message == null || !mounted) {
      return;
    }

    _handleNavigationMessage(message);
  }

  void _handleForegroundMessage(RemoteMessage message) {
    _handleNavigationMessage(message);

    final notification = message.notification;
    final title = notification?.title?.trim();
    final body = notification?.body?.trim();

    final parts = <String>[
      if (title != null && title.isNotEmpty) title,
      if (body != null && body.isNotEmpty) body,
    ];

    if (parts.isEmpty || !mounted) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null) {
        return;
      }

      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(parts.join('\n'))));
    });
  }

  void _handleNavigationMessage(RemoteMessage message) {
    final intent = passengerPushNavigationIntentFromMessage(message);
    final handler = widget.onNavigationIntent;

    if (intent == null || handler == null || !mounted) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      unawaited(handler(intent));
    });
  }

  @override
  void dispose() {
    _foregroundSubscription?.cancel();
    _openedSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
