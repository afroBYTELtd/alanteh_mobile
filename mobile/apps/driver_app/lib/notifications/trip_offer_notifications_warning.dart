import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';

import 'trip_offer_channel.dart';

/// "Notifications are off" banner for a driver on duty. Checks when shown
/// (app start on duty, going online) and whenever the app comes back.
class TripOfferNotificationsWarning extends StatefulWidget {
  const TripOfferNotificationsWarning({
    this.readState = readTripOfferNotificationState,
    this.openSettings = openTripOfferNotificationSettings,
    super.key,
  });

  final Future<TripOfferNotificationState> Function() readState;
  final Future<void> Function(TripOfferNotificationState state) openSettings;

  @override
  State<TripOfferNotificationsWarning> createState() =>
      _TripOfferNotificationsWarningState();
}

class _TripOfferNotificationsWarningState
    extends State<TripOfferNotificationsWarning> {
  TripOfferNotificationState _state = TripOfferNotificationState.unknown;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        if (state == AppLifecycleState.resumed) {
          _check();
        }
      },
    );
    _check();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    final TripOfferNotificationState state;
    try {
      state = await widget.readState();
    } on Object {
      return;
    }
    if (mounted && state != _state) {
      setState(() => _state = state);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_state == TripOfferNotificationState.ok ||
        _state == TripOfferNotificationState.unknown) {
      return const SizedBox.shrink();
    }
    return Container(
      key: const Key('trip-offer-notifications-off'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: AsmSpacing.space16),
      padding: const EdgeInsets.all(AsmSpacing.space16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4D6),
        borderRadius: BorderRadius.circular(AsmRadii.radius16),
        border: Border.all(color: const Color(0xFFE0B64A)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.notifications_off_outlined,
            color: Color(0xFF6B4E00),
          ),
          const SizedBox(width: AsmSpacing.space12),
          const Expanded(
            child: Text(
              'Notifications are off. You will miss trip offers when the app '
              'is closed.',
              style: TextStyle(
                color: Color(0xFF6B4E00),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          TextButton(
            key: const Key('trip-offer-notifications-turn-on'),
            onPressed: () => widget.openSettings(_state),
            child: const Text('Turn on'),
          ),
        ],
      ),
    );
  }
}
