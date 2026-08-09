import 'dart:io';

import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_app_config/asm_app_config.dart';
import 'package:asm_auth/asm_auth.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passenger_app/auth/passenger_registration.dart';
import 'package:passenger_app/auth/passenger_registration_flow.dart';
import 'package:passenger_app/main.dart';
import 'package:passenger_app/network/ghana_network_resilience.dart';

void main() {
  testWidgets('test_registration_flow_reaches_pending_screen', (tester) async {
    final submitter = _FakeRegistrationSubmitter(
      outcomes: const [
        PassengerRegistrationResult(
          status: 'pending_approval',
          registrationReference: 'REG-ABC1234567',
        ),
      ],
    );

    await tester.pumpWidget(
      _registrationApp(
        submitter: submitter,
        idempotencyKeyFactory: () => '123e4567-e89b-42d3-a456-426614174000',
      ),
    );

    await _openDetails(tester);
    await _fillValidDetails(tester);
    await _tapCreateAccount(tester);

    expect(find.text('Account submitted'), findsOneWidget);
    expect(find.text('Your account is being reviewed.'), findsOneWidget);
    expect(
      find.text(
        'We will notify you when it is approved — usually within a few minutes.',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('usually within a few hours'),
      findsNothing,
    );
    expect(find.text('Reference: REG-ABC1234567'), findsOneWidget);
    expect(submitter.calls, hasLength(1));
  });

  testWidgets('test_idempotency_key_generated_before_first_post', (
    tester,
  ) async {
    final submitter = _FakeRegistrationSubmitter(
      outcomes: const [
        PassengerRegistrationResult(
          status: 'pending_approval',
          registrationReference: 'REG-IDEMPOTENT1',
        ),
      ],
    );
    var factoryCalls = 0;
    String? generatedKey;

    await tester.pumpWidget(
      _registrationApp(
        submitter: submitter,
        idempotencyKeyFactory: () {
          factoryCalls += 1;
          generatedKey = PassengerRegistrationIdempotencyKey.generate();
          return generatedKey!;
        },
      ),
    );

    expect(factoryCalls, 0);
    expect(submitter.calls, isEmpty);

    await _openDetails(tester);

    expect(factoryCalls, 1);
    expect(submitter.calls, isEmpty);
    expect(
      generatedKey,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );

    await _fillValidDetails(tester);
    await _tapCreateAccount(tester);

    expect(submitter.calls.single.idempotencyKey, generatedKey);
    expect(factoryCalls, 1);
  });

  test('test_same_key_used_on_retry', () async {
    const key = '123e4567-e89b-42d3-a456-426614174000';
    final gateway = _SequenceRegistrationGateway([
      _networkFailure(),
      _networkFailure(),
      _networkFailure(),
      ApiResponse.success(const <String, Object?>{
        'status': 'pending_approval',
        'registration_reference': 'REG-REPLAY0001',
      }, statusCode: 200),
    ]);
    final observedDelays = <Duration>[];
    final submitter = ApiPassengerRegistrationSubmitter(
      gateway: gateway,
      retryDelay: (delay) async => observedDelays.add(delay),
    );

    final result = await submitter.submit(
      phoneNumber: '+233559991234',
      fullName: 'Passenger Retry',
      pin: '1234',
      idempotencyKey: key,
    );

    expect(result.registrationReference, 'REG-REPLAY0001');
    expect(gateway.headers, hasLength(4));
    expect(
      gateway.headers.map((headers) => headers['Idempotency-Key']).toList(),
      everyElement(key),
    );
    expect(observedDelays, GhanaRequestPolicy.retryBackoffs);
  });

  testWidgets('test_duplicate_phone_409_shows_friendly_error', (tester) async {
    final submitter = _FakeRegistrationSubmitter(
      outcomes: const [
        PassengerRegistrationException(
          type: PassengerRegistrationFailureType.duplicatePhone,
          message:
              'An account with this phone number already exists. Sign in instead.',
        ),
      ],
    );

    await tester.pumpWidget(
      _registrationApp(
        submitter: submitter,
        idempotencyKeyFactory: () => '123e4567-e89b-42d3-a456-426614174000',
      ),
    );

    await _openDetails(tester);
    await _fillValidDetails(tester);
    await _tapCreateAccount(tester);

    expect(
      find.text(
        'An account with this phone number already exists. Sign in instead.',
      ),
      findsOneWidget,
    );
    expect(submitter.calls, hasLength(1));
  });

  testWidgets('test_pin_mismatch_shows_error', (tester) async {
    final submitter = _FakeRegistrationSubmitter();

    await tester.pumpWidget(
      _registrationApp(
        submitter: submitter,
        idempotencyKeyFactory: () => '123e4567-e89b-42d3-a456-426614174000',
      ),
    );

    await _openDetails(tester);
    await tester.enterText(
      find.byKey(const Key('registration-full-name-field')),
      'Passenger Test',
    );
    await tester.enterText(
      find.byKey(const Key('registration-pin-field')),
      '1234',
    );
    await tester.enterText(
      find.byKey(const Key('registration-confirm-pin-field')),
      '4321',
    );
    await _tapCreateAccount(tester);

    expect(find.text('PINs do not match.'), findsOneWidget);
    expect(submitter.calls, isEmpty);
  });

  testWidgets('test_pin_not_4_digits_shows_error', (tester) async {
    final submitter = _FakeRegistrationSubmitter();

    await tester.pumpWidget(
      _registrationApp(
        submitter: submitter,
        idempotencyKeyFactory: () => '123e4567-e89b-42d3-a456-426614174000',
      ),
    );

    await _openDetails(tester);
    await tester.enterText(
      find.byKey(const Key('registration-full-name-field')),
      'Passenger Test',
    );
    await tester.enterText(
      find.byKey(const Key('registration-pin-field')),
      '123',
    );
    await tester.enterText(
      find.byKey(const Key('registration-confirm-pin-field')),
      '123',
    );
    await _tapCreateAccount(tester);

    expect(find.text('PIN must be exactly 4 numeric digits.'), findsWidgets);
    expect(submitter.calls, isEmpty);
  });

  testWidgets('test_name_too_short_shows_error', (tester) async {
    final submitter = _FakeRegistrationSubmitter();

    await tester.pumpWidget(
      _registrationApp(
        submitter: submitter,
        idempotencyKeyFactory: () => '123e4567-e89b-42d3-a456-426614174000',
      ),
    );

    await _openDetails(tester);
    await tester.enterText(
      find.byKey(const Key('registration-full-name-field')),
      'A',
    );
    await tester.enterText(
      find.byKey(const Key('registration-pin-field')),
      '1234',
    );
    await tester.enterText(
      find.byKey(const Key('registration-confirm-pin-field')),
      '1234',
    );
    await _tapCreateAccount(tester);

    expect(find.text('Full name must be 2 to 80 characters.'), findsOneWidget);
    expect(submitter.calls, isEmpty);
  });

  testWidgets('test_pending_account_login_shows_pending_message', (
    tester,
  ) async {
    await _pumpLoginStatus(tester, 'pending_approval');

    expect(
      find.text(
        'Your account is being reviewed.\n'
        'Please wait for approval before signing in.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('test_rejected_account_login_shows_rejected_message', (
    tester,
  ) async {
    await _pumpLoginStatus(tester, 'rejected');

    expect(
      find.text(
        'Your registration was not approved.\n'
        'Please contact us at contact@alanteh.io',
      ),
      findsOneWidget,
    );
  });

  testWidgets('test_inactive_account_login_shows_inactive_message', (
    tester,
  ) async {
    await _pumpLoginStatus(tester, 'inactive');

    expect(
      find.text(
        'This account is not active.\n'
        'Please contact us at contact@alanteh.io',
      ),
      findsOneWidget,
    );
  });

  testWidgets('test_register_link_visible_on_login_screen', (tester) async {
    final store = _MemoryAuthTokenStore();
    final authService = AuthService(
      apiGateway: const _StatusAuthApiGateway('pending_approval'),
      tokenStore: store,
      appContext: AuthAppContext.passenger,
    );

    await tester.pumpWidget(
      PassengerApp(
        configuration: AsmAppConfig.localGhana,
        showLoginShell: true,
        authTokenStore: store,
        authService: authService,
        registrationSubmitter: _FakeRegistrationSubmitter(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('passenger-register-link')), findsOneWidget);
    expect(find.text("Don't have an account? Register"), findsOneWidget);
  });

  test('test_pin_never_written_to_persistent_storage', () {
    final registrationSource = File(
      'lib/auth/passenger_registration.dart',
    ).readAsStringSync();
    final flowSource = File(
      'lib/auth/passenger_registration_flow.dart',
    ).readAsStringSync();
    final source = '$registrationSource\n$flowSource';

    expect(source, isNot(contains('asm_offline_queue')));
    expect(source, isNot(contains('sqflite')));
    expect(source, isNot(contains('SharedPreferences')));
    expect(source, isNot(contains('SecureAuthTokenStore')));
    expect(source, isNot(contains('flutter_secure_storage')));
    expect(source, isNot(contains('writeAsString')));
    expect(source, isNot(contains('writeAccessToken')));
    expect(source, isNot(contains('writeRefreshToken')));
  });

  testWidgets('test_offline_shows_retry_state_not_queue', (tester) async {
    const key = '123e4567-e89b-42d3-a456-426614174000';
    final submitter = _FakeRegistrationSubmitter(
      outcomes: const [
        PassengerRegistrationException(
          type: PassengerRegistrationFailureType.offline,
          message: 'No connection.\nPlease check your network and try again.',
        ),
        PassengerRegistrationResult(
          status: 'pending_approval',
          registrationReference: 'REG-OFFLINE001',
        ),
      ],
    );

    await tester.pumpWidget(
      _registrationApp(submitter: submitter, idempotencyKeyFactory: () => key),
    );

    await _openDetails(tester);
    await _fillValidDetails(tester);
    await _tapCreateAccount(tester);

    expect(
      find.text('No connection.\nPlease check your network and try again.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('registration-offline-retry')), findsOneWidget);

    final nameField = tester.widget<TextFormField>(
      find.byKey(const Key('registration-full-name-field')),
    );
    final pinField = tester.widget<TextFormField>(
      find.byKey(const Key('registration-pin-field')),
    );
    final confirmationField = tester.widget<TextFormField>(
      find.byKey(const Key('registration-confirm-pin-field')),
    );

    expect(nameField.controller?.text, 'Passenger Test');
    expect(pinField.controller?.text, '1234');
    expect(confirmationField.controller?.text, '1234');

    await tester.ensureVisible(
      find.byKey(const Key('registration-offline-retry')),
    );
    await tester.tap(find.byKey(const Key('registration-offline-retry')));
    await tester.pumpAndSettle();

    expect(find.text('Reference: REG-OFFLINE001'), findsOneWidget);
    expect(submitter.calls, hasLength(2));
    expect(
      submitter.calls.map((call) => call.idempotencyKey),
      everyElement(key),
    );

    final source = File(
      'lib/auth/passenger_registration_flow.dart',
    ).readAsStringSync();
    expect(source, isNot(contains('asm_offline_queue')));
  });
}

Widget _registrationApp({
  required PassengerRegistrationSubmitter submitter,
  required String Function() idempotencyKeyFactory,
}) {
  return MaterialApp(
    theme: AsmThemes.passenger,
    home: PassengerRegistrationFlow(
      submitter: submitter,
      idempotencyKeyFactory: idempotencyKeyFactory,
      onBackToSignIn: () {},
    ),
  );
}

Future<void> _openDetails(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('registration-phone-field')),
    '+233559991234',
  );
  await tester.ensureVisible(find.byKey(const Key('registration-continue')));
  await tester.tap(find.byKey(const Key('registration-continue')));
  await tester.pumpAndSettle();
  expect(find.text('Your details'), findsOneWidget);
}

Future<void> _fillValidDetails(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('registration-full-name-field')),
    'Passenger Test',
  );
  await tester.enterText(
    find.byKey(const Key('registration-pin-field')),
    '1234',
  );
  await tester.enterText(
    find.byKey(const Key('registration-confirm-pin-field')),
    '1234',
  );
}

Future<void> _tapCreateAccount(WidgetTester tester) async {
  await tester.ensureVisible(
    find.byKey(const Key('registration-create-account')),
  );
  await tester.tap(find.byKey(const Key('registration-create-account')));
  await tester.pumpAndSettle();
}

Future<void> _pumpLoginStatus(WidgetTester tester, String accountStatus) async {
  final store = _MemoryAuthTokenStore();
  final authService = AuthService(
    apiGateway: _StatusAuthApiGateway(accountStatus),
    tokenStore: store,
    appContext: AuthAppContext.passenger,
  );

  await tester.pumpWidget(
    PassengerApp(
      configuration: AsmAppConfig.localGhana,
      showLoginShell: true,
      authTokenStore: store,
      authService: authService,
      registrationSubmitter: _FakeRegistrationSubmitter(),
    ),
  );
  await tester.pumpAndSettle();

  await tester.enterText(
    find.byKey(const Key('passenger-phone-field')),
    '+233559991234',
  );
  await tester.enterText(find.byKey(const Key('passenger-pin-field')), '1234');
  await tester.ensureVisible(find.byKey(const Key('passenger-sign-in')));
  await tester.tap(find.byKey(const Key('passenger-sign-in')));
  await tester.pumpAndSettle();
}

ApiResponse<Map<String, Object?>> _networkFailure() {
  return ApiResponse.clientException(
    const AsmApiException(
      type: AsmApiExceptionType.network,
      message: 'Network unavailable.',
    ),
  );
}

class _RegistrationCall {
  const _RegistrationCall({
    required this.phoneNumber,
    required this.fullName,
    required this.pin,
    required this.idempotencyKey,
  });

  final String phoneNumber;
  final String fullName;
  final String pin;
  final String idempotencyKey;
}

class _FakeRegistrationSubmitter implements PassengerRegistrationSubmitter {
  _FakeRegistrationSubmitter({List<Object>? outcomes})
    : _outcomes = List<Object>.of(outcomes ?? const []);

  final List<Object> _outcomes;
  final List<_RegistrationCall> calls = [];

  @override
  Future<PassengerRegistrationResult> submit({
    required String phoneNumber,
    required String fullName,
    required String pin,
    required String idempotencyKey,
  }) async {
    calls.add(
      _RegistrationCall(
        phoneNumber: phoneNumber,
        fullName: fullName,
        pin: pin,
        idempotencyKey: idempotencyKey,
      ),
    );

    if (_outcomes.isEmpty) {
      throw StateError('No fake registration outcome configured.');
    }

    final outcome = _outcomes.removeAt(0);
    if (outcome is PassengerRegistrationResult) {
      return outcome;
    }
    if (outcome is PassengerRegistrationException) {
      throw outcome;
    }
    throw StateError('Unsupported fake registration outcome: $outcome');
  }
}

class _SequenceRegistrationGateway implements PassengerRegistrationApiGateway {
  _SequenceRegistrationGateway(this._responses);

  final List<ApiResponse<Map<String, Object?>>> _responses;
  final List<Map<String, String>> headers = [];

  @override
  Future<ApiResponse<Map<String, Object?>>> post(
    String path, {
    required Map<String, Object?> body,
    required Map<String, String> headers,
  }) async {
    this.headers.add(Map<String, String>.of(headers));
    if (_responses.isEmpty) {
      throw StateError('No fake gateway response configured.');
    }
    return _responses.removeAt(0);
  }
}

class _StatusAuthApiGateway implements AuthApiGateway {
  const _StatusAuthApiGateway(this.accountStatus);

  final String accountStatus;

  @override
  Future<ApiResponse<Map<String, Object?>>> post(
    String path, {
    required Map<String, Object?> body,
  }) async {
    return ApiResponse.apiFailure(
      AsmApiException(
        type: AsmApiExceptionType.badResponse,
        message: 'Authentication failed.',
        statusCode: 403,
        cause: <String, Object?>{
          'detail': 'This account is not approved for mobile access.',
          'account_status': accountStatus,
        },
      ),
    );
  }
}

class _MemoryAuthTokenStore implements AuthTokenStore {
  String? _accessToken;
  String? _refreshToken;

  @override
  Future<void> saveTokens(AuthTokens tokens) async {
    _accessToken = tokens.accessToken;
    _refreshToken = tokens.refreshToken;
  }

  @override
  Future<String?> readAccessToken() async => _accessToken;

  @override
  Future<String?> readRefreshToken() async => _refreshToken;

  @override
  Future<void> clearTokens() async {
    _accessToken = null;
    _refreshToken = null;
  }
}
