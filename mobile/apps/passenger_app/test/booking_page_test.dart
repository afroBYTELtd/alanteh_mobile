import 'dart:async';

import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_auth/asm_auth.dart';
import 'package:asm_app_config/asm_app_config.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:asm_ride_domain/asm_ride_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passenger_app/booking/booking_draft.dart';
import 'package:passenger_app/booking/booking_page.dart';
import 'package:passenger_app/booking/booking_submission.dart';
import 'package:passenger_app/main.dart';

void main() {
  testWidgets('renders simplified booking form without service context', (
    tester,
  ) async {
    _useSurface(tester, const Size(430, 1000));
    await tester.pumpWidget(_bookingTestApp());

    expect(find.text('Book a ride'), findsWidgets);
    expect(find.text('Where are you?'), findsOneWidget);
    expect(find.text('Where to?'), findsOneWidget);
    expect(find.text('How many passengers?'), findsOneWidget);
    expect(find.text('Special request (optional)'), findsOneWidget);
    expect(find.text('Request ride'), findsOneWidget);
    expect(find.byKey(const Key('booking-service-context')), findsNothing);
    expect(find.text('Approved service context'), findsNothing);

    expect(find.byKey(const Key('booking-pickup')), findsOneWidget);
    expect(find.byKey(const Key('booking-destination')), findsOneWidget);
    expect(find.byKey(const Key('booking-assistance')), findsOneWidget);
    expect(find.byKey(const Key('passenger-count-decrease')), findsOneWidget);
    expect(find.byKey(const Key('passenger-count-increase')), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('passenger-count-decrease')))
          .onPressed,
      isNull,
    );

    for (var count = 2; count <= 6; count++) {
      await tester.tap(find.byKey(const Key('passenger-count-increase')));
      await tester.pumpAndSettle();
    }

    expect(find.text('6'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('passenger-count-increase')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('keeps empty booking validation in passenger language', (
    tester,
  ) async {
    _useSurface(tester, const Size(430, 1000));
    await tester.pumpWidget(_bookingTestApp());

    await tester.ensureVisible(find.byKey(const Key('request-ride')));
    await tester.tap(find.byKey(const Key('request-ride')));
    await tester.pumpAndSettle();

    expect(find.text('Enter pickup location.'), findsOneWidget);
    expect(find.text('Enter destination.'), findsOneWidget);
    expect(find.text('Choose an approved service context.'), findsNothing);
    expect(find.text('No ride request has been sent.'), findsNothing);
  });

  test('booking draft rejects passenger counts outside accepted range', () {
    for (final passengerCount in <int>[0, 7]) {
      expect(
        () => BookingDraft(
          marketCode: MarketConfig.ghanaAccra.marketCode,
          serviceContext: RideServiceContextCode.otherApprovedRequest,
          pickupDescription: 'Osu',
          destinationDescription: 'Airport',
          passengerCount: passengerCount,
        ),
        throwsA(
          isA<BookingDraftValidationException>().having(
            (error) => error.message,
            'message',
            'Passenger count must be between 1 and 6.',
          ),
        ),
      );
    }
  });

  testWidgets(
    'local validation blocks invalid ride request before network request',
    (tester) async {
      _useSurface(tester, const Size(430, 1000));
      final submitter = _FakeRideRequestSubmitter.success();
      await tester.pumpWidget(_bookingTestApp(submitter: submitter));

      await tester.ensureVisible(find.byKey(const Key('request-ride')));
      await tester.tap(find.byKey(const Key('request-ride')));
      await tester.pumpAndSettle();

      expect(find.text('Enter pickup location.'), findsOneWidget);
      expect(find.text('Enter destination.'), findsOneWidget);
      expect(submitter.submissions, isEmpty);
      expect(find.text('Ride request received'), findsNothing);

      final tooLongPickup = _repeatedText(241, 'P');
      await tester.enterText(
        find.byKey(const Key('booking-pickup')),
        tooLongPickup,
      );
      await tester.enterText(
        find.byKey(const Key('booking-destination')),
        'Airport',
      );
      await tester.ensureVisible(find.byKey(const Key('request-ride')));
      await tester.tap(find.byKey(const Key('request-ride')));
      await tester.pumpAndSettle();

      expect(find.text('Pickup location is too long.'), findsOneWidget);
      expect(submitter.submissions, isEmpty);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('booking-pickup')))
            .controller!
            .text,
        tooLongPickup,
      );

      final tooLongDestination = _repeatedText(241, 'D');
      await tester.enterText(find.byKey(const Key('booking-pickup')), 'Osu');
      await tester.enterText(
        find.byKey(const Key('booking-destination')),
        tooLongDestination,
      );
      await tester.ensureVisible(find.byKey(const Key('request-ride')));
      await tester.tap(find.byKey(const Key('request-ride')));
      await tester.pumpAndSettle();

      expect(find.text('Destination is too long.'), findsOneWidget);
      expect(submitter.submissions, isEmpty);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('booking-destination')))
            .controller!
            .text,
        tooLongDestination,
      );

      final tooLongAssistance = _repeatedText(1001, 'A');
      await tester.enterText(
        find.byKey(const Key('booking-destination')),
        'Airport',
      );
      await tester.enterText(
        find.byKey(const Key('booking-assistance')),
        tooLongAssistance,
      );
      await tester.ensureVisible(find.byKey(const Key('request-ride')));
      await tester.tap(find.byKey(const Key('request-ride')));
      await tester.pumpAndSettle();

      expect(find.text('Special request is too long.'), findsOneWidget);
      expect(submitter.submissions, isEmpty);
      expect(find.text('Ride request received'), findsNothing);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('booking-assistance')))
            .controller!
            .text,
        tooLongAssistance,
      );
    },
  );

  testWidgets('accepts values above old caps and opens review', (tester) async {
    _useSurface(tester, const Size(430, 1000));
    final submitter = _FakeRideRequestSubmitter.success();
    final pickup = _repeatedText(161, 'P');
    final destination = _repeatedText(161, 'D');
    final assistance = _repeatedText(241, 'A');

    await tester.pumpWidget(_bookingTestApp(submitter: submitter));

    await tester.enterText(
      find.byKey(const Key('booking-pickup')),
      '  $pickup  ',
    );
    await tester.enterText(
      find.byKey(const Key('booking-destination')),
      '  $destination  ',
    );
    await tester.enterText(
      find.byKey(const Key('booking-assistance')),
      '  $assistance  ',
    );
    await tester.ensureVisible(find.byKey(const Key('request-ride')));
    await tester.tap(find.byKey(const Key('request-ride')));
    await tester.pumpAndSettle();

    expect(find.text('Pickup location is too long.'), findsNothing);
    expect(find.text('Destination is too long.'), findsNothing);
    expect(find.text('Special request is too long.'), findsNothing);
    expect(find.text('Confirm your ride'), findsWidgets);
    expect(find.text('Pickup'), findsOneWidget);
    expect(find.text('Destination'), findsOneWidget);
    expect(find.text('Passenger count'), findsOneWidget);
    expect(submitter.submissions, isEmpty);
  });

  testWidgets('successful request shows start new request and resets form', (
    tester,
  ) async {
    _useSurface(tester, const Size(430, 1000));
    final submitter = _FakeRideRequestSubmitter.success();
    final keys = <String>['APP-M2J-FIRST', 'APP-M2J-SECOND'];
    var keyIndex = 0;

    await tester.pumpWidget(
      _bookingTestApp(
        submitter: submitter,
        idempotencyKeyFactory: () => keys[keyIndex++],
      ),
    );

    await tester.enterText(
      find.byKey(const Key('booking-pickup')),
      '  Osu pickup point  ',
    );
    await tester.enterText(
      find.byKey(const Key('booking-destination')),
      '  Accra Mall  ',
    );
    await tester.enterText(
      find.byKey(const Key('booking-assistance')),
      '  Please call on arrival.  ',
    );

    final dynamic firstForm = tester.widget(
      find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == 'BookingForm',
      ),
    );
    firstForm.onPassengerCountChanged(3);
    await tester.pump();

    await tester.ensureVisible(find.byKey(const Key('request-ride')));
    await tester.tap(find.byKey(const Key('request-ride')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('confirm-and-request')));
    await tester.tap(find.byKey(const Key('confirm-and-request')));
    await tester.pumpAndSettle();

    expect(find.text('Ride request received'), findsOneWidget);
    expect(find.text('Reference: RR-APP-3A9F1C2B4E5D'), findsOneWidget);
    expect(find.text('Status: requested'), findsOneWidget);
    expect(
      find.text('Ride request received by the Control Center.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('start-new-request')), findsOneWidget);
    expect(find.byKey(const Key('confirm-and-request')), findsNothing);
    expect(submitter.submissions, hasLength(1));
    expect(submitter.submissions.single.passengerCount.value, 3);
    expect(submitter.idempotencyKeys, <String>['APP-M2J-FIRST']);

    await tester.tap(find.byKey(const Key('ride-request-success')));
    await tester.pumpAndSettle();

    expect(submitter.submissions, hasLength(1));
    expect(submitter.idempotencyKeys, <String>['APP-M2J-FIRST']);

    await tester.ensureVisible(find.byKey(const Key('start-new-request')));
    await tester.tap(find.byKey(const Key('start-new-request')));
    await tester.pumpAndSettle();

    expect(find.text('Ride request received'), findsNothing);
    expect(find.text('Reference: RR-APP-3A9F1C2B4E5D'), findsNothing);
    expect(find.byKey(const Key('booking-pickup')), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('booking-pickup')))
          .controller!
          .text,
      '',
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('booking-destination')))
          .controller!
          .text,
      '',
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('booking-assistance')))
          .controller!
          .text,
      '',
    );

    final dynamic resetForm = tester.widget(
      find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == 'BookingForm',
      ),
    );
    expect(resetForm.passengerCount, 1);

    await tester.enterText(
      find.byKey(const Key('booking-pickup')),
      'Cantonments',
    );
    await tester.enterText(
      find.byKey(const Key('booking-destination')),
      'Labadi',
    );
    await tester.ensureVisible(find.byKey(const Key('request-ride')));
    await tester.tap(find.byKey(const Key('request-ride')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('confirm-and-request')));
    await tester.tap(find.byKey(const Key('confirm-and-request')));
    await tester.pumpAndSettle();

    expect(find.text('Ride request received'), findsOneWidget);
    expect(submitter.submissions, hasLength(2));
    expect(submitter.submissions.last.pickupDescription.value, 'Cantonments');
    expect(submitter.submissions.last.destinationDescription.value, 'Labadi');
    expect(submitter.submissions.last.passengerCount.value, 1);
    expect(submitter.submissions.last.assistanceNote, isNull);
    expect(submitter.idempotencyKeys, <String>[
      'APP-M2J-FIRST',
      'APP-M2J-SECOND',
    ]);
  });

  testWidgets('success receipt copies only the backend request reference', (
    tester,
  ) async {
    _useSurface(tester, const Size(430, 1000));
    final submitter = _FakeRideRequestSubmitter.success();
    final copiedTexts = <String>[];

    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (methodCall) async {
        if (methodCall.method == 'Clipboard.setData') {
          final data = methodCall.arguments as Map<Object?, Object?>;
          copiedTexts.add(data['text']! as String);
        }

        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(_bookingTestApp(submitter: submitter));
    await tester.enterText(
      find.byKey(const Key('booking-pickup')),
      'Osu pickup point',
    );
    await tester.enterText(
      find.byKey(const Key('booking-destination')),
      'Accra Mall',
    );
    await tester.ensureVisible(find.byKey(const Key('request-ride')));
    await tester.tap(find.byKey(const Key('request-ride')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('confirm-and-request')));
    await tester.tap(find.byKey(const Key('confirm-and-request')));
    await tester.pumpAndSettle();

    expect(find.text('Ride request received'), findsOneWidget);
    expect(find.text('Reference: RR-APP-3A9F1C2B4E5D'), findsOneWidget);
    expect(
      find.text(
        'Keep this reference. The Control Center can use it to follow up.',
      ),
      findsOneWidget,
    );
    expect(find.text('Copy reference'), findsOneWidget);
    expect(find.text('Reference copied.'), findsNothing);

    await tester.ensureVisible(
      find.byKey(const Key('copy-ride-request-reference')),
    );
    await tester.tap(find.byKey(const Key('copy-ride-request-reference')));
    await tester.pumpAndSettle();

    expect(copiedTexts, <String>['RR-APP-3A9F1C2B4E5D']);
    expect(copiedTexts.single, isNot(contains('Osu pickup point')));
    expect(copiedTexts.single, isNot(contains('Accra Mall')));
    expect(copiedTexts.single, isNot(contains('passenger-access-token')));
    expect(copiedTexts.single, isNot(contains('https://')));
    expect(find.text('Reference copied.'), findsOneWidget);
  });

  testWidgets(
    'malformed success response does not show receipt copy controls',
    (tester) async {
      _useSurface(tester, const Size(430, 1000));
      final submitter = _FakeRideRequestSubmitter.success(
        result: const PassengerRideRequestResult(
          status: 'requested',
          message: 'Ride request received by the Control Center.',
        ),
      );

      await tester.pumpWidget(_bookingTestApp(submitter: submitter));
      await _enterValidBooking(tester);
      await tester.tap(find.byKey(const Key('request-ride')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-and-request')));
      await tester.pumpAndSettle();

      expect(find.text('Ride request received'), findsNothing);
      expect(find.text('Copy reference'), findsNothing);
      expect(find.text('Reference copied.'), findsNothing);
      expect(
        find.text(
          'Keep this reference. The Control Center can use it to follow up.',
        ),
        findsNothing,
      );
      expect(
        find.text(PassengerRideRequestSubmissionException.unknownErrorMessage),
        findsOneWidget,
      );
    },
  );

  for (final safeErrorCase
      in <MapEntry<String, PassengerRideRequestSubmissionException>>[
        MapEntry<String, PassengerRideRequestSubmissionException>(
          '403',
          const PassengerRideRequestSubmissionException(
            PassengerRideRequestSubmissionException.passengerRequiredMessage,
          ),
        ),
        MapEntry<String, PassengerRideRequestSubmissionException>(
          '409',
          const PassengerRideRequestSubmissionException(
            PassengerRideRequestSubmissionException.idempotencyConflictMessage,
          ),
        ),
        MapEntry<String, PassengerRideRequestSubmissionException>(
          '503',
          const PassengerRideRequestSubmissionException.serverUnavailable(),
        ),
        MapEntry<String, PassengerRideRequestSubmissionException>(
          'unknown',
          const PassengerRideRequestSubmissionException.unknown(),
        ),
      ]) {
    testWidgets('\${safeErrorCase.key} safe error keeps entered ride details', (
      tester,
    ) async {
      _useSurface(tester, const Size(430, 1000));
      final submitter = _FakeRideRequestSubmitter.failure(safeErrorCase.value);

      await tester.pumpWidget(_bookingTestApp(submitter: submitter));
      await tester.enterText(
        find.byKey(const Key('booking-pickup')),
        'Makola Market',
      );
      await tester.enterText(
        find.byKey(const Key('booking-destination')),
        'Labadi Beach',
      );
      await tester.enterText(
        find.byKey(const Key('booking-assistance')),
        'Keep the boot clear.',
      );

      final dynamic form = tester.widget(
        find.byWidgetPredicate(
          (widget) => widget.runtimeType.toString() == 'BookingForm',
        ),
      );
      form.onPassengerCountChanged(4);
      await tester.pump();

      await tester.ensureVisible(find.byKey(const Key('request-ride')));
      await tester.tap(find.byKey(const Key('request-ride')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('confirm-and-request')));
      await tester.tap(find.byKey(const Key('confirm-and-request')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ride-request-error')), findsOneWidget);
      expect(find.text(safeErrorCase.value.message), findsOneWidget);
      expect(find.text('Makola Market'), findsOneWidget);
      expect(find.text('Labadi Beach'), findsOneWidget);
      expect(find.text('Keep the boot clear.'), findsOneWidget);
      expect(submitter.submissions, hasLength(1));

      await tester.ensureVisible(find.byKey(const Key('edit-booking-details')));
      await tester.tap(find.byKey(const Key('edit-booking-details')));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('booking-pickup')))
            .controller!
            .text,
        'Makola Market',
      );
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('booking-destination')))
            .controller!
            .text,
        'Labadi Beach',
      );
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('booking-assistance')))
            .controller!
            .text,
        'Keep the boot clear.',
      );

      final dynamic editedForm = tester.widget(
        find.byWidgetPredicate(
          (widget) => widget.runtimeType.toString() == 'BookingForm',
        ),
      );
      expect(editedForm.passengerCount, 4);
    });
  }

  test(
    'api submitter sends CC4B request fields and never service context',
    () async {
      final client = _RecordingApiClient();
      final submitter = ApiPassengerRideRequestSubmitter(
        client,
        connectionConfigured: true,
      );
      final pickup = _repeatedText(240, 'P');
      final destination = _repeatedText(240, 'D');
      final assistance = _repeatedText(1000, 'A');

      await submitter.submit(
        BookingDraft(
          marketCode: MarketConfig.ghanaAccra.marketCode,
          serviceContext: RideServiceContextCode.otherApprovedRequest,
          pickupDescription: '  $pickup  ',
          destinationDescription: '  $destination  ',
          passengerCount: 6,
          assistanceNote: '  $assistance  ',
        ),
        idempotencyKey: 'APP-11111111-2222-4333-8444-555555555555',
      );

      final body = client.lastSubmission!.toJson();
      expect(body['pickup_location'], pickup);
      expect(body['destination'], destination);
      expect(body['passenger_count'], 6);
      expect(body['assistance_note'], assistance);
      expect(body.containsKey('service_context'), isFalse);
    },
  );

  test(
    'api submitter omits empty assistance note and service context',
    () async {
      final client = _RecordingApiClient();
      final submitter = ApiPassengerRideRequestSubmitter(
        client,
        connectionConfigured: true,
      );

      await submitter.submit(
        BookingDraft(
          marketCode: MarketConfig.ghanaAccra.marketCode,
          serviceContext: RideServiceContextCode.otherApprovedRequest,
          pickupDescription: 'Osu',
          destinationDescription: 'Airport',
          passengerCount: 1,
          assistanceNote: '   ',
        ),
        idempotencyKey: 'APP-22222222-3333-4333-8444-555555555555',
      );

      final body = client.lastSubmission!.toJson();
      expect(body['pickup_location'], 'Osu');
      expect(body['destination'], 'Airport');
      expect(body['passenger_count'], 1);
      expect(body.containsKey('assistance_note'), isFalse);
      expect(body.containsKey('service_context'), isFalse);
    },
  );

  testWidgets('validates locations and completes simplified booking flow', (
    tester,
  ) async {
    _useSurface(tester, const Size(430, 1000));
    final submitter = _FakeRideRequestSubmitter.success();
    await tester.pumpWidget(
      PassengerApp(
        configuration: _localQaEnabledConfig,
        rideRequestSubmitter: submitter,
      ),
    );

    FilledButton continueButton() => tester.widget<FilledButton>(
      find.byKey(const Key('continue-local-draft')),
    );
    IconButton swapButton() =>
        tester.widget<IconButton>(find.byKey(const Key('swap-route')));

    expect(continueButton().onPressed, isNull);
    expect(swapButton().onPressed, isNull);
    expect(find.byKey(const Key('clear-route')), findsNothing);
    expect(find.text('Book a ride'), findsOneWidget);
    expect(find.text('Where are you?'), findsOneWidget);

    await _selectLocation(
      tester,
      controlKey: 'choose-pickup',
      description: '  Solar Hotel  ',
    );
    expect(find.text('Solar Hotel'), findsOneWidget);
    expect(continueButton().onPressed, isNull);
    expect(swapButton().onPressed, isNull);
    expect(find.byKey(const Key('clear-route')), findsOneWidget);

    await tester.tap(find.byKey(const Key('choose-destination')));
    await tester.pumpAndSettle();
    expect(find.text('Recent this session'), findsOneWidget);
    expect(find.byKey(const Key('recent-location-0')), findsOneWidget);
    expect(find.text('Solar Hotel'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('location-description')),
      'solar hotel',
    );
    await tester.tap(find.byKey(const Key('use-location-description')));
    await tester.pumpAndSettle();

    expect(
      find.text('Pickup and destination must be different.'),
      findsOneWidget,
    );
    expect(continueButton().onPressed, isNull);

    await tester.tap(find.byKey(const Key('choose-destination')));
    await tester.pumpAndSettle();
    expect(find.text('Ghana'), findsOneWidget);
    expect(
      find.text('Local description only. No map search is connected.'),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const Key('location-description')),
      'Accra Airport',
    );
    await tester.tap(find.byKey(const Key('use-location-description')));
    await tester.pumpAndSettle();

    expect(continueButton().onPressed, isNotNull);
    expect(swapButton().onPressed, isNotNull);

    await tester.tap(find.byKey(const Key('swap-route')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const Key('choose-pickup')),
        matching: find.text('Accra Airport'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('choose-destination')),
        matching: find.text('Solar Hotel'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('swap-route')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('continue-local-draft')));
    await tester.pumpAndSettle();

    expect(find.text('Book a ride'), findsWidgets);
    expect(find.text('Where are you?'), findsOneWidget);
    expect(find.text('Where to?'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('booking-pickup')))
          .controller!
          .text,
      'Solar Hotel',
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('booking-destination')))
          .controller!
          .text,
      'Accra Airport',
    );

    await tester.tap(find.byKey(const Key('passenger-count-increase')));
    await tester.enterText(
      find.byKey(const Key('booking-assistance')),
      'Step-free access',
    );
    await tester.ensureVisible(find.byKey(const Key('request-ride')));
    await tester.tap(find.byKey(const Key('request-ride')));
    await tester.pumpAndSettle();

    expect(find.text('Confirm your ride'), findsWidgets);
    expect(find.text('Pickup'), findsOneWidget);
    expect(find.text('Destination'), findsOneWidget);
    expect(find.text('Passenger count'), findsOneWidget);
    expect(find.text('Payment method'), findsOneWidget);
    expect(find.text('MTN MoMo'), findsOneWidget);
    expect(find.text('Edit details'), findsOneWidget);
    expect(find.text('Confirm and request'), findsOneWidget);
    expect(find.text('Solar Hotel'), findsOneWidget);
    expect(find.text('Accra Airport'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('Step-free access'), findsOneWidget);
    expect(find.text('Service context'), findsNothing);
    expect(find.text('Operating market'), findsNothing);
    expect(find.text('Close draft'), findsNothing);

    await tester.ensureVisible(find.byKey(const Key('edit-booking-details')));
    await tester.tap(find.byKey(const Key('edit-booking-details')));
    await tester.pumpAndSettle();
    expect(find.text('Request ride'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('booking-pickup')))
          .controller!
          .text,
      'Solar Hotel',
    );

    await tester.ensureVisible(find.byKey(const Key('request-ride')));
    await tester.tap(find.byKey(const Key('request-ride')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('confirm-and-request')));
    await tester.tap(find.byKey(const Key('confirm-and-request')));
    await tester.pumpAndSettle();

    expect(find.text('Ride request received'), findsOneWidget);
    expect(
      find.text('Ride request received by the Control Center.'),
      findsOneWidget,
    );
    expect(find.text('Reference: RR-APP-3A9F1C2B4E5D'), findsOneWidget);
    expect(find.text('Status: requested'), findsOneWidget);
    expect(
      find.text('Ride request received by the Control Center.'),
      findsOneWidget,
    );
    expect(submitter.submissions, hasLength(1));
    expect(submitter.submissions.single.pickupDescription.value, 'Solar Hotel');
    expect(
      submitter.submissions.single.destinationDescription.value,
      'Accra Airport',
    );
    expect(submitter.submissions.single.passengerCount.value, 2);
    expect(
      submitter.submissions.single.assistanceNote?.value,
      'Step-free access',
    );
    expect(submitter.idempotencyKeys.single.startsWith('APP-'), isTrue);

    await tester.tap(find.byKey(const Key('finish-ride-request')));
    await tester.pumpAndSettle();

    expect(find.text('Map preview unavailable.'), findsOneWidget);
    expect(find.text('Book a ride'), findsOneWidget);
    expect(find.text('Where are you?'), findsOneWidget);
    expect(find.text('Where to?'), findsOneWidget);
    expect(find.text('Solar Hotel'), findsNothing);
    expect(find.text('Accra Airport'), findsNothing);
  });

  testWidgets('confirm and request shows loading then success', (tester) async {
    _useSurface(tester, const Size(430, 1000));
    final submitter = _FakeRideRequestSubmitter.pending();

    await tester.pumpWidget(
      _bookingTestApp(
        submitter: submitter,
        idempotencyKeyFactory: () => 'APP-11111111-2222-4333-8444-555555555555',
      ),
    );

    await _enterValidBooking(tester);
    await tester.tap(find.byKey(const Key('request-ride')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('confirm-and-request')));
    await tester.pump();

    expect(find.byKey(const Key('ride-request-loading')), findsOneWidget);
    expect(
      find.byKey(const Key('ride-request-loading-message')),
      findsOneWidget,
    );
    expect(find.text('Sending request...'), findsWidgets);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('confirm-and-request')))
          .onPressed,
      isNull,
    );

    await tester.tap(find.byKey(const Key('confirm-and-request')));
    await tester.pump();

    expect(submitter.submissions, hasLength(1));
    expect(submitter.idempotencyKeys, [
      'APP-11111111-2222-4333-8444-555555555555',
    ]);

    submitter.completeSuccess(
      const PassengerRideRequestResult(
        requestReference: 'RR-APP-3A9F1C2B4E5D',
        status: 'requested',
        message: 'Ride request received by the Control Center.',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ride request received'), findsOneWidget);
    expect(find.text('Reference: RR-APP-3A9F1C2B4E5D'), findsOneWidget);
    expect(find.text('Status: requested'), findsOneWidget);
    expect(
      find.text('Ride request received by the Control Center.'),
      findsOneWidget,
    );
    expect(submitter.idempotencyKeys, [
      'APP-11111111-2222-4333-8444-555555555555',
    ]);
  });

  testWidgets('malformed success response does not show fake success', (
    tester,
  ) async {
    _useSurface(tester, const Size(430, 1000));
    final submitter = _FakeRideRequestSubmitter.success(
      result: const PassengerRideRequestResult(
        status: 'requested',
        message: 'Ride request received by the Control Center.',
      ),
    );

    await tester.pumpWidget(_bookingTestApp(submitter: submitter));
    await _enterValidBooking(tester);
    await tester.tap(find.byKey(const Key('request-ride')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-and-request')));
    await tester.pumpAndSettle();

    expect(find.text('Ride request received'), findsNothing);
    expect(find.byKey(const Key('ride-request-reference')), findsNothing);
    expect(find.textContaining('RR-APP'), findsNothing);
    expect(find.byKey(const Key('ride-request-error')), findsOneWidget);
    expect(
      find.text('Something went wrong. Please try again.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'ride request timeout keeps details and retry reuses idempotency key',
    (tester) async {
      _useSurface(tester, const Size(430, 1000));
      final submitter = _FakeRideRequestSubmitter.timeoutThenSucceed();

      await tester.pumpWidget(
        _bookingTestApp(
          submitter: submitter,
          idempotencyKeyFactory: () => 'APP-timeout-retry-same-key',
        ),
      );

      await tester.enterText(find.byKey(const Key('booking-pickup')), 'Osu');
      await tester.enterText(
        find.byKey(const Key('booking-destination')),
        'Airport',
      );
      await tester.enterText(
        find.byKey(const Key('booking-assistance')),
        'Please call on arrival.',
      );

      await tester.ensureVisible(find.byKey(const Key('request-ride')));
      await tester.tap(find.byKey(const Key('request-ride')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('confirm-and-request')));
      await tester.tap(find.byKey(const Key('confirm-and-request')));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Cannot reach the server. Check your connection and try again.',
        ),
        findsOneWidget,
      );
      expect(find.text('Ride request received'), findsNothing);
      expect(find.text('Osu'), findsOneWidget);
      expect(find.text('Airport'), findsOneWidget);
      expect(find.text('Please call on arrival.'), findsOneWidget);
      expect(find.textContaining('TimeoutException'), findsNothing);
      expect(submitter.idempotencyKeys, <String>['APP-timeout-retry-same-key']);

      await tester.ensureVisible(find.byKey(const Key('retry-ride-request')));
      await tester.tap(find.byKey(const Key('retry-ride-request')));
      await tester.pumpAndSettle();

      expect(find.text('Ride request received'), findsOneWidget);
      expect(submitter.idempotencyKeys, <String>[
        'APP-timeout-retry-same-key',
        'APP-timeout-retry-same-key',
      ]);
    },
  );

  testWidgets('network failure shows retry and reuses idempotency key', (
    tester,
  ) async {
    _useSurface(tester, const Size(430, 1000));
    final submitter = _FakeRideRequestSubmitter.failThenSucceed();

    await tester.pumpWidget(
      _bookingTestApp(
        submitter: submitter,
        idempotencyKeyFactory: () => 'APP-aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
      ),
    );

    await _enterValidBooking(tester);
    await tester.tap(find.byKey(const Key('request-ride')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('confirm-and-request')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ride-request-error')), findsOneWidget);
    expect(
      find.text(
        'Cannot reach the server. Check your connection and try again.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Cannot reach the server. Check your connection and try again.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('retry-ride-request')), findsOneWidget);

    await tester.tap(find.byKey(const Key('retry-ride-request')));
    await tester.pumpAndSettle();

    expect(find.text('Ride request received'), findsOneWidget);
    expect(submitter.idempotencyKeys, [
      'APP-aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
      'APP-aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
    ]);
  });

  test('api submitter allows ride request when access token exists', () async {
    final store = MemoryAuthTokenStore();
    await store.saveTokens(
      AuthTokens(
        accessToken: 'stored-passenger-access',
        refreshToken: 'stored-passenger-refresh',
      ),
    );
    final client = _RecordingApiClient();
    final submitter = ApiPassengerRideRequestSubmitter(
      client,
      tokenStore: store,
    );

    final result = await submitter.submit(
      _validDraft(),
      idempotencyKey: 'APP-a1b2c3d4-e5f6-4890-abcd-ef0000067890',
    );

    expect(result.requestReference, 'RR-APP-3A9F1C2B4E5D');
    expect(client.wasCalled, isTrue);
    expect(
      client.lastSubmission?.idempotencyKey,
      'APP-a1b2c3d4-e5f6-4890-abcd-ef0000067890',
    );
    expect(client.lastSubmission?.pickupLocation, 'Osu');
    expect(client.lastSubmission?.destination, 'Airport');
    expect(client.lastSubmission?.passengerCount, 1);
    expect(
      client.lastSubmission?.toJson().containsKey('service_context'),
      isFalse,
    );
  });

  test('api submitter rejects malformed successful receipt', () async {
    final store = MemoryAuthTokenStore();
    await store.saveTokens(
      AuthTokens(
        accessToken: 'stored-passenger-access',
        refreshToken: 'stored-passenger-refresh',
      ),
    );
    final client = _RecordingApiClient(
      responses: <ApiResponse<PassengerRideRequestResult>>[
        ApiResponse.success(
          const PassengerRideRequestResult(
            status: 'requested',
            message: 'Ride request received by the Control Center.',
          ),
          statusCode: 201,
        ),
      ],
    );
    final submitter = ApiPassengerRideRequestSubmitter(
      client,
      tokenStore: store,
    );

    await expectLater(
      submitter.submit(_validDraft(), idempotencyKey: 'APP-malformed-success'),
      throwsA(
        isA<PassengerRideRequestSubmissionException>().having(
          (error) => error.message,
          'message',
          PassengerRideRequestSubmissionException.unknownErrorMessage,
        ),
      ),
    );
  });

  test(
    'api submitter blocks ride request when no access token exists',
    () async {
      final store = MemoryAuthTokenStore();
      final client = _RecordingApiClient();
      final submitter = ApiPassengerRideRequestSubmitter(
        client,
        tokenStore: store,
      );

      await expectLater(
        submitter.submit(
          _validDraft(),
          idempotencyKey: 'APP-aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
        ),
        throwsA(
          isA<PassengerRideRequestSubmissionException>()
              .having(
                (error) => error.message,
                'message',
                PassengerRideRequestSubmissionException.signInRequiredMessage,
              )
              .having(
                (error) => error.requiresSignIn,
                'requiresSignIn',
                isTrue,
              ),
        ),
      );

      expect(client.wasCalled, isFalse);
    },
  );

  test('api submitter allows ride request when access token exists', () async {
    final store = MemoryAuthTokenStore();
    await store.saveTokens(
      AuthTokens(
        accessToken: 'stored-passenger-access',
        refreshToken: 'stored-passenger-refresh',
      ),
    );
    final client = _RecordingApiClient();
    final submitter = ApiPassengerRideRequestSubmitter(
      client,
      tokenStore: store,
    );

    final result = await submitter.submit(
      _validDraft(),
      idempotencyKey: 'APP-a1b2c3d4-e5f6-4890-abcd-ef0000067890',
    );

    expect(result.requestReference, 'RR-APP-3A9F1C2B4E5D');
    expect(client.wasCalled, isTrue);
    expect(
      client.lastSubmission?.idempotencyKey,
      'APP-a1b2c3d4-e5f6-4890-abcd-ef0000067890',
    );
    expect(client.lastSubmission?.pickupLocation, 'Osu');
    expect(client.lastSubmission?.destination, 'Airport');
    expect(client.lastSubmission?.passengerCount, 1);
    expect(
      client.lastSubmission?.toJson().containsKey('service_context'),
      isFalse,
    );
  });

  test(
    'api submitter refreshes once and retries with same idempotency key',
    () async {
      final store = MemoryAuthTokenStore();
      await store.saveTokens(
        AuthTokens(
          accessToken: 'expired-passenger-access',
          refreshToken: 'stored-passenger-refresh',
        ),
      );
      final client = _RecordingApiClient(
        responses: <ApiResponse<PassengerRideRequestResult>>[
          ApiResponse.apiFailure(
            const AsmApiException(
              type: AsmApiExceptionType.authentication,
              message: 'Authentication credentials were not provided.',
              statusCode: 401,
            ),
          ),
          ApiResponse.success(
            const PassengerRideRequestResult(
              requestReference: 'RR-APP-3A9F1C2B4E5D',
              status: 'requested',
              message: 'Ride request received by the Control Center.',
            ),
            statusCode: 201,
          ),
        ],
      );
      final authApi = _RecordingAuthApiGateway(
        responseData: <String, Object?>{'access': 'new-passenger-access'},
      );
      final submitter = ApiPassengerRideRequestSubmitter(
        client,
        tokenStore: store,
        authService: AuthService(apiGateway: authApi, tokenStore: store),
      );

      final result = await submitter.submit(
        _validDraft(),
        idempotencyKey: 'APP-refresh-retry-same-key',
      );

      expect(result.requestReference, 'RR-APP-3A9F1C2B4E5D');
      expect(authApi.paths, <String>[AuthService.refreshPath]);
      expect(authApi.bodies.single, <String, Object?>{
        'refresh': 'stored-passenger-refresh',
      });
      expect(await store.readAccessToken(), 'new-passenger-access');
      expect(await store.readRefreshToken(), 'stored-passenger-refresh');
      expect(client.submissions, hasLength(2));
      expect(
        client.submissions.map((submission) => submission.idempotencyKey),
        ['APP-refresh-retry-same-key', 'APP-refresh-retry-same-key'],
      );
    },
  );

  test(
    'api submitter maps refresh timeout to safe message and does not retry ride request',
    () async {
      final store = MemoryAuthTokenStore();
      await store.saveTokens(
        AuthTokens(
          accessToken: 'expired-passenger-access',
          refreshToken: 'stored-passenger-refresh',
        ),
      );
      final client = _RecordingApiClient(
        responses: <ApiResponse<PassengerRideRequestResult>>[
          ApiResponse.apiFailure(
            const AsmApiException(
              type: AsmApiExceptionType.authentication,
              message: 'Authentication credentials were not provided.',
              statusCode: 401,
            ),
          ),
        ],
      );
      final authApi = _TimeoutAuthApiGateway();
      final submitter = ApiPassengerRideRequestSubmitter(
        client,
        tokenStore: store,
        authService: AuthService(apiGateway: authApi, tokenStore: store),
      );

      await expectLater(
        submitter.submit(_validDraft(), idempotencyKey: 'APP-refresh-timeout'),
        throwsA(
          isA<PassengerRideRequestSubmissionException>().having(
            (error) => error.message,
            'message',
            'Cannot reach the server. Check your connection and try again.',
          ),
        ),
      );

      expect(authApi.paths, <String>[AuthService.refreshPath]);
      expect(authApi.bodies.single, <String, Object?>{
        'refresh': 'stored-passenger-refresh',
      });
      expect(client.submissions, hasLength(1));
    },
  );

  test('api submitter clears tokens when 401 has no refresh token', () async {
    final store = _MutableAuthTokenStore(accessToken: 'expired-access');
    final client = _RecordingApiClient(
      responses: <ApiResponse<PassengerRideRequestResult>>[
        ApiResponse.apiFailure(
          const AsmApiException(
            type: AsmApiExceptionType.authentication,
            message: 'Authentication credentials were not provided.',
            statusCode: 401,
          ),
        ),
      ],
    );
    final submitter = ApiPassengerRideRequestSubmitter(
      client,
      tokenStore: store,
      authService: AuthService(
        apiGateway: _RecordingAuthApiGateway(),
        tokenStore: store,
      ),
    );

    await expectLater(
      submitter.submit(_validDraft(), idempotencyKey: 'APP-missing-refresh'),
      throwsA(
        isA<PassengerRideRequestSubmissionException>()
            .having(
              (error) => error.message,
              'message',
              PassengerRideRequestSubmissionException.signInRequiredMessage,
            )
            .having((error) => error.requiresSignIn, 'requiresSignIn', isTrue),
      ),
    );

    expect(client.submissions, hasLength(1));
    expect(await store.readAccessToken(), isNull);
    expect(await store.readRefreshToken(), isNull);
  });

  test('api submitter clears tokens when refresh fails', () async {
    final store = MemoryAuthTokenStore();
    await store.saveTokens(
      AuthTokens(
        accessToken: 'expired-passenger-access',
        refreshToken: 'stored-passenger-refresh',
      ),
    );
    final client = _RecordingApiClient(
      responses: <ApiResponse<PassengerRideRequestResult>>[
        ApiResponse.apiFailure(
          const AsmApiException(
            type: AsmApiExceptionType.authentication,
            message: 'Authentication credentials were not provided.',
            statusCode: 401,
          ),
        ),
      ],
    );
    final authApi = _RecordingAuthApiGateway(statusCode: 401);
    final submitter = ApiPassengerRideRequestSubmitter(
      client,
      tokenStore: store,
      authService: AuthService(apiGateway: authApi, tokenStore: store),
    );

    await expectLater(
      submitter.submit(_validDraft(), idempotencyKey: 'APP-refresh-fails'),
      throwsA(
        isA<PassengerRideRequestSubmissionException>()
            .having(
              (error) => error.message,
              'message',
              PassengerRideRequestSubmissionException.signInRequiredMessage,
            )
            .having((error) => error.requiresSignIn, 'requiresSignIn', isTrue),
      ),
    );

    expect(authApi.paths, <String>[AuthService.refreshPath]);
    expect(client.submissions, hasLength(1));
    expect(await store.readAccessToken(), isNull);
    expect(await store.readRefreshToken(), isNull);
  });

  test(
    'api submitter blocks ride request when API base URL is not configured',
    () async {
      final store = MemoryAuthTokenStore();
      await store.saveTokens(
        AuthTokens(
          accessToken: 'stored-passenger-access',
          refreshToken: 'stored-passenger-refresh',
        ),
      );
      final submitter = ApiPassengerRideRequestSubmitter.withDefaultClient(
        tokenStore: store,
      );

      await expectLater(
        submitter.submit(_validDraft(), idempotencyKey: 'APP-no-base-url'),
        throwsA(
          isA<PassengerRideRequestSubmissionException>()
              .having(
                (error) => error.message,
                'message',
                AsmApiClient.connectionNotConfiguredMessage,
              )
              .having(
                (error) => error.requiresSignIn,
                'requiresSignIn',
                isFalse,
              ),
        ),
      );
    },
  );

  test('api submitter maps 403 to passenger account required', () async {
    final store = MemoryAuthTokenStore();
    await store.saveTokens(
      AuthTokens(accessToken: 'access', refreshToken: 'refresh'),
    );
    final client = _RecordingApiClient(
      responses: <ApiResponse<PassengerRideRequestResult>>[
        ApiResponse.apiFailure(
          const AsmApiException(
            type: AsmApiExceptionType.badResponse,
            message: 'Raw backend 403 should not be visible.',
            statusCode: 403,
            cause: <String, Object?>{'detail': 'Raw forbidden detail'},
          ),
        ),
      ],
    );
    final submitter = ApiPassengerRideRequestSubmitter(
      client,
      tokenStore: store,
    );

    await expectLater(
      submitter.submit(_validDraft(), idempotencyKey: 'APP-403'),
      throwsA(
        isA<PassengerRideRequestSubmissionException>().having(
          (error) => error.message,
          'message',
          'Passenger account required.',
        ),
      ),
    );
  });

  test('api submitter maps 409 to safe idempotency conflict message', () async {
    final store = MemoryAuthTokenStore();
    await store.saveTokens(
      AuthTokens(accessToken: 'access', refreshToken: 'refresh'),
    );
    final client = _RecordingApiClient(
      responses: <ApiResponse<PassengerRideRequestResult>>[
        ApiResponse.apiFailure(
          const AsmApiException(
            type: AsmApiExceptionType.badResponse,
            message: 'Raw backend 409 should not be visible.',
            statusCode: 409,
            cause: <String, Object?>{'detail': 'Raw conflict detail'},
          ),
        ),
      ],
    );
    final submitter = ApiPassengerRideRequestSubmitter(
      client,
      tokenStore: store,
    );

    await expectLater(
      submitter.submit(_validDraft(), idempotencyKey: 'APP-409'),
      throwsA(
        isA<PassengerRideRequestSubmissionException>().having(
          (error) => error.message,
          'message',
          'This ride request was already used with different details. Please review and try again.',
        ),
      ),
    );
  });

  test('api submitter maps 503 to service unavailable message', () async {
    final store = MemoryAuthTokenStore();
    await store.saveTokens(
      AuthTokens(accessToken: 'access', refreshToken: 'refresh'),
    );
    final client = _RecordingApiClient(
      responses: <ApiResponse<PassengerRideRequestResult>>[
        ApiResponse.apiFailure(
          const AsmApiException(
            type: AsmApiExceptionType.server,
            message: 'Raw backend 503 should not be visible.',
            statusCode: 503,
          ),
        ),
      ],
    );
    final submitter = ApiPassengerRideRequestSubmitter(
      client,
      tokenStore: store,
    );

    await expectLater(
      submitter.submit(_validDraft(), idempotencyKey: 'APP-503'),
      throwsA(
        isA<PassengerRideRequestSubmissionException>().having(
          (error) => error.message,
          'message',
          'Service is temporarily unavailable. Please try again later.',
        ),
      ),
    );
  });

  test(
    'api submitter maps network failure to server reachability message',
    () async {
      final store = MemoryAuthTokenStore();
      await store.saveTokens(
        AuthTokens(accessToken: 'access', refreshToken: 'refresh'),
      );
      final client = _RecordingApiClient(
        responses: <ApiResponse<PassengerRideRequestResult>>[
          ApiResponse.clientException(
            const AsmApiException(
              type: AsmApiExceptionType.network,
              message: 'SocketException: raw technical network failure',
            ),
          ),
        ],
      );
      final submitter = ApiPassengerRideRequestSubmitter(
        client,
        tokenStore: store,
      );

      await expectLater(
        submitter.submit(_validDraft(), idempotencyKey: 'APP-network'),
        throwsA(
          isA<PassengerRideRequestSubmissionException>().having(
            (error) => error.message,
            'message',
            'Cannot reach the server. Check your connection and try again.',
          ),
        ),
      );
    },
  );

  test(
    'api submitter maps ride request timeout to server reachability message',
    () async {
      final store = MemoryAuthTokenStore();
      await store.saveTokens(
        AuthTokens(accessToken: 'access', refreshToken: 'refresh'),
      );
      final client = _RecordingApiClient(
        responses: <ApiResponse<PassengerRideRequestResult>>[
          ApiResponse.clientException(
            const AsmApiException(
              type: AsmApiExceptionType.timeout,
              message: 'TimeoutException: raw technical timeout',
            ),
          ),
        ],
      );
      final submitter = ApiPassengerRideRequestSubmitter(
        client,
        tokenStore: store,
      );

      await expectLater(
        submitter.submit(_validDraft(), idempotencyKey: 'APP-timeout'),
        throwsA(
          isA<PassengerRideRequestSubmissionException>().having(
            (error) => error.message,
            'message',
            'Cannot reach the server. Check your connection and try again.',
          ),
        ),
      );

      expect(client.submissions, hasLength(1));
    },
  );

  test('api submitter maps malformed response to safe fallback', () async {
    final store = MemoryAuthTokenStore();
    await store.saveTokens(
      AuthTokens(accessToken: 'access', refreshToken: 'refresh'),
    );
    final client = _RecordingApiClient(
      responses: <ApiResponse<PassengerRideRequestResult>>[
        ApiResponse.clientException(
          const AsmApiException(
            type: AsmApiExceptionType.badResponse,
            message: 'FormatException: raw malformed response',
          ),
        ),
      ],
    );
    final submitter = ApiPassengerRideRequestSubmitter(
      client,
      tokenStore: store,
    );

    await expectLater(
      submitter.submit(_validDraft(), idempotencyKey: 'APP-malformed'),
      throwsA(
        isA<PassengerRideRequestSubmissionException>().having(
          (error) => error.message,
          'message',
          'Something went wrong. Please try again.',
        ),
      ),
    );
  });

  test('api submitter accepts production API base URL without live HTTP', () {
    final store = MemoryAuthTokenStore();
    final submitter = ApiPassengerRideRequestSubmitter.withDefaultClient(
      tokenStore: store,
      baseUrl: 'https://control.alanteh.io',
    );

    expect(AsmApiBaseUrl.isUsable('https://control.alanteh.io'), isTrue);
    expect(submitter.client.baseUrl, 'https://control.alanteh.io');
    expect(submitter.connectionConfigured, isTrue);
  });

  test('api submitter uses configured API base URL', () {
    final store = MemoryAuthTokenStore();
    final submitter = ApiPassengerRideRequestSubmitter.withDefaultClient(
      tokenStore: store,
      baseUrl: 'https://example.test',
    );

    expect(submitter.client.baseUrl, 'https://example.test');
    expect(submitter.connectionConfigured, isTrue);
  });

  testWidgets('blocked ride request shows sign-in path', (tester) async {
    _useSurface(tester, const Size(430, 1000));
    var signInRequested = false;
    await tester.pumpWidget(
      _bookingTestApp(
        submitter: ApiPassengerRideRequestSubmitter.withDefaultClient(
          tokenStore: MemoryAuthTokenStore(),
        ),
        idempotencyKeyFactory: () => 'APP-11111111-2222-4333-8444-555555555555',
        onSignInRequired: () {
          signInRequested = true;
        },
      ),
    );

    await _enterValidBooking(tester);
    await tester.tap(find.byKey(const Key('request-ride')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-and-request')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ride-request-error')), findsOneWidget);
    expect(
      find.text(PassengerRideRequestSubmissionException.signInRequiredMessage),
      findsOneWidget,
    );
    expect(find.byKey(const Key('back-to-sign-in')), findsOneWidget);
    expect(find.byKey(const Key('retry-ride-request')), findsNothing);

    await tester.tap(find.byKey(const Key('back-to-sign-in')));
    await tester.pumpAndSettle();

    expect(signInRequested, isTrue);
  });

  testWidgets(
    'new request after completed success uses a new idempotency key',
    (tester) async {
      _useSurface(tester, const Size(430, 1000));
      final submitter = _FakeRideRequestSubmitter.success();
      var keyIndex = 0;
      final keys = <String>[
        'APP-first1111-2222-4333-8444-555555555555',
        'APP-second111-2222-4333-8444-555555555555',
      ];

      Future<void> completeRequest() async {
        await _enterValidBooking(tester);
        await tester.ensureVisible(find.byKey(const Key('request-ride')));
        await tester.tap(find.byKey(const Key('request-ride')));
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const Key('confirm-and-request')),
        );
        await tester.tap(find.byKey(const Key('confirm-and-request')));
        await tester.pumpAndSettle();
      }

      await tester.pumpWidget(
        _bookingTestApp(
          submitter: submitter,
          idempotencyKeyFactory: () => keys[keyIndex++],
        ),
      );
      await tester.pumpAndSettle();

      await completeRequest();

      expect(find.text('Ride request received'), findsOneWidget);
      expect(submitter.idempotencyKeys, <String>[keys.first]);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      await tester.pumpWidget(
        _bookingTestApp(
          submitter: submitter,
          idempotencyKeyFactory: () => keys[keyIndex++],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('booking-pickup')), findsOneWidget);

      await completeRequest();

      expect(find.text('Ride request received'), findsOneWidget);
      expect(submitter.idempotencyKeys, keys);
    },
  );

  testWidgets('clear route preserves session locations', (tester) async {
    _useSurface(tester, const Size(430, 1000));
    await tester.pumpWidget(
      const PassengerApp(configuration: _localQaEnabledConfig),
    );

    await _selectLocation(
      tester,
      controlKey: 'choose-pickup',
      description: 'Solar Hotel',
    );
    await _selectLocation(
      tester,
      controlKey: 'choose-destination',
      description: 'Accra Airport',
    );

    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('continue-local-draft')))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.byKey(const Key('clear-route')));
    await tester.pumpAndSettle();

    expect(find.text('Book a ride'), findsOneWidget);
    expect(find.text('Where are you?'), findsOneWidget);
    expect(find.text('Where to?'), findsOneWidget);
    expect(find.byKey(const Key('clear-route')), findsNothing);
    expect(
      tester.widget<IconButton>(find.byKey(const Key('swap-route'))).onPressed,
      isNull,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('continue-local-draft')))
          .onPressed,
      isNull,
    );

    await tester.tap(find.byKey(const Key('choose-pickup')));
    await tester.pumpAndSettle();
    expect(find.text('Recent this session'), findsOneWidget);
    expect(find.text('Solar Hotel'), findsOneWidget);
    expect(find.text('Accra Airport'), findsOneWidget);
  });

  testWidgets('removed internal booking wording stays absent', (tester) async {
    _useSurface(tester, const Size(430, 1000));
    await tester.pumpWidget(_bookingTestApp());

    for (final removedText in _removedPassengerTexts) {
      expect(find.text(removedText), findsNothing);
    }

    await tester.enterText(find.byKey(const Key('booking-pickup')), 'Osu');
    await tester.enterText(
      find.byKey(const Key('booking-destination')),
      'Airport',
    );
    await tester.ensureVisible(find.byKey(const Key('request-ride')));
    await tester.tap(find.byKey(const Key('request-ride')));
    await tester.pumpAndSettle();

    for (final removedText in _removedPassengerTexts) {
      expect(find.text(removedText), findsNothing);
    }
    for (final forbiddenText in _noLiveFeatureTexts) {
      expect(find.textContaining(forbiddenText), findsNothing);
    }
  });
}

