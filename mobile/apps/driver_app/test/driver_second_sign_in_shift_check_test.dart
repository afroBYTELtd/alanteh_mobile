import 'dart:async';
import 'dart:convert';

import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_auth/asm_auth.dart';
import 'package:asm_offline_queue/asm_offline_queue.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:driver_app/driver_duty_trips.dart';
import 'package:driver_app/main.dart';
import 'package:driver_app/network/driver_trip_action_resilience.dart';
import 'package:driver_app/network/ghana_network_resilience.dart';
import 'package:driver_app/readiness/driver_readiness_check.dart';
import 'package:driver_app/readiness/driver_shift_check_submission.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Lead, 7 Nov: an object shared across a sign-out and a second sign-in in
// the same app process has gone wrong twice. DriverApp hands the SAME
// shift check controller to every Work (the login shell passes its
// driverShiftCheckController to each new DriverShell), so through the real
// DriverApp: the first driver's stale-check note must not reach the second
// driver, and the automatic sync must work again after Work 1 stopped it.

const _staleNote = Key('driver-saved-shift-check-stale-note');

void main() {
  testWidgets('a second driver after sign-out: no note from the first, and '
      'the automatic sync sends their saved check', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    final now = DateTime.utc(2026, 11, 7, 9);
    final tokens = MemoryAuthTokenStore();
    final api = _AuthApi();
    final queue = _Queue();
    final gateway = _Gateway();
    final connectivity = _Connectivity();
    addTearDown(connectivity.close);
    var online = true;
    // One controller for the whole app process, as DriverApp shares it.
    final controller = DriverShiftCheckSubmissionController(
      queue: queue,
      gateway: gateway,
      isOnline: () async => online,
      connectivitySource: connectivity,
      currentDriverTag: () async =>
          driverQueueTagFromToken(await tokens.readRefreshToken()),
      now: () => now,
    );
    await queue.enqueue(_check('user:7', DateTime.utc(2026, 11, 6, 20)));

    await tester.pumpWidget(
      DriverApp(
        showLoginShell: true,
        authService: AuthService(
          apiGateway: api,
          tokenStore: tokens,
          appContext: AuthAppContext.driver,
        ),
        authTokenStore: tokens,
        driverDutyGateway: _Duty(),
        driverShiftCheckController: controller,
      ),
    );
    await tester.pumpAndSettle();

    Future<void> signInAndBackToWork(int userId) async {
      api.userId = userId;
      await tester.enterText(
        find.byKey(const Key('driver-phone-field')),
        '+23300000000$userId',
      );
      await tester.enterText(find.byKey(const Key('driver-pin-field')), '9876');
      await tester.tap(find.byKey(const Key('driver-sign-in')));
      await tester.pumpAndSettle();
      // No check today: Work opens the shift check; back to Work.
      expect(find.text('Shift check'), findsWidgets);
      await tester.pageBack();
      await tester.pumpAndSettle();
    }

    // Driver 7: Work's first sync drops yesterday's saved check: the note.
    await signInAndBackToWork(7);
    expect(find.byKey(_staleNote), findsOneWidget);

    await tester.tap(find.text('Account'));
    await tester.pumpAndSettle();
    final signOut = find.byKey(const Key('driver-account-sign-out'));
    await tester.ensureVisible(signOut);
    await tester.pumpAndSettle();
    await tester.tap(signOut);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('driver-sign-in')), findsOneWidget);

    // Driver 8 has a check saved to send; the phone is offline at sign-in,
    // so only the automatic sync (a connectivity change) can send it.
    final theirs = _check('user:8', now);
    await queue.enqueue(theirs);
    online = false;
    await signInAndBackToWork(8);

    expect(find.byKey(_staleNote), findsNothing);
    expect(gateway.keys, isEmpty);

    online = true;
    connectivity.emit(ConnectivityResult.wifi);
    await tester.pumpAndSettle();

    expect(gateway.keys, [theirs.idempotencyKey]);
    expect(
      (await queue.eventById(theirs.id))?.syncStatus,
      QueueSyncStatus.synced,
    );
    expect(find.byKey(_staleNote), findsNothing);
  });
}

