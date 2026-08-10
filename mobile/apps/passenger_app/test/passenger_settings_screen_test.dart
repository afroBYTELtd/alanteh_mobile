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

  testWidgets('test_privacy_policy_link_opens_correct_url', (tester) async {
    final opener = _RecordingLegalLinkOpener();

    await _pumpSettings(
      tester,
      store: _MemoryPreferenceStore(),
      opener: opener,
    );

    await tester.tap(
      find.byKey(const Key('passenger-settings-privacy-policy')),
    );
    await tester.pump();

    expect(opener.opened, <Uri>[Uri.parse(passengerPrivacyPolicyUrl)]);
  });

  testWidgets('test_terms_link_opens_correct_url', (tester) async {
    final opener = _RecordingLegalLinkOpener();

    await _pumpSettings(
      tester,
      store: _MemoryPreferenceStore(),
      opener: opener,
    );

    await tester.tap(find.byKey(const Key('passenger-settings-terms')));
    await tester.pump();

    expect(opener.opened, <Uri>[Uri.parse(passengerTermsOfServiceUrl)]);
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
  PassengerDeleteAccountSubmitter? submitter,
  bool deleteAccountLiveEnabled = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AsmThemes.passenger,
      home: PassengerSettingsScreen(
        preferenceStore: store,
        legalLinkOpener: opener ?? _RecordingLegalLinkOpener(),
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
