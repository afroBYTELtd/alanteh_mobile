// B7: the driver's duty summary stays current. Seen 24/25 Oct: the app was
// left on Work overnight and still said "online now" the next Accra day,
// though today's shift check was not done; a failed GO OFFLINE replaced
// Work with "You're offline" while the server still had the driver online.

import 'dart:async';

import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_auth/asm_auth.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:driver_app/driver_duty_trips.dart';
import 'package:driver_app/driver_home.dart';
import 'package:driver_app/driver_shell.dart';
import 'package:driver_app/network/driver_trip_action_gateway.dart';
import 'package:driver_app/readiness/driver_readiness_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _onlineChecked = DriverDutySummary(
  dutyStatus: 'online',
  shiftCheckToday: true,
);
const _onlineNotChecked = DriverDutySummary(
  dutyStatus: 'online',
  shiftCheckToday: false,
);

void main() {
  group('the duty summary reloads quietly', () {
    testWidgets('coming back to the app reloads it', (tester) async {
      final server = _DutyServer(_onlineChecked);
      await _pumpShell(tester, server);
      final calls = server.dutyCalls;

      await _toBackground(tester);
      await _toForeground(tester);

      expect(server.dutyCalls, calls + 1);
    });

    testWidgets('Work in front reloads it every 3 minutes', (tester) async {
      final server = _DutyServer(_onlineChecked);
      await _pumpShell(tester, server);
      final calls = server.dutyCalls;

      await tester.pump(driverDutyReloadInterval);
      expect(server.dutyCalls, calls + 1);
      await tester.pump(driverDutyReloadInterval);
      expect(server.dutyCalls, calls + 2);
    });

    testWidgets('no 3-minute reload on another tab or in the background', (
      tester,
    ) async {
      final server = _DutyServer(_onlineChecked);
      await _pumpShell(tester, server);
      final calls = server.dutyCalls;

      await _selectTab(tester, 'Trips');
      await tester.pump(driverDutyReloadInterval);
      expect(server.dutyCalls, calls, reason: 'Trips tab');

      // Work's "Driver duty summary" panel fetches once as it opens.
      await _selectTab(tester, 'Work');
      final callsOnWork = server.dutyCalls;
      await _toBackground(tester);
      await tester.pump(driverDutyReloadInterval);
      expect(server.dutyCalls, callsOnWork, reason: 'in the background');
    });

    testWidgets('the Accra day change reloads it on any tab, and the timer '
        'is set again for the next day', (tester) async {
      final clock = _Clock(DateTime.utc(2026, 10, 24, 23, 58));
      final server = _DutyServer(_onlineChecked);
      await _pumpShell(tester, server, clock: clock);
      await _selectTab(tester, 'Account');
      final calls = server.dutyCalls;

      // The timer was set at 23:58 for just after midnight.
      clock.value = DateTime.utc(2026, 10, 25, 0, 0, 30);
      await tester.pump(const Duration(minutes: 2) + driverDutyDayChangeDelay);
      expect(server.dutyCalls, calls + 1);

      clock.value = DateTime.utc(2026, 10, 26, 0, 0, 30);
      await tester.pump(const Duration(days: 1));
      expect(server.dutyCalls, calls + 2);
    });

    testWidgets('a failed reload keeps Work as it was', (tester) async {
      final server = _DutyServer(_onlineChecked);
      await _pumpShell(tester, server);

      server.failNextFetch = const DriverDutyApiException(
        DriverDutyApiFailureType.unavailable,
        'Cannot reach the server.',
        noAnswer: true,
      );
      await tester.pump(driverDutyReloadInterval);
      await _settle(tester);

      expect(find.byKey(const Key('driver-offline-screen')), findsNothing);
      expect(find.byKey(const Key('driver-online-status')), findsOneWidget);
    });

    testWidgets('a session that ended shows as it does today', (tester) async {
      final server = _DutyServer(_onlineChecked);
      await _pumpShell(tester, server);

      server.failNextFetch = const DriverDutyApiException(
        DriverDutyApiFailureType.sessionExpired,
        'Session expired.',
      );
      await tester.pump(driverDutyReloadInterval);
      await _settle(tester);

      expect(find.byKey(const Key('driver-offline-screen')), findsOneWidget);
    });

    testWidgets('an answer older than a GO OFFLINE is dropped', (tester) async {
      final server = _DutyServer(_onlineChecked);
      await _pumpShell(tester, server);

      final hold = Completer<void>();
      server.holdNextFetch = hold;
      await _toBackground(tester);
      await _toForeground(tester); // a reload goes out: the server says online

      await tester.tap(find.byKey(const Key('driver-go-offline')));
      await _settle(tester);
      expect(find.byKey(const Key('driver-offline-status')), findsOneWidget);

      hold.complete();
      await _settle(tester);
      expect(
        find.byKey(const Key('driver-offline-status')),
        findsOneWidget,
        reason: 'the older "online" answer must not undo the GO OFFLINE',
      );
    });

    testWidgets('no 3-minute reload while a screen is open over Work', (
      tester,
    ) async {
      final server = _DutyServer(_onlineChecked);
      await _pumpShell(tester, server);
      unawaited(
        Navigator.of(
          tester.element(find.byType(DriverShell)),
        ).push<void>(MaterialPageRoute<void>(builder: (_) => const Scaffold())),
      );
      await _settle(tester);
      final calls = server.dutyCalls;

      await tester.pump(driverDutyReloadInterval);
      expect(server.dutyCalls, calls);
    });

    testWidgets('no reload starts while GO OFFLINE is out, so its older '
        'answer cannot undo it', (tester) async {
      final server = _DutyServer(_onlineChecked);
      await _pumpShell(tester, server);

      final update = Completer<void>();
      server.holdNextUpdate = update;
      await tester.tap(find.byKey(const Key('driver-go-offline')));
      await tester.pump();

      final fetch = Completer<void>();
      server.holdNextFetch = fetch;
      await _toBackground(tester);
      await _toForeground(tester); // the server still says online

      update.complete();
      await _settle(tester);
      fetch.complete();
      await _settle(tester);

      expect(find.byKey(const Key('driver-offline-status')), findsOneWidget);
    });

    testWidgets('no second reload while one is out', (tester) async {
      final server = _DutyServer(_onlineChecked);
      await _pumpShell(tester, server);
      final calls = server.dutyCalls;

      final hold = Completer<void>();
      server.holdNextFetch = hold;
      await _toBackground(tester);
      await _toForeground(tester);
      await _toBackground(tester);
      await _toForeground(tester);
      expect(server.dutyCalls, calls + 1);

      hold.complete();
      await _settle(tester);
    });
  });

  group("online without today's shift check", () {
    testWidgets('the header, the banner, and the duty card say so', (
      tester,
    ) async {
      final server = _DutyServer(_onlineNotChecked);
      await _pumpShell(tester, server);

      expect(
        find.text("Today's shift · online · shift check needed"),
        findsOneWidget,
      );
      expect(find.text(driverShiftCheckNeededMessage), findsOneWidget);
      expect(
        driverShiftCheckNeededMessage,
        "You're online, but today's shift check isn't done. You won't get "
        'automatic trips until you do it.',
      );
      expect(find.byKey(const Key('driver-online-status')), findsOneWidget);
      expect(find.byKey(const Key('driver-go-offline')), findsOneWidget);
    });

    testWidgets('Start shift check on the banner opens the shift check', (
      tester,
    ) async {
      final server = _DutyServer(_onlineNotChecked);
      await _pumpShell(tester, server);

      await tester.tap(
        find.byKey(const Key('driver-shift-check-needed-start')),
      );
      await _settle(tester);

      expect(find.byType(DriverReadinessPage), findsOneWidget);
    });

    testWidgets('GO OFFLINE on the duty card takes the driver offline', (
      tester,
    ) async {
      final server = _DutyServer(_onlineNotChecked);
      await _pumpShell(tester, server);

      await tester.tap(find.byKey(const Key('driver-go-offline')));
      await _settle(tester);

      expect(server.updates, [DriverOperationalDutyStatus.offline]);
      expect(find.text(driverShiftCheckNeededMessage), findsNothing);
    });

    testWidgets('once the check is done, a reload removes the banner', (
      tester,
    ) async {
      final server = _DutyServer(_onlineNotChecked);
      await _pumpShell(tester, server);
      expect(find.text(driverShiftCheckNeededMessage), findsOneWidget);

      server.current = _onlineChecked;
      await tester.pump(driverDutyReloadInterval);
      await _settle(tester);

      expect(find.text(driverShiftCheckNeededMessage), findsNothing);
      expect(find.text("Today's shift · online now"), findsOneWidget);
    });
  });

  group('a failed GO OFFLINE', () {
    testWidgets('no answer from the server: the driver stays online and is '
        'told to check the connection', (tester) async {
      final server = _DutyServer(_onlineChecked)
        ..failNextUpdate = const DriverDutyApiException(
          DriverDutyApiFailureType.unavailable,
          'Cannot reach the server.',
          noAnswer: true,
        );
      await _pumpShell(tester, server);

      await tester.tap(find.byKey(const Key('driver-go-offline')));
      await _settle(tester);

      expect(find.byKey(const Key('driver-offline-screen')), findsNothing);
      expect(find.byKey(const Key('driver-online-status')), findsOneWidget);
      expect(find.text(driverGoOfflineNoAnswerMessage), findsOneWidget);
      expect(
        driverGoOfflineNoAnswerMessage,
        "Couldn't go offline. You may still get trip offers. Check your "
        'connection and tap Retry.',
      );
    });

    testWidgets('the server answered with an error: the driver stays online '
        'and is told to retry', (tester) async {
      final server = _DutyServer(_onlineChecked)
        ..failNextUpdate = const DriverDutyApiException(
          DriverDutyApiFailureType.unavailable,
          'Server error.',
        );
      await _pumpShell(tester, server);

      await tester.tap(find.byKey(const Key('driver-go-offline')));
      await _settle(tester);

      expect(find.byKey(const Key('driver-offline-screen')), findsNothing);
      expect(find.byKey(const Key('driver-online-status')), findsOneWidget);
      expect(find.text(driverGoOfflineFailedMessage), findsOneWidget);
      expect(
        driverGoOfflineFailedMessage,
        "Couldn't go offline. You may still get trip offers. Tap Retry.",
      );
    });

    testWidgets('Retry sends GO OFFLINE again; when it lands the message '
        'goes and the driver is offline', (tester) async {
      final server = _DutyServer(_onlineChecked)
        ..failNextUpdate = const DriverDutyApiException(
          DriverDutyApiFailureType.unavailable,
          'Cannot reach the server.',
          noAnswer: true,
        );
      await _pumpShell(tester, server);
      await tester.tap(find.byKey(const Key('driver-go-offline')));
      await _settle(tester);

      await tester.tap(find.byKey(const Key('driver-go-offline-retry')));
      await _settle(tester);

      expect(server.updates, [
        DriverOperationalDutyStatus.offline,
        DriverOperationalDutyStatus.offline,
      ]);
      expect(find.text(driverGoOfflineNoAnswerMessage), findsNothing);
      expect(find.byKey(const Key('driver-offline-status')), findsOneWidget);
    });

    testWidgets('if a reload then finds the driver offline (GO OFFLINE did '
        'land), the message goes and does not come back', (tester) async {
      final server = _DutyServer(_onlineChecked)
        ..failNextUpdate = const DriverDutyApiException(
          DriverDutyApiFailureType.unavailable,
          'Cannot reach the server.',
          noAnswer: true,
        );
      await _pumpShell(tester, server);
      await tester.tap(find.byKey(const Key('driver-go-offline')));
      await _settle(tester);
      expect(find.text(driverGoOfflineNoAnswerMessage), findsOneWidget);

      server.current = const DriverDutySummary(
        dutyStatus: 'offline',
        shiftCheckToday: true,
      );
      await tester.pump(driverDutyReloadInterval);
      await _settle(tester);

      expect(find.text(driverGoOfflineNoAnswerMessage), findsNothing);
      expect(find.byKey(const Key('driver-offline-status')), findsOneWidget);

      // Online again later: the old message must not come back.
      server.current = _onlineChecked;
      await tester.pump(driverDutyReloadInterval);
      await _settle(tester);
      expect(find.byKey(const Key('driver-online-status')), findsOneWidget);
      expect(find.text(driverGoOfflineNoAnswerMessage), findsNothing);
    });

    testWidgets('a session that ended shows as it does today', (tester) async {
      final server = _DutyServer(_onlineChecked)
        ..failNextUpdate = const DriverDutyApiException(
          DriverDutyApiFailureType.sessionExpired,
          'Session expired.',
        );
      await _pumpShell(tester, server);

      await tester.tap(find.byKey(const Key('driver-go-offline')));
      await _settle(tester);

      expect(find.byKey(const Key('driver-offline-screen')), findsOneWidget);
      expect(find.text(driverGoOfflineNoAnswerMessage), findsNothing);
      expect(find.text(driverGoOfflineFailedMessage), findsNothing);
    });
  });

  group('the duty gateway tells "no answer" from "the server answered"', () {
    for (final (label, response, noAnswer) in [
      ('network', _failure(AsmApiExceptionType.network), true),
      ('timeout', _failure(AsmApiExceptionType.timeout), true),
      ('500', _failure(AsmApiExceptionType.server, statusCode: 500), false),
      ('502', _status(502), false),
      ('400', _status(400), false),
    ]) {
      test('$label: noAnswer is $noAnswer', () async {
        final gateway = AsmDriverDutyGateway.withApiClient(
          apiClient: _AnsweringDutyApiClient(response),
          tokenStore: _TokenStore(),
          refreshAccessToken: () async => DriverTokenRefreshOutcome.refreshed,
          dutyRetryDelay: (_) async {},
        );

        await expectLater(
          gateway.updateDutyStatus(DriverOperationalDutyStatus.offline),
          throwsA(
            isA<DriverDutyApiException>().having(
              (error) => error.noAnswer,
              'noAnswer',
              noAnswer,
            ),
          ),
        );
      });
    }

    test('a token refresh that does not complete: noAnswer', () async {
      final gateway = AsmDriverDutyGateway.withApiClient(
        apiClient: _AnsweringDutyApiClient(_status(200)),
        tokenStore: _TokenStore(expired: true),
        refreshAccessToken: () async =>
            DriverTokenRefreshOutcome.temporarilyUnavailable,
        dutyRetryDelay: (_) async {},
      );

      await expectLater(
        gateway.updateDutyStatus(DriverOperationalDutyStatus.offline),
        throwsA(
          isA<DriverDutyApiException>().having(
            (error) => error.noAnswer,
            'noAnswer',
            true,
          ),
        ),
      );
    });
  });

  testWidgets('24/25 Oct: left on Work overnight, after the Accra day '
      'change Work says "online · shift check needed"', (tester) async {
    final clock = _Clock(DateTime.utc(2026, 10, 24, 23, 59));
    final server = _DutyServer(_onlineChecked);
    await _pumpShell(tester, server, clock: clock);
    expect(find.text("Today's shift · online now"), findsOneWidget);

    // Midnight in Accra: the server keeps the driver online, but today's
    // shift check is not done yet.
    server.current = _onlineNotChecked;
    clock.value = DateTime.utc(2026, 10, 25, 0, 0, 30);
    await tester.pump(const Duration(minutes: 1) + driverDutyDayChangeDelay);
    await _settle(tester);

    expect(
      find.text("Today's shift · online · shift check needed"),
      findsOneWidget,
    );
    expect(find.text(driverShiftCheckNeededMessage), findsOneWidget);
    expect(find.byKey(const Key('driver-online-status')), findsOneWidget);
    expect(find.byKey(const Key('driver-go-offline')), findsOneWidget);
  });
}

