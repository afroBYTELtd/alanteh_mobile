import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';

import '../network/driver_offer_response_resilience.dart';
import 'driver_offer_coordinator.dart';
import 'driver_pending_offer_card.dart';
import 'driver_pending_offer_store.dart';

/// The home screen's offers area: the card for the earliest-expiring
/// pending offer, or [waitingPanel] when there is none.
class DriverPendingOffersPanel extends StatefulWidget {
  const DriverPendingOffersPanel({
    required this.coordinator,
    required this.controllerFactory,
    required this.waitingPanel,
    this.pickupTimeLookup,
    this.onAccepted,
    super.key,
  });

  final DriverOfferCoordinator coordinator;
  final DriverOfferResponseControllerFactory controllerFactory;
  final Widget waitingPanel;
  final DriverOfferPickupTimeLookup? pickupTimeLookup;
  final ValueChanged<String>? onAccepted;

  @override
  State<DriverPendingOffersPanel> createState() =>
      _DriverPendingOffersPanelState();
}

class _DriverPendingOffersPanelState extends State<DriverPendingOffersPanel> {
  /// True while a live card is shown: only then is the poll paused.
  bool _showingCard = false;

  /// The offer whose card said it can no longer be answered. A re-offer of
  /// the same trip is a different offer, and a live one.
  DriverOfferIdentity? _ended;

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

  @override
  Widget build(BuildContext context) {
    final offer = widget.coordinator.store.firstOffer;
    final identity = offer == null ? null : DriverOfferIdentity.of(offer);
    if (offer == null) {
      _ended = null;
    }
    _track(identity != null && identity != _ended);
    if (offer == null) {
      return widget.waitingPanel;
    }
    return DriverPendingOfferCard(
      key: ValueKey<DriverOfferIdentity>(identity!),
      tripReference: offer.tripReference,
      store: widget.coordinator.store,
      controllerFactory: widget.controllerFactory,
      pickupTimeLookup: widget.pickupTimeLookup,
      onAccepted: widget.onAccepted,
      onEnded: () {
        _ended = identity;
        _track(false);
      },
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

  /// True while the card here is live: only then is the poll paused.
  bool _pausing = false;

  @override
  void initState() {
    super.initState();
    _setPausing(true);
  }

  @override
  void dispose() {
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

  void _finished(String reference) {
    final next = widget.coordinator.store.firstOffer;
    if (next != null && next.tripReference != reference) {
      setState(() => _reference = next.tripReference);
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
            key: ValueKey<String>('screen-offer-$_reference'),
            tripReference: _reference,
            store: widget.coordinator.store,
            controllerFactory: widget.controllerFactory,
            pickupTimeLookup: widget.pickupTimeLookup,
            onAccepted: (reference) =>
                widget.onAccepted?.call(context, reference),
            onFinished: _finished,
            onEnded: () => _setPausing(false),
          ),
        ),
      ),
    );
  }
}