const _removedPassengerTexts = [
  'Approved service context',
  'LOCAL DEMO',
  'Plan a demo ride',
  'Local draft',
  'local draft',
  'controlled pilot',
  'gh-accra',
  'This stays on this device',
  'No ride request has been sent',
  'Operating market',
  'Service context',
  'Close draft',
  'GHANA PILOT',
  'No ride service is connected',
];

const _noLiveFeatureTexts = [
  'request_reference',
  'Paystack',
  'GPS',
  'GoogleMap',
  'WebSocket',
];

String _repeatedText(int length, String character) {
  return List<String>.filled(length, character).join();
}

const _localQaEnabledConfig = AsmAppConfig(
  environment: RuntimeEnvironment.local,
  market: MarketConfig.ghanaAccra,
  capabilities: CapabilityConfig(),
  localQaEnabled: true,
);

Future<void> _selectLocation(
  WidgetTester tester, {
  required String controlKey,
  required String description,
}) async {
  await tester.tap(find.byKey(Key(controlKey)));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const Key('location-description')),
    description,
  );
  await tester.tap(find.byKey(const Key('use-location-description')));
  await tester.pumpAndSettle();
}

Future<void> _enterValidBooking(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('booking-pickup')), 'Osu');
  await tester.enterText(
    find.byKey(const Key('booking-destination')),
    'Airport',
  );
}

