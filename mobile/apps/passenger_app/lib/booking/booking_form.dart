import 'package:asm_app_config/asm_app_config.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:asm_ride_domain/asm_ride_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'booking_draft.dart';

class BookingForm extends StatelessWidget {
  const BookingForm({
    required this.market,
    required this.formKey,
    required this.serviceContext,
    required this.pickupController,
    required this.destinationController,
    required this.assistanceController,
    required this.passengerCount,
    required this.onServiceContextChanged,
    required this.onPassengerCountChanged,
    required this.onReview,
    super.key,
  });

  final MarketConfig market;
  final GlobalKey<FormState> formKey;
  final RideServiceContextCode? serviceContext;
  final TextEditingController pickupController;
  final TextEditingController destinationController;
  final TextEditingController assistanceController;
  final int passengerCount;
  final ValueChanged<RideServiceContextCode?> onServiceContextChanged;
  final ValueChanged<int> onPassengerCountChanged;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Form(
      key: formKey,
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(
          AsmSpacing.space20,
          AsmSpacing.space16,
          AsmSpacing.space20,
          AsmSpacing.space32,
        ),
        children: [
          _LocalDemoHeading(message: _bookingContextMessage(market)),
          const SizedBox(height: AsmSpacing.space24),
          DropdownButtonFormField<RideServiceContextCode>(
            key: const Key('booking-service-context'),
            initialValue: serviceContext,
            decoration: const InputDecoration(
              labelText: 'Approved service context',
              border: OutlineInputBorder(),
            ),
            isExpanded: true,
            items: RideServiceContextCode.values
                .map(
                  (serviceContext) => DropdownMenuItem(
                    value: serviceContext,
                    child: Text(serviceContext.label),
                  ),
                )
                .toList(),
            onChanged: onServiceContextChanged,
            validator: (value) =>
                value == null ? 'Choose an approved service context.' : null,
          ),
          const SizedBox(height: AsmSpacing.space16),
          TextFormField(
            key: const Key('booking-pickup'),
            controller: pickupController,
            textInputAction: TextInputAction.next,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Pickup description',
              hintText: 'Hotel reception or approved pickup point',
              border: OutlineInputBorder(),
            ),
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Enter a pickup description.'
                : value.trim().length > 160
                ? 'Pickup description must be 160 characters or fewer.'
                : null,
          ),
          const SizedBox(height: AsmSpacing.space16),
          TextFormField(
            key: const Key('booking-destination'),
            controller: destinationController,
            textInputAction: TextInputAction.next,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Destination description',
              hintText: 'Approved destination or meeting point',
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              final destination = value?.trim() ?? '';
              if (destination.isEmpty) {
                return 'Enter a destination description.';
              }
              if (destination.length > 160) {
                return 'Destination description must be 160 characters or fewer.';
              }
              if (destination.toLowerCase() ==
                  pickupController.text.trim().toLowerCase()) {
                return 'Destination must be different from pickup.';
              }
              return null;
            },
          ),
          const SizedBox(height: AsmSpacing.space20),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Passengers',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton.outlined(
                key: const Key('passenger-count-decrease'),
                tooltip: 'Decrease passenger count',
                onPressed: passengerCount > 1
                    ? () => onPassengerCountChanged(passengerCount - 1)
                    : null,
                icon: const Icon(Icons.remove),
              ),
              Semantics(
                label: '$passengerCount passengers',
                child: ExcludeSemantics(
                  child: SizedBox(
                    width: 48,
                    child: Text(
                      '$passengerCount',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
              IconButton.filledTonal(
                key: const Key('passenger-count-increase'),
                tooltip: 'Increase passenger count',
                onPressed: passengerCount < 6
                    ? () => onPassengerCountChanged(passengerCount + 1)
                    : null,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          const SizedBox(height: AsmSpacing.space20),
          TextFormField(
            key: const Key('booking-assistance'),
            controller: assistanceController,
            minLines: 2,
            maxLines: 3,
            maxLength: 240,
            inputFormatters: [LengthLimitingTextInputFormatter(240)],
            textInputAction: TextInputAction.done,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Assistance note (optional)',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: AsmSpacing.space8),
          Text(
            'This stays on this device while the draft is open.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: AsmSpacing.space24),
          FilledButton.icon(
            key: const Key('review-local-draft'),
            onPressed: onReview,
            icon: const Icon(Icons.fact_check_outlined),
            label: const Text('Review local draft'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
          ),
        ],
      ),
    );
  }
}

String _bookingContextMessage(MarketConfig market) {
  final operatingModel = switch (market.operatingModel) {
    OperatingModel.controlledPilot => 'controlled pilot',
  };
  return 'Local draft for the $operatingModel in ${market.city}, '
      '${market.countryName} (${market.marketCode}).';
}

class _LocalDemoHeading extends StatelessWidget {
  const _LocalDemoHeading({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AsmSpacing.space12,
            vertical: AsmSpacing.space8,
          ),
          decoration: BoxDecoration(
            color: colors.primaryContainer,
            borderRadius: BorderRadius.circular(AsmRadii.radius6),
          ),
          child: Text(
            'LOCAL DEMO',
            style: TextStyle(
              color: colors.onPrimaryContainer,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: AsmSpacing.space12),
        Text(
          message,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: colors.onSurfaceVariant,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}
