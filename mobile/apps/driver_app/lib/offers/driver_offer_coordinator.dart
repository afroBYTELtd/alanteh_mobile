import 'dart:async';

import 'driver_pending_offer_store.dart';

typedef DriverPeriodicTimerFactory =
    Timer Function(Duration interval, void Function(Timer timer) onTick);

/// A push tap that arrived before the driver was signed in.
final class DriverQueuedOfferTap {
  const DriverQueuedOfferTap({
    required this.tripReference,
    required this.queuedAt,
  });

  final String tripReference;

  /// The monotonic clock's reading when the tap arrived.
  final Duration queuedAt;
}

/// Owns the pending-offer store for one app run: when to fetch, the push tap
/// that arrived before sign-in, and forgetting everything when the session
/// changes.
///
/// Fetches on start, on resume, on any offer push, and every
/// [DriverOfferCardTiming.pollInterval] while the driver is on duty with the
/// app in front and no offer card open.
final class DriverOfferCoordinator {
  DriverOfferCoordinator({
    required this.store,
    this.identity,
    DriverPeriodicTimerFactory? periodicTimer,
  }) : _periodicTimer = periodicTimer ?? Timer.periodic;

  final DriverPendingOfferStore store;
  final DriverIdentityCachingDutyGateway? identity;
  final DriverPeriodicTimerFactory _periodicTimer;

  bool _onDuty = false;
  bool _foreground = true;
  int _openCards = 0;
  Timer? _timer;
  DriverQueuedOfferTap? _queuedTap;

  /// True while the poll timer is running.
  bool get polling => _timer?.isActive ?? false;

  bool get _shouldPoll => _onDuty && _foreground && _openCards == 0;

  /// The shell reports duty after every duty change.
  void setOnDuty(bool onDuty) {
    if (_onDuty == onDuty) {
      return;
    }
    _onDuty = onDuty;
    _reschedule(fetchNow: onDuty);
  }

  /// The app reports going to the background and coming back.
  void setForeground(bool foreground) {
    if (_foreground == foreground) {
      return;
    }
    _foreground = foreground;
    _reschedule(fetchNow: foreground);
  }

  /// An offer card opened or closed (the poll pauses while one is open).
  void cardOpened() {
    _openCards += 1;
    _reschedule(fetchNow: false);
  }

  void cardClosed() {
    if (_openCards > 0) {
      _openCards -= 1;
    }
    _reschedule(fetchNow: false);
  }

  /// Fetches, then says whether a pushed or tapped offer opens its card. A
  /// list the fetch brings decides. If the fetch fails, or takes longer than
  /// [DriverOfferCardTiming.staleListWait], the list held before decides, as
  /// it always did: an automatic offer lives 45 s, so a card dropped for a
  /// slow network is a lost ride. With nothing held to open from, it waits
  /// for the fetch to finish.
  Future<bool> fetchThenCanOpen(String tripReference) async {
    var fetched = false;
    final fetch = store.refresh().whenComplete(() => fetched = true);
    await fetch.timeout(DriverOfferCardTiming.staleListWait, onTimeout: () {});
    if (!fetched && store.offerFor(tripReference) == null) {
      await fetch;
    }
    return store.offerFor(tripReference) != null;
  }

  /// An offer push arrived.
  Future<void> offerPushed() => store.refresh();

  void _reschedule({required bool fetchNow}) {
    if (!_shouldPoll) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    if (fetchNow) {
      unawaited(store.refresh());
    }
    if (_timer?.isActive ?? false) {
      return;
    }
    _timer = _periodicTimer(
      DriverOfferCardTiming.pollInterval,
      (_) => unawaited(store.refresh()),
    );
  }

  /// Remember a push tap that arrived before sign-in.
  void queueTap(String tripReference) {
    _queuedTap = DriverQueuedOfferTap(
      tripReference: tripReference.trim(),
      queuedAt: store.clock.now,
    );
  }

  /// The queued tap if it is younger than
  /// [DriverOfferCardTiming.coldStartTapLifetime]; it is removed either way.
  DriverQueuedOfferTap? takeTap() {
    final tap = _queuedTap;
    _queuedTap = null;
    if (tap == null ||
        store.clock.now - tap.queuedAt >
            DriverOfferCardTiming.coldStartTapLifetime) {
      return null;
    }
    return tap;
  }

  /// Sign-out, session end or a different driver.
  void clear() {
    _queuedTap = null;
    identity?.clear();
    store.clear();
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
