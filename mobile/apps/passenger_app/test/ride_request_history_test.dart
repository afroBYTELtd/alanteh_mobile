import 'dart:async';
import 'dart:io';

import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_auth/asm_auth.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passenger_app/payment_rating/passenger_payment_rating_contract.dart';
import 'package:passenger_app/payment_rating/passenger_payment_rating_page.dart';
import 'package:passenger_app/ride_requests/ride_request_history.dart';

void main() {
  test('history repository uses accepted list and detail endpoints', () async {
    final store = MemoryAuthTokenStore();
    await store.saveTokens(AuthTokens(accessToken: 'a', refreshToken: 'r'));

    final gateway = _FakeHistoryGateway(
      responses: <String, Object?>{
        ApiPassengerRideRequestHistoryRepository.listPath: <String, Object?>{
          'results': <Object?>[_recordJson(reference: 'RR-APP-NEWEST')],
        },
        '/api/rides/requests/RR-APP-NEWEST/': _recordJson(
          reference: 'RR-APP-NEWEST',
          controlCenterMessage: 'Passenger-safe detail update.',
        ),
      },
    );

    final repository = ApiPassengerRideRequestHistoryRepository(
      gateway,
      tokenStore: store,
    );

    final records = await repository.fetchRequests();
    final detail = await repository.fetchRequest('RR-APP-NEWEST');

    expect(records.single.requestReference, 'RR-APP-NEWEST');
    expect(detail.requestReference, 'RR-APP-NEWEST');
    expect(gateway.paths, <String>[
      '/api/rides/requests/',
      '/api/rides/requests/RR-APP-NEWEST/',
    ]);
  });

  test(
    'converted request parses trip reference and fetches canonical trip detail',
    () async {
      final store = MemoryAuthTokenStore();
      await store.saveTokens(AuthTokens(accessToken: 'a', refreshToken: 'r'));

      final gateway = _FakeHistoryGateway(
        responses: <String, Object?>{
          '/api/rides/requests/RR-APP-CONVERTED/': _recordJson(
            reference: 'RR-APP-CONVERTED',
            status: 'converted',
            tripReference: 'TRIP-READ/001',
          ),
          '/api/trips/TRIP-READ%2F001/': <String, Object?>{
            'trip_reference': 'TRIP-READ/001',
            'trip_status': 'arrived_at_pickup',
            'control_center_message': 'Your driver has arrived.',
          },
        },
      );

      final repository = ApiPassengerRideRequestHistoryRepository(
        gateway,
        tokenStore: store,
      );

      final request = await repository.fetchRequest('RR-APP-CONVERTED');
      final trip = await repository.fetchTrip(request.normalizedTripReference!);

      expect(request.status, 'converted');
      expect(request.normalizedTripReference, 'TRIP-READ/001');
      expect(trip.tripReference, 'TRIP-READ/001');
      expect(trip.status, 'arrived_at_pickup');
      expect(trip.passengerState, PassengerRideState.driverArrived);
      expect(trip.isTerminal, isFalse);
      expect(gateway.paths, <String>[
        '/api/rides/requests/RR-APP-CONVERTED/',
        '/api/trips/TRIP-READ%2F001/',
      ]);
    },
  );

  testWidgets('request history shows loading state', (tester) async {
    final pending = Completer<List<PassengerRideRequestRecord>>();

    await _pumpHistory(
      tester,
      _FakeRepository(listLoader: () => pending.future),
    );

    expect(
      find.byKey(const Key('ride-request-history-loading')),
      findsOneWidget,
    );

    pending.complete(const <PassengerRideRequestRecord>[]);
    await tester.pumpAndSettle();
  });

  testWidgets('request history shows loaded records newest first', (
    tester,
  ) async {
    final newest = _record(
      reference: 'RR-APP-NEWEST',
      createdAt: DateTime.utc(2026, 7, 11, 13),
      pickup: 'Accra Mall',
      destination: 'Kotoka International Airport',
      latestStaffState: 'Request received.',
    );
    final older = _record(
      reference: 'RR-APP-OLDER',
      createdAt: DateTime.utc(2026, 7, 11, 12),
      pickup: 'Osu',
      destination: 'Airport City',
    );

    await _pumpHistory(
      tester,
      _FakeRepository(
        listLoader: () async => <PassengerRideRequestRecord>[older, newest],
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('ride-request-history-loaded')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('trip-card-route-title')), findsNWidgets(2));
    expect(find.text('RR-APP-NEWEST'), findsNothing);
    expect(find.text('RR-APP-OLDER'), findsNothing);
    expect(find.text('Received by ALANTEH'), findsWidgets);
    expect(find.text('Request received.'), findsWidgets);

    final newestTop = tester.getTopLeft(
      find.byKey(const ValueKey<String>('ride-request-RR-APP-NEWEST')),
    );
    final olderTop = tester.getTopLeft(
      find.byKey(const ValueKey<String>('ride-request-RR-APP-OLDER')),
    );

    expect(newestTop.dy, lessThan(olderTop.dy));
  });

  testWidgets('request history shows empty state', (tester) async {
    await _pumpHistory(
      tester,
      _FakeRepository(
        listLoader: () async => const <PassengerRideRequestRecord>[],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ride-request-history-empty')), findsOneWidget);
    expect(
      find.text('No trips yet. Book your first ALANTEH ride.'),
      findsOneWidget,
    );
  });

  testWidgets('request history shows safe error state', (tester) async {
    await _pumpHistory(
      tester,
      _FakeRepository(
        listLoader: () => Future<List<PassengerRideRequestRecord>>.error(
          const PassengerRideRequestHistoryException.network(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ride-request-history-error')), findsOneWidget);
    expect(
      find.text(PassengerRideRequestHistoryException.networkMessage),
      findsOneWidget,
    );
    expect(find.byKey(const Key('ride-request-history-retry')), findsOneWidget);
  });

  testWidgets('request history shows safe session expired state', (
    tester,
  ) async {
    var signInRequested = false;

    await _pumpHistory(
      tester,
      _FakeRepository(
        listLoader: () => Future<List<PassengerRideRequestRecord>>.error(
          const PassengerRideRequestHistoryException.sessionExpired(),
        ),
      ),
      onSignInRequired: () {
        signInRequested = true;
      },
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('ride-request-history-session-expired')),
      findsOneWidget,
    );
    expect(find.text('Session expired'), findsOneWidget);
    expect(
      find.text(PassengerRideRequestHistoryException.sessionExpiredMessage),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('ride-request-history-sign-in-again')),
    );

    expect(signInRequested, isTrue);
  });

  testWidgets('request detail displays only passenger-safe fields', (
    tester,
  ) async {
    final summary = _record(
      reference: 'RR-APP-DETAIL',
      pickup: 'Accra Mall',
      destination: 'Kotoka International Airport',
    );

    final detail = _record(
      reference: 'RR-APP-DETAIL',
      pickup: 'Accra Mall',
      destination: 'Kotoka International Airport',
      passengerCount: 2,
      requestedPickupTime: DateTime.utc(2026, 7, 11, 14, 30),
      status: 'under_review',
      tripCreated: false,
      controlCenterMessage: 'Your request is being reviewed.',
    );

    await _pumpHistory(
      tester,
      _FakeRepository(
        listLoader: () async => <PassengerRideRequestRecord>[summary],
        detailLoader: (_) async => detail,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('ride-request-RR-APP-DETAIL')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ride-request-detail-loaded')), findsOneWidget);
    expect(find.text('Trip details'), findsOneWidget);
    expect(find.text('RR-APP-DETAIL'), findsNothing);
    expect(find.text('Accra Mall'), findsOneWidget);
    expect(find.text('Kotoka International Airport'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('Being reviewed'), findsOneWidget);
    expect(find.text('Confirmed'), findsNothing);
    expect(find.text('Not yet converted into a trip'), findsNothing);
    expect(find.text('Your request is being reviewed.'), findsWidgets);
  });

  testWidgets(
    'converted active history record delegates to tracking instead of static detail',
    (tester) async {
      PassengerRideRequestRecord? openedRecord;
      final converted = _record(
        reference: 'RR-APP-ACTIVE-TRIP',
        status: 'converted',
        tripCreated: true,
      );

      await _pumpHistory(
        tester,
        _FakeRepository(
          listLoader: () async => <PassengerRideRequestRecord>[converted],
          detailLoader: (_) async => converted,
        ),
        onOpenActiveTracking: (record) async {
          openedRecord = record;
        },
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('ride-request-RR-APP-ACTIVE-TRIP')),
      );
      await tester.pump();

      expect(openedRecord, same(converted));
      expect(find.byKey(const Key('ride-request-detail-loaded')), findsNothing);
    },
  );

  testWidgets(
    'enriched active converted history record still delegates to tracking',
    (tester) async {
      PassengerRideRequestRecord? openedRecord;

      final repository = _TripAwareFakeRepository(
        listLoader: () async => <PassengerRideRequestRecord>[
          _record(
            reference: 'RR-APP-ENRICHED-ACTIVE',
            status: 'converted',
            tripCreated: true,
            latestStaffState: 'Trip record created.',
            tripReference: 'TRIP-ENRICHED-ACTIVE',
          ),
        ],
        tripLoader: (tripReference) async => PassengerTripRecord(
          tripReference: tripReference,
          status: 'in_progress',
          controlCenterMessage: 'Your trip is in progress.',
        ),
      );

      await _pumpHistory(
        tester,
        repository,
        onOpenActiveTracking: (record) async {
          openedRecord = record;
        },
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(
          const ValueKey<String>('ride-request-RR-APP-ENRICHED-ACTIVE'),
        ),
      );
      await tester.pump();

      expect(repository.tripCalls, <String>['TRIP-ENRICHED-ACTIVE']);
      expect(openedRecord, isNotNull);
      expect(openedRecord!.status, 'in_progress');
      expect(openedRecord!.tripReference, 'TRIP-ENRICHED-ACTIVE');
      expect(find.byKey(const Key('ride-request-detail-loaded')), findsNothing);
    },
  );

  testWidgets('history screens do not render sensitive fields', (tester) async {
    final record = _record(
      reference: 'RR-APP-SAFE',
      pickup: 'Accra Mall',
      destination: 'Airport City',
      controlCenterMessage: 'Passenger-safe ALANTEH update.',
    );

    await _pumpHistory(
      tester,
      _FakeRepository(
        listLoader: () async => <PassengerRideRequestRecord>[record],
        detailLoader: (_) async => record,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('ride-request-RR-APP-SAFE')),
    );
    await tester.pumpAndSettle();

    for (final sensitiveText in <String>[
      'PIN',
      'access token',
      'refresh token',
      'Authorization',
      'phone',
      'email',
      'idempotency key',
      'raw payload',
    ]) {
      expect(
        find.textContaining(sensitiveText, findRichText: true),
        findsNothing,
      );
    }
  });

  testWidgets('history toolbar refresh reloads requests', (tester) async {
    var calls = 0;

    await _pumpHistory(
      tester,
      _FakeRepository(
        listLoader: () async {
          calls += 1;
          return <PassengerRideRequestRecord>[
            _record(
              reference: calls == 1 ? 'RR-APP-FIRST' : 'RR-APP-REFRESHED',
            ),
          ];
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pickup → Destination'), findsOneWidget);

    await tester.tap(find.byTooltip('Refresh requests'));
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(find.text('Pickup → Destination'), findsOneWidget);
    expect(find.text('RR-APP-FIRST'), findsNothing);
  });

  testWidgets('history pull to refresh reloads requests', (tester) async {
    var calls = 0;

    await _pumpHistory(
      tester,
      _FakeRepository(
        listLoader: () async {
          calls += 1;
          return <PassengerRideRequestRecord>[
            _record(
              reference: calls == 1
                  ? 'RR-APP-BEFORE-PULL'
                  : 'RR-APP-AFTER-PULL',
              pickup: calls == 1 ? 'Before pickup' : 'After pickup',
              destination: 'Destination',
            ),
          ];
        },
      ),
    );
    await tester.pumpAndSettle();

    final refreshState = tester.state<RefreshIndicatorState>(
      find.byType(RefreshIndicator),
    );

    final refreshFuture = refreshState.show();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 500));
    await refreshFuture;
    await tester.pump(const Duration(milliseconds: 100));

    expect(calls, 2);
    expect(find.text('After pickup → Destination'), findsOneWidget);
    expect(find.text('Before pickup → Destination'), findsNothing);
    expect(find.text('RR-APP-AFTER-PULL'), findsNothing);
    expect(find.text('RR-APP-BEFORE-PULL'), findsNothing);
  });

  testWidgets(
    'history detail uses backend payment endpoints instead of summary fare or receipt flag',
    (tester) async {
      final paymentRepository = _HistoryPaymentRatingRepository();

      final record = _record(
        reference: 'RR-APP-PAYMENT-DETAIL',
        status: 'completed',
        fareDisplay: 'GHS 999',
        hasMobileReceipt: true,
      );

      await _pumpHistory(
        tester,
        _FakeRepository(
          listLoader: () async => <PassengerRideRequestRecord>[record],
          detailLoader: (_) async => record,
        ),
        paymentRatingRepository: paymentRepository,
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(
          const ValueKey<String>('ride-request-RR-APP-PAYMENT-DETAIL'),
        ),
      );
      await tester.pumpAndSettle();

      final openPayment = find.byKey(
        const Key('open-payment-rating-from-history'),
      );

      expect(openPayment, findsOneWidget);

      await tester.ensureVisible(openPayment);
      await tester.tap(openPayment);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byType(PassengerPaymentRatingPage), findsOneWidget);
      expect(paymentRepository.references, <String>[
        'RR-APP-PAYMENT-DETAIL',
        'RR-APP-PAYMENT-DETAIL',
        'RR-APP-PAYMENT-DETAIL',
      ]);

      expect(find.text('GHS 999'), findsNothing);
      expect(find.byKey(const Key('initiate-payment')), findsNothing);
      expect(
        find.byKey(const Key('payment-not-available-state')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('payment-confirmed-state')), findsNothing);
      expect(find.byKey(const Key('payment-receipt-state')), findsNothing);
      expect(paymentRepository.receiptCalls, 0);
    },
  );

  testWidgets('test_converted_record_with_trip_fetches_and_shows_completed', (
    tester,
  ) async {
    final repository = _TripAwareFakeRepository(
      listLoader: () async => <PassengerRideRequestRecord>[
        _record(
          reference: 'RR-APP-COMPLETED',
          status: 'converted',
          tripCreated: true,
          latestStaffState: 'Trip record created.',
          tripReference: 'TRIP-COMPLETED',
          fareDisplay: 'GHS 45.00',
        ),
      ],
      tripLoader: (tripReference) async => PassengerTripRecord(
        tripReference: tripReference,
        status: 'completed_pending_review',
        controlCenterMessage: 'Awaiting operations review',
      ),
    );

    await _pumpHistory(tester, repository);
    await tester.pumpAndSettle();

    expect(repository.tripCalls, <String>['TRIP-COMPLETED']);
    expect(
      find.byKey(
        const ValueKey<String>('ride-request-status-completed_pending_review'),
      ),
      findsOneWidget,
    );
    expect(find.text('Thank you for riding with ALANTEH.'), findsOneWidget);
    expect(find.text('Request update'), findsNothing);
    expect(find.text('Trip record created.'), findsNothing);
    expect(find.textContaining('pending review'), findsNothing);
    expect(find.text('GH₵45.00'), findsOneWidget);
  });

  testWidgets(
    'test_converted_record_trip_fetch_failure_shows_fallback_gracefully',
    (tester) async {
      final repository = _TripAwareFakeRepository(
        listLoader: () async => <PassengerRideRequestRecord>[
          _record(
            reference: 'RR-APP-FALLBACK',
            status: 'converted',
            tripCreated: true,
            latestStaffState: 'Trip record created.',
            tripReference: 'TRIP-FAIL',
          ),
        ],
        tripLoader: (_) => Future<PassengerTripRecord>.error(
          const PassengerRideRequestHistoryException.network(),
        ),
      );

      await _pumpHistory(tester, repository);
      await tester.pumpAndSettle();

      expect(repository.tripCalls, <String>['TRIP-FAIL']);
      expect(find.text('Request update'), findsOneWidget);
      expect(find.text('Trip record created.'), findsOneWidget);
      expect(find.byKey(const Key('ride-request-history-error')), findsNothing);
      expect(find.byKey(const Key('history-card-fare')), findsNothing);
    },
  );

  testWidgets('test_non_converted_records_not_enriched', (tester) async {
    final repository = _TripAwareFakeRepository(
      listLoader: () async => <PassengerRideRequestRecord>[
        _record(
          reference: 'RR-APP-NOT-CONVERTED',
          status: 'requested',
          tripReference: 'TRIP-MUST-NOT-FETCH',
        ),
      ],
      tripLoader: (tripReference) async => PassengerTripRecord(
        tripReference: tripReference,
        status: 'completed_pending_review',
      ),
    );

    await _pumpHistory(tester, repository);
    await tester.pumpAndSettle();

    expect(repository.tripCalls, isEmpty);
    expect(find.text('Received by ALANTEH'), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey<String>('ride-request-status-completed_pending_review'),
      ),
      findsNothing,
    );
    expect(
      find.byKey(
        const ValueKey<String>('ride-request-status-completed_confirmed'),
      ),
      findsNothing,
    );
  });

  testWidgets('test_book_again_preserved_on_completed_card', (tester) async {
    PassengerRideRequestRecord? selectedRecord;

    final repository = _TripAwareFakeRepository(
      listLoader: () async => <PassengerRideRequestRecord>[
        _record(
          reference: 'RR-APP-REBOOK-COMPLETED',
          status: 'converted',
          tripCreated: true,
          tripReference: 'TRIP-REBOOK-COMPLETED',
        ),
      ],
      tripLoader: (tripReference) async => PassengerTripRecord(
        tripReference: tripReference,
        status: 'completed_pending_review',
      ),
    );

    await _pumpHistory(
      tester,
      repository,
      onBookAgain: (record) {
        selectedRecord = record;
      },
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const ValueKey<String>('ride-request-status-completed_pending_review'),
      ),
      findsOneWidget,
    );
    expect(find.text('Book again'), findsOneWidget);

    await tester.tap(find.byKey(const Key('history-card-book-again')));
    await tester.pump();

    expect(selectedRecord, isNotNull);
    expect(selectedRecord!.requestReference, 'RR-APP-REBOOK-COMPLETED');
    expect(selectedRecord!.status, 'completed_pending_review');
    expect(selectedRecord!.tripReference, 'TRIP-REBOOK-COMPLETED');
  });

  testWidgets('test_history_load_fetches_each_unique_trip_once', (
    tester,
  ) async {
    final repository = _TripAwareFakeRepository(
      listLoader: () async => <PassengerRideRequestRecord>[
        _record(
          reference: 'RR-APP-SHARED-ONE',
          status: 'converted',
          tripCreated: true,
          tripReference: 'TRIP-SHARED',
        ),
        _record(
          reference: 'RR-APP-SHARED-TWO',
          status: 'converted',
          tripCreated: true,
          tripReference: 'TRIP-SHARED',
        ),
        _record(
          reference: 'RR-APP-UNIQUE',
          status: 'converted',
          tripCreated: true,
          tripReference: 'TRIP-UNIQUE',
        ),
      ],
      tripLoader: (tripReference) async => PassengerTripRecord(
        tripReference: tripReference,
        status: 'completed_pending_review',
      ),
    );

    await _pumpHistory(tester, repository);
    await tester.pumpAndSettle();

    expect(repository.tripCalls, <String>['TRIP-SHARED', 'TRIP-UNIQUE']);
    expect(find.text('Completed'), findsNWidgets(3));
  });

  testWidgets(
    'test_completed_pending_review_shows_completed_label_not_raw_status',
    (tester) async {
      await _pumpHistory(
        tester,
        _FakeRepository(
          listLoader: () async => <PassengerRideRequestRecord>[
            _record(
              reference: 'RR-APP-RAW-STATUS',
              status: 'completed_pending_review',
              controlCenterMessage: 'Awaiting operations review',
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(
          const ValueKey<String>(
            'ride-request-status-completed_pending_review',
          ),
        ),
        findsOneWidget,
      );
      expect(find.text('completed_pending_review'), findsNothing);
      expect(find.textContaining('pending review'), findsNothing);
      expect(find.text('Thank you for riding with ALANTEH.'), findsOneWidget);
      expect(find.byKey(const Key('history-card-fare')), findsNothing);
    },
  );

  testWidgets('test_return_button_only_on_completed_cards', (tester) async {
    await _pumpHistory(
      tester,
      _FakeRepository(
        listLoader: () async => <PassengerRideRequestRecord>[
          _record(
            reference: 'RR-RETURN-COMPLETED',
            status: 'completed_confirmed',
          ),
          _record(reference: 'RR-RETURN-REQUESTED', status: 'requested'),
          _record(reference: 'RR-RETURN-REVIEW', status: 'under_review'),
          _record(reference: 'RR-RETURN-ACCEPTED', status: 'accepted_for_trip'),
        ],
      ),
      onReturn: (_) {},
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('history-card-return')), findsOneWidget);

    await tester.tap(find.byKey(const Key('trip-filter-active')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('history-card-return')), findsNothing);

    await tester.tap(find.byKey(const Key('trip-filter-completed')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('history-card-return')), findsOneWidget);
  });

  testWidgets('test_tab_filter_all_shows_everything', (tester) async {
    await _pumpHistory(
      tester,
      _FakeRepository(
        listLoader: () async => <PassengerRideRequestRecord>[
          _record(
            reference: 'RR-ALL-REQUESTED',
            pickup: 'Requested pickup',
            status: 'requested',
            createdAt: DateTime(2026, 8, 12, 15),
          ),
          _record(
            reference: 'RR-ALL-COMPLETED',
            pickup: 'Completed pickup',
            status: 'completed_confirmed',
            createdAt: DateTime(2026, 8, 12, 14),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('ride-request-RR-ALL-REQUESTED')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('ride-request-RR-ALL-COMPLETED')),
      findsOneWidget,
    );
  });

  testWidgets('test_tab_filter_active_shows_correct_statuses', (tester) async {
    await _pumpHistory(
      tester,
      _FakeRepository(
        listLoader: () async => <PassengerRideRequestRecord>[
          _record(
            reference: 'RR-ACTIVE-REQUESTED',
            status: 'requested',
            createdAt: DateTime(2026, 8, 12, 15, 3),
          ),
          _record(
            reference: 'RR-ACTIVE-REVIEW',
            status: 'under_review',
            createdAt: DateTime(2026, 8, 12, 15, 2),
          ),
          _record(
            reference: 'RR-ACTIVE-ACCEPTED',
            status: 'accepted_for_trip',
            createdAt: DateTime(2026, 8, 12, 15, 1),
          ),
          _record(
            reference: 'RR-ACTIVE-COMPLETED',
            status: 'completed_confirmed',
            createdAt: DateTime(2026, 8, 12, 15),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('trip-filter-active')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('ride-request-status-requested')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('ride-request-status-under_review')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey<String>('ride-request-status-completed_confirmed'),
      ),
      findsNothing,
    );

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('ride-request-RR-ACTIVE-ACCEPTED')),
      260,
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const ValueKey<String>('ride-request-status-accepted_for_trip'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey<String>('ride-request-status-completed_confirmed'),
      ),
      findsNothing,
    );
  });

  testWidgets('test_tab_filter_completed_shows_correct_statuses', (
    tester,
  ) async {
    final repository = _TripAwareFakeRepository(
      listLoader: () async => <PassengerRideRequestRecord>[
        _record(
          reference: 'RR-COMPLETE-CONFIRMED',
          status: 'completed_confirmed',
          createdAt: DateTime(2026, 8, 12, 15, 3),
        ),
        _record(
          reference: 'RR-COMPLETE-PENDING',
          status: 'completed_pending_review',
          createdAt: DateTime(2026, 8, 12, 15, 2),
        ),
        _record(
          reference: 'RR-COMPLETE-CONVERTED',
          status: 'converted',
          tripCreated: true,
          tripReference: 'TRIP-COMPLETE-CONVERTED',
          createdAt: DateTime(2026, 8, 12, 15, 1),
        ),
        _record(
          reference: 'RR-COMPLETE-ACTIVE',
          status: 'accepted_for_trip',
          createdAt: DateTime(2026, 8, 12, 15),
        ),
      ],
      tripLoader: (reference) async => PassengerTripRecord(
        tripReference: reference,
        status: 'completed_confirmed',
      ),
    );

    await _pumpHistory(tester, repository);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('trip-filter-completed')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('ride-request-RR-COMPLETE-CONFIRMED')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('ride-request-RR-COMPLETE-PENDING')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('ride-request-RR-COMPLETE-ACTIVE')),
      findsNothing,
    );

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('ride-request-RR-COMPLETE-CONVERTED')),
      260,
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('ride-request-RR-COMPLETE-CONVERTED')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('ride-request-RR-COMPLETE-ACTIVE')),
      findsNothing,
    );
    expect(repository.tripCalls, <String>['TRIP-COMPLETE-CONVERTED']);
  });

  testWidgets('test_fare_shown_when_available', (tester) async {
    await _pumpHistory(
      tester,
      _FakeRepository(
        listLoader: () async => <PassengerRideRequestRecord>[
          _record(
            reference: 'RR-FARE-CONFIRMED',
            status: 'completed_confirmed',
            fareDisplay: 'GHS 35',
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('GH₵35.00'), findsOneWidget);
    expect(find.byKey(const Key('history-card-fare')), findsOneWidget);
  });

  testWidgets('test_fare_hidden_when_not_confirmed', (tester) async {
    await _pumpHistory(
      tester,
      _FakeRepository(
        listLoader: () async => <PassengerRideRequestRecord>[
          _record(
            reference: 'RR-FARE-ACTIVE',
            status: 'accepted_for_trip',
            fareDisplay: 'GHS 35',
          ),
          _record(
            reference: 'RR-FARE-ZERO',
            status: 'completed_confirmed',
            fareDisplay: '0',
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('GH₵35.00'), findsNothing);
    expect(find.text('GH₵0.00'), findsNothing);
    expect(find.byKey(const Key('history-card-fare')), findsNothing);
  });

  testWidgets('test_date_formatted_human_readable', (tester) async {
    await _pumpHistory(
      tester,
      _FakeRepository(
        listLoader: () async => <PassengerRideRequestRecord>[
          _record(
            reference: 'RR-HUMAN-DATE',
            createdAt: DateTime(2026, 8, 12, 15, 53),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('12 Aug 2026 at 15:53'), findsOneWidget);
    expect(find.textContaining('2026-08-12'), findsNothing);
  });

  testWidgets('test_empty_state_all_tab', (tester) async {
    var bookRideTapped = false;

    await _pumpHistory(
      tester,
      _FakeRepository(
        listLoader: () async => const <PassengerRideRequestRecord>[],
      ),
      onBookRide: () {
        bookRideTapped = true;
      },
    );
    await tester.pumpAndSettle();

    expect(
      find.text('No trips yet. Book your first ALANTEH ride.'),
      findsOneWidget,
    );
    expect(find.text('Book a ride'), findsOneWidget);

    await tester.tap(find.byKey(const Key('empty-history-book-ride')));
    await tester.pump();

    expect(bookRideTapped, isTrue);
  });

  testWidgets('test_empty_state_active_tab', (tester) async {
    await _pumpHistory(
      tester,
      _FakeRepository(
        listLoader: () async => const <PassengerRideRequestRecord>[],
      ),
      onBookRide: () {},
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('trip-filter-active')));
    await tester.pumpAndSettle();

    expect(find.text('No active rides right now.'), findsOneWidget);
    expect(find.text('Book a ride'), findsOneWidget);
  });

  testWidgets('test_empty_state_completed_tab', (tester) async {
    await _pumpHistory(
      tester,
      _FakeRepository(
        listLoader: () async => const <PassengerRideRequestRecord>[],
      ),
      onBookRide: () {},
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('trip-filter-completed')));
    await tester.pumpAndSettle();

    expect(find.text('No completed trips yet.'), findsOneWidget);
    expect(find.text('Book a ride'), findsNothing);
  });

  test('Passenger navigation and receipt link to request history', () {
    final homeSource = File('lib/passenger_home.dart').readAsStringSync();

    final shellSource = File('lib/passenger_shell.dart').readAsStringSync();

    final reviewSource = File(
      'lib/booking/booking_review.dart',
    ).readAsStringSync();

    expect(homeSource, contains("label: const Text('My Ride Requests')"));
    expect(homeSource, contains("Key('open-ride-request-history')"));
    expect(reviewSource, contains("label: const Text('View my requests')"));
    expect(reviewSource, isNot(contains("label: const Text('Back to home')")));
    expect(
      RegExp(
        r'if \(widget\.rideRequestHistoryRepository != null\)',
      ).allMatches(shellSource),
      hasLength(2),
    );
    expect(
      RegExp(r'await _openRideRequests\(\);').allMatches(shellSource),
      hasLength(2),
    );
    expect(shellSource, contains('1 => PassengerRideRequestHistoryPage('));
    expect(
      shellSource,
      contains('const EmptyPassengerRideRequestHistoryRepository()'),
    );
    expect(shellSource, isNot(contains("title: 'No ride requests yet'")));
  });

  test('Driver app remains free of Passenger history integration', () {
    final driverDirectory = Directory('../driver_app/lib');

    expect(driverDirectory.existsSync(), isTrue);

    final source = driverDirectory
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .map((file) => file.readAsStringSync())
        .join('\n');

    expect(source, isNot(contains('/api/rides/requests/')));
    expect(source, isNot(contains('PassengerRideRequestHistory')));
  });
}

Future<void> _pumpHistory(
  WidgetTester tester,
  PassengerRideRequestHistoryRepository repository, {
  VoidCallback? onSignInRequired,
  PassengerPaymentRatingRepository? paymentRatingRepository,
  Future<void> Function(PassengerRideRequestRecord)? onOpenActiveTracking,
  ValueChanged<PassengerRideRequestRecord>? onBookAgain,
  ValueChanged<PassengerRideRequestRecord>? onReturn,
  VoidCallback? onBookRide,
}) async {
  tester.view.physicalSize = const Size(430, 900);
  tester.view.devicePixelRatio = 1;

  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: AsmThemes.passenger,
      home: PassengerRideRequestHistoryPage(
        repository: repository,
        paymentRatingRepository: paymentRatingRepository,
        onSignInRequired: onSignInRequired,
        onOpenActiveTracking: onOpenActiveTracking,
        onBookAgain: onBookAgain,
        onReturn: onReturn,
        onBookRide: onBookRide,
      ),
    ),
  );
}

PassengerRideRequestRecord _record({
  required String reference,
  String pickup = 'Pickup',
  String destination = 'Destination',
  String status = 'requested',
  int passengerCount = 1,
  DateTime? requestedPickupTime,
  bool tripCreated = false,
  String? latestStaffState,
  DateTime? createdAt,
  String? controlCenterMessage,
  String? tripReference,
  String? fareDisplay,
  bool hasMobileReceipt = true,
}) {
  return PassengerRideRequestRecord(
    requestReference: reference,
    status: status,
    pickupLocation: pickup,
    destination: destination,
    passengerCount: passengerCount,
    requestedPickupTime: requestedPickupTime,
    createdAt: createdAt ?? DateTime.utc(2026, 7, 11, 12),
    updatedAt: DateTime.utc(2026, 7, 11, 13),
    hasMobileReceipt: hasMobileReceipt,
    tripCreated: tripCreated,
    latestStaffState: latestStaffState,
    controlCenterMessage: controlCenterMessage,
    tripReference: tripReference,
    fareDisplay: fareDisplay,
  );
}

Map<String, Object?> _recordJson({
  required String reference,
  String status = 'requested',
  String? controlCenterMessage,
  String? tripReference,
}) {
  final result = <String, Object?>{
    'request_reference': reference,
    'status': status,
    'pickup_location': 'Accra Mall',
    'destination': 'Kotoka International Airport',
    'passenger_count': 1,
    'requested_pickup_time': null,
    'created_at': '2026-07-11T12:00:00Z',
    'updated_at': '2026-07-11T13:00:00Z',
    'source_channel': 'passenger_app',
    'has_mobile_receipt': true,
    'latest_staff_state': 'Request received.',
    'trip_created': false,
  };
  if (controlCenterMessage != null) {
    result['control_center_message'] = controlCenterMessage;
  }
  if (tripReference != null) {
    result['trip_reference'] = tripReference;
  }
  return result;
}

class _FakeRepository implements PassengerRideRequestHistoryRepository {
  const _FakeRepository({required this.listLoader, this.detailLoader});

  final Future<List<PassengerRideRequestRecord>> Function() listLoader;

  final Future<PassengerRideRequestRecord> Function(String requestReference)?
  detailLoader;

  @override
  Future<List<PassengerRideRequestRecord>> fetchRequests() {
    return listLoader();
  }

  @override
  Future<PassengerRideRequestRecord> fetchRequest(String requestReference) {
    final loader = detailLoader;
    if (loader == null) {
      return Future<PassengerRideRequestRecord>.error(
        const PassengerRideRequestHistoryException.notFound(),
      );
    }
    return loader(requestReference);
  }
}

class _TripAwareFakeRepository
    implements
        PassengerRideRequestHistoryRepository,
        PassengerTripLifecycleRepository {
  _TripAwareFakeRepository({
    required this.listLoader,
    required this.tripLoader,
  });

  final Future<List<PassengerRideRequestRecord>> Function() listLoader;
  final Future<PassengerTripRecord> Function(String tripReference) tripLoader;
  final List<String> tripCalls = <String>[];

  @override
  Future<List<PassengerRideRequestRecord>> fetchRequests() {
    return listLoader();
  }

  @override
  Future<PassengerRideRequestRecord> fetchRequest(String requestReference) {
    return Future<PassengerRideRequestRecord>.error(
      const PassengerRideRequestHistoryException.notFound(),
    );
  }

  @override
  Future<PassengerTripRecord> fetchTrip(String tripReference) {
    tripCalls.add(tripReference);
    return tripLoader(tripReference);
  }
}

class _FakeHistoryGateway implements PassengerRideRequestHistoryApiGateway {
  _FakeHistoryGateway({required this.responses});

  final Map<String, Object?> responses;
  final List<String> paths = <String>[];

  @override
  Future<ApiResponse<T>> get<T>(String path, {JsonDecoder<T>? decoder}) async {
    paths.add(path);

    final payload = responses[path];

    if (payload == null || decoder == null) {
      return ApiResponse.apiFailure(
        const AsmApiException(
          type: AsmApiExceptionType.notFound,
          message: 'Not found.',
          statusCode: 404,
        ),
      );
    }

    return ApiResponse.success(decoder(payload), statusCode: 200);
  }
}

class _HistoryPaymentRatingRepository
    implements PassengerPaymentRatingRepository {
  final List<String> references = <String>[];
  int receiptCalls = 0;

  @override
  Future<PassengerFareSnapshot> fetchFare(String requestReference) async {
    references.add(requestReference);

    return PassengerFareSnapshot(
      requestReference: requestReference,
      fareStatus: 'fare_not_ready',
      canPay: false,
      message: 'The final fare is not ready yet.',
    );
  }

  @override
  Future<PassengerPaymentSnapshot> fetchPayment(String requestReference) async {
    references.add(requestReference);

    return PassengerPaymentSnapshot(
      requestReference: requestReference,
      paymentStatus: 'payment_not_available',
      canPay: false,
      canRetry: false,
      message: 'Payment is not available yet.',
    );
  }

  @override
  Future<PassengerRatingSnapshot> fetchRating(String requestReference) async {
    references.add(requestReference);

    return PassengerRatingSnapshot(
      requestReference: requestReference,
      ratingStatus: 'rating_not_open',
      canRate: false,
      message: 'Rating is not available yet.',
    );
  }

  @override
  Future<PassengerPaymentSnapshot> initiatePayment(
    String requestReference, {
    required String idempotencyKey,
  }) {
    throw StateError('Payment initiation was not expected.');
  }

  @override
  Future<PassengerPaymentReceiptSnapshot> fetchReceipt(
    String requestReference,
  ) {
    receiptCalls += 1;
    throw const PassengerPaymentRatingException.notFound();
  }

  @override
  Future<PassengerRatingSnapshot> submitRating(
    String requestReference,
    PassengerRatingSubmission submission,
  ) {
    throw StateError('Rating submission was not expected.');
  }
}
