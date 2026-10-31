import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../driver_back_to_work.dart';
import '../driver_duty_trips.dart';
import '../network/driver_offer_response_resilience.dart';
import 'driver_offer_coordinator.dart';
import 'driver_pending_offer_card.dart';
import 'driver_pending_offer_store.dart';
import 'driver_pending_offers.dart';

/// The home screen's offers area: the card for the earliest-expiring
/// pending offer, or [waitingPanel] when there is none.
class DriverPendingOffersPanel extends StatefulWidget {
  const DriverPendingOffersPanel({
    required this.coordinator,
    required this.controllerFactory,
    required this.waitingPanel,
    this.pickupTimeLookup,
    this.onAccepted,
    this.pickDeclineReason,
    this.openAssignedTrips,
    this.openPopups,
    super.key,
  });

  final DriverOfferCoordinator coordinator;
  final DriverOfferResponseControllerFactory controllerFactory;
  final Widget waitingPanel;
  final DriverOfferPickupTimeLookup? pickupTimeLookup;
  final ValueChanged<String>? onAccepted;

  /// The card's own when null.
  final DriverDeclineReasonPicker? pickDeclineReason;
  final void Function(BuildContext context)? openAssignedTrips;

  /// See [DriverPendingOfferCard.openPopups].
  final ValueListenable<int>? openPopups;

  @override
  State<DriverPendingOffersPanel> createState() =>
      _DriverPendingOffersPanelState();
}

class _DriverPendingOffersPanelState extends State<DriverPendingOffersPanel> {
  /// True while a live card is shown: only then is the poll slowed.
  bool _showingCard = false;

  /// The offer whose card said it can no longer be answered. A re-offer of
  /// the same trip is a different offer, and a live one.
  DriverOfferIdentity? _ended;

  /// An ended card the driver did not answer. It stays, saying why, until
  /// it clears, even after the list drops its offer; a newer offer takes
  /// its place at once.
  ({DriverOfferIdentity identity, String reference})? _held;

  @override
  void initState() {
    super.initState();
    widget.coordinator.store.addListener(_changed);
  }

  @override
  void dispose() {
    widget.coordinator.store.removeListener(_changed);
    if (_showingCard) {
      widget.coordinator.cardClosed();
    }
    super.dispose();
  }

  void _changed() {
    if (mounted) {
      setState(() {});
    }
  }

  void _track(bool showingCard) {
    if (showingCard == _showingCard) {
      return;
    }
    _showingCard = showingCard;
    if (showingCard) {
      widget.coordinator.cardOpened();
    } else {
      widget.coordinator.cardClosed();
    }
  }

