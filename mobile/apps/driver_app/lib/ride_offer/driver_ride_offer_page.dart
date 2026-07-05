import 'package:asm_app_config/asm_app_config.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:asm_ride_domain/asm_ride_domain.dart';
import 'package:flutter/material.dart';

import 'driver_ride_offer_decision_preview.dart';
import 'driver_ride_offer_pending_preview.dart';
import 'driver_ride_offer_preview.dart';

class DriverRideOfferPage extends StatefulWidget {
  const DriverRideOfferPage({required this.market, super.key});

  final MarketConfig market;

  @override
  State<DriverRideOfferPage> createState() => _DriverRideOfferPageState();
}

class _DriverRideOfferPageState extends State<DriverRideOfferPage> {
  late DriverRideOfferPreview _preview;

  @override
  void initState() {
    super.initState();
    _preview = DriverRideOfferPreview(
      marketCode: widget.market.marketCode,
      serviceContext: RideServiceContextCode.airportConnection,
      pickupDescription: 'Solar Hotel',
      destinationDescription: 'Accra Airport',
      passengerCount: 2,
    );
  }

  @override
  Widget build(BuildContext context) {
    final marketLabel = widget.market.countryName;

    return Scaffold(
      appBar: AppBar(title: const Text('New trip')),
      body: SafeArea(
        child: Semantics(
          label: 'New trip',
          container: true,
          explicitChildNodes: true,
          child: ListView(
            padding: const EdgeInsets.all(AsmSpacing.space20),
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AsmSpacing.space12,
                runSpacing: AsmSpacing.space8,
                children: [
                  _StatusBadge(status: _preview.status),
                  Text(
                    marketLabel,
                    key: const Key('ride-offer-market'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: AsmSpacing.space20),
              if (_preview.status == DriverRideOfferPreviewStatus.pending)
                DriverRideOfferPendingPreview(
                  preview: _preview,
                  onAcceptPreview: () {
                    setState(() => _preview = _preview.acceptPreview());
                  },
                  onDeclinePreview: () {
                    setState(() => _preview = _preview.declinePreview());
                  },
                )
              else
                DriverRideOfferDecisionPreview(
                  preview: _preview,
                  onClosePreview: () => Navigator.of(context).pop(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final DriverRideOfferPreviewStatus status;

  @override
  Widget build(BuildContext context) {
    final label = switch (status) {
      DriverRideOfferPreviewStatus.pending => 'New trip',
      DriverRideOfferPreviewStatus.acceptedPreview => 'Accepted',
      DriverRideOfferPreviewStatus.declinedPreview => 'Declined',
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AsmColors.brandGreen,
        borderRadius: BorderRadius.circular(AsmRadii.radius6),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
