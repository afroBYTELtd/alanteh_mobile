import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_app_config/asm_app_config.dart';
import 'package:asm_auth/asm_auth.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:asm_ride_domain/asm_ride_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passenger_app/booking/booking_draft.dart';
import 'package:passenger_app/booking/booking_page.dart';
import 'package:passenger_app/booking/booking_submission.dart';
import 'package:passenger_app/booking/scheduled_pickup.dart';
import 'package:passenger_app/ride_requests/ride_request_history.dart';
import 'package:passenger_app/tracking/ride_tracking_screen.dart';

void main() {
  group('scheduled pickup rules', () {
    test('earliest pickup is an hour ahead, rounded up to 15 minutes', () {
      expect(
        earliestScheduledPickup(DateTime(2026, 10, 1, 8, 52)),
        DateTime(2026, 10, 1, 10, 0),
      );
      expect(
        earliestScheduledPickup(DateTime(2026, 10, 1, 9, 0)),
        DateTime(2026, 10, 1, 10, 0),
      );
      expect(
        earliestScheduledPickup(DateTime(2026, 10, 1, 9, 0, 30)),
        DateTime(2026, 10, 1, 10, 15),
      );
    });

    test('latest pickup is seven days ahead, rounded down', () {
      expect(
        latestScheduledPickup(DateTime(2026, 10, 1, 8, 52)),
        DateTime(2026, 10, 8, 8, 45),
      );
    });

    test('slots for a day stay inside the window in 15-minute steps', () {
      final now = DateTime(2026, 10, 1, 21, 52);

      final today = scheduledPickupSlotsOn(DateTime(2026, 10, 1), now);
      expect(today.first, DateTime(2026, 10, 1, 23, 0));
      expect(today.last, DateTime(2026, 10, 1, 23, 45));
      expect(today, hasLength(4));

      final lastDay = scheduledPickupSlotsOn(DateTime(2026, 10, 8), now);
      expect(lastDay.first, DateTime(2026, 10, 8, 0, 0));
      expect(lastDay.last, DateTime(2026, 10, 8, 21, 45));

      expect(scheduledPickupSlotsOn(DateTime(2026, 10, 9), now), isEmpty);
    });

    test('a pickup must be between one hour and seven days ahead', () {
      final now = DateTime(2026, 10, 1, 8, 0);

      expect(
        checkScheduledPickup(now.add(const Duration(minutes: 59)), now),
        ScheduledPickupProblem.tooSoon,
      );
      expect(
        checkScheduledPickup(now.add(const Duration(minutes: 60)), now),
        isNull,
      );
      expect(
        checkScheduledPickup(now.add(const Duration(days: 7, minutes: 1)), now),
        ScheduledPickupProblem.tooFar,
      );
    });

    test('pickups are written the way the push notifications write them', () {
      expect(
        formatScheduledPickup(DateTime(2026, 10, 3, 9, 0)),
        'Sat 3 Oct, 09:00',
      );
    });
  });

  group('booking draft', () {
    test('keeps the pickup time and can clear it', () {
      final pickup = DateTime.utc(2026, 10, 3, 9);
      final draft = _draft(requestedPickupTime: pickup);

      expect(draft.requestedPickupTime, pickup);
      expect(draft.copyWith(passengerCount: 2).requestedPickupTime, pickup);
      expect(
        draft.copyWith(clearRequestedPickupTime: true).requestedPickupTime,
        isNull,
      );
    });
  });

  group('submitting a scheduled ride', () {
    test('forwards the pickup time to the API client', () async {
      final client = _RecordingApiClient();
      final submitter = await _submitter(client);
      final pickup = DateTime.utc(2026, 10, 3, 9);

      await submitter.submit(
        _draft(requestedPickupTime: pickup),
        idempotencyKey: 'APP-scheduled',
      );

      expect(client.lastSubmission!.requestedPickupTime, pickup);
    });

    for (final errorCase in <_ErrorCase>[
      const _ErrorCase(
        status: 400,
        code: 'requested_pickup_time_invalid',
        detail: 'requested_pickup_time must be an ISO 8601 date and time.',
        shown:
            PassengerRideRequestSubmissionException.pickupTimeUnreadableMessage,
      ),
      const _ErrorCase(
        status: 400,
        code: 'requested_pickup_time_timezone_required',
        detail: 'requested_pickup_time must include a UTC offset.',
        shown:
            PassengerRideRequestSubmissionException.pickupTimeUnreadableMessage,
      ),
      const _ErrorCase(
        status: 400,
        code: 'requested_pickup_time_too_soon',
        detail:
            'Scheduled pickups must be at least 60 minutes from now. '
            'Book a ride now instead.',
        shown:
            'Scheduled pickups must be at least 60 minutes from now. '
            'Book a ride now instead.',
      ),
      const _ErrorCase(
        status: 400,
        code: 'requested_pickup_time_too_far',
        detail: 'Scheduled pickups can be at most 7 days ahead.',
        shown: 'Scheduled pickups can be at most 7 days ahead.',
      ),
      const _ErrorCase(
        status: 409,
        code: 'scheduled_slot_full',
        detail: 'That pickup time is fully booked. Please choose another time.',
        shown: 'That pickup time is fully booked. Please choose another time.',
      ),
      const _ErrorCase(
        status: 409,
        code: 'scheduled_ride_limit_reached',
        detail: 'You can have at most 3 upcoming scheduled rides.',
        shown: 'You can have at most 3 upcoming scheduled rides.',
      ),
      const _ErrorCase(
        status: 409,
        code: 'scheduled_slot_full',
        detail: null,
        shown: PassengerRideRequestSubmissionException.slotFullMessage,
      ),
      const _ErrorCase(
        status: 409,
        code: 'scheduled_ride_limit_reached',
        detail: null,
        shown:
            PassengerRideRequestSubmissionException.scheduledRideLimitMessage,
      ),
      const _ErrorCase(
        status: 400,
        code: 'requested_pickup_time_too_soon',
        detail: null,
        shown: PassengerRideRequestSubmissionException.pickupTooSoonMessage,
      ),
      const _ErrorCase(
        status: 400,
        code: 'requested_pickup_time_too_far',
        detail: null,
        shown: PassengerRideRequestSubmissionException.pickupTooFarMessage,
      ),
    ]) {
      test(
        'maps ${errorCase.status} ${errorCase.code} '
        '(${errorCase.detail == null ? 'no detail' : 'with detail'})',
        () async {
          final client = _RecordingApiClient(
            response: ApiResponse.apiFailure(
              AsmApiException(
                type: AsmApiExceptionType.badResponse,
                message: 'raw',
                statusCode: errorCase.status,
                cause: <String, Object?>{
                  'code': errorCase.code,
                  if (errorCase.detail != null) 'detail': errorCase.detail,
                },
              ),
            ),
          );
          final submitter = await _submitter(client);

          await expectLater(
            submitter.submit(
              _draft(requestedPickupTime: DateTime.utc(2026, 10, 3, 9)),
              idempotencyKey: 'APP-${errorCase.code}',
            ),
            throwsA(
              isA<PassengerRideRequestSubmissionException>()
                  .having((error) => error.message, 'message', errorCase.shown)
                  .having((error) => error.code, 'code', errorCase.code),
            ),
          );
        },
      );
    }

    test('a 409 without a code is still the idempotency conflict', () async {
      final client = _RecordingApiClient(
        response: ApiResponse.apiFailure(
          const AsmApiException(
            type: AsmApiExceptionType.badResponse,
            message: 'raw',
            statusCode: 409,
            cause: <String, Object?>{
              'detail':
                  'Idempotency-Key was already used for a different request.',
            },
          ),
        ),
      );
      final submitter = await _submitter(client);

      await expectLater(
        submitter.submit(_draft(), idempotencyKey: 'APP-conflict'),
        throwsA(
          isA<PassengerRideRequestSubmissionException>()
              .having(
                (error) => error.message,
                'message',
                PassengerRideRequestSubmissionException
                    .idempotencyConflictMessage,
              )
              .having((error) => error.code, 'code', isNull),
        ),
      );
    });
  });

  group('booking page', () {
    // Thursday 1 October 2026, 08:52 local time.
    final start = DateTime(2026, 10, 1, 8, 52);

    testWidgets('ride now is the default and sends no pickup time', (
      tester,
    ) async {
      final submitter = _PageSubmitter();
      await _pumpBookingPage(tester, submitter: submitter, now: () => start);

      await _tapKey(tester, 'request-ride');
      expect(find.byKey(const Key('booking-review-pickup-time')), findsNothing);
      await _tapKey(tester, 'confirm-and-request');

      expect(submitter.drafts.single.requestedPickupTime, isNull);
    });

    testWidgets('scheduling sends the chosen slot', (tester) async {
      final submitter = _PageSubmitter();
      await _pumpBookingPage(tester, submitter: submitter, now: () => start);

      await tester.tap(find.text('Schedule'));
      await _settle(tester);
      expect(find.text('Thu 1 Oct'), findsOneWidget);

      await _tapKey(tester, 'booking-pickup-time');
      expect(find.byKey(const Key('pickup-slot-09:45')), findsNothing);
      await _tapKey(tester, 'pickup-slot-10:30');
      await _tapKey(tester, 'request-ride');

      expect(
        find.descendant(
          of: find.byKey(const Key('booking-review-pickup-time')),
          matching: find.text('Thu 1 Oct, 10:30'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: await _revealKey(tester, 'confirm-and-request'),
          matching: find.text('Schedule ride'),
        ),
        findsOneWidget,
      );
      await _tapKey(tester, 'confirm-and-request');

      expect(
        submitter.drafts.single.requestedPickupTime,
        DateTime(2026, 10, 1, 10, 30).toUtc(),
      );
      expect(await _revealKey(tester, 'start-new-request'), findsOneWidget);
    });

    testWidgets('schedule without a time cannot be reviewed', (tester) async {
      final submitter = _PageSubmitter();
      await _pumpBookingPage(tester, submitter: submitter, now: () => start);

      await tester.tap(find.text('Schedule'));
      await _settle(tester);
      await _tapKey(tester, 'request-ride');

      expect(find.text('Choose a pickup time.'), findsOneWidget);
      expect(find.byKey(const Key('confirm-and-request')), findsNothing);
    });

    testWidgets('confirm re-checks that the pickup is still an hour away', (
      tester,
    ) async {
      final submitter = _PageSubmitter();
      var now = start;
      await _pumpBookingPage(tester, submitter: submitter, now: () => now);

      await tester.tap(find.text('Schedule'));
      await _settle(tester);
      await _tapKey(tester, 'booking-pickup-time');
      await _tapKey(tester, 'pickup-slot-10:00');
      await _tapKey(tester, 'request-ride');

      now = DateTime(2026, 10, 1, 9, 5);
      await _tapKey(tester, 'confirm-and-request');

      expect(submitter.drafts, isEmpty);
      expect(find.byKey(const Key('request-ride')), findsOneWidget);
      expect(
        find.text(PassengerRideRequestSubmissionException.pickupTooSoonMessage),
        findsOneWidget,
      );
    });

    testWidgets('a booking the backend did not record as scheduled is not '
        'shown as scheduled', (tester) async {
      final submitter = _PageSubmitter(echoPickupTime: false);
      await _pumpBookingPage(tester, submitter: submitter, now: () => start);

      await tester.tap(find.text('Schedule'));
      await _settle(tester);
      await _tapKey(tester, 'booking-pickup-time');
      await _tapKey(tester, 'pickup-slot-11:00');
      await _tapKey(tester, 'request-ride');
      await _tapKey(tester, 'confirm-and-request');

      expect(find.byKey(const Key('start-new-request')), findsNothing);
      expect(
        find.text(
          PassengerRideRequestSubmissionException.pickupNotConfirmedMessage,
        ),
        findsOneWidget,
      );
      // A failure state (Try again replays the same request), not success.
      expect(await _revealKey(tester, 'retry-ride-request'), findsOneWidget);
      expect(find.byKey(const Key('start-new-request')), findsNothing);
    });

    testWidgets('a full hour sends the passenger back to pick another time', (
      tester,
    ) async {
      final submitter = _PageSubmitter(
        failure: const PassengerRideRequestSubmissionException(
          'That pickup time is fully booked. Please choose another time.',
          code: PassengerRideRequestSubmissionException.slotFullCode,
        ),
      );
      await _pumpBookingPage(tester, submitter: submitter, now: () => start);

      await tester.tap(find.text('Schedule'));
      await _settle(tester);
      await _tapKey(tester, 'booking-pickup-time');
      await _tapKey(tester, 'pickup-slot-11:00');
      await _tapKey(tester, 'request-ride');
      await _tapKey(tester, 'confirm-and-request');

      expect(find.byKey(const Key('request-ride')), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('booking-pickup-time-error')))
            .data,
        'That pickup time is fully booked. Please choose another time.',
      );
      // The rest of the booking is kept.
      expect(find.text('Osu Oxford Street'), findsOneWidget);
      expect(find.byKey(const Key('booking-pickup-time')), findsOneWidget);
      expect(find.byKey(const Key('booking-book-for-now')), findsNothing);
    });

    testWidgets('reaching the limit offers booking for now', (tester) async {
      final submitter = _PageSubmitter(
        failure: const PassengerRideRequestSubmissionException(
          'You can have at most 3 upcoming scheduled rides.',
          code: PassengerRideRequestSubmissionException.scheduledRideLimitCode,
        ),
      );
      await _pumpBookingPage(tester, submitter: submitter, now: () => start);

      await tester.tap(find.text('Schedule'));
      await _settle(tester);
      await _tapKey(tester, 'booking-pickup-time');
      await _tapKey(tester, 'pickup-slot-11:00');
      await _tapKey(tester, 'request-ride');
      await _tapKey(tester, 'confirm-and-request');

      expect(find.byKey(const Key('booking-view-my-rides')), findsOneWidget);
      await _tapKey(tester, 'booking-book-for-now');

      expect(find.byKey(const Key('booking-pickup-time')), findsNothing);
      expect(find.byKey(const Key('booking-pickup-time-error')), findsNothing);
    });
  });

  group('after booking', () {
    // Thursday 1 October 2026, 06:00; pickup Thursday 09:00.
    final now = DateTime(2026, 10, 1, 6, 0);
    final pickup = DateTime(2026, 10, 1, 9, 0);

    test('a ride booked for later is recognised until a driver takes it', () {
      final waiting = _record(status: 'requested', requestedPickupTime: pickup);

      expect(scheduledPickupAwaitingDriver(waiting, now), pickup);
      expect(
        scheduledPickupAwaitingDriver(_record(status: 'requested'), now),
        isNull,
      );
      expect(
        scheduledPickupAwaitingDriver(
          _record(status: 'driver_accepted', requestedPickupTime: pickup),
          now,
        ),
        isNull,
      );
      // Not yet enriched with its trip: the real state is unknown.
      expect(
        scheduledPickupAwaitingDriver(
          _record(status: 'converted', requestedPickupTime: pickup),
          now,
        ),
        isNull,
      );
      expect(
        scheduledPickupAwaitingDriver(
          waiting,
          pickup.add(const Duration(minutes: 1)),
        ),
        isNull,
      );
    });

    testWidgets('tracking shows the booking, not a driver search', (
      tester,
    ) async {
      final record = _record(
        status: 'requested',
        requestedPickupTime: pickup,
        controlCenterMessage: 'Still finding you a driver.',
      );
      await _pumpTracking(tester, record, now: () => now);

      expect(find.byKey(const Key('ride-scheduled-state')), findsOneWidget);
      expect(find.byKey(const Key('looking-for-driver-state')), findsNothing);
      expect(find.text('Ride scheduled'), findsOneWidget);
      expect(find.textContaining('Thu 1 Oct, 09:00'), findsOneWidget);
      expect(find.text('Still finding you a driver.'), findsNothing);
      await _disposeTracking(tester);
    });

    testWidgets('once the pickup time has passed it is a driver search again', (
      tester,
    ) async {
      final record = _record(status: 'requested', requestedPickupTime: pickup);
      await _pumpTracking(
        tester,
        record,
        now: () => pickup.add(const Duration(minutes: 5)),
      );

      expect(find.byKey(const Key('ride-scheduled-state')), findsNothing);
      expect(find.byKey(const Key('looking-for-driver-state')), findsOneWidget);
      await _disposeTracking(tester);
    });

    testWidgets('a driver who accepts early is confirmed for the pickup time', (
      tester,
    ) async {
      final record = _record(
        status: 'driver_accepted',
        requestedPickupTime: pickup,
        controlCenterMessage: 'Your driver is on the way.',
        driverName: 'Kwame Mensah',
      );
      await _pumpTracking(
        tester,
        record,
        now: () => pickup.subtract(const Duration(minutes: 50)),
      );

      expect(find.byKey(const Key('vehicle-en-route-state')), findsOneWidget);
      expect(find.text('Driver confirmed for 09:00'), findsOneWidget);
      expect(find.text('Your vehicle is on the way'), findsNothing);
      expect(find.text('Your driver is on the way.'), findsNothing);
      await _disposeTracking(tester);
    });

    testWidgets('my ride requests label a ride booked for later', (
      tester,
    ) async {
      final later = DateTime.now().add(const Duration(hours: 3));
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AsmThemes.passenger,
          home: PassengerRideRequestHistoryPage(
            repository: _StaticHistoryRepository(<PassengerRideRequestRecord>[
              _record(
                status: 'requested',
                requestedPickupTime: later,
                reference: 'RR-APP-LATER',
              ),
            ]),
          ),
        ),
      );
      await _settle(tester);

      expect(
        find.byKey(const ValueKey<String>('ride-request-status-scheduled')),
        findsOneWidget,
      );
      expect(
        find.text('Scheduled · ${formatScheduledPickup(later)}'),
        findsOneWidget,
      );
    });
  });
}

