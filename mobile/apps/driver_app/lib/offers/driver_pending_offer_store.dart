import 'dart:async';

import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_auth/asm_auth.dart';
import 'package:flutter/foundation.dart';

import '../driver_duty_trips.dart';
import '../network/driver_trip_action_gateway.dart';
import 'driver_pending_offers.dart';

const driverPendingOffersPath = '/api/driver/trips/pending/';

/// Timings for the pending-offers card. An automatic offer lasts 45 s, so
/// none of these may use up the window the way the general 15 s / four
/// attempt policy does.
abstract final class DriverOfferCardTiming {
  /// How long a fetched list of pending offers counts as current: one poll
  /// ([pollInterval]) plus a slow answer. An older list may still show, but
  /// nothing new is prepared or opened from it.
  static const listingFreshFor = Duration(seconds: 20);

  /// How long a pushed or tapped offer, or a card shown from an old list,
  /// waits for a fetch before it goes ahead with the list it has.
  static const staleListWait = Duration(seconds: 5);

  /// Offer fetch: one try of at most 5 s, and one more after 1 s.
  static const fetchConnectTimeout = Duration(seconds: 4);
  static const fetchRequestTimeout = Duration(seconds: 5);
  static const fetchRetryBackoffs = <Duration>[Duration(seconds: 1)];

  /// Accept and decline: at most three tries of 6 s, 1 s and 2 s apart
  /// (21 s worst case), all with the same idempotency key.
  static const responseConnectTimeout = Duration(seconds: 4);
  static const responseRequestTimeout = Duration(seconds: 6);
  static const responseRetryBackoffs = <Duration>[
    Duration(seconds: 1),
    Duration(seconds: 2),
  ];

  /// Without the pickup label, or not knowing whether the ride is for now
  /// or later, after this long the card says
  /// "Couldn't load trip details" (the countdown keeps running).
  static const detailsTimeout = Duration(seconds: 8);

  /// Foreground check while on duty.
  static const pollInterval = Duration(seconds: 12);

  /// An automatic offer's time ran out, but the check at zero can come a
  /// moment before the server expires it: ask again this long after zero.
  static const expiredRecheckDelay = Duration(seconds: 3);

  /// An automatic offer whose time ran out leaves the home screen this long
  /// after zero, even if the server still lists it as pending.
  static const expiredRemovalDelay = Duration(seconds: 5);

  /// A push tap that arrived before sign-in is dropped after this long.
  static const coldStartTapLifetime = Duration(minutes: 2);
}

/// The phone's monotonic clock: unaffected by the user changing the time.
abstract interface class DriverMonotonicClock {
  Duration get now;
}

final class StopwatchDriverMonotonicClock implements DriverMonotonicClock {
  StopwatchDriverMonotonicClock() : _stopwatch = Stopwatch()..start();

  final Stopwatch _stopwatch;

  @override
  Duration get now => _stopwatch.elapsed;
}

/// What one fetch came to.
sealed class DriverPendingOffersFetch {
  const DriverPendingOffersFetch();
}

final class DriverPendingOffersFetched extends DriverPendingOffersFetch {
  const DriverPendingOffersFetched(this.json);

  final Object? json;
}

/// No network, a timeout or a server error: nothing was judged.
final class DriverPendingOffersUnavailable extends DriverPendingOffersFetch {
  const DriverPendingOffersUnavailable();
}

/// The server refused the session and a refresh could not restore it.
final class DriverPendingOffersSessionExpired extends DriverPendingOffersFetch {
  const DriverPendingOffersSessionExpired();
}

abstract interface class DriverPendingOffersSource {
  Future<DriverPendingOffersFetch> fetch();
}

/// `GET /api/driver/trips/pending/` with the card's short timeouts. A 401
/// refreshes the session once through the driver's shared refresh, then
/// asks again.
final class ApiDriverPendingOffersSource implements DriverPendingOffersSource {
  ApiDriverPendingOffersSource({
    required this.client,
    this.refreshAccessToken,
    Future<void> Function(Duration duration)? delay,
  }) : _delay = delay ?? Future<void>.delayed;

  /// A client built with [DriverOfferCardTiming]'s fetch timeouts.
  final AsmApiClient client;
  final DriverAccessTokenRefresh? refreshAccessToken;
  final Future<void> Function(Duration duration) _delay;

  @override
  Future<DriverPendingOffersFetch> fetch() async {
    var response = await _getWithOneRetry();
    if (response.statusCode == 401) {
      final refresh = refreshAccessToken;
      if (refresh == null) {
        return const DriverPendingOffersSessionExpired();
      }
      final DriverTokenRefreshOutcome outcome;
      try {
        outcome = await refresh();
      } on Object {
        return const DriverPendingOffersUnavailable();
      }
      switch (outcome) {
        case DriverTokenRefreshOutcome.refreshed:
          response = await _getWithOneRetry();
        case DriverTokenRefreshOutcome.sessionExpired:
          return const DriverPendingOffersSessionExpired();
        case DriverTokenRefreshOutcome.temporarilyUnavailable:
          return const DriverPendingOffersUnavailable();
      }
      if (response.statusCode == 401) {
        return const DriverPendingOffersSessionExpired();
      }
    }
    if (response.isSuccess) {
      return DriverPendingOffersFetched(response.data);
    }
    return const DriverPendingOffersUnavailable();
  }

