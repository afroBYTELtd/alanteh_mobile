import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_auth/asm_auth.dart';
import 'package:driver_app/safety/driver_safety_settings_screen.dart';
import 'package:driver_app/safety/driver_trip_safety.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('test_share_trip_payload_matches_approved_allowlist_exactly', () {
    const summary = DriverTripSafetySummary(
      tripReference: 'TRIP-ABC123',
      tripStatus: 'in_progress',
      pickup: 'Osu, Accra',
      destination: 'Airport, Accra',
      passengerCount: 2,
    );

    expect(
      summary.build(),
      <String>[
        'Trip reference: TRIP-ABC123',
        'Trip status: in_progress',
        'Passengers: 2',
        'Pickup: Osu, Accra',
        'Destination: Airport, Accra',
      ].join('\n'),
    );

    expect(summary.build().split('\n'), hasLength(5));
  });

  test('test_share_trip_payload_excludes_gps_fields', () {
    const summary = DriverTripSafetySummary(
      tripReference: 'TRIP-ABC123',
      tripStatus: 'in_progress',
      pickup: '5.60500, -0.16680',
      destination: '-1.23450, +4.56780',
      passengerCount: 1,
    );

    final text = summary.build().toLowerCase();

    for (final forbidden in <String>[
      'driver phone',
      'passenger phone',
      'trusted contact phone',
      'vehicle gps',
      'latitude',
      'longitude',
      'internal id',
      'authentication',
      'session',
      'payment',
      'tracking url',
      'http://',
      'https://',
      '5.60500',
      '-0.16680',
      '-1.23450',
      '+4.56780',
    ]) {
      expect(text, isNot(contains(forbidden)), reason: forbidden);
    }

    expect(text, contains('pickup: not shared for privacy'));
    expect(text, contains('destination: not shared for privacy'));
  });

  test('test_shared_summary_never_emits_coordinate_only_pickup', () {
    const summary = DriverTripSafetySummary(
      tripReference: 'TRIP-ABC123',
      tripStatus: 'driver_en_route',
      pickup: '5.60500, -0.16680',
      destination: 'Ghana Sea Port',
      passengerCount: 1,
    );

    final text = summary.build();

    expect(text, contains('Pickup: Not shared for privacy'));
    expect(text, isNot(contains('5.60500')));
    expect(text, isNot(contains('-0.16680')));
    expect(text, contains('Destination: Ghana Sea Port'));
  });

  test('test_sms_uri_preserves_spaces_and_newlines_without_literal_plus', () {
    const summary = 'Trip reference: TRIP-ABC123\nTrip status: driver_en_route';

    final uri = buildDriverTrustedContactSmsUri(
      phone: '233555000111',
      summary: summary,
    );

    expect(uri.scheme, 'sms');
    expect(uri.path, '233555000111');
    expect(uri.queryParameters['body'], summary);
    expect(uri.queryParameters['body'], isNot(contains('+')));
    expect(uri.toString(), contains('%0A'));
  });

  test(
    'test_trusted_contact_settings_patch_rejects_other_profile_fields',
    () async {
      final gateway = _RecordingTrustedContactApiGateway();
      final repository = ApiDriverTrustedContactRepository(
        apiGateway: gateway,
        tokenStore: _MemoryAuthTokenStore('test-access-token'),
        connectionConfigured: true,
      );

      final saved = await repository.save(
        name: 'Ama Mensah',
        phone: '+233555000111',
      );

      expect(gateway.patchPaths, <String>[driverProfileEndpoint]);
      expect(gateway.patchBodies, hasLength(1));
      expect(gateway.patchBodies.single, <String, Object?>{
        'emergency_contact_name': 'Ama Mensah',
        'emergency_contact_phone': '+233555000111',
      });
      expect(gateway.patchBodies.single.keys.toSet(), <String>{
        'emergency_contact_name',
        'emergency_contact_phone',
      });
      expect(saved.name, 'Ama Mensah');
      expect(saved.phone, '+233555000111');
    },
  );

  test('trusted-contact GET reads only emergency contact fields', () async {
    final gateway = _RecordingTrustedContactApiGateway(
      getResponse: <String, Object?>{
        'emergency_contact_name': 'Ama Mensah',
        'emergency_contact_phone': '+233555000111',
        'full_name': 'Driver Name Must Not Be Used',
        'phone_number': '+233999999999',
      },
    );
    final repository = ApiDriverTrustedContactRepository(
      apiGateway: gateway,
      tokenStore: _MemoryAuthTokenStore('test-access-token'),
      connectionConfigured: true,
    );

    final contact = await repository.fetch();

    expect(gateway.getPaths, <String>[driverProfileEndpoint]);
    expect(contact.name, 'Ama Mensah');
    expect(contact.phone, '+233555000111');
  });

  test('emergency URI is exactly tel:191', () {
    expect(driverEmergency191Uri.scheme, 'tel');
    expect(driverEmergency191Uri.path, '191');
    expect(driverEmergency191Uri.toString(), 'tel:191');
  });

  testWidgets('test_trusted_contact_settings_save_and_display', (tester) async {
    final repository = _MemoryTrustedContactRepository(
      const DriverTrustedContact(name: 'Ama Mensah', phone: '+233555000111'),
    );

    await tester.pumpWidget(
      MaterialApp(home: DriverSafetySettingsScreen(repository: repository)),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('driver-trusted-contact-saved-card')),
      findsOneWidget,
    );
    expect(find.text('Ama Mensah'), findsWidgets);
    expect(find.text('+233555000111'), findsWidgets);

    await tester.enterText(
      find.byKey(const Key('driver-trusted-contact-name')),
      'Akosua Owusu',
    );
    await tester.enterText(
      find.byKey(const Key('driver-trusted-contact-phone')),
      '+233555000222',
    );
    await tester.tap(find.byKey(const Key('driver-trusted-contact-save')));
    await tester.pumpAndSettle();

    expect(repository.saveCalls, 1);
    expect(repository.contact.name, 'Akosua Owusu');
    expect(repository.contact.phone, '+233555000222');
    expect(find.text('Akosua Owusu'), findsWidgets);
    expect(find.text('+233555000222'), findsWidgets);
    expect(find.text('Trusted contact saved.'), findsOneWidget);
  });

  test('test_safety_alert_sends_all_fields_to_the_correct_endpoint', () async {
    final gateway = _RecordingSafetyAlertApiGateway();
    final repository = ApiDriverSafetyAlertRepository(
      apiGateway: gateway,
      tokenStore: _MemoryAuthTokenStore('test-access-token'),
      connectionConfigured: true,
    );

    await repository.send(
      tripReference: 'TRIP-ABC123',
      latitude: 5.605,
      longitude: -0.1668,
    );

    expect(gateway.postPaths, <String>[driverSafetyAlertEndpoint]);
    expect(gateway.postBodies.single, <String, Object?>{
      'trip_reference': 'TRIP-ABC123',
      'latitude': '5.605',
      'longitude': '-0.1668',
    });
  });

  test('test_safety_alert_omits_unset_fields', () async {
    final gateway = _RecordingSafetyAlertApiGateway();
    final repository = ApiDriverSafetyAlertRepository(
      apiGateway: gateway,
      tokenStore: _MemoryAuthTokenStore('test-access-token'),
      connectionConfigured: true,
    );

    await repository.send();

    expect(gateway.postBodies.single, <String, Object?>{});
  });

  test('test_safety_alert_throws_when_api_rejects', () async {
    final gateway = _RecordingSafetyAlertApiGateway(succeed: false);
    final repository = ApiDriverSafetyAlertRepository(
      apiGateway: gateway,
      tokenStore: _MemoryAuthTokenStore('test-access-token'),
      connectionConfigured: true,
    );

    await expectLater(
      repository.send(tripReference: 'TRIP-ABC123'),
      throwsA(isA<DriverSafetyAlertException>()),
    );
  });

  test('test_safety_alert_requires_sign_in', () async {
    final gateway = _RecordingSafetyAlertApiGateway();
    final repository = ApiDriverSafetyAlertRepository(
      apiGateway: gateway,
      tokenStore: _MemoryAuthTokenStore(null),
      connectionConfigured: true,
    );

    await expectLater(
      repository.send(),
      throwsA(isA<DriverSafetyAlertException>()),
    );
    expect(gateway.postPaths, isEmpty);
  });
}

