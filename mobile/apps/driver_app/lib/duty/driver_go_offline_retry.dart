import 'dart:async';
import 'dart:math';

import 'package:asm_offline_queue/asm_offline_queue.dart';

import '../driver_duty_trips.dart';
import '../network/driver_trip_action_resilience.dart';

/// Waits between tries of a failed GO OFFLINE; after the last, it keeps
/// trying at the last one (sign-in build A3).
const driverGoOfflineRetryDelays = <Duration>[
  Duration(seconds: 5),
  Duration(seconds: 15),
  Duration(seconds: 30),
  Duration(seconds: 60),
];

const driverGoOfflineQueueReference = 'driver-go-offline';

/// A failed GO OFFLINE (the lead's addendum to A3): kept in the app's
/// queue, tagged with the signed-in driver, and retried until the server
/// confirms, also after the app restarts. Going online cancels it. Only
/// the signed-in driver's is ever sent; the 7-day housekeeping clears old
/// ones.
final class DriverGoOfflineRetry {
  DriverGoOfflineRetry({
    required this.queue,
    required this.driverTag,
    Future<void> Function(Duration delay)? wait,
  }) : _wait = wait ?? ((delay) => Future<void>.delayed(delay));

  final DriverTripActionPersistentQueue queue;
  final Future<String?> Function() driverTag;
  final Future<void> Function(Duration delay) _wait;

  bool _stopped = false;
  Future<void>? _running;

  static String _id(String tag) => 'driver-go-offline:$tag';

  Future<String?> _tag() async {
    try {
      return await driverTag();
    } on Object {
      return null;
    }
  }

  /// Keeps a GO OFFLINE to send (one per driver).
  Future<void> remember() async {
    final tag = await _tag();
    if (tag == null) {
      return;
    }
    await queue.enqueue(
      QueuedEvent(
        id: _id(tag),
        eventType: driverDutyStatusPath,
        tripReference: driverGoOfflineQueueReference,
        driverId: tag,
        payloadJson: const <String, Object?>{'status': 'offline'},
        idempotencyKey: 'DRIVER-GO-OFFLINE-$tag',
        deviceTimestamp: DateTime.now(),
      ),
    );
  }

  /// A kept GO OFFLINE for the signed-in driver that is still to send (a
  /// queue that cannot delete marks a cancelled one failed for good).
  Future<bool> isPending() async {
    final tag = await _tag();
    if (tag == null) {
      return false;
    }
    final event = await queue.eventById(_id(tag));
    return event != null &&
        event.syncStatus != QueueSyncStatus.permanentlyFailed &&
        event.syncStatus != QueueSyncStatus.synced;
  }

  /// The driver went online: no more tries, and the record goes.
  Future<void> cancel() => _forget();

  /// The screen went away: tries stop, the record stays for next time.
  void stop() => _stopped = true;

  Future<void> _forget() async {
    final tag = await _tag();
    if (tag == null) {
      return;
    }
    final queue = this.queue;
    if (queue is DriverQueueCleanup) {
      await (queue as DriverQueueCleanup).removeWhere(
        (event) => event.id == _id(tag),
      );
    } else {
      await queue.markPermanentlyFailed(_id(tag));
    }
  }

  /// Sends the kept GO OFFLINE until the server confirms ([onLanded]), the
  /// session ends ([onSessionEnded]; the record goes), or it is cancelled.
  /// [waitFirst]: right after a failed try, wait the first delay before
  /// trying again. One run at a time.
  Future<void> runUntilLanded(
    DriverDutyStatusGateway gateway, {
    required void Function(DriverDutyTransition transition) onLanded,
    required void Function() onSessionEnded,
    bool waitFirst = false,
  }) {
    return _running ??= _run(
      gateway,
      onLanded: onLanded,
      onSessionEnded: onSessionEnded,
      waitFirst: waitFirst,
    ).whenComplete(() => _running = null);
  }

  Future<void> _run(
    DriverDutyStatusGateway gateway, {
    required void Function(DriverDutyTransition transition) onLanded,
    required void Function() onSessionEnded,
    required bool waitFirst,
  }) async {
    var attempt = 0;
    if (waitFirst) {
      await _wait(driverGoOfflineRetryDelays.first);
      attempt = 1;
    }
    while (!_stopped && await isPending()) {
      try {
        final transition = await gateway.updateDutyStatus(
          DriverOperationalDutyStatus.offline,
        );
        await _forget();
        onLanded(transition);
        return;
      } on DriverDutyApiException catch (error) {
        if (error.isSessionExpired) {
          await _forget();
          onSessionEnded();
          return;
        }
      } on Object {
        // Not confirmed: try again.
      }
      final delays = driverGoOfflineRetryDelays;
      await _wait(delays[min(attempt, delays.length - 1)]);
      attempt += 1;
    }
  }
}