class _FakeRideRequestSubmitter implements PassengerRideRequestSubmitter {
  _FakeRideRequestSubmitter._({
    this.result = const PassengerRideRequestResult(
      requestReference: 'RR-APP-3A9F1C2B4E5D',
      status: 'requested',
      message: 'Ride request received by the Control Center.',
    ),
    this.failFirst = false,
    this.pending = false,
    this.failure,
  });

  factory _FakeRideRequestSubmitter.success({
    PassengerRideRequestResult result = const PassengerRideRequestResult(
      requestReference: 'RR-APP-3A9F1C2B4E5D',
      status: 'requested',
      message: 'Ride request received by the Control Center.',
    ),
  }) {
    return _FakeRideRequestSubmitter._(result: result);
  }

  factory _FakeRideRequestSubmitter.pending() {
    return _FakeRideRequestSubmitter._(pending: true);
  }

  factory _FakeRideRequestSubmitter.failThenSucceed() {
    return _FakeRideRequestSubmitter._(failFirst: true);
  }

  factory _FakeRideRequestSubmitter.timeoutThenSucceed() {
    return _FakeRideRequestSubmitter._(failFirst: true);
  }

  factory _FakeRideRequestSubmitter.failure(
    PassengerRideRequestSubmissionException failure,
  ) {
    return _FakeRideRequestSubmitter._(failure: failure);
  }

