import 'dart:async';

import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_auth/asm_auth.dart';
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
    await tester.ensureVisible(find.byKey(const Key('new-message-send')));
    await tester.pumpAndSettle();
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

  testWidgets('test_choose_trip_tap_opens_trip_picker', (tester) async {
    await _pumpForm(
      tester,
      initialCategory: 'Lost item',
      repository: _FakeTripHistoryRepository(),
      submitter: _RecordingSupportMessageSubmitter(),
    );

    await tester.tap(find.byKey(const Key('new-message-trip')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('new-message-trip-picker')), findsOneWidget);
    expect(find.byKey(const Key('new-message-trip-empty')), findsOneWidget);
  });

  testWidgets('test_trip_picker_loads_existing_trip_history', (tester) async {
    final repository = _FakeTripHistoryRepository(
      records: <PassengerRideRequestRecord>[
        _tripRecord(
          tripReference: 'TRIP-LOAD123',
          pickup: 'Airport',
          destination: 'Osu',
          createdAt: DateTime(2026, 8, 11, 9),
        ),
      ],
    );

    await _pumpForm(
      tester,
      initialCategory: 'Lost item',
      repository: repository,
      submitter: _RecordingSupportMessageSubmitter(),
    );

    expect(repository.fetchRequestsCalls, 1);

    await tester.tap(find.byKey(const Key('new-message-trip')));
    await tester.pumpAndSettle();

    expect(repository.fetchRequestsCalls, 1);
    expect(
      find.byKey(const ValueKey('new-message-trip-option-TRIP-LOAD123')),
      findsOneWidget,
    );
  });

  testWidgets('test_trip_picker_displays_route_and_date', (tester) async {
    await _pumpForm(
      tester,
      initialCategory: 'Lost item',
      repository: _FakeTripHistoryRepository(
        records: <PassengerRideRequestRecord>[
          _tripRecord(
            tripReference: 'TRIP-DISPLAY123',
            pickup: 'Accra Mall',
            destination: 'Osu',
            createdAt: DateTime(2026, 8, 10, 12),
          ),
        ],
      ),
      submitter: _RecordingSupportMessageSubmitter(),
    );

    await tester.tap(find.byKey(const Key('new-message-trip')));
    await tester.pumpAndSettle();

    expect(find.text('Accra Mall → Osu'), findsOneWidget);
    expect(find.text('10 Aug 2026'), findsOneWidget);
  });

  testWidgets('test_trip_selection_returns_trip_reference', (tester) async {
    final submitter = _RecordingSupportMessageSubmitter();

    await _pumpForm(
      tester,
      initialCategory: 'Lost item',
      repository: _FakeTripHistoryRepository(
        records: <PassengerRideRequestRecord>[
          _tripRecord(
            tripReference: 'TRIP-SELECT123',
            pickup: 'Airport',
            destination: 'East Legon',
            createdAt: DateTime(2026, 8, 12, 10),
          ),
        ],
      ),
      submitter: submitter,
    );

    await tester.tap(find.byKey(const Key('new-message-trip')));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('new-message-trip-option-TRIP-SELECT123')),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Airport → East Legon'), findsOneWidget);

    await _fillValidRequiredFields(tester);
    await tester.tap(find.byKey(const Key('new-message-send')));
    await tester.pumpAndSettle();

    expect(submitter.calls, 1);
    expect(submitter.lastTripReference, 'TRIP-SELECT123');
  });

  testWidgets('test_trip_picker_remains_optional', (tester) async {
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

  testWidgets('test_choose_trip_control_is_tappable_when_form_loaded', (
    tester,
  ) async {
    await _pumpForm(
      tester,
      initialCategory: 'Lost item',
      repository: _FakeTripHistoryRepository(),
      submitter: _RecordingSupportMessageSubmitter(),
    );

    final control = _renderedTripTextField(tester);
    expect(control.readOnly, isTrue);
    expect(control.onTap, isNotNull);

    await tester.tap(find.byKey(const Key('new-message-trip')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('new-message-trip-picker')), findsOneWidget);
  });

  testWidgets('test_choose_trip_field_renders_single_non_overlapping_prompt', (
    tester,
  ) async {
    await _pumpForm(
      tester,
      initialCategory: 'Lost item',
      repository: _FakeTripHistoryRepository(),
      submitter: _RecordingSupportMessageSubmitter(),
    );

    final field = _renderedTripTextField(tester);

    expect(field.decoration?.labelText, isNull);
    expect(field.decoration?.hintText, 'Select a trip (optional)');
    expect(find.text('Select a trip (optional)'), findsOneWidget);
    expect(find.text('Choose trip (optional)'), findsNothing);
  });

  testWidgets('test_choose_trip_field_enabled_after_trip_history_load', (
    tester,
  ) async {
    final repository = _FakeTripHistoryRepository(
      records: <PassengerRideRequestRecord>[
        _tripRecord(
          tripReference: 'TRIP-ENABLED123',
          pickup: 'Airport',
          destination: 'Osu',
          createdAt: DateTime(2026, 8, 13, 8),
        ),
      ],
    );

    await _pumpForm(
      tester,
      initialCategory: 'Lost item',
      repository: repository,
      submitter: _RecordingSupportMessageSubmitter(),
    );

    expect(repository.fetchRequestsCalls, 1);

    final field = _renderedTripTextField(tester);
    expect(field.readOnly, isTrue);
    expect(field.onTap, isNotNull);
    expect(field.decoration?.enabled, isTrue);
  });

  testWidgets('test_tapping_rendered_choose_trip_field_opens_picker', (
    tester,
  ) async {
    await _pumpForm(
      tester,
      initialCategory: 'Lost item',
      repository: _FakeTripHistoryRepository(
        records: <PassengerRideRequestRecord>[
          _tripRecord(
            tripReference: 'TRIP-TAP123',
            pickup: 'Airport',
            destination: 'Osu',
            createdAt: DateTime(2026, 8, 13, 8),
          ),
        ],
      ),
      submitter: _RecordingSupportMessageSubmitter(),
    );

    await tester.tap(find.byKey(const Key('new-message-trip')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('new-message-trip-picker')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('new-message-trip-option-TRIP-TAP123')),
      findsOneWidget,
    );
  });

  testWidgets('test_picker_displays_trip_route_and_date', (tester) async {
    await _pumpForm(
      tester,
      initialCategory: 'Lost item',
      repository: _FakeTripHistoryRepository(
        records: <PassengerRideRequestRecord>[
          _tripRecord(
            tripReference: 'TRIP-VISUAL123',
            pickup: 'Accra Mall',
            destination: 'Osu',
            createdAt: DateTime(2026, 8, 13, 9),
          ),
        ],
      ),
      submitter: _RecordingSupportMessageSubmitter(),
    );

    await tester.tap(find.byKey(const Key('new-message-trip')));
    await tester.pumpAndSettle();

    expect(find.text('Accra Mall → Osu'), findsOneWidget);
    expect(find.text('13 Aug 2026'), findsOneWidget);
  });

  testWidgets('test_selecting_trip_sets_trip_reference', (tester) async {
    final submitter = _RecordingSupportMessageSubmitter();

    await _pumpForm(
      tester,
      initialCategory: 'Lost item',
      repository: _FakeTripHistoryRepository(
        records: <PassengerRideRequestRecord>[
          _tripRecord(
            tripReference: 'TRIP-SET123',
            pickup: 'Airport',
            destination: 'East Legon',
            createdAt: DateTime(2026, 8, 13, 10),
          ),
        ],
      ),
      submitter: submitter,
    );

    await tester.tap(find.byKey(const Key('new-message-trip')));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('new-message-trip-option-TRIP-SET123')),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Airport → East Legon'), findsOneWidget);

    await _fillValidRequiredFields(tester);
    await tester.tap(find.byKey(const Key('new-message-send')));
    await tester.pumpAndSettle();

    expect(submitter.calls, 1);
    expect(submitter.lastTripReference, 'TRIP-SET123');
  });

  testWidgets('test_choose_trip_remains_optional', (tester) async {
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

  testWidgets('test_trip_history_async_completion_enables_real_control', (
    tester,
  ) async {
    final repository = _CompletingTripHistoryRepository();

    await _pumpForm(
      tester,
      initialCategory: 'Lost item',
      repository: repository,
      submitter: _RecordingSupportMessageSubmitter(),
    );

    var field = _renderedTripTextField(tester);
    expect(field.onTap, isNotNull);

    repository.complete(<PassengerRideRequestRecord>[
      _tripRecord(
        tripReference: 'TRIP-ASYNC123',
        pickup: 'Airport',
        destination: 'Osu',
        createdAt: DateTime(2026, 8, 13, 11),
      ),
    ]);
    await tester.pump();

    field = _renderedTripTextField(tester);
    expect(field.onTap, isNotNull);

    await tester.tap(find.byKey(const Key('new-message-trip')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('new-message-trip-picker')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('new-message-trip-option-TRIP-ASYNC123')),
      findsOneWidget,
    );
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

  testWidgets(
    'test_ios_small_viewport_keyboard_does_not_overflow_new_message_form',
    (tester) async {
      await _pumpCompactKeyboardForm(
        tester,
        repository: _FakeTripHistoryRepository(),
        submitter: _RecordingSupportMessageSubmitter(),
      );

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('new-message-scroll-view')), findsOneWidget);
    },
  );

  testWidgets('test_message_field_remains_reachable_with_keyboard_open', (
    tester,
  ) async {
    await _pumpCompactKeyboardForm(
      tester,
      repository: _FakeTripHistoryRepository(),
      submitter: _RecordingSupportMessageSubmitter(),
    );

    final message = find.byKey(const Key('new-message-message'));
    await tester.ensureVisible(message);
    await tester.pumpAndSettle();

    expect(message.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('test_send_action_remains_reachable_with_keyboard_open', (
    tester,
  ) async {
    await _pumpCompactKeyboardForm(
      tester,
      repository: _FakeTripHistoryRepository(),
      submitter: _RecordingSupportMessageSubmitter(),
    );

    final send = find.byKey(const Key('new-message-send'));
    await tester.ensureVisible(send);
    await tester.pumpAndSettle();

    expect(send.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('test_message_under_10_characters_blocks_submission', (
    tester,
  ) async {
    final submitter = _RecordingSupportMessageSubmitter();

    await _pumpForm(
      tester,
      initialCategory: 'Lost item',
      repository: _FakeTripHistoryRepository(),
      submitter: submitter,
    );

    await tester.enterText(
      find.byKey(const Key('new-message-message')),
      'QA lost',
    );
    await tester.tap(find.byKey(const Key('new-message-send')));
    await tester.pump();

    expect(submitter.calls, 0);
    expect(find.byKey(const Key('new-message-success')), findsNothing);
  });

  test(
    'test_under_10_message_makes_zero_support_message_post_requests',
    () async {
      final client = _RecordingSupportMessageApiClient();
      final tokenStore = _SupportMessageAuthTokenStore(
        accessToken: 'test-access-token',
      );
      final submitter = ApiPassengerSupportMessageSubmitter(
        client,
        tokenStore: tokenStore,
        connectionConfigured: true,
      );

      await expectLater(
        submitter.submit(
          category: 'Lost item',
          tripReference: null,
          name: 'Test Passenger',
          message: 'QA lost',
        ),
        throwsA(
          isA<PassengerSupportMessageException>().having(
            (error) => error.message,
            'message',
            'Message must be at least 10 characters.',
          ),
        ),
      );

      expect(client.postCalls, 0);
    },
  );

  testWidgets('test_message_10_characters_or_more_allows_submission', (
    tester,
  ) async {
    final submitter = _RecordingSupportMessageSubmitter();

    await _pumpForm(
      tester,
      initialCategory: 'Lost item',
      repository: _FakeTripHistoryRepository(),
      submitter: submitter,
    );

    await tester.enterText(
      find.byKey(const Key('new-message-message')),
      '1234567890',
    );
    await tester.tap(find.byKey(const Key('new-message-send')));
    await tester.pumpAndSettle();

    expect(submitter.calls, 1);
    expect(find.byKey(const Key('new-message-success')), findsOneWidget);
  });

  testWidgets('test_validation_error_visible_for_short_message', (
    tester,
  ) async {
    await _pumpForm(
      tester,
      initialCategory: 'Lost item',
      repository: _FakeTripHistoryRepository(),
      submitter: _RecordingSupportMessageSubmitter(),
    );

    await tester.enterText(
      find.byKey(const Key('new-message-message')),
      'QA lost',
    );
    await tester.tap(find.byKey(const Key('new-message-send')));
    await tester.pump();

    expect(
      find.text('Message must be at least 10 characters.'),
      findsOneWidget,
    );
  });

  testWidgets('test_trip_selection_preserved_when_keyboard_opens', (
    tester,
  ) async {
    final repository = _FakeTripHistoryRepository(
      records: <PassengerRideRequestRecord>[
        _tripRecord(
          tripReference: 'TRIP-KEYBOARD123',
          pickup: 'Airport',
          destination: 'East Legon',
          createdAt: DateTime(2026, 8, 17, 12),
        ),
      ],
    );
    final submitter = _RecordingSupportMessageSubmitter();

    await _pumpCompactForm(
      tester,
      repository: repository,
      submitter: submitter,
      keyboardInset: 0,
    );

    await tester.ensureVisible(find.byKey(const Key('new-message-trip')));
    await tester.tap(find.byKey(const Key('new-message-trip')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('new-message-trip-option-TRIP-KEYBOARD123')),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Airport → East Legon'), findsOneWidget);

    await _pumpCompactForm(
      tester,
      repository: repository,
      submitter: submitter,
      keyboardInset: 300,
    );

    expect(find.textContaining('Airport → East Legon'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpCompactKeyboardForm(
  WidgetTester tester, {
  required PassengerRideRequestHistoryRepository repository,
  required PassengerSupportMessageSubmitter submitter,
}) {
  return _pumpCompactForm(
    tester,
    repository: repository,
    submitter: submitter,
    keyboardInset: 300,
  );
}

Future<void> _pumpCompactForm(
  WidgetTester tester, {
  required PassengerRideRequestHistoryRepository repository,
  required PassengerSupportMessageSubmitter submitter,
  required double keyboardInset,
}) async {
  tester.view.physicalSize = const Size(375, 812);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: AsmThemes.passenger,
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(375, 812),
          devicePixelRatio: 1,
          viewInsets: EdgeInsets.only(bottom: keyboardInset),
        ),
        child: NewMessageForm(
          initialCategory: 'Lost item',
          initialPassengerName: 'Test Passenger',
          tripHistoryRepository: repository,
          submitter: submitter,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
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

TextField _renderedTripTextField(WidgetTester tester) {
  return tester.widget<TextField>(
    find.descendant(
      of: find.byKey(const Key('new-message-trip')),
      matching: find.byType(TextField),
    ),
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

final class _CompletingTripHistoryRepository
    implements PassengerRideRequestHistoryRepository {
  final Completer<List<PassengerRideRequestRecord>> _completer =
      Completer<List<PassengerRideRequestRecord>>();

  int fetchRequestsCalls = 0;

  void complete(List<PassengerRideRequestRecord> records) {
    _completer.complete(records);
  }

  @override
  Future<List<PassengerRideRequestRecord>> fetchRequests() {
    fetchRequestsCalls += 1;
    return _completer.future;
  }

  @override
  Future<PassengerRideRequestRecord> fetchRequest(String requestReference) {
    return Future<PassengerRideRequestRecord>.error(
      const PassengerRideRequestHistoryException.notFound(),
    );
  }
}

final class _FakeTripHistoryRepository
    implements PassengerRideRequestHistoryRepository {
  _FakeTripHistoryRepository({
    this.records = const <PassengerRideRequestRecord>[],
  });

  final List<PassengerRideRequestRecord> records;
  int fetchRequestsCalls = 0;

  @override
  Future<List<PassengerRideRequestRecord>> fetchRequests() async {
    fetchRequestsCalls += 1;
    return records;
  }

  @override
  Future<PassengerRideRequestRecord> fetchRequest(String requestReference) {
    return Future<PassengerRideRequestRecord>.error(
      const PassengerRideRequestHistoryException.notFound(),
    );
  }
}

final class _RecordingSupportMessageApiClient extends AsmApiClient {
  _RecordingSupportMessageApiClient() : super(baseUrl: 'https://example.test');

  int postCalls = 0;

  @override
  Future<ApiResponse<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
    JsonDecoder<T>? decoder,
  }) async {
    postCalls += 1;
    throw StateError('Unexpected support-message POST.');
  }
}

final class _SupportMessageAuthTokenStore implements AuthTokenStore {
  _SupportMessageAuthTokenStore({this._accessToken});

  String? _accessToken;

  @override
  Future<void> saveTokens(AuthTokens tokens) async {
    _accessToken = tokens.accessToken;
  }

  @override
  Future<String?> readAccessToken() async => _accessToken;

  @override
  Future<String?> readRefreshToken() async => null;

  @override
  Future<void> clearTokens() async {
    _accessToken = null;
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
