import 'package:flutter/material.dart';

import '../network/driver_rating_gateway.dart';
import 'driver_rating.dart';
import 'driver_rating_form.dart';

class DriverRatingPage extends StatefulWidget {
  const DriverRatingPage({
    required this.gateway,
    required this.tripReference,
    super.key,
  });

  final ApiDriverRatingGateway gateway;
  final String tripReference;

  @override
  State<DriverRatingPage> createState() => _DriverRatingPageState();
}

class _DriverRatingPageState extends State<DriverRatingPage> {
  late Future<DriverRatingSnapshot> _future;
  DriverRatingSnapshot? _rating;

  @override
  void initState() {
    super.initState();
    _future = widget.gateway.fetchRating(widget.tripReference);
  }

  Future<void> _submit({
    required int overallScore,
    required int comfortScore,
    required int conductScore,
    required int cleanlinessScore,
    required String feedbackNote,
  }) async {
    final result = await widget.gateway.submitRating(
      tripReference: widget.tripReference,
      overallScore: overallScore,
      comfortScore: comfortScore,
      conductScore: conductScore,
      cleanlinessScore: cleanlinessScore,
      feedbackNote: feedbackNote,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _rating = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rate passenger')),
      body: FutureBuilder<DriverRatingSnapshot>(
        future: _future,
        builder: (context, snapshot) {
          final rating = _rating ?? snapshot.data;

          if (snapshot.connectionState != ConnectionState.done &&
              rating == null) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError && rating == null) {
            return const Center(
              key: Key('driver-rating-load-error'),
              child: Text('Rating could not be loaded.'),
            );
          }

          if (rating?.submitted == true) {
            return _SubmittedRatingView(
              rating: rating!,
              onBack: () => Navigator.of(context).maybePop(),
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: DriverRatingForm(onSubmit: _submit),
          );
        },
      ),
    );
  }
}

class _SubmittedRatingView extends StatelessWidget {
  const _SubmittedRatingView({required this.rating, required this.onBack});

  final DriverRatingSnapshot rating;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final feedback = rating.feedbackNote?.trim() ?? '';

    return SingleChildScrollView(
      key: const Key('driver-rating-submitted'),
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            children: [
              Container(
                key: const Key('driver-rating-success-icon'),
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: colors.primary,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.check_rounded,
                  size: 54,
                  color: colors.onPrimary,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Rating submitted',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                'Thanks for sharing your feedback.\n'
                'Your rating has been saved.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.45,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              Container(
                key: const Key('driver-rating-score-card'),
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: [
                    _SubmittedScoreRow(
                      label: 'Overall',
                      score: rating.overallScore,
                      valueKey: const Key('driver-rating-score-overall'),
                    ),
                    const Divider(height: 24),
                    _SubmittedScoreRow(
                      label: 'Comfort',
                      score: rating.comfortScore,
                      valueKey: const Key('driver-rating-score-comfort'),
                    ),
                    const Divider(height: 24),
                    _SubmittedScoreRow(
                      label: 'Conduct',
                      score: rating.conductScore,
                      valueKey: const Key('driver-rating-score-conduct'),
                    ),
                    const Divider(height: 24),
                    _SubmittedScoreRow(
                      label: 'Cleanliness',
                      score: rating.cleanlinessScore,
                      valueKey: const Key('driver-rating-score-cleanliness'),
                    ),
                    if (feedback.isNotEmpty) ...[
                      const Divider(height: 32),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Your feedback',
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        key: const Key('driver-rating-feedback-summary'),
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '“$feedback”',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const Key('driver-rating-back-to-trip'),
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('Back to trip'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubmittedScoreRow extends StatelessWidget {
  const _SubmittedScoreRow({
    required this.label,
    required this.score,
    required this.valueKey,
  });

  final String label;
  final int? score;
  final Key valueKey;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final safeScore = score != null && score! >= 1 && score! <= 5 ? score! : 0;

    return Row(
      children: [
        SizedBox(
          width: 88,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: List<Widget>.generate(
              5,
              (index) => Padding(
                padding: const EdgeInsets.only(left: 2),
                child: Icon(
                  index < safeScore
                      ? Icons.star_rounded
                      : Icons.star_border_rounded,
                  size: 19,
                  color: index < safeScore
                      ? colors.primary
                      : colors.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 30,
          child: Text(
            '$safeScore/5',
            key: valueKey,
            textAlign: TextAlign.end,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}
