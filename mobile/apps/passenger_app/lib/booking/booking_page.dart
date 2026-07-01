import 'package:asm_app_config/asm_app_config.dart';
import 'package:asm_ride_domain/asm_ride_domain.dart';
import 'package:flutter/material.dart';

import 'booking_draft.dart';
import 'booking_form.dart';
import 'booking_review.dart';

class BookingPage extends StatefulWidget {
  const BookingPage({
    required this.market,
    this.initialPickupDescription = '',
    this.initialDestinationDescription = '',
    super.key,
  });

  final MarketConfig market;
  final String initialPickupDescription;
  final String initialDestinationDescription;

  @override
  State<BookingPage> createState() => _BookingPageState();
}

class _BookingPageState extends State<BookingPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _pickupController;
  late final TextEditingController _destinationController;
  final _assistanceController = TextEditingController();

  RideServiceContextCode? _serviceContext;
  int _passengerCount = 1;
  BookingDraft? _draft;

  @override
  void initState() {
    super.initState();
    _pickupController = TextEditingController(
      text: widget.initialPickupDescription,
    );
    _destinationController = TextEditingController(
      text: widget.initialDestinationDescription,
    );
  }

  @override
  void dispose() {
    _pickupController.dispose();
    _destinationController.dispose();
    _assistanceController.dispose();
    super.dispose();
  }

  void _reviewDraft() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _draft = BookingDraft(
        marketCode: widget.market.marketCode,
        serviceContext: _serviceContext!,
        pickupDescription: _pickupController.text,
        destinationDescription: _destinationController.text,
        passengerCount: _passengerCount,
        assistanceNote: _assistanceController.text,
      );
    });
  }

  void _editDraft() {
    setState(() => _draft = null);
  }

  void _closeDraft() {
    _draft = null;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Plan a demo ride')),
      body: SafeArea(
        child: _draft == null
            ? BookingForm(
                market: widget.market,
                formKey: _formKey,
                serviceContext: _serviceContext,
                pickupController: _pickupController,
                destinationController: _destinationController,
                assistanceController: _assistanceController,
                passengerCount: _passengerCount,
                onServiceContextChanged: (value) {
                  setState(() => _serviceContext = value);
                },
                onPassengerCountChanged: (value) {
                  setState(() => _passengerCount = value);
                },
                onReview: _reviewDraft,
              )
            : BookingReview(
                draft: _draft!,
                market: widget.market,
                onEdit: _editDraft,
                onClose: _closeDraft,
              ),
      ),
    );
  }
}