Future<void> _pumpShell(
  WidgetTester tester,
  _DutyServer server, {
  _Clock? clock,
}) async {
  final now = clock ?? _Clock(DateTime.utc(2026, 10, 24, 10));
  await tester.pumpWidget(
    MaterialApp(
      theme: AsmThemes.driver,
      home: DriverShell(
        driverDutyGateway: server,
        deviceNow: () => now.value,
        onlineTransitionDuration: Duration.zero,
      ),
    ),
  );
  await _settle(tester);
}

Future<void> _selectTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await _settle(tester);
}

Future<void> _toBackground(WidgetTester tester) async {
  for (final state in const [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
  await tester.pump();
}

Future<void> _toForeground(WidgetTester tester) async {
  for (final state in const [
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
  await tester.pump();
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i += 1) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

final class _Clock {
  _Clock(this.value);

  DateTime value;
}

/// The server's duty state. A fetch answers with the state at the moment
/// it was asked, so a held answer is an old one.
final class _DutyServer implements DriverDutyGateway, DriverDutyStatusGateway {
  _DutyServer(this.current);

  DriverDutySummary current;
  int dutyCalls = 0;
  Completer<void>? holdNextFetch;
  Completer<void>? holdNextUpdate;
  Object? failNextFetch;
  Object? failNextUpdate;
  final updates = <DriverOperationalDutyStatus>[];

  @override
  Future<DriverDutySummary> fetchDuty() async {
    dutyCalls += 1;
    final answer = current;
    final hold = holdNextFetch;
    if (hold != null) {
      holdNextFetch = null;
      await hold.future;
    }
    final failure = failNextFetch;
    if (failure != null) {
      failNextFetch = null;
      throw failure;
    }
    return answer;
  }

  @override
  Future<List<DriverAssignedTrip>> fetchTrips() async =>
      const <DriverAssignedTrip>[];

  @override
  Future<DriverAssignedTrip> fetchTripDetail(String tripReference) async =>
      throw StateError('not used');

  @override
  Future<DriverDutyTransition> updateDutyStatus(
    DriverOperationalDutyStatus status,
  ) async {
    updates.add(status);
    final hold = holdNextUpdate;
    if (hold != null) {
      holdNextUpdate = null;
      await hold.future;
    }
    final failure = failNextUpdate;
    if (failure != null) {
      failNextUpdate = null;
      throw failure;
    }
    final transition = DriverDutyTransition(
      dutyStatus: status.wireValue,
      since: DateTime.utc(2026, 10, 25),
    );
    current = current.withDutyTransition(transition);
    return transition;
  }
}

ApiResponse<Object?> _failure(AsmApiExceptionType type, {int? statusCode}) =>
    ApiResponse<Object?>.apiFailure(
      AsmApiException(type: type, message: 'failed', statusCode: statusCode),
    );

ApiResponse<Object?> _status(int statusCode) => ApiResponse<Object?>.apiFailure(
  AsmApiException(
    type: AsmApiExceptionType.badResponse,
    message: 'failed',
    statusCode: statusCode,
  ),
);

final class _AnsweringDutyApiClient
    implements DriverDutyApiClient, DriverDutyPostApiClient {
  _AnsweringDutyApiClient(this.response);

  final ApiResponse<Object?> response;

  @override
  Future<ApiResponse<T>> get<T>(String path, {JsonDecoder<T>? decoder}) =>
      throw StateError('not used');

  @override
  Future<ApiResponse<T>> post<T>(
    String path, {
    Object? data,
    Map<String, String>? headers,
    JsonDecoder<T>? decoder,
  }) async {
    final error = response.error;
    if (error == null) {
      return ApiResponse<T>.success(
        decoder!(<String, Object?>{
          'duty_status': 'offline',
          'since': '2026-10-25T00:00:00Z',
        }),
        statusCode: 200,
      );
    }
    return ApiResponse<T>.apiFailure(error);
  }
}

final class _TokenStore implements AuthTokenStore {
  _TokenStore({this.expired = false});

  final bool expired;

  // exp 4102444800 (2100) or 1 (1970).
  String get _token =>
      expired ? 'e30.eyJleHAiOjF9.' : 'e30.eyJleHAiOjQxMDI0NDQ4MDB9.';

  @override
  Future<String?> readAccessToken() async => _token;

  @override
  Future<String?> readRefreshToken() async => 'refresh';

  @override
  Future<void> saveTokens(AuthTokens tokens) async {}

  @override
  Future<void> clearTokens() async {}
}
