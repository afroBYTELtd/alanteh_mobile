// B9: the Trips list and Work's "Driver duty summary" stay current. Seen
// 30 Oct: a declined offer still showed on Trips as "Driver offer sent";
// 31 Oct: Work's panel said "Active trips 1" from an old load.

import 'dart:async';

import 'package:asm_design_system/asm_design_system.dart';
import 'package:driver_app/driver_duty_trips.dart';
import 'package:driver_app/driver_reload_signal.dart';
import 'package:driver_app/driver_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _offered = DriverAssignedTrip(
  reference: 'TRIP-4B162D11198C',
  status: 'driver_offer_sent',
);
const _declined = DriverAssignedTrip(
  reference: 'TRIP-4B162D11198C',
  status: 'driver_declined',
);
const _other = DriverAssignedTrip(reference: 'TRIP-NEW', status: 'dispatched');

void main() {
  group('the Trips list reloads quietly', () {
    testWidgets('coming back to the app reloads it, with the list kept on '
        'screen meanwhile', (tester) async {
      final h = _Harness([_offered]);
      await h.pumpOnTrips(tester);
      final calls = h.server.tripCalls;

      final hold = Completer<void>();
      h.server
        ..trips = [_declined]
        ..holdNextTrips = hold;
      await _toBackground(tester);
      await _toForeground(tester);

      expect(h.server.tripCalls, calls + 1);
      expect(find.byKey(const Key('driver-trips-loading')), findsNothing);
      expect(find.text('Driver offer sent'), findsOneWidget);

      hold.complete();
      await _settle(tester);
      expect(find.text('Driver offer sent'), findsNothing);
    });

    testWidgets('Trips in front reloads it every 3 minutes', (tester) async {
      final h = _Harness([_offered]);
      await h.pumpOnTrips(tester);
      final calls = h.server.tripCalls;

      await tester.pump(driverDutyReloadInterval);
      await _settle(tester);
      expect(h.server.tripCalls, calls + 1);
    });

    testWidgets('the 30 Oct case: a change in the pending offers reloads it, '
        'and the declined offer no longer says "Driver offer sent"', (
      tester,
    ) async {
      final h = _Harness([_offered]);
      await h.pumpOnTrips(tester);
      expect(find.text('Driver offer sent'), findsOneWidget);

      h.server.trips = [_declined];
      h.signal.ping();
      await _settle(tester);

      expect(find.text('Driver offer sent'), findsNothing);
      expect(find.text('TRIP-4B162D11198C'), findsOneWidget);
    });

    testWidgets('back from a trip screen it reloads quietly, once', (
      tester,
    ) async {
      final h = _Harness([_offered]);
      await h.pumpOnTrips(tester);
      h.pushScreen(tester);
      await _settle(tester);
      final calls = h.server.tripCalls;

      h.server.trips = [_declined, _other];
      h.popScreen(tester);
      await tester.pump();
      expect(find.byKey(const Key('driver-trips-loading')), findsNothing);
      await _settle(tester);

      expect(h.server.tripCalls, calls + 1);
      expect(find.text('TRIP-NEW'), findsOneWidget);
    });

    testWidgets('not while a trip screen is on top (a trip action may be '
        'running there); once back, one reload', (tester) async {
      final h = _Harness([_offered]);
      await h.pumpOnTrips(tester);
      h.pushScreen(tester);
      await _settle(tester);
      final calls = h.server.tripCalls;

      h.signal
        ..ping()
        ..ping();
      await _settle(tester);
      expect(h.server.tripCalls, calls);

      h.popScreen(tester);
      await _settle(tester);
      expect(h.server.tripCalls, calls + 1);
    });

    testWidgets('a failed reload keeps the list', (tester) async {
      final h = _Harness([_offered]);
      await h.pumpOnTrips(tester);

      h.server.failNextTrips = StateError('no network');
      h.signal.ping();
      await _settle(tester);

      expect(find.text('TRIP-4B162D11198C'), findsOneWidget);
      expect(find.byKey(const Key('driver-trips-error')), findsNothing);
    });

    testWidgets('one at a time: asks during a reload make one more after it', (
      tester,
    ) async {
      final h = _Harness([_offered]);
      await h.pumpOnTrips(tester);
      final calls = h.server.tripCalls;

      final hold = h.server.holdNextTrips = Completer<void>();
      h.signal.ping();
      await tester.pump();
      h.signal
        ..ping()
        ..ping()
        ..ping();
      await tester.pump();
      expect(h.server.tripCalls, calls + 1);

      hold.complete();
      await _settle(tester);
      expect(h.server.tripCalls, calls + 2);
    });

    testWidgets('an answer that started before Refresh is dropped', (
      tester,
    ) async {
      final h = _Harness([_offered]);
      await h.pumpOnTrips(tester);

      // The quiet reload asks while the server still has the offer.
      final hold = h.server.holdNextTrips = Completer<void>();
      h.signal.ping();
      await tester.pump();

      h.server.trips = [_declined, _other];
      await tester.tap(find.byKey(const Key('driver-trips-refresh')));
      await _settle(tester);
      expect(find.text('TRIP-NEW'), findsOneWidget);

      hold.complete();
      await _settle(tester);
      expect(find.text('TRIP-NEW'), findsOneWidget);
      expect(find.text('Driver offer sent'), findsNothing);
    });
  });

  group("Work's Driver duty summary", () {
    testWidgets('shows the shell\'s summary, and a reload updates it with '
        'one fetch', (tester) async {
      final h = _Harness(const []);
      h.server.duty = const DriverDutySummary(
        dutyStatus: 'online',
        shiftCheckToday: true,
        activeTripCount: 1,
        assignedTripCount: 18,
      );
      await h.pumpShell(tester);
      expect(h.server.dutyCalls, 1, reason: 'the shell\'s own load only');
      expect(_detail(tester, 'Active trips'), '1');

      h.server.duty = const DriverDutySummary(
        dutyStatus: 'online',
        shiftCheckToday: true,
        activeTripCount: 0,
        assignedTripCount: 18,
      );
      h.signal.ping();
      await _settle(tester);

      expect(h.server.dutyCalls, 2);
      expect(_detail(tester, 'Active trips'), '0');
    });

    testWidgets('Refresh reloads it quietly through the shell', (tester) async {
      final h = _Harness(const []);
      await h.pumpShell(tester);
      final calls = h.server.dutyCalls;

      await tester.ensureVisible(find.byKey(const Key('driver-duty-refresh')));
      await tester.tap(find.byKey(const Key('driver-duty-refresh')));
      await tester.pump();
      expect(
        find.byKey(const Key('driver-duty-startup-loading')),
        findsNothing,
      );
      await _settle(tester);

      expect(h.server.dutyCalls, calls + 1);
    });
  });
}