  final PassengerRideRequestResult result;
  final bool failFirst;
  final bool pending;
  final PassengerRideRequestSubmissionException? failure;
  final submissions = <BookingDraft>[];
  final idempotencyKeys = <String>[];
  Completer<PassengerRideRequestResult>? _completer;

  @override
  Future<PassengerRideRequestResult> submit(
    BookingDraft draft, {
    required String idempotencyKey,
  }) {
    submissions.add(draft);
    idempotencyKeys.add(idempotencyKey);

    if (pending) {
      _completer ??= Completer<PassengerRideRequestResult>();
      return _completer!.future;
    }

    final configuredFailure = failure;
    if (configuredFailure != null) {
      throw configuredFailure;
    }

    if (failFirst && submissions.length == 1) {
      throw const PassengerRideRequestSubmissionException(
        'Cannot reach the server. Check your connection and try again.',
      );
    }

    return Future<PassengerRideRequestResult>.value(result);
  }

  void completeSuccess(PassengerRideRequestResult value) {
    _completer?.complete(value);
  }
}

class _TimeoutAuthApiGateway implements AuthApiGateway {
  final paths = <String>[];
  final bodies = <Map<String, Object?>>[];

  @override
  Future<ApiResponse<Map<String, Object?>>> post(
    String path, {
    required Map<String, Object?> body,
  }) async {
    paths.add(path);
    bodies.add(Map<String, Object?>.of(body));

    return ApiResponse.clientException(
      const AsmApiException(
        type: AsmApiExceptionType.timeout,
        message: 'TimeoutException: raw technical refresh timeout',
      ),
    );
  }
}

