import 'dart:async';

import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';

import '../driver_duty_trips.dart';
import '../network/driver_offer_response_gateway.dart';
import '../network/driver_offer_response_resilience.dart';
import 'driver_pending_offer_store.dart';
import 'driver_pending_offers.dart';

/// The fare line when the server sends no fare: staff confirm fares.
const driverOfferFareToBeConfirmed = 'Fare to be confirmed by dispatch';

typedef DriverOfferPickupTimeLookup =
    Future<DriverOfferPickupTime> Function(String tripReference);

typedef DriverDeclineReasonPicker =
    Future<DriverDeclineChoice?> Function(BuildContext context);

/// A pending trip offer: the pickup, the fare, the time left, Accept and
/// Decline. It appears at once, from whatever the store already knows.
class DriverPendingOfferCard extends StatefulWidget {
  const DriverPendingOfferCard({
    required this.tripReference,
    required this.store,
    required this.controllerFactory,
    this.pickupTimeLookup,
    this.pickDeclineReason = showDriverDeclineReasonSheet,
    this.onAccepted,
    this.onFinished,
    this.onEnded,
    this.tickInterval = const Duration(seconds: 1),
    this.detailsTimeout = DriverOfferCardTiming.detailsTimeout,
    super.key,
  });

  final String tripReference;
  final DriverPendingOfferStore store;
  final DriverOfferResponseControllerFactory controllerFactory;

  /// Asked when the offer does not say whether the ride is for now.
  final DriverOfferPickupTimeLookup? pickupTimeLookup;
  final DriverDeclineReasonPicker pickDeclineReason;

  /// The driver accepted; open the trip.
  final ValueChanged<String>? onAccepted;

  /// Declined, expired or ended; the card can go.
  final ValueChanged<String>? onFinished;

  /// Called once when the offer can no longer be answered here (time ran
  /// out, it ended, or the driver answered). Only a live card should pause
  /// the offers poll.
  final VoidCallback? onEnded;
  final Duration tickInterval;
  final Duration detailsTimeout;

  @override
  State<DriverPendingOfferCard> createState() => _DriverPendingOfferCardState();
}

class _DriverPendingOfferCardState extends State<DriverPendingOfferCard> {
  DriverOfferResponseResilienceController? _controller;
  Future<DriverOfferResponseResilienceController?>? _preparing;
  bool _prepareFailed = false;

  Timer? _ticker;
  Timer? _detailsTimer;
  bool _detailsTimedOut = false;

  late final Duration _openedAt;
  DriverPendingOffer? _lastOffer;
  DriverOfferPickupTime? _lookedUpPickupTime;
  bool _lookupRunning = false;

  bool _sending = false;
  bool _responded = false;
  bool _expired = false;
  bool _reportedEnded = false;

  /// When the countdown reached zero (monotonic), for the re-check and the
  /// local removal after it.
  Duration? _ranOutAt;
  bool _rechecked = false;
  bool _removedLocally = false;

  /// Final: the offer ended (expiry race, taken back, gone from the list).
  String? _endedMessage;

  /// Not final: the driver can try again.
  String? _message;

  DriverPendingOfferStore get _store => widget.store;
  String get _reference => widget.tripReference.trim();

  @override
  void initState() {
    super.initState();
    _openedAt = _store.clock.now;
    _store.addListener(_onStoreChanged);
    _ticker = Timer.periodic(widget.tickInterval, (_) => _onTick());
    _startDetailsTimer();
    _preparing = _prepare();
    _onStoreChanged(rebuild: false);
  }

  @override
  void dispose() {
    _store.removeListener(_onStoreChanged);
    _ticker?.cancel();
    _detailsTimer?.cancel();
    if (_locked && !_responded) {
      // Closing an ended card clears it from the home screen too. Not
      // during dispose itself: the store's listeners rebuild.
      final store = _store;
      final reference = _reference;
      scheduleMicrotask(() => store.forget(reference));
    }
    super.dispose();
  }

  void _reportIfEnded() {
    if (_locked && !_reportedEnded) {
      _reportedEnded = true;
      widget.onEnded?.call();
    }
  }

  Future<DriverOfferResponseResilienceController?> _prepare() async {
    try {
      final controller = await widget.controllerFactory(_reference);
      await controller.prepareWhenOfferDisplayed();
      if (mounted) {
        setState(() {
          _controller = controller;
          _prepareFailed = false;
        });
      }
      return controller;
    } on Object {
      if (mounted) {
        setState(() => _prepareFailed = true);
      }
      return null;
    }
  }