PassengerRideRequestRecord _record({
  required String status,
  DateTime? requestedPickupTime,
  String? controlCenterMessage,
  String? driverName,
  String reference = 'RR-APP-SCHEDULED01',
}) {
  return PassengerRideRequestRecord(
    requestReference: reference,
    status: status,
    pickupLocation: 'Osu Oxford Street',
    destination: 'Kotoka International Airport',
    passengerCount: 1,
    createdAt: DateTime(2026, 9, 29, 12),
    updatedAt: DateTime(2026, 9, 29, 12),
    hasMobileReceipt: true,
    tripCreated: false,
    requestedPickupTime: requestedPickupTime,
    controlCenterMessage: controlCenterMessage,
    driverName: driverName,
  );
}

Future<void> _pumpTracking(
  WidgetTester tester,
  PassengerRideRequestRecord record, {
  required DateTime Function() now,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AsmThemes.passenger,
      home: RideTrackingScreen(
        repository: _StaticHistoryRepository(<PassengerRideRequestRecord>[
          record,
        ]),
        requestReference: record.requestReference,
        initialRecord: record,
        pollInterval: const Duration(hours: 1),
        clock: now,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _disposeTracking(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
  await tester.pump();
}

class _StaticHistoryRepository
    implements PassengerRideRequestHistoryRepository {
  _StaticHistoryRepository(this.records);

  final List<PassengerRideRequestRecord> records;

  @override
  Future<List<PassengerRideRequestRecord>> fetchRequests() async => records;

  @override
  Future<PassengerRideRequestRecord> fetchRequest(
    String requestReference,
  ) async {
    return records.firstWhere(
      (record) => record.requestReference == requestReference,
    );
  }
}

Future<void> _pumpBookingPage(
  WidgetTester tester, {
  required _PageSubmitter submitter,
  required DateTime Function() now,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AsmThemes.passenger,
      home: BookingPage(
        market: MarketConfig.ghanaAccra,
        initialPickupDescription: 'Osu Oxford Street',
        initialDestinationDescription: 'Kotoka International Airport',
        rideRequestSubmitter: submitter,
        idempotencyKeyFactory: () => 'APP-scheduled-page',
        clock: now,
      ),
    ),
  );
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  // Fixed frames rather than pumpAndSettle: the route preview can keep a
  // progress indicator running.
  for (var frame = 0; frame < 8; frame += 1) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<Finder> _revealKey(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  for (var attempt = 0; attempt < 20 && finder.evaluate().isEmpty; attempt++) {
    await tester.drag(find.byType(ListView).last, const Offset(0, -220));
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 100));
  return finder;
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  await tester.tap(await _revealKey(tester, key));
  await _settle(tester);
}

class _PageSubmitter implements PassengerRideRequestSubmitter {
  _PageSubmitter({this.echoPickupTime = true, this.failure});

  final bool echoPickupTime;
  final PassengerRideRequestSubmissionException? failure;
  final drafts = <BookingDraft>[];

  @override
  Future<PassengerRideRequestResult> submit(
    BookingDraft draft, {
    required String idempotencyKey,
  }) async {
    drafts.add(draft);
    final configuredFailure = failure;
    if (configuredFailure != null) {
      throw configuredFailure;
    }
    return PassengerRideRequestResult(
      requestReference: 'RR-APP-3A9F1C2B4E5D',
      status: 'requested',
      message: 'Ride request received by the Control Center.',
      requestedPickupTime: echoPickupTime ? draft.requestedPickupTime : null,
    );
  }
}

class _ErrorCase {
  const _ErrorCase({
    required this.status,
    required this.code,
    required this.detail,
    required this.shown,
  });

  final int status;
  final String code;
  final String? detail;
  final String shown;
}

BookingDraft _draft({DateTime? requestedPickupTime}) {
  return BookingDraft(
    marketCode: MarketConfig.ghanaAccra.marketCode,
    serviceContext: RideServiceContextCode.otherApprovedRequest,
    pickupDescription: 'Osu',
    destinationDescription: 'Airport',
    passengerCount: 1,
    requestedPickupTime: requestedPickupTime,
  );
}

Future<ApiPassengerRideRequestSubmitter> _submitter(
  _RecordingApiClient client,
) async {
  final store = MemoryAuthTokenStore();
  await store.saveTokens(
    AuthTokens(accessToken: 'access', refreshToken: 'refresh'),
  );
  return ApiPassengerRideRequestSubmitter(client, tokenStore: store);
}

class _RecordingApiClient extends AsmApiClient {
  _RecordingApiClient({this.response})
    : super(baseUrl: 'https://control.example/api/');

  final ApiResponse<PassengerRideRequestResult>? response;
  PassengerRideRequestSubmission? lastSubmission;

  @override
  Future<ApiResponse<PassengerRideRequestResult>> submitPassengerRideRequest(
    PassengerRideRequestSubmission submission,
  ) async {
    lastSubmission = submission;
    return response ??
        ApiResponse.success(
          PassengerRideRequestResult(
            requestReference: 'RR-APP-3A9F1C2B4E5D',
            status: 'requested',
            message: 'Ride request received by the Control Center.',
            requestedPickupTime: submission.requestedPickupTime,
          ),
          statusCode: 201,
        );
  }
}
