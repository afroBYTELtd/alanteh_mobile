import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_auth/asm_auth.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const passengerPrivacyPolicyUrl = 'https://alanteh.io/privacy';
const passengerTermsOfServiceUrl = 'https://alanteh.io/terms';
const passengerDeleteAccountEndpoint = '/api/passenger/delete-account/';
const passengerDeleteAccountLiveEnabled = false;

const passengerDeleteAccountSuccessTitle = 'Account deletion requested.';
const passengerDeleteAccountSuccessMessage =
    'Your account will be fully removed within 7 days.';

const _settingsChannelName = 'io.alanteh.passenger/settings';
const _rideUpdatesPreferenceKey = 'ride_updates';
const _soundAlertsPreferenceKey = 'sound_alerts';

final class PassengerNotificationPreferences {
  const PassengerNotificationPreferences({
    required this.rideUpdates,
    required this.soundAlerts,
  });

  final bool rideUpdates;
  final bool soundAlerts;
}

abstract interface class PassengerSettingsPreferenceStore {
  Future<PassengerNotificationPreferences> read();

  Future<void> saveRideUpdates(bool value);

  Future<void> saveSoundAlerts(bool value);
}

final class PlatformPassengerSettingsPreferenceStore
    implements PassengerSettingsPreferenceStore {
  const PlatformPassengerSettingsPreferenceStore();

  static const MethodChannel _channel = MethodChannel(_settingsChannelName);

  @override
  Future<PassengerNotificationPreferences> read() async {
    final rideUpdates =
        await _channel.invokeMethod<bool>(
          'readPreference',
          const <String, Object?>{'key': _rideUpdatesPreferenceKey},
        ) ??
        true;
    final soundAlerts =
        await _channel.invokeMethod<bool>(
          'readPreference',
          const <String, Object?>{'key': _soundAlertsPreferenceKey},
        ) ??
        true;

    return PassengerNotificationPreferences(
      rideUpdates: rideUpdates,
      soundAlerts: soundAlerts,
    );
  }

  @override
  Future<void> saveRideUpdates(bool value) {
    return _write(_rideUpdatesPreferenceKey, value);
  }

  @override
  Future<void> saveSoundAlerts(bool value) {
    return _write(_soundAlertsPreferenceKey, value);
  }

  Future<void> _write(String key, bool value) async {
    await _channel.invokeMethod<void>('writePreference', <String, Object?>{
      'key': key,
      'value': value,
    });
  }
}

abstract interface class PassengerLegalLinkOpener {
  Future<void> open(Uri uri);
}

final class PlatformPassengerLegalLinkOpener
    implements PassengerLegalLinkOpener {
  const PlatformPassengerLegalLinkOpener();

  static const MethodChannel _channel = MethodChannel(_settingsChannelName);

  @override
  Future<void> open(Uri uri) async {
    await _channel.invokeMethod<void>('openInAppBrowser', <String, Object?>{
      'url': uri.toString(),
    });
  }
}

final class PassengerDeleteAccountResult {
  const PassengerDeleteAccountResult({
    required this.status,
    required this.message,
  });

  final String status;
  final String message;
}

abstract interface class PassengerDeleteAccountApiGateway {
  Future<ApiResponse<Map<String, Object?>>> post(String path);
}

final class AsmPassengerDeleteAccountApiGateway
    implements PassengerDeleteAccountApiGateway {
  const AsmPassengerDeleteAccountApiGateway(this.client);

  final AsmApiClient client;

  @override
  Future<ApiResponse<Map<String, Object?>>> post(String path) {
    return client.post<Map<String, Object?>>(path, decoder: _decodeObjectMap);
  }
}

abstract interface class PassengerDeleteAccountSubmitter {
  Future<PassengerDeleteAccountResult> submit();
}