  void _release() {
    if (mounted && _held != null) {
      setState(() => _held = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.coordinator.store;
    final offer = store.firstOffer;
    var shown = offer == null
        ? null
        : (
            identity: DriverOfferIdentity.of(offer),
            reference: offer.tripReference,
          );
    final held = _held;
    // Held only while the server left the offer out; one dropped here
    // (closed, answered or cleared) goes at once, as before.
    if (held != null &&
        !store.forgets(held.identity) &&
        (shown == null || shown.identity == held.identity)) {
      shown = held;
    } else {
      _held = null;
    }
    if (shown == null) {
      _ended = null;
    }
    _track(shown != null && shown.identity != _ended);
    if (shown == null) {
      return widget.waitingPanel;
    }
    final identity = shown.identity;
    final reference = shown.reference;
    return DriverPendingOfferCard(
      key: ValueKey<DriverOfferIdentity>(identity),
      tripReference: reference,
      store: widget.coordinator.store,
      controllerFactory: widget.controllerFactory,
      pickupTimeLookup: widget.pickupTimeLookup,
      pickDeclineReason:
          widget.pickDeclineReason ?? showDriverDeclineReasonSheet,
      openAssignedTrips:
          widget.openAssignedTrips ?? DriverBackToWork.goToAssignedTrips,
      openPopups: widget.openPopups,
      onAccepted: (reference) {
        _release();
        widget.onAccepted?.call(reference);
      },
      onFinished: (_) => _release(),
      onEnded: () {
        _ended = identity;
        _held = (identity: identity, reference: reference);
        _track(false);
      },
      onCleared: _release,
    );
  }
}

/// The card on its own screen, for a push tap. It appears at once; after an
/// answer it moves to the next pending offer, or closes.
class DriverPendingOfferScreen extends StatefulWidget {
  const DriverPendingOfferScreen({
    required this.tripReference,
    required this.coordinator,
    required this.controllerFactory,
    this.pickupTimeLookup,
    this.onAccepted,
    super.key,
  });

  final String tripReference;
  final DriverOfferCoordinator coordinator;
  final DriverOfferResponseControllerFactory controllerFactory;
  final DriverOfferPickupTimeLookup? pickupTimeLookup;

  /// Called with the screen's context so the caller can replace it with the
  /// trip.
  final void Function(BuildContext context, String tripReference)? onAccepted;

  @override
  State<DriverPendingOfferScreen> createState() =>
      _DriverPendingOfferScreenState();
}

class _DriverPendingOfferScreenState extends State<DriverPendingOfferScreen> {
  late String _reference = widget.tripReference;

  /// Bumped when the screen moves to another offer, so the card starts
  /// fresh even for a re-offer of the same trip.
  int _cardGeneration = 0;

  /// True while the card here is live: only then is the poll paused.
  bool _pausing = false;

  /// The offer the card showed when it ended; null while it is live.
  DriverOfferIdentity? _endedOffer;

  /// The offer the card is showing, kept while it is live.
  DriverOfferIdentity? _shown;

  DriverPendingOfferStore get _store => widget.coordinator.store;

  @override
  void initState() {
    super.initState();
    _setPausing(true);
    _store.addListener(_onStoreChanged);
    _noteShown();
  }

  @override
  void dispose() {
    _store.removeListener(_onStoreChanged);
    _setPausing(false);
    super.dispose();
  }

  void _setPausing(bool pausing) {
    if (pausing == _pausing) {
      return;
    }
    _pausing = pausing;
    if (pausing) {
      widget.coordinator.cardOpened();
    } else {
      widget.coordinator.cardClosed();
    }
  }

  void _noteShown() {
    final listed = _store.offerFor(_reference);
    if (_endedOffer == null && listed != null) {
      _shown = DriverOfferIdentity.of(listed);
    }
  }

  void _onStoreChanged() {
    _noteShown();
    _moveToNewerLiveOffer();
  }

  void _ended() {
    _endedOffer ??= _shown ?? DriverOfferIdentity(_reference);
    _setPausing(false);
    // The card reports this from its own updates; move on after the frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _moveToNewerLiveOffer();
      }
    });
  }

  /// The ended card has shown why for long enough, with nothing open on
  /// top: a newer live offer takes its place, or the screen closes.
  void _cleared() {
    if (!mounted) {
      return;
    }
    _moveToNewerLiveOffer();
    if (_endedOffer != null) {
      Navigator.of(context).maybePop();
    }
  }

  /// An ended card yields to a newer live offer; a live card never does.
  void _moveToNewerLiveOffer() {
    final ended = _endedOffer;
    if (ended == null || !mounted) {
      return;
    }
    for (final offer in _store.offers) {
      final identity = DriverOfferIdentity.of(offer);
      final left = _store.remaining(offer.tripReference);
      final live =
          offer.expiry is! DriverOfferExpiresAt || left != Duration.zero;
      if (identity != ended && live) {
        setState(() {
          _reference = offer.tripReference;
          _cardGeneration += 1;
          _endedOffer = null;
          _shown = identity;
        });
        _setPausing(true);
        return;
      }
    }
  }

  void _finished(String reference) {
    final next = _store.firstOffer;
    if (next != null && next.tripReference != reference) {
      setState(() {
        _reference = next.tripReference;
        _cardGeneration += 1;
        _endedOffer = null;
        _shown = DriverOfferIdentity.of(next);
      });
      _setPausing(true);
      return;
    }
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('offer-screen'),
      backgroundColor: AsmColors.driverVisualSurface,
      appBar: AppBar(title: const Text('Trip offer')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AsmSpacing.space20),
          child: DriverPendingOfferCard(
            key: ValueKey<String>('screen-offer-$_reference-$_cardGeneration'),
            tripReference: _reference,
            store: _store,
            controllerFactory: widget.controllerFactory,
            pickupTimeLookup: widget.pickupTimeLookup,
            onAccepted: (reference) =>
                widget.onAccepted?.call(context, reference),
            onFinished: _finished,
            onEnded: _ended,
            onCleared: _cleared,
          ),
        ),
      ),
    );
  }
}
