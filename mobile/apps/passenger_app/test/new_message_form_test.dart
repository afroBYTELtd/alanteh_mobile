import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passenger_app/account/passenger_settings_screen.dart';
import 'package:passenger_app/ride_requests/ride_request_history.dart';
import 'package:passenger_app/support/new_message_form.dart';

void main() {
  setUp(resetPassengerSupportCategorySessionForTesting);
  tearDown(resetPassengerSupportCategorySessionForTesting);

  testWidgets('test_categories_fetched_from_api_on_form_load', (tester) async {
    final client = _RecordingSupportCategoryApiClient(
      responseBody: const <String, Object?>{
        'categories': <Object?>[
          'Lost item',
          'General enquiry',
          'Trip issue',
          'Other',
        ],
      },
    );
    setPassengerSupportCategoryFetcherForTesting(
      ApiPassengerSupportCategoryFetcher(
        client: client,
        connectionConfigured: true,
      ),
    );

    await _pumpForm(
      tester,
      repository: _FakeTripHistoryRepository(),
      submitter: _RecordingSupportMessageSubmitter(),
    );

    expect(client.getCalls, 1);
    expect(client.lastPath, passengerSupportCategoriesEndpoint);
  });

  testWidgets('test_api_categories_populate_dropdown', (tester) async {
    setPassengerSupportCategoryFetcherForTesting(
      _FakeSupportCategoryFetcher(
        categories: const <String>['API category A', 'API category B'],
      ),
    );

    await _pumpForm(
      tester,
      repository: _FakeTripHistoryRepository(),
      submitter: _RecordingSupportMessageSubmitter(),
    );

    final dropdown = tester.widget<DropdownButton<String>>(
      find.descendant(
        of: find.byKey(const Key('new-message-category')),
        matching: find.byType(DropdownButton<String>),
      ),
    );

    expect(
      dropdown.items!.map((item) => item.value).toList(growable: false),
      const <String>['API category A', 'API category B'],
    );
  });

  testWidgets('test_fallback_categories_used_when_fetch_fails', (tester) async {
    setPassengerSupportCategoryFetcherForTesting(
      _FakeSupportCategoryFetcher(shouldFail: true),
    );

    await _pumpForm(
      tester,
      repository: _FakeTripHistoryRepository(),
      submitter: _RecordingSupportMessageSubmitter(),
    );

    final dropdown = tester.widget<DropdownButton<String>>(
      find.descendant(
        of: find.byKey(const Key('new-message-category')),
        matching: find.byType(DropdownButton<String>),
      ),
    );

    expect(
      dropdown.items!.map((item) => item.value).toList(growable: false),
      const <String>['Lost item', 'General enquiry', 'Trip issue', 'Other'],
    );
  });

  testWidgets('test_initial_category_locks_selection_regardless_of_source', (
    tester,
  ) async {
    setPassengerSupportCategoryFetcherForTesting(
      _FakeSupportCategoryFetcher(
        categories: const <String>[
          'Lost item',
          'General enquiry',
          'Trip issue',
          'Other',
        ],
      ),
    );

    await _pumpForm(
      tester,
      initialCategory: 'Lost item',
      repository: _FakeTripHistoryRepository(),
      submitter: _RecordingSupportMessageSubmitter(),
    );

    var field = tester.widget<DropdownButtonFormField<String>>(
      find.byKey(const Key('new-message-category')),
    );
    expect(field.initialValue, 'Lost item');
    expect(field.onChanged, isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    resetPassengerSupportCategorySessionForTesting();
    setPassengerSupportCategoryFetcherForTesting(
      _FakeSupportCategoryFetcher(shouldFail: true),
    );

    await _pumpForm(
      tester,
      initialCategory: 'Lost item',
      repository: _FakeTripHistoryRepository(),
      submitter: _RecordingSupportMessageSubmitter(),
    );

    field = tester.widget<DropdownButtonFormField<String>>(
      find.byKey(const Key('new-message-category')),
    );
    expect(field.initialValue, 'Lost item');
    expect(field.onChanged, isNull);
  });

  testWidgets('test_categories_cached_for_session', (tester) async {
    final fetcher = _FakeSupportCategoryFetcher(
      categories: const <String>[
        'Lost item',
        'General enquiry',
        'Trip issue',
        'Other',
      ],
    );
    setPassengerSupportCategoryFetcherForTesting(fetcher);

    await _pumpForm(
      tester,
      repository: _FakeTripHistoryRepository(),
      submitter: _RecordingSupportMessageSubmitter(),
    );
    expect(fetcher.calls, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    await _pumpForm(
      tester,
      repository: _FakeTripHistoryRepository(),
      submitter: _RecordingSupportMessageSubmitter(),
    );

    expect(fetcher.calls, 1);
  });

  testWidgets('test_lost_item_from_settings_prefills_category', (tester) async {
    await _pumpSettings(
      tester,
      tripRepository: _FakeTripHistoryRepository(),
      submitter: _RecordingSupportMessageSubmitter(),
    );

    await tester.tap(find.byKey(const Key('passenger-settings-lost-item')));
    await tester.pumpAndSettle();

    final field = tester.widget<DropdownButtonFormField<String>>(
      find.byKey(const Key('new-message-category')),
    );

    expect(find.byType(NewMessageForm), findsOneWidget);
    expect(field.initialValue, 'Lost item');
  });

  testWidgets('test_lost_item_category_locked_when_initial_category_provided', (
    tester,
  ) async {
    await _pumpForm(
      tester,
      initialCategory: 'Lost item',
      repository: _FakeTripHistoryRepository(),
      submitter: _RecordingSupportMessageSubmitter(),
    );

    final field = tester.widget<DropdownButtonFormField<String>>(
      find.byKey(const Key('new-message-category')),
    );

    expect(field.initialValue, 'Lost item');
    expect(field.onChanged, isNull);
  });

  testWidgets('test_category_selectable_when_no_initial_category', (
    tester,
  ) async {
    await _pumpForm(
      tester,
      repository: _FakeTripHistoryRepository(),
      submitter: _RecordingSupportMessageSubmitter(),
    );

    final before = tester.widget<DropdownButtonFormField<String>>(
      find.byKey(const Key('new-message-category')),
    );
    expect(before.onChanged, isNotNull);

    await tester.tap(find.byKey(const Key('new-message-category')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('General enquiry').last);
    await tester.pumpAndSettle();

    final after = tester.widget<DropdownButtonFormField<String>>(
      find.byKey(const Key('new-message-category')),
    );
    expect(after.initialValue, 'General enquiry');
  });

  testWidgets('test_send_requires_name_and_message', (tester) async {
    final submitter = _RecordingSupportMessageSubmitter();

    await _pumpForm(
      tester,
      initialCategory: 'Lost item',
      repository: _FakeTripHistoryRepository(),
      submitter: submitter,
    );

    await tester.enterText(find.byKey(const Key('new-message-name')), '');
    await tester.tap(find.byKey(const Key('new-message-send')));
    await tester.pump();

    expect(find.text('Name is required.'), findsOneWidget);
    expect(find.text('Message is required.'), findsOneWidget);
    expect(submitter.calls, 0);

    await tester.enterText(find.byKey(const Key('new-message-name')), 'A');
    await tester.enterText(
      find.byKey(const Key('new-message-message')),
      'Too short',
    );
    await tester.tap(find.byKey(const Key('new-message-send')));
    await tester.pump();

    expect(find.text('Name must be at least 2 characters.'), findsOneWidget);
    expect(
      find.text('Message must be at least 10 characters.'),
      findsOneWidget,
    );
    expect(submitter.calls, 0);
  });

  testWidgets('test_choose_trip_optional', (tester) async {
    final submitter = _RecordingSupportMessageSubmitter();

    await _pumpForm(
      tester,
      initialCategory: 'Lost item',
      repository: _FakeTripHistoryRepository(),
      submitter: submitter,
    );

    await _fillValidRequiredFields(tester);
    await tester.tap(find.byKey(const Key('new-message-send')));
    await tester.pumpAndSettle();

    expect(submitter.calls, 1);
    expect(submitter.lastTripReference, isNull);
    expect(find.byKey(const Key('new-message-success')), findsOneWidget);
  });

  testWidgets('test_attachment_optional', (tester) async {
    final submitter = _RecordingSupportMessageSubmitter();

    await _pumpForm(
      tester,
      initialCategory: 'Lost item',
      repository: _FakeTripHistoryRepository(),
      submitter: submitter,
    );

    await _fillValidRequiredFields(tester);
    expect(
      find.byKey(const Key('new-message-attachment-thumbnail')),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('new-message-send')));
    await tester.pumpAndSettle();

    expect(submitter.calls, 1);
    expect(find.byKey(const Key('new-message-success')), findsOneWidget);
  });

  testWidgets('test_trip_picker_populated_from_history', (tester) async {
    await _pumpForm(
      tester,
      initialCategory: 'Lost item',
      repository: _FakeTripHistoryRepository(
        records: <PassengerRideRequestRecord>[
          _tripRecord(
            tripReference: 'TRIP-ABC123',
            pickup: 'Accra Mall',
            destination: 'Osu',
            createdAt: DateTime(2026, 8, 10, 12),
          ),
        ],
      ),
      submitter: _RecordingSupportMessageSubmitter(),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('new-message-trip')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Accra Mall → Osu'), findsWidgets);
    expect(find.textContaining('10 Aug 2026'), findsWidgets);
  });

  testWidgets('test_success_shows_ticket_reference', (tester) async {
    final submitter = _RecordingSupportMessageSubmitter(
      result: const PassengerSupportMessageResult(reference: 'MSG-ABC1234567'),
    );

    await _pumpForm(
      tester,
      initialCategory: 'Lost item',
      repository: _FakeTripHistoryRepository(),
      submitter: submitter,
    );

    await _fillValidRequiredFields(tester);
    await tester.tap(find.byKey(const Key('new-message-send')));
    await tester.pumpAndSettle();

    expect(find.text('Message sent'), findsWidgets);
    expect(
      find.text(
        'Your message has been received.\n'
        'We will get back to you shortly.',
      ),
      findsOneWidget,
    );
    expect(find.text('Reference: MSG-ABC1234567'), findsOneWidget);
    expect(find.byKey(const Key('new-message-done')), findsOneWidget);
  });

  testWidgets('test_failure_shows_retry', (tester) async {
    final submitter = _RecordingSupportMessageSubmitter(
      failuresBeforeSuccess: 1,
    );

    await _pumpForm(
      tester,
      initialCategory: 'Lost item',
      repository: _FakeTripHistoryRepository(),
      submitter: submitter,
    );

    await _fillValidRequiredFields(tester);
    await tester.tap(find.byKey(const Key('new-message-send')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('new-message-failure-state')), findsOneWidget);
    expect(find.byKey(const Key('new-message-retry')), findsOneWidget);
    expect(_textValue(tester, const Key('new-message-name')), 'Test Passenger');
    expect(
      _textValue(tester, const Key('new-message-message')),
      'I left my bag in the vehicle.',
    );

    await tester.tap(find.byKey(const Key('new-message-retry')));
    await tester.pumpAndSettle();

    expect(submitter.calls, 2);
    expect(find.byKey(const Key('new-message-success')), findsOneWidget);
  });

  testWidgets('test_name_field_remains_editable', (tester) async {
    await _pumpForm(
      tester,
      initialCategory: 'Lost item',
      repository: _FakeTripHistoryRepository(),
      submitter: _RecordingSupportMessageSubmitter(),
    );

    expect(_textValue(tester, const Key('new-message-name')), 'Test Passenger');

    await tester.enterText(
      find.byKey(const Key('new-message-name')),
      'Edited Passenger',
    );
    await tester.pump();

    expect(
      _textValue(tester, const Key('new-message-name')),
      'Edited Passenger',
    );
  });

  testWidgets('test_new_message_form_reusable_widget', (tester) async {
    await _pumpForm(
      tester,
      repository: _FakeTripHistoryRepository(),
      submitter: _RecordingSupportMessageSubmitter(),
    );

    expect(find.byType(NewMessageForm), findsOneWidget);

    final category = tester.widget<DropdownButtonFormField<String>>(
      find.byKey(const Key('new-message-category')),
    );
    expect(category.initialValue, isNull);
    expect(category.onChanged, isNotNull);

    expect(find.byKey(const Key('new-message-name')), findsOneWidget);
    expect(find.byKey(const Key('new-message-trip')), findsOneWidget);
    expect(find.byKey(const Key('new-message-message')), findsOneWidget);
    expect(find.byKey(const Key('new-message-attachment')), findsOneWidget);
    expect(find.byKey(const Key('new-message-send')), findsOneWidget);
  });
}

Future<void> _pumpSettings(
  WidgetTester tester, {
  required PassengerRideRequestHistoryRepository tripRepository,
  required PassengerSupportMessageSubmitter submitter,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AsmThemes.passenger,
      home: PassengerSettingsScreen(
        passengerName: 'Test Passenger',
        tripHistoryRepository: tripRepository,
        supportMessageSubmitter: submitter,
        onAccountDeletionRequested: () async {},
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpForm(
  WidgetTester tester, {
  String? initialCategory,
  required PassengerRideRequestHistoryRepository repository,
  required PassengerSupportMessageSubmitter submitter,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AsmThemes.passenger,
      home: NewMessageForm(
        initialCategory: initialCategory,
        initialPassengerName: 'Test Passenger',
        tripHistoryRepository: repository,
        submitter: submitter,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _fillValidRequiredFields(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('new-message-name')),
    'Test Passenger',
  );
  await tester.enterText(
    find.byKey(const Key('new-message-message')),
    'I left my bag in the vehicle.',
  );
}

String _textValue(WidgetTester tester, Key key) {
  return tester.widget<TextFormField>(find.byKey(key)).controller!.text;
}

PassengerRideRequestRecord _tripRecord({
  required String tripReference,
  required String pickup,
  required String destination,
  required DateTime createdAt,
}) {
  return PassengerRideRequestRecord(
    requestReference: 'RR-TEST',
    status: 'completed_confirmed',
    pickupLocation: pickup,
    destination: destination,
    passengerCount: 1,
    createdAt: createdAt,
    updatedAt: createdAt,
    hasMobileReceipt: true,
    tripCreated: true,
    tripReference: tripReference,
  );
}

final class _FakeSupportCategoryFetcher
    implements PassengerSupportCategoryFetcher {
  _FakeSupportCategoryFetcher({
    this.categories = const <String>[],
    this.shouldFail = false,
  });

  final List<String> categories;
  final bool shouldFail;
  int calls = 0;

  @override
  Future<List<String>> fetch() async {
    calls += 1;
    if (shouldFail) {
      throw const FormatException('Category fetch failed.');
    }
    return categories;
  }
}

final class _RecordingSupportCategoryApiClient extends AsmApiClient {
  _RecordingSupportCategoryApiClient({required this.responseBody})
    : super(baseUrl: 'https://example.test');

  final Map<String, Object?> responseBody;

  int getCalls = 0;
  String? lastPath;

  @override
  Future<ApiResponse<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    JsonDecoder<T>? decoder,
  }) async {
    getCalls += 1;
    lastPath = path;

    final decoded = decoder == null ? responseBody as T : decoder(responseBody);

    return ApiResponse<T>.success(decoded, statusCode: 200);
  }
}

final class _FakeTripHistoryRepository
    implements PassengerRideRequestHistoryRepository {
  _FakeTripHistoryRepository({
    this.records = const <PassengerRideRequestRecord>[],
  });

  final List<PassengerRideRequestRecord> records;

  @override
  Future<List<PassengerRideRequestRecord>> fetchRequests() async => records;

  @override
  Future<PassengerRideRequestRecord> fetchRequest(String requestReference) {
    return Future<PassengerRideRequestRecord>.error(
      const PassengerRideRequestHistoryException.notFound(),
    );
  }
}

final class _RecordingSupportMessageSubmitter
    implements PassengerSupportMessageSubmitter {
  _RecordingSupportMessageSubmitter({
    this.result = const PassengerSupportMessageResult(
      reference: 'MSG-TEST123456',
    ),
    this.failuresBeforeSuccess = 0,
  });

  final PassengerSupportMessageResult result;
  final int failuresBeforeSuccess;

  int calls = 0;
  String? lastTripReference;

  @override
  Future<PassengerSupportMessageResult> submit({
    required String category,
    required String? tripReference,
    required String name,
    required String message,
  }) async {
    calls += 1;
    lastTripReference = tripReference;

    if (calls <= failuresBeforeSuccess) {
      throw const PassengerSupportMessageException(
        'Support messaging is temporarily unavailable. Please try again later.',
      );
    }

    return result;
  }
}
