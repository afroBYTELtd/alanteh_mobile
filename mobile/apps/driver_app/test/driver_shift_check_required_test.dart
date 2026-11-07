import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_auth/asm_auth.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:driver_app/driver_duty_trips.dart';
import 'package:driver_app/driver_shell.dart';
import 'package:driver_app/foundation/driver_foundation_widgets.dart';
import 'package:driver_app/network/driver_trip_action_gateway.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Sign-in build A3: GO ONLINE answered 409 shift_check_required (the app
// thought today's check was done, for example just after midnight) shows
// Work's own "shift check needed" state, not the offline screen.

const _required = <String, Object?>{
  'detail': 'Today’s Driver shift check is required before going online.',
  'code': 'shift_check_required',
};

void main() {
  group('the duty gateway', () {
    Future<Object?> goOnlineAnswered(ApiResponse<Object?> answer) async {
      final tokens = MemoryAuthTokenStore();
      await tokens.saveTokens(
        AuthTokens(
          // exp 2100-01-01: never refreshed by the guard.
          accessToken: 'e30.eyJleHAiOjQxMDI0NDQ4MDB9.',
          refreshToken: 'refresh',
        ),
      );
      final gateway = AsmDriverDutyGateway.withApiClient(
        apiClient: _AnsweringClient(answer),
        tokenStore: tokens,
        refreshAccessToken: () async => DriverTokenRefreshOutcome.refreshed,
        dutyRetryDelay: (_) async {},
      );
      try {
        await gateway.updateDutyStatus(DriverOperationalDutyStatus.online);
        return null;
      } on Object catch (error) {
        return error;
      }
    }

    test('409 shift_check_required is its own failure', () async {
      final error = await goOnlineAnswered(
        ApiResponse.apiFailure(
          const AsmApiException(
            type: AsmApiExceptionType.badResponse,
            message: 'conflict',
            statusCode: 409,
            cause: _required,
          ),
        ),
      );

      expect(
        error,
        isA<DriverDutyApiException>().having(
          (e) => e.isShiftCheckRequired,
          'isShiftCheckRequired',
          isTrue,
        ),
      );
    });

    test('another 409 is not', () async {
      final error = await goOnlineAnswered(
        ApiResponse.apiFailure(
          const AsmApiException(
            type: AsmApiExceptionType.badResponse,
            message: 'conflict',
            statusCode: 409,
            cause: {'code': 'something_else'},
          ),
        ),
      );

      expect(
        error,
        isA<DriverDutyApiException>().having(
          (e) => e.isShiftCheckRequired,
          'isShiftCheckRequired',
          isFalse,
        ),
      );
    });

    test('the code alone without a 409 is not', () async {
      final error = await goOnlineAnswered(
        ApiResponse.apiFailure(
          const AsmApiException(
            type: AsmApiExceptionType.badResponse,
            message: 'bad request',
            statusCode: 400,
            cause: _required,
          ),
        ),
      );

      expect(
        error,
        isA<DriverDutyApiException>().having(
          (e) => e.isShiftCheckRequired,
          'isShiftCheckRequired',
          isFalse,
        ),
      );
    });
  });

  group('Work', () {
    final now = DateTime(2026, 11, 8, 0, 5);

    testWidgets('GO ONLINE refused for the shift check: shift check needed', (
      tester,
    ) async {
      final gateway = _Duty(
        DriverDutySummary(
          driverReference: 'DRV-001',
          dutyStatus: 'offline',
          dutySince: DateTime(2026, 11, 7, 18),
          // Yesterday's answer, still on screen after midnight.
          shiftCheckToday: true,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AsmThemes.driver,
          home: DriverShell(driverDutyGateway: gateway, deviceNow: () => now),
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      await tester.tap(find.text('GO ONLINE'));
      await tester.pumpAndSettle();

      // An offline driver's "shift check needed": the duty panel offers
      // the shift check instead of GO ONLINE.
      expect(find.text('START SHIFT CHECK'), findsOneWidget);
      expect(find.byType(DriverOfflineState), findsNothing);
      expect(find.text('GO ONLINE'), findsNothing);
    });
  });
}

final class _AnsweringClient
    implements DriverDutyApiClient, DriverDutyPostApiClient {
  _AnsweringClient(this.answer);

  final ApiResponse<Object?> answer;

  @override
  Future<ApiResponse<T>> get<T>(String path, {JsonDecoder<T>? decoder}) =>
      throw StateError('GET not used');

  @override
  Future<ApiResponse<T>> post<T>(
    String path, {
    Object? data,
    Map<String, String>? headers,
    JsonDecoder<T>? decoder,
  }) async => ApiResponse<T>.apiFailure(answer.error!);
}

final class _Duty implements DriverDutyGateway, DriverDutyStatusGateway {
  _Duty(this.current);

  DriverDutySummary current;

  @override
  Future<DriverDutySummary> fetchDuty() async => current;

  @override
  Future<List<DriverAssignedTrip>> fetchTrips() async =>
      const <DriverAssignedTrip>[];

  @override
  Future<DriverAssignedTrip> fetchTripDetail(String tripReference) =>
      throw StateError('not used');

  @override
  Future<DriverDutyTransition> updateDutyStatus(
    DriverOperationalDutyStatus status,
  ) async {
    throw const DriverDutyApiException(
      DriverDutyApiFailureType.shiftCheckRequired,
      'Today’s Driver shift check is required before going online.',
    );
  }
}
