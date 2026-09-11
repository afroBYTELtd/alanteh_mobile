import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_auth/asm_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passenger_app/safety/passenger_safety_settings_screen.dart';
import 'package:passenger_app/safety/passenger_trip_safety.dart';

void main() {
  test('test_share_trip_payload_matches_approved_allowlist_exactly', () {
    const summary = PassengerTripSafetySummary(
      tripReference: 'TRIP-ABC123',
      tripStatus: 'in_progress',
      driverFirstName: 'Kwame',
      vehicleType: 'SUV',
      vehicleColour: 'White',
      plate: 'GT 1234-26',
      pickup: 'Osu, Accra',
      destination: 'Airport, Accra',
    );

    expect(
      summary.build(),
      <String>[
        'Trip reference: TRIP-ABC123',
        'Trip status: in_progress',
        'Driver first name: Kwame',
        'Vehicle type: SUV',
        'Vehicle colour: White',
        'Plate: GT 1234-26',
        'Pickup: Osu, Accra',
        'Destination: Airport, Accra',
      ].join('\n'),
    );

    expect(summary.build().split('\n'), hasLength(8));
  });

  test('test_share_trip_payload_excludes_phone_and_gps_fields', () {
    const summary = PassengerTripSafetySummary(
      tripReference: 'TRIP-ABC123',
      tripStatus: 'in_progress',
      driverFirstName: 'Kwame',
      vehicleType: 'SUV',
      vehicleColour: 'White',
      plate: 'GT 1234-26',
      pickup: '5.60500, -0.16680',
      destination: '-1.23450, +4.56780',
    );

    final text = summary.build().toLowerCase();

    for (final forbidden in <String>[
      'driver phone',
      'passenger phone',
      'trusted contact phone',
      'vehicle gps',
      'passenger gps',
      'latitude',
      'longitude',
      'internal id',
      'authentication',
      'session',
      'payment',
      'identity document',
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
    const summary = PassengerTripSafetySummary(
      tripReference: 'TRIP-ABC123',
      tripStatus: 'driver_accepted',
      driverFirstName: 'Kwame',
      vehicleType: 'Solar Taxi',
      vehicleColour: 'Blue',
      plate: 'GT 1234-26',
      pickup: '5.60500, -0.16680',
      destination: 'Ghana Sea Port',
    );

    final text = summary.build();

    expect(text, contains('Pickup: Not shared for privacy'));
    expect(text, isNot(contains('5.60500')));
    expect(text, isNot(contains('-0.16680')));
    expect(text, contains('Destination: Ghana Sea Port'));
  });

  test('test_shared_summary_never_emits_coordinate_only_destination', () {
    const summary = PassengerTripSafetySummary(
      tripReference: 'TRIP-ABC123',
      tripStatus: 'driver_accepted',
      driverFirstName: 'Kwame',
      vehicleType: 'Solar Taxi',
      vehicleColour: 'Blue',
      plate: 'GT 1234-26',
      pickup: 'Solar Hotel',
      destination: '5.60370,-0.18700',
    );

    final text = summary.build();

    expect(text, contains('Pickup: Solar Hotel'));
    expect(text, contains('Destination: Not shared for privacy'));
    expect(text, isNot(contains('5.60370')));
    expect(text, isNot(contains('-0.18700')));
  });

  test('test_sms_uri_preserves_spaces_and_newlines_without_literal_plus', () {
    const summary = 'Trip reference: TRIP-ABC123\nTrip status: driver_accepted';

    final uri = buildTrustedContactSmsUri(
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
    'trusted-contact SMS uses recipient only as address, not body content',
    () {
      const summary = PassengerTripSafetySummary(
        tripReference: 'TRIP-ABC123',
        tripStatus: 'in_progress',
        driverFirstName: 'Kwame',
        vehicleType: 'SUV',
        vehicleColour: 'White',
        plate: 'GT 1234-26',
        pickup: 'Osu, Accra',
        destination: 'Airport, Accra',
      );

      const recipient = '+233555000111';
      final uri = buildTrustedContactSmsUri(
        phone: recipient,
        summary: summary.build(),
      );

      expect(uri.scheme, 'sms');
      expect(uri.path, recipient);
      expect(uri.queryParameters['body'], summary.build());
      expect(summary.build(), isNot(contains(recipient)));
    },
  );

  test(
    'test_trusted_contact_settings_patch_rejects_other_profile_fields',
    () async {
      final gateway = _RecordingTrustedContactApiGateway();
      final repository = ApiPassengerTrustedContactRepository(
        apiGateway: gateway,
        tokenStore: _MemoryAuthTokenStore('test-access-token'),
        connectionConfigured: true,
      );

      final saved = await repository.save(
        name: 'Ama Mensah',
        phone: '+233555000111',
      );

      expect(gateway.patchPaths, <String>[passengerProfileEndpoint]);
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
        'display_name': 'Passenger Name Must Not Be Used',
        'phone_number': '+233999999999',
      },
    );
    final repository = ApiPassengerTrustedContactRepository(
      apiGateway: gateway,
      tokenStore: _MemoryAuthTokenStore('test-access-token'),
      connectionConfigured: true,
    );

    final contact = await repository.fetch();

    expect(gateway.getPaths, <String>[passengerProfileEndpoint]);
    expect(contact.name, 'Ama Mensah');
    expect(contact.phone, '+233555000111');
  });

  test('emergency URI is exactly tel:191', () {
    expect(passengerEmergency191Uri.scheme, 'tel');
    expect(passengerEmergency191Uri.path, '191');
    expect(passengerEmergency191Uri.toString(), 'tel:191');
  });

  testWidgets('test_trusted_contact_settings_save_and_display', (tester) async {
    final repository = _MemoryTrustedContactRepository(
      const PassengerTrustedContact(name: 'Ama Mensah', phone: '+233555000111'),
    );

    await tester.pumpWidget(
      MaterialApp(home: PassengerSafetySettingsScreen(repository: repository)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('trusted-contact-saved-card')), findsOneWidget);
    expect(find.text('Ama Mensah'), findsWidgets);
    expect(find.text('+233555000111'), findsWidgets);

    await tester.enterText(
      find.byKey(const Key('trusted-contact-name')),
      'Akosua Owusu',
    );
    await tester.enterText(
      find.byKey(const Key('trusted-contact-phone')),
      '+233555000222',
    );
    await tester.tap(find.byKey(const Key('trusted-contact-save')));
    await tester.pumpAndSettle();

    expect(repository.saveCalls, 1);
    expect(repository.contact.name, 'Akosua Owusu');
    expect(repository.contact.phone, '+233555000222');
    expect(find.text('Akosua Owusu'), findsWidgets);
    expect(find.text('+233555000222'), findsWidgets);
    expect(find.text('Trusted contact saved.'), findsOneWidget);
  });
}

final class _MemoryTrustedContactRepository
    implements PassengerTrustedContactRepository {
  _MemoryTrustedContactRepository(this.contact);

  PassengerTrustedContact contact;
  int fetchCalls = 0;
  int saveCalls = 0;

  @override
  Future<PassengerTrustedContact> fetch() async {
    fetchCalls += 1;
    return contact;
  }

  @override
  Future<PassengerTrustedContact> save({
    required String name,
    required String phone,
  }) async {
    saveCalls += 1;
    contact = PassengerTrustedContact(name: name.trim(), phone: phone.trim());
    return contact;
  }
}

final class _RecordingTrustedContactApiGateway
    implements PassengerTrustedContactApiGateway {
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
