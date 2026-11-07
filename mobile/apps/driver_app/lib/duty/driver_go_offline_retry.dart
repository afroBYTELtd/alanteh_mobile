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

  /// Each run, and each stop, takes a new number; a run whose number is no
  /// longer current ends at its next step. Nothing here is permanent: the
  /// next run (a new Work after sign-in) works again (lead, 7 Nov).
  int _generation = 0;
  Completer<void> _interrupt = Completer<void>();
  Future<void>? _running;

  /// The newest Work's callbacks: a run that lands after a new Work started
  /// tells that Work, not the one that went away.
  void Function(DriverDutyTransition transition)? _onLanded;
  void Function()? _onSessionEnded;

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

  /// Work went away: the current run ends at its next step (a wait is cut
  /// short), its callbacks are dropped, and the record stays for the next
  /// run.
  void stop() {
    _generation += 1;
    // Nothing may call back into the Work that went away; a newer run
    // brings its own Work's callbacks.
    _onLanded = null;
    _onSessionEnded = null;
    _interruptWaits();
  }

  void _interruptWaits() {
    final interrupt = _interrupt;
    _interrupt = Completer<void>();
    if (!interrupt.isCompleted) {
      interrupt.complete();
    }
  }

  Future<void> _waitOrInterrupt(Duration delay) {
    final interrupted = _interrupt.future;
    return Future.any(<Future<void>>[_wait(delay), interrupted]);
  }

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
  /// trying again. A new run ends the older one (its wait is cut short) and
  /// starts only when the older one has ended, so two requests never go
  /// side by side.
  Future<void> runUntilLanded(
    DriverDutyStatusGateway gateway, {
    required void Function(DriverDutyTransition transition) onLanded,
    required void Function() onSessionEnded,
    bool waitFirst = false,
  }) {
    _onLanded = onLanded;
    _onSessionEnded = onSessionEnded;
    _generation += 1;
    final generation = _generation;
    _interruptWaits();
    final previous = _running ?? Future<void>.value();
    final run = previous.then(
      (_) => _run(gateway, generation: generation, waitFirst: waitFirst),
    );
    _running = run;
    unawaited(
      run.whenComplete(() {
        if (identical(_running, run)) {
          _running = null;
        }
      }),
    );
    return run;
  }

  Future<void> _run(
    DriverDutyStatusGateway gateway, {
    required int generation,
    required bool waitFirst,
  }) async {
    bool current() => generation == _generation;
    var attempt = 0;
    if (waitFirst) {
      await _waitOrInterrupt(driverGoOfflineRetryDelays.first);
      attempt = 1;
    }
    while (current() && await isPending()) {
      try {
        final transition = await gateway.updateDutyStatus(
          DriverOperationalDutyStatus.offline,
        );
        await _forget();
        _onLanded?.call(transition);
        return;
      } on DriverDutyApiException catch (error) {
        if (error.isSessionExpired) {
          await _forget();
          _onSessionEnded?.call();
          return;
        }
      } on Object {
        // Not confirmed: try again.
      }
      if (!current()) {
        return;
      }
      final delays = driverGoOfflineRetryDelays;
      await _waitOrInterrupt(delays[min(attempt, delays.length - 1)]);
      attempt += 1;
    }
  }
}