  void _startDetailsTimer() {
    _detailsTimer?.cancel();
    _detailsTimer = Timer(widget.detailsTimeout, () {
      if (mounted && !_readyToShow) {
        setState(() => _detailsTimedOut = true);
      }
    });
  }

  void _onStoreChanged({bool rebuild = true}) {
    final current = _store.offerFor(_reference);
    if (current != null) {
      _lastOffer = current;
      _lookUpPickupTimeIfNeeded(current);
    } else if (!_responded && !_locked) {
      final snapshot = _store.snapshot;
      if (snapshot != null && snapshot.receivedAt >= _openedAt) {
        _endedMessage = driverOfferNoLongerAvailableMessage;
      }
    }
    _reportIfEnded();
    if (rebuild && mounted) {
      setState(() {});
    }
  }

  void _onTick() {
    if (!mounted) {
      return;
    }
    final left = _remaining;
    if (left == Duration.zero && !_locked && !_sending) {
      _expired = true;
      _ranOutAt = _store.clock.now;
      unawaited(_store.refresh());
    }
    final ranOutAt = _ranOutAt;
    if (ranOutAt != null) {
      final since = _store.clock.now - ranOutAt;
      if (!_rechecked && since >= DriverOfferCardTiming.expiredRecheckDelay) {
        _rechecked = true;
        unawaited(_store.refresh());
      }
      if (!_removedLocally &&
          since >= DriverOfferCardTiming.expiredRemovalDelay) {
        _removedLocally = true;
        _store.forget(_reference);
      }
    }
    _reportIfEnded();
    setState(() {});
  }

  void _lookUpPickupTimeIfNeeded(DriverPendingOffer offer) {
    final lookup = widget.pickupTimeLookup;
    if (offer.pickupTime is! DriverOfferPickupTimeUnknown ||
        _lookedUpPickupTime != null ||
        _lookupRunning ||
        lookup == null) {
      return;
    }
    _lookupRunning = true;
    lookup(_reference)
        .then((time) {
          if (mounted) {
            setState(() => _lookedUpPickupTime = time);
          }
        })
        .catchError((Object _) {})
        .whenComplete(() => _lookupRunning = false);
  }

  DriverPendingOffer? get _offer => _store.offerFor(_reference) ?? _lastOffer;

  Duration? get _remaining => _store.remaining(_reference);

  DriverOfferPickupTime get _pickupTime {
    final fromOffer = _offer?.pickupTime;
    if (fromOffer != null && fromOffer is! DriverOfferPickupTimeUnknown) {
      return fromOffer;
    }
    return _lookedUpPickupTime ?? const DriverOfferPickupTimeUnknown();
  }

  bool get _readyToShow =>
      (_offer?.detailsKnown ?? false) &&
      _pickupTime is! DriverOfferPickupTimeUnknown;

  bool get _locked => _expired || _endedMessage != null || _responded;

  bool get _canAccept =>
      !_locked && !_sending && _controller != null && _readyToShow;

  bool get _canDecline => !_locked && !_sending;

  Future<void> _tryAgain() async {
    setState(() {
      _detailsTimedOut = false;
      _message = null;
      _lookedUpPickupTime = null;
    });
    _startDetailsTimer();
    if (_prepareFailed) {
      _preparing = _prepare();
    }
    final current = _store.offerFor(_reference);
    if (current != null) {
      _lookUpPickupTimeIfNeeded(current);
    }
    await _store.refresh();
  }

  Future<void> _accept() async {
    final controller = _controller;
    if (controller == null || !_canAccept) {
      return;
    }
    setState(() {
      _sending = true;
      _message = null;
    });
    final result = await controller.accept();
    if (!mounted) {
      return;
    }
    setState(() {
      _sending = false;
      if (result.accepted) {
        _responded = true;
      } else {
        _applyFailure(result.error, result.message);
      }
    });
    _reportIfEnded();
    if (result.accepted) {
      _store.forget(_reference);
      widget.onAccepted?.call(_reference);
    }
  }