final class ApiPassengerDeleteAccountSubmitter
    implements PassengerDeleteAccountSubmitter {
  const ApiPassengerDeleteAccountSubmitter({
    required this.apiGateway,
    required this.tokenStore,
    required this.connectionConfigured,
  });

  factory ApiPassengerDeleteAccountSubmitter.withDefaultClient({
    required AuthTokenStore tokenStore,
    String? baseUrl,
  }) {
    final connectionConfigured = AsmApiBaseUrl.isUsable(baseUrl);
    final resolvedBaseUrl = connectionConfigured
        ? baseUrl!.trim()
        : 'http://127.0.0.1:8000';

    return ApiPassengerDeleteAccountSubmitter(
      apiGateway: AsmPassengerDeleteAccountApiGateway(
        AsmApiClient(
          baseUrl: resolvedBaseUrl,
          tokenProvider: _PassengerSettingsTokenProvider(tokenStore),
        ),
      ),
      tokenStore: tokenStore,
      connectionConfigured: connectionConfigured,
    );
  }

  final PassengerDeleteAccountApiGateway apiGateway;
  final AuthTokenStore tokenStore;
  final bool connectionConfigured;

  @override
  Future<PassengerDeleteAccountResult> submit() async {
    final accessToken = (await tokenStore.readAccessToken())?.trim();

    if (accessToken == null || accessToken.isEmpty) {
      throw const PassengerDeleteAccountException(
        'Please sign in again to continue.',
      );
    }

    if (!connectionConfigured) {
      throw const PassengerDeleteAccountException(
        AsmApiClient.connectionNotConfiguredMessage,
      );
    }

    final response = await apiGateway.post(passengerDeleteAccountEndpoint);

    if (response.isSuccess &&
        response.statusCode == 200 &&
        response.data != null) {
      final status = response.data!['status'];
      final message = response.data!['message'];

      if (status == 'deletion_requested' &&
          message == passengerDeleteAccountSuccessMessage) {
        return const PassengerDeleteAccountResult(
          status: 'deletion_requested',
          message: passengerDeleteAccountSuccessMessage,
        );
      }
    }

    throw PassengerDeleteAccountException(
      response.error?.message ??
          'Unable to request account deletion. Please try again.',
    );
  }
}

final class UnavailablePassengerDeleteAccountSubmitter
    implements PassengerDeleteAccountSubmitter {
  const UnavailablePassengerDeleteAccountSubmitter();

  @override
  Future<PassengerDeleteAccountResult> submit() {
    throw const PassengerDeleteAccountException(
      'Account deletion is coming soon.',
    );
  }
}

final class PassengerDeleteAccountException implements Exception {
  const PassengerDeleteAccountException(this.message);

  final String message;

  @override
  String toString() => 'PassengerDeleteAccountException: $message';
}

final class _PassengerSettingsTokenProvider implements TokenProvider {
  const _PassengerSettingsTokenProvider(this.tokenStore);

  final AuthTokenStore tokenStore;

  @override
  Future<String?> getAccessToken() => tokenStore.readAccessToken();
}

Map<String, Object?> _decodeObjectMap(Object? json) {
  if (json is Map<String, Object?>) {
    return json;
  }

  if (json is Map) {
    return json.map<String, Object?>(
      (key, value) => MapEntry(key.toString(), value),
    );
  }

  throw const FormatException('Expected a JSON object.');
}

class PassengerSettingsScreen extends StatefulWidget {
  const PassengerSettingsScreen({
    this.preferenceStore = const PlatformPassengerSettingsPreferenceStore(),
    this.legalLinkOpener = const PlatformPassengerLegalLinkOpener(),
    this.deleteAccountSubmitter =
        const UnavailablePassengerDeleteAccountSubmitter(),
    this.deleteAccountLiveEnabled = false,
    required this.onAccountDeletionRequested,
    super.key,
  });

  final PassengerSettingsPreferenceStore preferenceStore;
  final PassengerLegalLinkOpener legalLinkOpener;
  final PassengerDeleteAccountSubmitter deleteAccountSubmitter;
  final bool deleteAccountLiveEnabled;
  final Future<void> Function() onAccountDeletionRequested;

  @override
  State<PassengerSettingsScreen> createState() =>
      _PassengerSettingsScreenState();
}

