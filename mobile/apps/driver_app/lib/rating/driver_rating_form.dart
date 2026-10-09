import 'package:flutter/material.dart';

class DriverRatingForm extends StatefulWidget {
  const DriverRatingForm({
    required this.onSubmit,
    super.key,
  });

  final Future<void> Function({
    required int overallScore,
    required int comfortScore,
    required int conductScore,
    required int cleanlinessScore,
    required String feedbackNote,
  }) onSubmit;

  @override
  State<DriverRatingForm> createState() => _DriverRatingFormState();
}

class _DriverRatingFormState extends State<DriverRatingForm> {
  int? overall;
  int? comfort;
  int? conduct;
  int? cleanliness;

  final feedbackController = TextEditingController();

  Future<void> _submit() async {
    if (overall == null ||
        comfort == null ||
        conduct == null ||
        cleanliness == null) {
      return;
    }

    await widget.onSubmit(
      overallScore: overall!,
      comfortScore: comfort!,
      conductScore: conduct!,
      cleanlinessScore: cleanliness!,
      feedbackNote: feedbackController.text.trim(),
    );
  }

  @override
  void dispose() {
    feedbackController.dispose();
    super.dispose();
  }

  Widget _stars(
    String label,
    int? value,
    ValueChanged<int> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        Row(
          children: List.generate(
            5,
            (index) => IconButton(
              key: Key('$label-${index + 1}'),
              onPressed: () => onChanged(index + 1),
              icon: Icon(
                index < (value ?? 0)
                    ? Icons.star
                    : Icons.star_border,
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('driver-rating-form'),
      children: [
        _stars('Overall', overall, (v) => setState(() => overall = v)),
        _stars('Comfort', comfort, (v) => setState(() => comfort = v)),
        _stars('Conduct', conduct, (v) => setState(() => conduct = v)),
        _stars(
          'Cleanliness',
          cleanliness,
          (v) => setState(() => cleanliness = v),
        ),
        TextField(
          key: const Key('driver-rating-feedback'),
          controller: feedbackController,
          maxLength: 1000,
          decoration: const InputDecoration(
            labelText: 'Optional feedback',
          ),
        ),
        ElevatedButton(
          key: const Key('submit-driver-rating'),
          onPressed: _submit,
          child: const Text('Rate passenger'),
        ),
      ],
    );
  }
}