/// The value next to [label] in the duty panel.
String? _detail(WidgetTester tester, String label) {
  final row = find.ancestor(of: find.text(label), matching: find.byType(Row));
  final texts = find
      .descendant(of: row.first, matching: find.byType(Text))
      .evaluate()
      .map((element) => (element.widget as Text).data)
      .where((text) => text != label)
      .toList();
  return texts.isEmpty ? null : texts.single;
}

final class _Harness {
  _Harness(List<DriverAssignedTrip> trips) : server = _Server(trips);

  final _Server server;
  final signal = DriverReloadSignal();
  final _navigator = GlobalKey<NavigatorState>();

  Future<void> pumpShell(WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: _navigator,
        theme: AsmThemes.driver,
        home: DriverShell(
          driverDutyGateway: server,
          deviceNow: () => DateTime.utc(2026, 10, 31, 10),
          onlineTransitionDuration: Duration.zero,
          reloadSignal: signal,
        ),
      ),
    );
    await _settle(tester);
  }

  Future<void> pumpOnTrips(WidgetTester tester) async {
    await pumpShell(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Trips'),
      ),
    );
    await _settle(tester);
  }

  /// A trip screen over the tabs.
  void pushScreen(WidgetTester tester) => unawaited(
    _navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Trip screen')),
      ),
    ),
  );

  void popScreen(WidgetTester tester) => _navigator.currentState!.pop();
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

/// A trips fetch answers with the list at the moment it was asked, so a
/// held answer is an old one.
final class _Server implements DriverDutyGateway {
  _Server(this.trips);

  List<DriverAssignedTrip> trips;
  DriverDutySummary duty = const DriverDutySummary(
    dutyStatus: 'online',
    shiftCheckToday: true,
  );
  int tripCalls = 0;
  int dutyCalls = 0;
  Completer<void>? holdNextTrips;
  Object? failNextTrips;

  @override
  Future<DriverDutySummary> fetchDuty() async {
    dutyCalls += 1;
    return duty;
  }

  @override
  Future<List<DriverAssignedTrip>> fetchTrips() async {
    tripCalls += 1;
    final answer = trips;
    final hold = holdNextTrips;
    if (hold != null) {
      holdNextTrips = null;
      await hold.future;
    }
    final failure = failNextTrips;
    if (failure != null) {
      failNextTrips = null;
      throw failure;
    }
    return answer;
  }

  @override
  Future<DriverAssignedTrip> fetchTripDetail(String tripReference) async =>
      throw StateError('not used');
}