QueuedEvent _check(String driver, DateTime at) => QueuedEvent(
  id: 'driver-shift-check:$driver:${at.microsecondsSinceEpoch}',
  eventType: driverShiftCheckPath,
  tripReference: driverShiftCheckQueueReference,
  driverId: driver,
  payloadJson: DriverShiftCheckSubmission.fromReadiness(
    check: _complete(),
    batteryNeedsAttention: false,
    submittedAt: at,
  ).toJson(),
  idempotencyKey: 'DRIVER-SHIFT-CHECK-$driver-${at.microsecondsSinceEpoch}',
  deviceTimestamp: at,
  createdAt: at,
);

DriverReadinessCheck _complete() {
  var check = DriverReadinessCheck.empty();
  for (final item in DriverReadinessItem.values) {
    check = check.toggle(item);
  }
  return check;
}

String _jwt(Map<String, Object?> payload) {
  String part(Map<String, Object?> json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  return '${part({'alg': 'HS256'})}.${part(payload)}.sig';
}

/// Signs in whichever driver [userId] says; sign-out answers 200.
final class _AuthApi implements AuthApiGateway {
  int userId = 7;

  @override
  Future<ApiResponse<Map<String, Object?>>> post(
    String path, {
    required Map<String, Object?> body,
  }) async => ApiResponse<Map<String, Object?>>.success(
    path == AuthService.logoutPath
        ? <String, Object?>{'detail': 'Signed out.'}
        : <String, Object?>{
            'access': 'driver-access-$userId',
            'refresh': _jwt(<String, Object?>{
              'user_id': userId,
              'exp':
                  DateTime.now()
                      .add(const Duration(days: 30))
                      .millisecondsSinceEpoch ~/
                  1000,
            }),
            'account_type': 'driver',
            'account': <String, Object?>{},
          },
    statusCode: 200,
  );
}

/// Offline, no shift check today.
final class _Duty implements DriverDutyGateway {
  @override
  Future<DriverDutySummary> fetchDuty() async => DriverDutySummary(
    driverReference: 'DRV-001',
    dutyStatus: 'offline',
    dutySince: DateTime(2026, 11, 6, 8),
    shiftCheckToday: false,
  );

  @override
  Future<List<DriverAssignedTrip>> fetchTrips() async =>
      const <DriverAssignedTrip>[];

  @override
  Future<DriverAssignedTrip> fetchTripDetail(String tripReference) =>
      throw StateError('not used');
}

final class _Gateway implements DriverShiftCheckGateway {
  final keys = <String>[];

  @override
  Future<ApiResponse<Object?>> submit({
    required Map<String, Object?> body,
    required String idempotencyKey,
  }) async {
    keys.add(idempotencyKey);
    return ApiResponse<Object?>.success(const <String, Object?>{
      'ok': true,
    }, statusCode: 201);
  }
}

final class _Connectivity implements GhanaConnectivitySource {
  final _changes = StreamController<List<ConnectivityResult>>.broadcast();

  void emit(ConnectivityResult result) =>
      _changes.add(<ConnectivityResult>[result]);

  Future<void> close() => _changes.close();

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async =>
      const <ConnectivityResult>[ConnectivityResult.wifi];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => _changes.stream;
}

final class _Queue
    implements DriverTripActionPersistentQueue, DriverQueueCleanup {
  final events = <String, QueuedEvent>{};

  @override
  Future<QueuedEvent> enqueue(QueuedEvent event) async =>
      events[event.id] = event;

  @override
  Future<QueuedEvent?> eventById(String id) async => events[id];

  @override
  Future<List<QueuedEvent>> pendingEvents() async => events.values
      .where(
        (e) =>
            e.syncStatus == QueueSyncStatus.pending ||
            e.syncStatus == QueueSyncStatus.failed,
      )
      .toList();

  @override
  Future<void> markSynced(String id) async {
    events[id] = events[id]!.copyWith(syncStatus: QueueSyncStatus.synced);
  }

  @override
  Future<void> markFailed(String id) async {
    events[id] = events[id]!.copyWith(syncStatus: QueueSyncStatus.failed);
  }

  @override
  Future<void> markPermanentlyFailed(String id) async {
    events[id] = events[id]!.copyWith(
      syncStatus: QueueSyncStatus.permanentlyFailed,
    );
  }

  @override
  Future<int> removeWhere(bool Function(QueuedEvent event) test) async {
    final ids = events.values.where(test).map((e) => e.id).toList();
    ids.forEach(events.remove);
    return ids.length;
  }
}