Widget _bookingTestApp({
  PassengerRideRequestSubmitter? submitter,
  String Function()? idempotencyKeyFactory,
  VoidCallback? onSignInRequired,
}) {
  return MaterialApp(
    theme: AsmThemes.passenger,
    home: BookingPage(
      market: MarketConfig.ghanaAccra,
      rideRequestSubmitter: submitter,
      idempotencyKeyFactory: idempotencyKeyFactory,
      onSignInRequired: onSignInRequired,
    ),
  );
}

BookingDraft _validDraft() {
  return BookingDraft(
    marketCode: MarketConfig.ghanaAccra.marketCode,
    serviceContext: RideServiceContextCode.otherApprovedRequest,
    pickupDescription: 'Osu',
    destinationDescription: 'Airport',
    passengerCount: 1,
  );
}

class _RecordingApiClient extends AsmApiClient {
  _RecordingApiClient({
    List<ApiResponse<PassengerRideRequestResult>>? responses,
  }) : _responses = responses ?? <ApiResponse<PassengerRideRequestResult>>[],
       super(baseUrl: 'https://control.example/api/');

  final List<ApiResponse<PassengerRideRequestResult>> _responses;
  bool wasCalled = false;
  PassengerRideRequestSubmission? lastSubmission;
  final submissions = <PassengerRideRequestSubmission>[];