  Future<void> _decline() async {
    if (!_canDecline) {
      return;
    }
    final choice = await widget.pickDeclineReason(context);
    if (choice == null || !mounted || !_canDecline) {
      return;
    }
    setState(() {
      _sending = true;
      _message = null;
    });
    var controller = _controller ?? await _preparing;
    controller ??= await (_preparing = _prepare());
    if (!mounted) {
      return;
    }
    if (controller == null) {
      setState(() {
        _sending = false;
        _message = 'Could not send. Check your connection and try again.';
      });
      return;
    }
    final result = await controller.decline(
      reason: choice.reason,
      reasonNote: choice.reasonNote,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _sending = false;
      if (result.succeeded) {
        _responded = true;
      } else {
        _applyFailure(result.error, result.message);
      }
    });
    _reportIfEnded();
    if (result.succeeded) {
      _store.forget(_reference);
      widget.onFinished?.call(_reference);
    }
  }

  void _applyFailure(DriverOfferResponseException? error, String? message) {
    if (error?.type == DriverOfferResponseFailureType.offerUnavailable) {
      _endedMessage = error!.message;
      unawaited(_store.refresh());
      return;
    }
    _message =
        message ?? 'Could not send. Check your connection and try again.';
  }

  String get _countdownText {
    if (_expired) {
      return 'Offer expired';
    }
    final expiry = _offer?.expiry;
    if (expiry is DriverOfferNeverExpires) {
      return 'Waiting for your response';
    }
    final left = _remaining;
    if (expiry is! DriverOfferExpiresAt || left == null) {
      return 'Respond quickly';
    }
    final seconds = left.inSeconds;
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')} left';
  }

  @override
  Widget build(BuildContext context) {
    final offer = _offer;
    final pickupTime = _pickupTime;
    final othersWaiting = _store.offers
        .where((other) => other.tripReference != _reference)
        .length;
    final fare = offer?.fareAmount;
    final passengers = offer?.passengerCount;
    final note = _endedMessage ?? _message;

    return Container(
      key: const Key('offer-card'),
      width: double.infinity,
      padding: const EdgeInsets.all(AsmSpacing.space20),
      decoration: BoxDecoration(
        color: AsmColors.driverCardElevated,
        borderRadius: BorderRadius.circular(AsmRadii.radius24),
        border: Border.all(color: AsmColors.driverMintAction, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'New trip request',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                ),
              ),
              Text(
                _countdownText,
                key: const Key('offer-card-countdown'),
                style: const TextStyle(
                  color: AsmColors.driverMintAction,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: AsmSpacing.space12),
          Text(
            offer?.pickupLabel ?? 'Loading trip details…',
            key: const Key('offer-card-pickup'),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          if (offer != null) ...[
            const SizedBox(height: AsmSpacing.space8),
            Row(
              children: [
                if (passengers != null)
                  Text(
                    passengers == 1 ? '1 passenger' : '$passengers passengers',
                    key: const Key('offer-card-passengers'),
                    style: const TextStyle(
                      color: AsmColors.driverTextSecondary,
                    ),
                  ),
                const SizedBox(width: AsmSpacing.space12),
                Expanded(
                  child: Text(
                    fare == null
                        ? driverOfferFareToBeConfirmed
                        : [
                            offer.fareCurrency,
                            fare,
                          ].whereType<String>().join(' '),
                    key: const Key('offer-card-fare'),
                    textAlign: TextAlign.end,
                    style: fare == null
                        ? const TextStyle(
                            color: AsmColors.driverTextSecondary,
                            fontWeight: FontWeight.w700,
                          )
                        : const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                  ),
                ),
              ],
            ),
          ],
          if (pickupTime is DriverOfferPickupAt) ...[
            const SizedBox(height: AsmSpacing.space12),
            DriverScheduledPickupBadge(
              key: const Key('offer-card-scheduled'),
              label: driverScheduledPickupLabel(pickupTime.at),
            ),
          ],
          if ((_detailsTimedOut && !_readyToShow && !_locked) ||
              (_prepareFailed && !_locked)) ...[
            const SizedBox(height: AsmSpacing.space12),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    "Couldn't load trip details",
                    key: Key('offer-card-details-failed'),
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton(
                  key: const Key('offer-card-try-again'),
                  onPressed: _tryAgain,
                  child: const Text('Try again'),
                ),
              ],
            ),
          ],
          if (note != null) ...[
            const SizedBox(height: AsmSpacing.space12),
            Text(
              note,
              key: const Key('offer-card-message'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
          const SizedBox(height: AsmSpacing.space16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const Key('offer-card-decline'),
                  onPressed: _canDecline ? _decline : null,
                  child: const Text('Decline'),
                ),
              ),
              const SizedBox(width: AsmSpacing.space12),
              Expanded(
                child: FilledButton(
                  key: const Key('offer-card-accept'),
                  onPressed: _canAccept ? _accept : null,
                  child: Text(_sending ? 'Sending…' : 'Accept'),
                ),
              ),
            ],
          ),
          if (othersWaiting > 0) ...[
            const SizedBox(height: AsmSpacing.space12),
            Text(
              othersWaiting == 1
                  ? '1 more offer waiting'
                  : '$othersWaiting more offers waiting',
              key: const Key('offer-card-more-offers'),
              style: const TextStyle(color: AsmColors.driverTextSecondary),
            ),
          ],
        ],
      ),
    );
  }
}