class _PassengerSettingsScreenState extends State<PassengerSettingsScreen> {
  bool _rideUpdates = true;
  bool _soundAlerts = true;
  bool _isLoading = true;
  bool _isDeleting = false;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    try {
      final preferences = await widget.preferenceStore.read();
      if (!mounted) {
        return;
      }

      setState(() {
        _rideUpdates = preferences.rideUpdates;
        _soundAlerts = preferences.soundAlerts;
        _isLoading = false;
      });
    } on Object {
      if (!mounted) {
        return;
      }

      setState(() => _isLoading = false);
    }
  }

  Future<void> _setRideUpdates(bool value) async {
    final previous = _rideUpdates;
    setState(() => _rideUpdates = value);

    try {
      await widget.preferenceStore.saveRideUpdates(value);
    } on Object {
      if (!mounted) {
        return;
      }
      setState(() => _rideUpdates = previous);
      _showSettingsError('Unable to save this setting. Please try again.');
    }
  }

  Future<void> _setSoundAlerts(bool value) async {
    final previous = _soundAlerts;
    setState(() => _soundAlerts = value);

    try {
      await widget.preferenceStore.saveSoundAlerts(value);
    } on Object {
      if (!mounted) {
        return;
      }
      setState(() => _soundAlerts = previous);
      _showSettingsError('Unable to save this setting. Please try again.');
    }
  }

  Future<void> _openLegal(String value) async {
    try {
      await widget.legalLinkOpener.open(Uri.parse(value));
    } on Object {
      if (!mounted) {
        return;
      }
      _showSettingsError('Unable to open this page. Please try again.');
    }
  }

  Future<void> _confirmDeleteAccount() async {
    if (!widget.deleteAccountLiveEnabled || _isDeleting) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('passenger-settings-delete-confirmation'),
        title: const Text('Delete account?'),
        content: const Text(
          'This will permanently delete your ALANTEH account\n'
          'and all your trip history. This cannot be undone.',
        ),
        actions: [
          TextButton(
            key: const Key('passenger-settings-delete-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('passenger-settings-delete-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete account'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() => _isDeleting = true);

    try {
      await widget.deleteAccountSubmitter.submit();

      if (!mounted) {
        return;
      }

      await widget.onAccountDeletionRequested();

      if (mounted) {
        setState(() => _isDeleting = false);
      }
    } on PassengerDeleteAccountException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _isDeleting = false);
      _showSettingsError(error.message);
    } on Object {
      if (!mounted) {
        return;
      }
      setState(() => _isDeleting = false);
      _showSettingsError(
        'Unable to request account deletion. Please try again.',
      );
    }
  }

  void _showSettingsError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AsmSpacing.space4,
        AsmSpacing.space12,
        AsmSpacing.space4,
        AsmSpacing.space8,
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF171B12),
          fontSize: 16,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _settingsCard({required List<Widget> children}) {
    return Card(
      elevation: 0,
      color: AsmColors.passengerCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AsmRadii.radius20),
        side: const BorderSide(color: AsmColors.passengerLine),
      ),
      child: Column(children: children),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('passenger-settings-screen'),
      appBar: AppBar(title: const Text('Settings')),
      body: AsmScreenSurface(
        scrollable: true,
        padding: const EdgeInsets.fromLTRB(
          AsmSpacing.space16,
          AsmSpacing.space12,
          AsmSpacing.space16,
          AsmSpacing.space32,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sectionTitle('Notifications'),
            _settingsCard(
              children: [
                SwitchListTile(
                  key: const Key('passenger-settings-ride-updates'),
                  title: const Text('Ride updates'),
                  value: _rideUpdates,
                  onChanged: _isLoading ? null : _setRideUpdates,
                ),
                const Divider(height: 1),
                SwitchListTile(
                  key: const Key('passenger-settings-sound-alerts'),
                  title: const Text('Sound alerts'),
                  value: _soundAlerts,
                  onChanged: _isLoading ? null : _setSoundAlerts,
                ),
              ],
            ),
            const SizedBox(height: AsmSpacing.space12),
            _sectionTitle('Legal'),
            _settingsCard(
              children: [
                ListTile(
                  key: const Key('passenger-settings-privacy-policy'),
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const Text('Privacy Policy'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openLegal(passengerPrivacyPolicyUrl),
                ),
                const Divider(height: 1),
                ListTile(
                  key: const Key('passenger-settings-terms'),
                  leading: const Icon(Icons.description_outlined),
                  title: const Text('Terms of Service'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openLegal(passengerTermsOfServiceUrl),
                ),
              ],
            ),
            const SizedBox(height: AsmSpacing.space12),
            _sectionTitle('Account'),
            _settingsCard(
              children: [
                ListTile(
                  key: const Key('passenger-settings-delete-account'),
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('Delete account'),
                  subtitle: Text(
                    widget.deleteAccountLiveEnabled
                        ? 'Permanently delete your ALANTEH account'
                        : 'Coming soon',
                  ),
                  trailing: _isDeleting
                      ? const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : widget.deleteAccountLiveEnabled
                      ? const Icon(Icons.chevron_right)
                      : const Icon(Icons.lock_outline),
                  onTap: widget.deleteAccountLiveEnabled
                      ? _confirmDeleteAccount
                      : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