final class _MemoryTrustedContactRepository
    implements DriverTrustedContactRepository {
  _MemoryTrustedContactRepository(this.contact);

  DriverTrustedContact contact;
  int fetchCalls = 0;
  int saveCalls = 0;

  @override
  Future<DriverTrustedContact> fetch() async {
    fetchCalls += 1;
    return contact;
  }

  @override
  Future<DriverTrustedContact> save({
    required String name,
    required String phone,
  }) async {
    saveCalls += 1;
    contact = DriverTrustedContact(name: name.trim(), phone: phone.trim());
    return contact;
  }
}

final class _RecordingTrustedContactApiGateway
    implements DriverTrustedContactApiGateway {
  _RecordingTrustedContactApiGateway({
    this.getResponse = const <String, Object?>{
      'emergency_contact_name': 'Ama Mensah',
      'emergency_contact_phone': '+233555000111',
    },
  });

  final Map<String, Object?> getResponse;
  final List<String> getPaths = <String>[];
  final List<String> patchPaths = <String>[];
  final List<Map<String, Object?>> patchBodies = <Map<String, Object?>>[];

  @override
  Future<ApiResponse<Map<String, Object?>>> get(String path) async {
    getPaths.add(path);
    return ApiResponse.success(
      Map<String, Object?>.of(getResponse),
      statusCode: 200,
    );
  }

  @override
  Future<ApiResponse<Map<String, Object?>>> patch(
    String path, {
    required Map<String, Object?> data,
  }) async {
    patchPaths.add(path);
    patchBodies.add(Map<String, Object?>.of(data));
    return ApiResponse.success(Map<String, Object?>.of(data), statusCode: 200);
  }
}

final class _RecordingSafetyAlertApiGateway
    implements DriverSafetyAlertApiGateway {
  _RecordingSafetyAlertApiGateway({this.succeed = true});

  final bool succeed;
  final List<String> postPaths = <String>[];
  final List<Map<String, Object?>> postBodies = <Map<String, Object?>>[];

  @override
  Future<ApiResponse<Map<String, Object?>>> post(
    String path, {
    required Map<String, Object?> data,
  }) async {
    postPaths.add(path);
    postBodies.add(Map<String, Object?>.of(data));

    if (!succeed) {
      return ApiResponse.apiFailure(
        const AsmApiException(
          type: AsmApiExceptionType.server,
          message: 'Unable to send your alert.',
        ),
      );
    }

    return ApiResponse.success(
      <String, Object?>{'id': 1, 'status': 'received'},
      statusCode: 201,
    );
  }
}

final class _MemoryAuthTokenStore implements AuthTokenStore {
  _MemoryAuthTokenStore(this._accessToken);

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