  Future<ApiResponse<Object?>> _getWithOneRetry() async {
    var attempt = 0;
    while (true) {
      final response = await client.get<Object?>(driverPendingOffersPath);
      if (attempt >= DriverOfferCardTiming.fetchRetryBackoffs.length ||
          !_transient(response)) {
        return response;
      }
      await _delay(DriverOfferCardTiming.fetchRetryBackoffs[attempt]);
      attempt += 1;
    }
  }

  static bool _transient(ApiResponse<Object?> response) {
    final type = response.error?.type;
    return type == AsmApiExceptionType.network ||
        type == AsmApiExceptionType.timeout ||
        type == AsmApiExceptionType.server ||
        const <int>{502, 503, 504}.contains(response.statusCode);
  }
}

/// One offer: a trip reference and when it was assigned. A re-offer of the
/// same trip is a different offer. [assignedAt] is null when the server did
/// not send it (an older server).
@immutable
final class DriverOfferIdentity {
  const DriverOfferIdentity(this.tripReference, [this.assignedAt]);

  DriverOfferIdentity.of(DriverPendingOffer offer)
    : this(offer.tripReference, offer.assignedAt);

  final String tripReference;
  final DateTime? assignedAt;

  @override
  bool operator ==(Object other) =>
      other is DriverOfferIdentity &&
      other.tripReference == tripReference &&
      other.assignedAt == assignedAt;

  @override
  int get hashCode => Object.hash(tripReference, assignedAt);
}

/// The latest pending offers, shared by the home screen, the push handler
/// and the offer card.
final class DriverPendingOfferStore extends ChangeNotifier {
  DriverPendingOfferStore({
    required this.source,
    DriverMonotonicClock? clock,
    this.onSessionExpired,
    DateTime Function()? wallClock,
  }) : clock = clock ?? StopwatchDriverMonotonicClock(),
       _wallClock = wallClock ?? DateTime.now;

  final DateTime Function() _wallClock;

  /// When the current list arrived, by the wall clock too: the monotonic
  /// clock stops while the phone sleeps, so after a long sleep it alone
  /// would call a half-hour-old list current.
  DateTime? _receivedAtWall;

  /// True while the list of pending offers came from the last fetch, and
  /// that fetch is at most [DriverOfferCardTiming.listingFreshFor] old.
  bool get isFresh {
    final current = _snapshot;
    final receivedAtWall = _receivedAtWall;
    if (current == null || receivedAtWall == null || _lastFetchFailed) {
      return false;
    }
    const limit = DriverOfferCardTiming.listingFreshFor;
    return clock.now - current.receivedAt <= limit &&
        _wallClock().difference(receivedAtWall) <= limit;
  }

  final DriverPendingOffersSource source;
  final DriverMonotonicClock clock;

  /// Called when a fetch finds the session ended.
  final Future<void> Function()? onSessionExpired;

  DriverPendingOffersSnapshot? _snapshot;
  bool _lastFetchFailed = false;
  Future<void>? _inFlight;

  /// Offers dropped locally, by trip reference and `assigned_at`: a re-offer
  /// of the same trip has a new `assigned_at` and is a new offer. Without an
  /// `assigned_at` (an older server) the whole trip is dropped, as before.
  final Set<DriverOfferIdentity> _forgotten = <DriverOfferIdentity>{};

  /// Bumped by [clear]; a fetch started under an older generation is ignored.
  int _generation = 0;

  DriverPendingOffersSnapshot? get snapshot => _snapshot;

  /// True after a fetch failed and before the next one succeeds.
  bool get lastFetchFailed => _lastFetchFailed;

  /// Fetch now. Callers that arrive while a fetch is running share it.
  Future<void> refresh() {
    return _inFlight ??= _fetch().whenComplete(() => _inFlight = null);
  }

  /// A fresh fetch that leaves after any fetch now running has finished
  /// (a caller that needs an answer newer than that one).
  Future<void> refreshAfterCurrent() {
    final running = _inFlight;
    return running == null ? refresh() : running.then((_) => refresh());
  }

