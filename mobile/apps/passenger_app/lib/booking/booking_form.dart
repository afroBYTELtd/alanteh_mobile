import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class BookingForm extends StatelessWidget {
  const BookingForm({
    required this.formKey,
    required this.pickupController,
    required this.destinationController,
    required this.assistanceController,
    required this.passengerCount,
    required this.onPassengerCountChanged,
    required this.onReview,
    super.key,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController pickupController;
  final TextEditingController destinationController;
  final TextEditingController assistanceController;
  final int passengerCount;
  final ValueChanged<int> onPassengerCountChanged;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

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
          Text(
            'Book a ride',
            style: textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AsmSpacing.space8),
          Text(
            'Tell us where to pick you up and where you are going.',
            style: textTheme.bodyLarge?.copyWith(
              color: colors.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: AsmSpacing.space24),
          TextFormField(
            key: const Key('booking-pickup'),
            controller: pickupController,
            textInputAction: TextInputAction.next,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Where are you?',
              hintText: 'Pickup address or landmark',
              border: OutlineInputBorder(),
            ),
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Enter where you are.'
                : value.trim().length > 160
                ? 'Pickup must be 160 characters or fewer.'
                : null,
          ),
          const SizedBox(height: AsmSpacing.space16),
          TextFormField(
            key: const Key('booking-destination'),
            controller: destinationController,
            textInputAction: TextInputAction.next,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Where to?',
              hintText: 'Destination address or landmark',
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              final destination = value?.trim() ?? '';
              if (destination.isEmpty) {
                return 'Enter where to.';
              }
              if (destination.length > 160) {
                return 'Destination must be 160 characters or fewer.';
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
                  'How many passengers?',
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
              labelText: 'Special request (optional)',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: AsmSpacing.space24),
          FilledButton.icon(
            key: const Key('request-ride'),
            onPressed: onReview,
            icon: const Icon(Icons.directions_car_filled_outlined),
            label: const Text('Request ride'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
          ),
        ],
      ),
    );
  }
}
