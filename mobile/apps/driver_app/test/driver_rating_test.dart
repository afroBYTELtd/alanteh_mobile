import 'package:asm_api_client/asm_api_client.dart';
import 'package:driver_app/network/driver_rating_gateway.dart';
import 'package:driver_app/rating/driver_rating.dart';
import 'package:driver_app/rating/driver_rating_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DriverRatingSnapshot', () {
    test('decodes submitted rating response', () {
      final rating = DriverRatingSnapshot.fromJson(<String, Object?>{
        'trip_reference': 'TRIP-001',
        'submitted': true,
        'rating': <String, Object?>{
          'overall_score': 5,
          'comfort_score': 5,
          'conduct_score': 4,
          'cleanliness_score': 5,
          'feedback_note': 'Good passenger',
          'submitted_at': '2026-09-08T10:00:00Z',
        },
      });

      expect(rating.tripReference, 'TRIP-001');
      expect(rating.submitted, true);
      expect(rating.overallScore, 5);
      expect(rating.feedbackNote, 'Good passenger');
      expect(rating.submittedAt, isNotNull);
    });

    test('decodes empty rating response', () {
      final rating = DriverRatingSnapshot.fromJson(<String, Object?>{
        'trip_reference': 'TRIP-002',
        'submitted': false,
        'rating': null,
      });

      expect(rating.tripReference, 'TRIP-002');
      expect(rating.submitted, false);
      expect(rating.overallScore, isNull);
    });
  });

  group('Driver rating validation', () {
    test('accepts score range 1 to 5', () {
      expect(isValidDriverRatingScore(1), true);
      expect(isValidDriverRatingScore(5), true);
      expect(isValidDriverRatingScore(0), false);
      expect(isValidDriverRatingScore(6), false);
      expect(isValidDriverRatingScore(null), false);
    });

    test('accepts feedback up to 1000 characters', () {
      expect(isValidDriverRatingFeedback('short'), true);
      expect(isValidDriverRatingFeedback('x' * 1000), true);
      expect(isValidDriverRatingFeedback('x' * 1001), false);
    });
  });

  group('Corrected duplicate rating contract', () {
    test('HTTP 200 duplicate response uses normal success path', () async {
      final api = _ScriptedDriverRatingApi(
        getPayload: _unsubmittedPayload(),
        postPayload: _submittedPayload(),
        postStatusCode: 200,
      );
      final gateway = ApiDriverRatingGateway(apiGateway: api);

      final result = await gateway.submitRating(
        tripReference: 'TRIP-DUPLICATE-200',
        overallScore: 5,
        comfortScore: 4,
        conductScore: 5,
        cleanlinessScore: 5,
        feedbackNote: 'Already submitted',
      );

      expect(api.postCalls, 1);
      expect(result.submitted, true);
      expect(result.overallScore, 5);
      expect(result.feedbackNote, 'Good passenger');
    });

    testWidgets('existing submitted GET shows read-only state', (tester) async {
      final api = _ScriptedDriverRatingApi(
        getPayload: _submittedPayload(),
        postPayload: _submittedPayload(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: DriverRatingPage(
            gateway: ApiDriverRatingGateway(apiGateway: api),
            tripReference: 'TRIP-DUPLICATE-200',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('driver-rating-submitted')), findsOneWidget);
      expect(
        find.byKey(const Key('driver-rating-success-icon')),
        findsOneWidget,
      );
      expect(find.text('Rating submitted'), findsOneWidget);
      expect(
        find.text(
          'Thanks for sharing your feedback.\nYour rating has been saved.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('driver-rating-score-card')), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('driver-rating-score-overall')))
            .data,
        '5/5',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('driver-rating-score-comfort')))
            .data,
        '4/5',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('driver-rating-score-conduct')))
            .data,
        '5/5',
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(const Key('driver-rating-score-cleanliness')),
            )
            .data,
        '5/5',
      );
      expect(
        find.byKey(const Key('driver-rating-feedback-summary')),
        findsOneWidget,
      );
      expect(find.textContaining('Good passenger'), findsOneWidget);
      expect(
        find.byKey(const Key('driver-rating-back-to-trip')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('driver-rating-back-to-trip')),
            )
            .onPressed,
        isNotNull,
      );
      expect(find.byKey(const Key('driver-rating-form')), findsNothing);
      expect(find.byKey(const Key('submit-driver-rating')), findsNothing);
      expect(api.getCalls, 1);
      expect(api.postCalls, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('submitted state omits feedback section when blank', (
      tester,
    ) async {
      final api = _ScriptedDriverRatingApi(
        getPayload: _submittedPayload(feedbackNote: ''),
        postPayload: _submittedPayload(feedbackNote: ''),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: DriverRatingPage(
            gateway: ApiDriverRatingGateway(apiGateway: api),
            tripReference: 'TRIP-DUPLICATE-200',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('driver-rating-submitted')), findsOneWidget);
      expect(find.byKey(const Key('driver-rating-score-card')), findsOneWidget);
      expect(
        find.byKey(const Key('driver-rating-feedback-summary')),
        findsNothing,
      );
      expect(find.text('Your feedback'), findsNothing);
      expect(find.byKey(const Key('driver-rating-form')), findsNothing);
      expect(find.byKey(const Key('submit-driver-rating')), findsNothing);
      expect(
        find.byKey(const Key('driver-rating-back-to-trip')),
        findsOneWidget,
      );
      expect(api.postCalls, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'duplicate HTTP 200 submit becomes read-only without retry or exception',
      (tester) async {
        final api = _ScriptedDriverRatingApi(
          getPayload: _unsubmittedPayload(),
          postPayload: _submittedPayload(),
          postStatusCode: 200,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: DriverRatingPage(
              gateway: ApiDriverRatingGateway(apiGateway: api),
              tripReference: 'TRIP-DUPLICATE-200',
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('driver-rating-form')), findsOneWidget);

        await tester.tap(find.byKey(const Key('Overall-5')));
        await tester.tap(find.byKey(const Key('Comfort-4')));
        await tester.tap(find.byKey(const Key('Conduct-5')));
        await tester.tap(find.byKey(const Key('Cleanliness-5')));
        await tester.enterText(
          find.byKey(const Key('driver-rating-feedback')),
          'Already submitted',
        );
        await tester.tap(find.byKey(const Key('submit-driver-rating')));
        await tester.pumpAndSettle();

        expect(api.getCalls, 1);
        expect(api.postCalls, 1);
        expect(
          find.byKey(const Key('driver-rating-submitted')),
          findsOneWidget,
        );
        expect(find.text('Rating submitted'), findsOneWidget);
        expect(find.byKey(const Key('driver-rating-form')), findsNothing);
        expect(find.byKey(const Key('submit-driver-rating')), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('GET failure does not expose an editable rating form', (
      tester,
    ) async {
      final api = _ScriptedDriverRatingApi(
        getPayload: _unsubmittedPayload(),
        postPayload: _submittedPayload(),
        getError: const AsmApiException(
          type: AsmApiExceptionType.server,
          message: 'Synthetic rating load failure.',
          statusCode: 500,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: DriverRatingPage(
            gateway: ApiDriverRatingGateway(apiGateway: api),
            tripReference: 'TRIP-GET-FAILURE',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('driver-rating-load-error')), findsOneWidget);
      expect(find.text('Rating could not be loaded.'), findsOneWidget);
      expect(find.byKey(const Key('driver-rating-form')), findsNothing);
      expect(find.byKey(const Key('submit-driver-rating')), findsNothing);
      expect(api.getCalls, 1);
      expect(api.postCalls, 0);
      expect(tester.takeException(), isNull);
    });
  });
}

Map<String, Object?> _unsubmittedPayload() {
  return <String, Object?>{
    'trip_reference': 'TRIP-DUPLICATE-200',
    'submitted': false,
    'rating': null,
  };
}

Map<String, Object?> _submittedPayload({
  String feedbackNote = 'Good passenger',
}) {
  return <String, Object?>{
    'trip_reference': 'TRIP-DUPLICATE-200',
    'submitted': true,
    'rating': <String, Object?>{
      'overall_score': 5,
      'comfort_score': 4,
      'conduct_score': 5,
      'cleanliness_score': 5,
      'feedback_note': feedbackNote,
      'submitted_at': '2026-09-09T00:00:00Z',
    },
  };
}

final class _ScriptedDriverRatingApi implements DriverRatingApiGateway {
  _ScriptedDriverRatingApi({
    required this.getPayload,
    required this.postPayload,
    this.postStatusCode = 201,
    this.getError,
  });

  final Object? getPayload;
  final Object? postPayload;
  final int postStatusCode;
  final AsmApiException? getError;

  int getCalls = 0;
  int postCalls = 0;

  @override
  Future<ApiResponse<T>> get<T>(String path, {JsonDecoder<T>? decoder}) async {
    getCalls += 1;

    if (getError != null) {
      return ApiResponse<T>.apiFailure(getError!);
    }

    final decoded = decoder!(getPayload);
    return ApiResponse<T>.success(decoded, statusCode: 200);
  }

  @override
  Future<ApiResponse<T>> post<T>(
    String path, {
    Object? data,
    JsonDecoder<T>? decoder,
  }) async {
    postCalls += 1;

    final decoded = decoder!(postPayload);
    return ApiResponse<T>.success(decoded, statusCode: postStatusCode);
  }
}
