import 'dart:async';

import 'package:flutter/foundation.dart';

import '../driver_reload_signal.dart';
import '../notifications/push_notification_runtime.dart';
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

/// Writes one diagnostic line; [debugPrint] in the app.
typedef DriverOfferFetchLog = void Function(String line);

/// Why the coordinator fetched the pending offers, as the diagnostic line
/// names it. Going on duty counts as a poll: it starts the poll.
enum DriverOfferFetchReason {
  poll('poll'),
  pushAssigned('push_assigned'),
  pushCancelled('push_cancelled'),
  resume('resume'),
  cardOpen('card_open');

  const DriverOfferFetchReason(this.logName);

  final String logName;
}

/// Owns the pending-offer store for one app run: when to fetch, the push tap
/// that arrived before sign-in, and forgetting everything when the session
/// changes.
///
/// Fetches on start, on resume, on any offer or cancel push, and while the
/// driver is on duty with the app in front: every
/// [DriverOfferCardTiming.pollInterval], or every
/// [DriverOfferCardTiming.openCardPollInterval] while an offer card is open.
/// Each fetch it starts writes one line: `OFFER_FETCH reason=… offers=N
/// changed=…`, with no trip reference, name or phone number.
final class DriverOfferCoordinator {
  DriverOfferCoordinator({
    required this.store,
    this.identity,
    DriverPeriodicTimerFactory? periodicTimer,
    DriverOfferFetchLog? log,
  }) : _periodicTimer = periodicTimer ?? Timer.periodic,
       _log = log ?? debugPrint {
    _lastOfferSet = _offerSet();
    store.addListener(_storeChanged);
  }

  final DriverPendingOfferStore store;
  final DriverIdentityCachingDutyGateway? identity;
  final DriverPeriodicTimerFactory _periodicTimer;
  final DriverOfferFetchLog _log;

  bool _onDuty = false;
  bool _foreground = true;
  int _openCards = 0;
  Timer? _timer;
  Duration? _timerInterval;
  DriverQueuedOfferTap? _queuedTap;

  final _offerSetChanged = DriverReloadSignal();
  Set<DriverOfferIdentity> _lastOfferSet = const {};

  /// Pinged when the pending offers change, whatever the cause: a new
  /// offer, one answered, expired, cancelled or taken back.
  Listenable get offerSetChanged => _offerSetChanged;

  /// True while the poll timer is running.
  bool get polling => _timer?.isActive ?? false;

  /// How often the running poll fetches; null while it is stopped.
  Duration? get pollInterval => polling ? _timerInterval : null;

  bool get _shouldPoll => _onDuty && _foreground;

  /// The shell reports duty after every duty change.
  void setOnDuty(bool onDuty) {
    if (_onDuty == onDuty) {
      return;
    }
    _onDuty = onDuty;
    _reschedule(fetchNow: onDuty ? DriverOfferFetchReason.poll : null);
  }

  /// The app reports going to the background and coming back. Back in
  /// front it fetches at once, card open or not: an offer may have ended
  /// while the app was away.
  void setForeground(bool foreground) {
    if (_foreground == foreground) {
      return;
    }
    _foreground = foreground;
    _reschedule(fetchNow: foreground ? DriverOfferFetchReason.resume : null);
  }

  /// An offer card opened or closed (the poll slows while one is open).
  void cardOpened() {
    _openCards += 1;
    _reschedule();
  }

  void cardClosed() {
    if (_openCards > 0) {
      _openCards -= 1;
    }
    _reschedule();
  }

  /// Fetches, then says whether a pushed or tapped offer opens its card. A
  /// list the fetch brings decides. If the fetch fails, or takes longer than
  /// [DriverOfferCardTiming.staleListWait], the list held before decides, as
  /// it always did: an automatic offer lives 45 s, so a card dropped for a
  /// slow network is a lost ride. With nothing held to open from, it waits
  /// for the fetch to finish.
  Future<bool> fetchThenCanOpen(
    String tripReference, {
    DriverOfferFetchReason reason = DriverOfferFetchReason.cardOpen,
  }) async {
    var fetched = false;
    final fetch = _fetch(reason).whenComplete(() => fetched = true);
    await fetch.timeout(DriverOfferCardTiming.staleListWait, onTimeout: () {});
    if (!fetched && store.offerFor(tripReference) == null) {
      await fetch;
    }
    return store.offerFor(tripReference) != null;
  }

  /// An offer push arrived.
  Future<void> offerPushed() => _fetch(DriverOfferFetchReason.pushAssigned);

  /// A trip push arrived with the app in front. A cancel fetches at once,
  /// so an open card for that offer ends; an offer push is fetched by the
  /// card it opens ([fetchThenCanOpen]), so it is not fetched twice.
  void tripPushed(String eventType) {
    if (driverTripCancelledPushTypes.contains(eventType)) {
      unawaited(_fetch(DriverOfferFetchReason.pushCancelled));
    }
  }

  Future<void> _fetch(DriverOfferFetchReason reason) {
    final before = _offerSet();
    return store.refresh().whenComplete(() {
      final after = _offerSet();
      _log(
        'OFFER_FETCH reason=${reason.logName} offers=${after.length} '
        'changed=${!setEquals(before, after)}',
      );
    });
  }

  Set<DriverOfferIdentity> _offerSet() => {
    for (final offer in store.offers) DriverOfferIdentity.of(offer),
  };

  void _storeChanged() {
    final current = _offerSet();
    if (setEquals(current, _lastOfferSet)) {
      return;
    }
    _lastOfferSet = current;
    _offerSetChanged.ping();
  }

  void _reschedule({DriverOfferFetchReason? fetchNow}) {
    if (!_shouldPoll) {
      _timer?.cancel();
      _timer = null;
      _timerInterval = null;
      return;
    }
    if (fetchNow != null) {
      unawaited(_fetch(fetchNow));
    }
    final interval = _openCards == 0
        ? DriverOfferCardTiming.pollInterval
        : DriverOfferCardTiming.openCardPollInterval;
    if ((_timer?.isActive ?? false) && _timerInterval == interval) {
      return;
    }
    _timer?.cancel();
    _timerInterval = interval;
    _timer = _periodicTimer(
      interval,
      (_) => unawaited(_fetch(DriverOfferFetchReason.poll)),
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
