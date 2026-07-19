import 'dart:async';

import 'package:asm_app_config/asm_app_config.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:asm_ride_domain/asm_ride_domain.dart';
import 'package:flutter/material.dart';

import '../trip_progress/driver_trip_visual_sequence.dart';
import 'driver_ride_offer_decision_preview.dart';
import 'driver_ride_offer_pending_preview.dart';
import 'driver_ride_offer_preview.dart';

class DriverRideOfferPage extends StatefulWidget {
  const DriverRideOfferPage({
    required this.market,
    this.countdownDuration = const Duration(seconds: 14),
    this.tickInterval = const Duration(seconds: 1),
    super.key,
  });

  final MarketConfig market;
  final Duration countdownDuration;
  final Duration tickInterval;

  @override
  State<DriverRideOfferPage> createState() => _DriverRideOfferPageState();
}

enum _DriverRideOfferVisualScreen { preview, detail }

class _DriverRideOfferPageState extends State<DriverRideOfferPage> {
  late DriverRideOfferPreview _preview;
  late int _secondsRemaining;
  late final int _countdownTotalSeconds;
  _DriverRideOfferVisualScreen _screen = _DriverRideOfferVisualScreen.preview;
  Timer? _timer;

  @override
  void initState() {
    super.initState();

    final configuredSeconds = widget.countdownDuration.inSeconds;
    _countdownTotalSeconds = configuredSeconds > 0 ? configuredSeconds : 14;
    _secondsRemaining = _countdownTotalSeconds;

    _preview = DriverRideOfferPreview(
      marketCode: widget.market.marketCode,
      serviceContext: RideServiceContextCode.otherApprovedRequest,
      pickupDescription: 'Accra Mall',
      destinationDescription: 'Accra Market',
      passengerCount: 2,
    );

    _timer = Timer.periodic(widget.tickInterval, _handleCountdownTick);
  }

  void _handleCountdownTick(Timer timer) {
    if (!mounted || _preview.status != DriverRideOfferPreviewStatus.pending) {
      timer.cancel();
      return;
    }

    if (_secondsRemaining <= 1) {
      timer.cancel();
      setState(() {
        _secondsRemaining = 0;
        _preview = _preview.expirePreview();
      });
      return;
    }

    setState(() => _secondsRemaining -= 1);
  }

  void _showDetails() {
    setState(() => _screen = _DriverRideOfferVisualScreen.detail);
  }

  void _showPreview() {
    setState(() => _screen = _DriverRideOfferVisualScreen.preview);
  }

  void _accept() {
    _timer?.cancel();
    setState(() => _preview = _preview.acceptPreview());
  }

  void _decline() {
    _timer?.cancel();
    setState(() => _preview = _preview.declinePreview());
  }

  Future<void> _openTripSequence() async {
    final completed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => const DriverTripVisualSequencePage(),
      ),
    );

    if (!mounted || completed != true) {
      return;
    }

    Navigator.of(context).pop();
  }

  void _close() {
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pending = _preview.status == DriverRideOfferPreviewStatus.pending;
    final detail = pending && _screen == _DriverRideOfferVisualScreen.detail;

    return Scaffold(
      key: const Key('driver-ride-offer-page'),
      appBar: detail
          ? AppBar(
              leading: IconButton(
                key: const Key('ride-offer-back-to-preview'),
                onPressed: _showPreview,
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back',
              ),
              title: const Text('Ride offer'),
            )
          : null,
      body: SafeArea(
        child: Semantics(
          label: pending ? 'New ride offer' : 'Ride offer response',
          container: true,
          explicitChildNodes: true,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AsmSpacing.space20,
              AsmSpacing.space24,
              AsmSpacing.space20,
              AsmSpacing.space32,
            ),
            children: [
              if (pending)
                DriverRideOfferPendingPreview(
                  preview: _preview,
                  countdownSeconds: _secondsRemaining,
                  countdownTotalSeconds: _countdownTotalSeconds,
                  showDetails: detail,
                  onViewDetails: _showDetails,
                  onAcceptPreview: _accept,
                  onDeclinePreview: _decline,
                )
              else
                DriverRideOfferDecisionPreview(
                  preview: _preview,
                  onClosePreview: _close,
                  onNavigateToPickup:
                      _preview.status ==
                          DriverRideOfferPreviewStatus.acceptedPreview
                      ? _openTripSequence
                      : null,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
