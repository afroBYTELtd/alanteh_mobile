import 'dart:async';

import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_auth/asm_auth.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passenger_app/account/passenger_settings_screen.dart';
import 'package:passenger_app/passenger_shell.dart';

void main() {
  testWidgets('test_settings_screen_reachable_from_account_tab', (
    tester,
  ) async {
    final store = _MemoryPreferenceStore();
    final opener = _RecordingLegalLinkOpener();

    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: PassengerShell(
          settingsPreferenceStore: store,
          legalLinkOpener: opener,
        ),
      ),
    );

    await tester.tap(find.text('Account'));
    await tester.pumpAndSettle();

    final settingsRow = find.byKey(const Key('passenger-account-settings'));
    await tester.ensureVisible(settingsRow);
    await tester.tap(settingsRow);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('passenger-settings-screen')), findsOneWidget);
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Legal'), findsOneWidget);
    expect(find.text('Account'), findsOneWidget);
  });

  testWidgets('test_notification_toggles_persist_locally', (tester) async {
    final store = _MemoryPreferenceStore();

    await _pumpSettings(tester, store: store);

    expect(_switchValue(tester, 'passenger-settings-ride-updates'), isTrue);
    expect(_switchValue(tester, 'passenger-settings-sound-alerts'), isTrue);

    await tester.tap(find.byKey(const Key('passenger-settings-ride-updates')));
    await tester.pump();

    await tester.tap(find.byKey(const Key('passenger-settings-sound-alerts')));
    await tester.pump();

    expect(store.rideUpdates, isFalse);
    expect(store.soundAlerts, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    await _pumpSettings(tester, store: store);

    expect(_switchValue(tester, 'passenger-settings-ride-updates'), isFalse);
    expect(_switchValue(tester, 'passenger-settings-sound-alerts'), isFalse);
  });

  testWidgets('test_privacy_policy_tap_opens_dialog_not_browser', (
    tester,
  ) async {
    final opener = _RecordingLegalLinkOpener();
    final pending = Completer<PassengerLegalDocument>();
    final fetcher = _RecordingLegalDocumentFetcher(pending: pending);

    await _pumpSettings(
      tester,
      store: _MemoryPreferenceStore(),
      opener: opener,
      legalDocumentFetcher: fetcher,
    );

    expect(fetcher.paths, isEmpty);

    await tester.tap(
      find.byKey(const Key('passenger-settings-privacy-policy')),
    );
    await tester.pump();

    expect(find.byKey(const Key('passenger-legal-dialog')), findsOneWidget);
    expect(
      find.byKey(const Key('passenger-legal-dialog-loading')),
      findsOneWidget,
    );
    expect(fetcher.paths, <String>[passengerPrivacyPolicyEndpoint]);
    expect(opener.opened, isEmpty);

    pending.complete(
      const PassengerLegalDocument(
        title: 'Privacy Policy',
        content: 'Privacy content',
      ),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('test_terms_tap_opens_dialog_not_browser', (tester) async {
    final opener = _RecordingLegalLinkOpener();
    final pending = Completer<PassengerLegalDocument>();
    final fetcher = _RecordingLegalDocumentFetcher(pending: pending);

    await _pumpSettings(
      tester,
      store: _MemoryPreferenceStore(),
      opener: opener,
      legalDocumentFetcher: fetcher,
    );

    expect(fetcher.paths, isEmpty);

    await tester.tap(find.byKey(const Key('passenger-settings-terms')));
    await tester.pump();

    expect(find.byKey(const Key('passenger-legal-dialog')), findsOneWidget);
    expect(
      find.byKey(const Key('passenger-legal-dialog-loading')),
      findsOneWidget,
    );
    expect(fetcher.paths, <String>[passengerTermsOfServiceEndpoint]);
    expect(opener.opened, isEmpty);

    pending.complete(
      const PassengerLegalDocument(
        title: 'Terms of Service',
        content: 'Terms content',
      ),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('test_dialog_shows_title_from_api_response', (tester) async {
    final fetcher = _RecordingLegalDocumentFetcher(
      documents: const <String, PassengerLegalDocument>{
        passengerPrivacyPolicyEndpoint: PassengerLegalDocument(
          title: 'ALANTEH Privacy Policy',
          content: 'Privacy document body.',
        ),
      },
    );

    await _pumpSettings(
      tester,
      store: _MemoryPreferenceStore(),
      legalDocumentFetcher: fetcher,
    );

    await tester.tap(
      find.byKey(const Key('passenger-settings-privacy-policy')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('passenger-legal-dialog-title')),
      findsOneWidget,
    );
    expect(find.text('ALANTEH Privacy Policy'), findsOneWidget);
  });

  testWidgets('test_dialog_shows_content_from_api_response', (tester) async {
    const apiContent =
        'This privacy policy content came from the public content API.';
    final fetcher = _RecordingLegalDocumentFetcher(
      documents: const <String, PassengerLegalDocument>{
        passengerPrivacyPolicyEndpoint: PassengerLegalDocument(
          title: 'Privacy Policy',
          content: apiContent,
        ),
      },
    );

    await _pumpSettings(
      tester,
      store: _MemoryPreferenceStore(),
      legalDocumentFetcher: fetcher,
    );

    await tester.tap(
      find.byKey(const Key('passenger-settings-privacy-policy')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('passenger-legal-dialog-content')),
      findsOneWidget,
    );
    expect(find.text(apiContent), findsOneWidget);
  });

  testWidgets('test_ok_button_dismisses_dialog', (tester) async {
    final fetcher = _RecordingLegalDocumentFetcher(
      documents: const <String, PassengerLegalDocument>{
        passengerPrivacyPolicyEndpoint: PassengerLegalDocument(
          title: 'Privacy Policy',
          content: 'Privacy document body.',
        ),
      },
    );

    await _pumpSettings(
      tester,
      store: _MemoryPreferenceStore(),
      legalDocumentFetcher: fetcher,
    );

    await tester.tap(
      find.byKey(const Key('passenger-settings-privacy-policy')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('passenger-legal-dialog-ok')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('passenger-legal-dialog')), findsNothing);
  });

  testWidgets('test_ok_returns_to_settings_no_navigation_change', (
    tester,
  ) async {
    final fetcher = _RecordingLegalDocumentFetcher(
      documents: const <String, PassengerLegalDocument>{
        passengerTermsOfServiceEndpoint: PassengerLegalDocument(
          title: 'Terms of Service',
          content: 'Terms document body.',
        ),
      },
    );

    await _pumpSettings(
      tester,
      store: _MemoryPreferenceStore(),
      legalDocumentFetcher: fetcher,
    );

    await tester.tap(find.byKey(const Key('passenger-settings-terms')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('passenger-legal-dialog-ok')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('passenger-settings-screen')), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.byKey(const Key('passenger-legal-dialog')), findsNothing);
  });

  testWidgets('test_api_failure_shows_fallback_message_in_dialog', (
    tester,
  ) async {
    final fetcher = _RecordingLegalDocumentFetcher(failing: true);

    await _pumpSettings(
      tester,
      store: _MemoryPreferenceStore(),
      legalDocumentFetcher: fetcher,
    );

    await tester.tap(
      find.byKey(const Key('passenger-settings-privacy-policy')),
    );
    await tester.pumpAndSettle();

    expect(find.text(passengerPrivacyPolicyFailureMessage), findsOneWidget);
    expect(find.byKey(const Key('passenger-legal-dialog-ok')), findsOneWidget);

    await tester.tap(find.byKey(const Key('passenger-legal-dialog-ok')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('passenger-settings-terms')));
    await tester.pumpAndSettle();

    expect(find.text(passengerTermsOfServiceFailureMessage), findsOneWidget);
    expect(find.byKey(const Key('passenger-legal-dialog-ok')), findsOneWidget);
  });

  testWidgets('test_no_url_opened_under_any_condition', (tester) async {
    final opener = _RecordingLegalLinkOpener();
    final fetcher = _MixedLegalDocumentFetcher();

    await _pumpSettings(
      tester,
      store: _MemoryPreferenceStore(),
      opener: opener,
      legalDocumentFetcher: fetcher,
    );

    await tester.tap(
      find.byKey(const Key('passenger-settings-privacy-policy')),
    );
    await tester.pumpAndSettle();
    expect(opener.opened, isEmpty);

    await tester.tap(find.byKey(const Key('passenger-legal-dialog-ok')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('passenger-settings-terms')));
    await tester.pumpAndSettle();
    expect(find.text(passengerTermsOfServiceFailureMessage), findsOneWidget);
    expect(opener.opened, isEmpty);

    await tester.tap(find.byKey(const Key('passenger-legal-dialog-ok')));
    await tester.pumpAndSettle();
    expect(opener.opened, isEmpty);
  });

  testWidgets('test_content_area_scrollable_independently', (tester) async {
    final longContent = List<String>.generate(
      80,
      (index) => 'Legal document paragraph ${index + 1}.',
    ).join('\n\n');
    final fetcher = _RecordingLegalDocumentFetcher(
      documents: <String, PassengerLegalDocument>{
        passengerPrivacyPolicyEndpoint: PassengerLegalDocument(
          title: 'Scrollable Privacy Policy',
          content: longContent,
        ),
      },
    );

    await _pumpSettings(
      tester,
      store: _MemoryPreferenceStore(),
      legalDocumentFetcher: fetcher,
    );

    await tester.tap(
      find.byKey(const Key('passenger-settings-privacy-policy')),
    );
    await tester.pumpAndSettle();

    final scrollFinder = find.byKey(
      const Key('passenger-legal-dialog-content-scroll'),
    );
    final titleFinder = find.byKey(const Key('passenger-legal-dialog-title'));
    final okFinder = find.byKey(const Key('passenger-legal-dialog-ok'));
    final contentFinder = find.byKey(
      const Key('passenger-legal-dialog-content'),
    );

    expect(scrollFinder, findsOneWidget);
    expect(
      find.ancestor(
        of: contentFinder,
        matching: find.byType(SingleChildScrollView),
      ),
      findsOneWidget,
    );
    expect(
      find.ancestor(
        of: titleFinder,
        matching: find.byType(SingleChildScrollView),
      ),
      findsNothing,
    );
    expect(
      find.ancestor(of: okFinder, matching: find.byType(SingleChildScrollView)),
      findsNothing,
    );

    final beforeTitle = tester.getTopLeft(titleFinder);
    final beforeOk = tester.getTopLeft(okFinder);

    await tester.drag(scrollFinder, const Offset(0, -300));
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(titleFinder), beforeTitle);
    expect(tester.getTopLeft(okFinder), beforeOk);
  });

  testWidgets('test_delete_account_confirmation_dialog_shows', (tester) async {
    await _pumpSettings(
      tester,
      store: _MemoryPreferenceStore(),
      deleteAccountLiveEnabled: true,
    );

    await tester.tap(
      find.byKey(const Key('passenger-settings-delete-account')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Delete account?'), findsOneWidget);
    expect(
      find.text(
        'This will permanently delete your ALANTEH account\n'
        'and all your trip history. This cannot be undone.',
      ),
      findsOneWidget,
    );
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Delete account'), findsNWidgets(2));
  });

  testWidgets('test_delete_account_calls_backend_endpoint', (tester) async {
    final tokenStore = MemoryAuthTokenStore();
    await tokenStore.saveTokens(
      AuthTokens(
        accessToken: 'test-passenger-access',
        refreshToken: 'test-passenger-refresh',
      ),
    );
    final gateway = _RecordingDeleteGateway();
    final submitter = ApiPassengerDeleteAccountSubmitter(
      apiGateway: gateway,
      tokenStore: tokenStore,
      connectionConfigured: true,
    );

    await _pumpSettings(
      tester,
      store: _MemoryPreferenceStore(),
      submitter: submitter,
      deleteAccountLiveEnabled: true,
    );

    await tester.tap(
      find.byKey(const Key('passenger-settings-delete-account')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('passenger-settings-delete-confirm')),
    );
    await tester.pumpAndSettle();

    expect(gateway.paths, <String>[passengerDeleteAccountEndpoint]);
    expect(find.byKey(const Key('passenger-settings-screen')), findsOneWidget);
  });

  testWidgets('test_delete_account_navigates_to_login_after_confirm', (
    tester,
  ) async {
    final tokenStore = MemoryAuthTokenStore();
    await tokenStore.saveTokens(
      AuthTokens(
        accessToken: 'test-passenger-access',
        refreshToken: 'test-passenger-refresh',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: _DeletionNavigationHarness(tokenStore: tokenStore),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('passenger-settings-delete-account')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('passenger-settings-delete-confirm')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('passenger-login-test-screen')),
      findsOneWidget,
    );
    expect(find.text(passengerDeleteAccountSuccessTitle), findsOneWidget);
    expect(find.text(passengerDeleteAccountSuccessMessage), findsOneWidget);
    expect(await tokenStore.readAccessToken(), isNull);
    expect(await tokenStore.readRefreshToken(), isNull);
  });

  testWidgets('test_cancel_dismisses_dialog_without_action', (tester) async {
    final submitter = _RecordingDeleteSubmitter();

    await _pumpSettings(
      tester,
      store: _MemoryPreferenceStore(),
      submitter: submitter,
      deleteAccountLiveEnabled: true,
    );

    await tester.tap(
      find.byKey(const Key('passenger-settings-delete-account')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('passenger-settings-delete-cancel')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('passenger-settings-delete-confirmation')),
      findsNothing,
    );
    expect(submitter.calls, 0);
    expect(find.byKey(const Key('passenger-settings-screen')), findsOneWidget);
  });
}

Future<void> _pumpSettings(
  WidgetTester tester, {
  required PassengerSettingsPreferenceStore store,
  PassengerLegalLinkOpener? opener,
  PassengerLegalDocumentFetcher? legalDocumentFetcher,
  PassengerDeleteAccountSubmitter? submitter,
  bool deleteAccountLiveEnabled = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AsmThemes.passenger,
      home: PassengerSettingsScreen(
        preferenceStore: store,
        legalLinkOpener: opener ?? _RecordingLegalLinkOpener(),
        legalDocumentFetcher: legalDocumentFetcher,
        deleteAccountSubmitter:
            submitter ?? const UnavailablePassengerDeleteAccountSubmitter(),
        deleteAccountLiveEnabled: deleteAccountLiveEnabled,
        onAccountDeletionRequested: () async {},
      ),
    ),
  );
  await tester.pumpAndSettle();
}

bool _switchValue(WidgetTester tester, String key) {
  return tester.widget<SwitchListTile>(find.byKey(Key(key))).value;
}

final class _MemoryPreferenceStore implements PassengerSettingsPreferenceStore {
  bool rideUpdates = true;
  bool soundAlerts = true;

  @override
  Future<PassengerNotificationPreferences> read() async {
    return PassengerNotificationPreferences(
      rideUpdates: rideUpdates,
      soundAlerts: soundAlerts,
    );
  }

  @override
  Future<void> saveRideUpdates(bool value) async {
    rideUpdates = value;
  }

  @override
  Future<void> saveSoundAlerts(bool value) async {
    soundAlerts = value;
  }
}

final class _RecordingLegalLinkOpener implements PassengerLegalLinkOpener {
  final List<Uri> opened = <Uri>[];

  @override
  Future<void> open(Uri uri) async {
    opened.add(uri);
  }
}

final class _RecordingLegalDocumentFetcher
    implements PassengerLegalDocumentFetcher {
  _RecordingLegalDocumentFetcher({
    this.documents = const <String, PassengerLegalDocument>{},
    this.failing = false,
    this.pending,
  });

  final Map<String, PassengerLegalDocument> documents;
  final bool failing;
  final Completer<PassengerLegalDocument>? pending;
  final List<String> paths = <String>[];

  @override
  Future<PassengerLegalDocument> fetch(String path) async {
    paths.add(path);

    final pendingRequest = pending;
    if (pendingRequest != null) {
      return pendingRequest.future;
    }

    if (failing) {
      throw const PassengerLegalDocumentException('Test failure.');
    }

    final document = documents[path];
    if (document == null) {
      throw const PassengerLegalDocumentException('Missing test document.');
    }

    return document;
  }
}

final class _MixedLegalDocumentFetcher
    implements PassengerLegalDocumentFetcher {
  @override
  Future<PassengerLegalDocument> fetch(String path) async {
    if (path == passengerPrivacyPolicyEndpoint) {
      return const PassengerLegalDocument(
        title: 'Privacy Policy',
        content: 'Privacy document body.',
      );
    }

    throw const PassengerLegalDocumentException('Test failure.');
  }
}

final class _RecordingDeleteGateway
    implements PassengerDeleteAccountApiGateway {
  final List<String> paths = <String>[];

  @override
  Future<ApiResponse<Map<String, Object?>>> post(String path) async {
    paths.add(path);
    return ApiResponse<Map<String, Object?>>.success(const <String, Object?>{
      'status': 'deletion_requested',
      'message': passengerDeleteAccountSuccessMessage,
    }, statusCode: 200);
  }
}

final class _RecordingDeleteSubmitter
    implements PassengerDeleteAccountSubmitter {
  int calls = 0;

  @override
  Future<PassengerDeleteAccountResult> submit() async {
    calls += 1;
    return const PassengerDeleteAccountResult(
      status: 'deletion_requested',
      message: passengerDeleteAccountSuccessMessage,
    );
  }
}

class _DeletionNavigationHarness extends StatefulWidget {
  const _DeletionNavigationHarness({required this.tokenStore});

  final AuthTokenStore tokenStore;

  @override
  State<_DeletionNavigationHarness> createState() =>
      _DeletionNavigationHarnessState();
}

class _DeletionNavigationHarnessState
    extends State<_DeletionNavigationHarness> {
  bool _loginVisible = false;

  @override
  Widget build(BuildContext context) {
    if (_loginVisible) {
      return const Scaffold(
        key: Key('passenger-login-test-screen'),
        body: Column(
          children: [
            Text(passengerDeleteAccountSuccessTitle),
            Text(passengerDeleteAccountSuccessMessage),
            Text('Passenger login'),
          ],
        ),
      );
    }

    return PassengerSettingsScreen(
      preferenceStore: _MemoryPreferenceStore(),
      legalLinkOpener: _RecordingLegalLinkOpener(),
      deleteAccountSubmitter: _RecordingDeleteSubmitter(),
      deleteAccountLiveEnabled: true,
      onAccountDeletionRequested: () async {
        await widget.tokenStore.clearTokens();
        if (!mounted) {
          return;
        }
        setState(() => _loginVisible = true);
      },
    );
  }
}
