import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

final class DriverPushNavigationIntent {
  const DriverPushNavigationIntent({
    required this.eventType,
    required this.tripReference,
  });

  final String eventType;
  final String tripReference;
}

DriverPushNavigationIntent? driverPushNavigationIntentFromMessage(
  RemoteMessage message,
) {
  final eventType = _requiredPushDataString(message.data, 'event_type');
  final tripReference = _requiredPushDataString(message.data, 'trip_reference');

  if (eventType == null ||
      eventType != 'driver_assigned' ||
      tripReference == null) {
    return null;
  }

  return DriverPushNavigationIntent(
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

abstract interface class DriverPushMessageSource {
  Stream<RemoteMessage> get foregroundMessages;
  Stream<RemoteMessage> get openedMessages;
  Future<RemoteMessage?> getInitialMessage();
}

final class FirebaseDriverPushMessageSource implements DriverPushMessageSource {
  const FirebaseDriverPushMessageSource();

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
    this.onForegroundIntent,
    this.foregroundEnabled = true,
    this.messageSource,
    super.key,
  });

  final Widget child;
  final Future<void> Function(DriverPushNavigationIntent intent)?
  onNavigationIntent;

  /// An offer push while the app is open. Returns true when it was shown
  /// (for example as the offer card); otherwise the text snackbar appears,
  /// with an "Open" action.
  final Future<bool> Function(DriverPushNavigationIntent intent)?
  onForegroundIntent;

  /// False while signed out: foreground messages are not shown.
  final bool foregroundEnabled;
  final DriverPushMessageSource? messageSource;

  @override
  State<FirebaseForegroundPushListener> createState() =>
      _FirebaseForegroundPushListenerState();
}

class _FirebaseForegroundPushListenerState
    extends State<FirebaseForegroundPushListener> {
  late final DriverPushMessageSource _messageSource;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _openedSubscription;

  @override
  void initState() {
    super.initState();
    _messageSource =
        widget.messageSource ?? const FirebaseDriverPushMessageSource();

    _foregroundSubscription = _messageSource.foregroundMessages.listen(
      _handleForegroundMessage,
    );

    _openedSubscription = _messageSource.openedMessages.listen(
      _handleOpenedMessage,
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

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    if (!widget.foregroundEnabled) {
      return;
    }
    final intent = driverPushNavigationIntentFromMessage(message);
    final onForeground = widget.onForegroundIntent;
    if (intent != null && onForeground != null) {
      final shown = await onForeground(intent);
      if (shown || !mounted) {
        return;
      }
    }
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

      final open = widget.onNavigationIntent;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(parts.join('\n')),
            action: intent != null && open != null
                ? SnackBarAction(
                    key: const Key('push-snackbar-open'),
                    label: 'Open',
                    onPressed: () => unawaited(open(intent)),
                  )
                : null,
          ),
        );
    });
  }

  void _handleOpenedMessage(RemoteMessage message) {
    final intent = driverPushNavigationIntentFromMessage(message);
    final handler = widget.onNavigationIntent;

    if (intent == null || handler == null || !mounted) {
      return;
    }

    unawaited(handler(intent));
  }

  void _handleNavigationMessage(RemoteMessage message) {
    final intent = driverPushNavigationIntentFromMessage(message);
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
