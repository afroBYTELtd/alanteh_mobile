import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

class FirebaseForegroundPushListener extends StatefulWidget {
  const FirebaseForegroundPushListener({required this.child, super.key});

  final Widget child;

  @override
  State<FirebaseForegroundPushListener> createState() =>
      _FirebaseForegroundPushListenerState();
}

class _FirebaseForegroundPushListenerState
    extends State<FirebaseForegroundPushListener> {
  StreamSubscription<RemoteMessage>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = FirebaseMessaging.onMessage.listen(_handleMessage);
  }

  void _handleMessage(RemoteMessage message) {
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

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