  Future<void> _fetch() async {
    final generation = _generation;
    final started = clock.now;
    DriverPendingOffersFetch result;
    try {
      result = await source.fetch();
    } on Object {
      result = const DriverPendingOffersUnavailable();
    }
    if (generation != _generation) {
      return;
    }
    final arrived = clock.now;

    switch (result) {
      case DriverPendingOffersFetched(:final json):
        try {
          _snapshot = parseDriverPendingOffers(
            json,
            receivedAt: arrived,
            requestDuration: arrived - started,
          );
          _receivedAtWall = _wallClock();
          _forgotten.retainWhere((forgotten) {
            final listed = _snapshot!.offerFor(forgotten.tripReference);
            return listed != null &&
                (forgotten.assignedAt == null ||
                    forgotten.assignedAt == listed.assignedAt);
          });
          _lastFetchFailed = false;
        } on FormatException {
          _lastFetchFailed = true;
        }
      case DriverPendingOffersUnavailable():
        _lastFetchFailed = true;
      case DriverPendingOffersSessionExpired():
        clear();
        final handler = onSessionExpired;
        if (handler != null) {
          await handler();
        }
        return;
    }
    notifyListeners();
  }

  /// Time left on the offer, or null when it has no countdown or is gone.
  Duration? remaining(String tripReference) {
    final current = _snapshot;
    final offer = offerFor(tripReference);
    if (current == null || offer == null) {
      return null;
    }
    return current.remaining(offer, clock.now);
  }

  DriverPendingOffer? offerFor(String tripReference) {
    final offer = _snapshot?.offerFor(tripReference);
    return offer == null || _isForgotten(offer) ? null : offer;
  }

  /// The offers still to answer, earliest expiry first.
  List<DriverPendingOffer> get offers => <DriverPendingOffer>[
    for (final offer in _snapshot?.offers ?? const <DriverPendingOffer>[])
      if (!_isForgotten(offer)) offer,
  ];

  bool _isForgotten(DriverPendingOffer offer) =>
      _forgotten.contains(DriverOfferIdentity.of(offer)) ||
      _forgotten.contains(DriverOfferIdentity(offer.tripReference));

  /// The offer the card should show first: the earliest expiry.
  DriverPendingOffer? get firstOffer {
    final remainingOffers = offers;
    return remainingOffers.isEmpty ? null : remainingOffers.first;
  }

  /// Drop one offer locally after it was answered or ran out: the offer
  /// listed now for [tripReference], or the whole trip if none is listed.
  void forget(String tripReference) {
    final listed = _snapshot?.offerFor(tripReference);
    final identity = listed == null
        ? DriverOfferIdentity(tripReference.trim())
        : DriverOfferIdentity.of(listed);
    if (_forgotten.add(identity)) {
      notifyListeners();
    }
  }

  /// Drop exactly [identity] locally (a card dropping the offer it showed).
  void forgetOffer(DriverOfferIdentity identity) {
    if (_forgotten.add(identity)) {
      notifyListeners();
    }
  }

  /// Sign-out, session end or a different driver: forget everything, and
  /// ignore the answer of any fetch still running for the old session.
  void clear() {
    _generation += 1;
    _snapshot = null;
    _receivedAtWall = null;
    _lastFetchFailed = false;
    _forgotten.clear();
    _inFlight = null;
    notifyListeners();
  }
}

/// Remembers the driver reference and duty status from every duty fetch the
/// app already makes, so an offer never waits for a profile fetch. Duty
/// changes (GO OFFLINE, GO ONLINE) pass through to [inner].
final class DriverIdentityCachingDutyGateway
    implements DriverDutyGateway, DriverDutyStatusGateway {
  DriverIdentityCachingDutyGateway(this.inner);

  final DriverDutyGateway inner;

  String? _driverReference;
  bool _onDuty = false;
  int _generation = 0;

  String? get driverReference => _driverReference;

  /// True when the last duty fetch said the driver is online.
  bool get onDuty => _onDuty;

  void clear() {
    _generation += 1;
    _driverReference = null;
    _onDuty = false;
  }

  @override
  Future<DriverDutySummary> fetchDuty() async {
    final generation = _generation;
    final summary = await inner.fetchDuty();
    if (generation == _generation) {
      final reference = summary.driverReference?.trim();
      _driverReference = reference == null || reference.isEmpty
          ? null
          : reference;
      _onDuty = summary.isOnline;
    }
    return summary;
  }

  @override
  Future<DriverDutyTransition> updateDutyStatus(
    DriverOperationalDutyStatus status,
  ) async {
    final changes = inner;
    if (changes is! DriverDutyStatusGateway) {
      throw const DriverDutyApiException(
        DriverDutyApiFailureType.badResponse,
        'Driver duty action is not configured.',
      );
    }
    final generation = _generation;
    final transition = await (changes as DriverDutyStatusGateway)
        .updateDutyStatus(status);
    if (generation == _generation) {
      _onDuty = transition.dutyStatus == 'online';
    }
    return transition;
  }

  @override
  Future<List<DriverAssignedTrip>> fetchTrips() => inner.fetchTrips();

  @override
  Future<DriverAssignedTrip> fetchTripDetail(String tripReference) =>
      inner.fetchTripDetail(tripReference);
}

/// The stored access token, for the card's own clients.
final class DriverStoredAccessTokenProvider implements TokenProvider {
  const DriverStoredAccessTokenProvider(this.tokenStore);

  final AuthTokenStore tokenStore;

  @override
  Future<String?> getAccessToken() => tokenStore.readAccessToken();
}