  @override
  Future<ApiResponse<PassengerRideRequestResult>> submitPassengerRideRequest(
    PassengerRideRequestSubmission submission,
  ) async {
    wasCalled = true;
    lastSubmission = submission;
    submissions.add(submission);
    if (_responses.isNotEmpty) {
      return _responses.removeAt(0);
    }
    return ApiResponse.success(
      const PassengerRideRequestResult(
        requestReference: 'RR-APP-3A9F1C2B4E5D',
        status: 'requested',
        message: 'Ride request received by the Control Center.',
      ),
      statusCode: 201,
    );
  }
}

class _RecordingAuthApiGateway implements AuthApiGateway {
  _RecordingAuthApiGateway({
    this.responseData = const <String, Object?>{'access': 'new-access'},
    this.statusCode = 200,
  });

  final Map<String, Object?> responseData;
  final int statusCode;
  final paths = <String>[];
  final bodies = <Map<String, Object?>>[];

  @override
  Future<ApiResponse<Map<String, Object?>>> post(
    String path, {
    required Map<String, Object?> body,
  }) async {
    paths.add(path);
    bodies.add(Map<String, Object?>.of(body));

    if (statusCode < 200 || statusCode >= 300) {
      return ApiResponse.apiFailure(
        AsmApiException(
          type: AsmApiExceptionType.authentication,
          message: 'Refresh failed.',
          statusCode: statusCode,
        ),
      );
    }

    return ApiResponse.success(responseData, statusCode: statusCode);
  }
}

class _MutableAuthTokenStore implements AuthTokenStore {
  _MutableAuthTokenStore({this.accessToken});

  String? accessToken;
  String? refreshToken;

  @override
  Future<void> saveTokens(AuthTokens tokens) async {
    accessToken = tokens.accessToken;
    refreshToken = tokens.refreshToken;
  }

  @override
  Future<String?> readAccessToken() async => accessToken;

  @override
  Future<String?> readRefreshToken() async => refreshToken;

  @override
  Future<void> clearTokens() async {
    accessToken = null;
    refreshToken = null;
  }
}

void _useSurface(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
