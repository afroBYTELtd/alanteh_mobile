import 'dart:convert';
import 'dart:io';

import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_offline_queue/asm_offline_queue.dart';
import 'package:driver_app/network/driver_trip_action_resilience.dart';
import 'package:driver_app/readiness/driver_readiness_check.dart';
import 'package:driver_app/readiness/driver_shift_check_submission.dart';
import 'package:flutter_test/flutter_test.dart';

// Sign-in build A3, the shift check queue and the server's day:
// - a queued shift check carries the signed-in driver (user:<id> from the
//   token); only the signed-in driver's checks are ever sent;
// - housekeeping (app start and sign-in) deletes untagged checks from older
//   builds, another driver's checks at sign-in, and every event older than
//   7 days;
// - submitted_at goes as UTC ending in "Z";
// - a queued check from an earlier day (beyond the server's 10 min grace)
//   is not sent; 409 shift_check_stale is not "submitted".

const _me = 'user:7';
const _other = 'user:8';
const _staleText =
    "This shift check was done on an earlier day. Do today's shift check.";

void main() {
  group('the driver tag from the token', () {
    String jwt(Map<String, Object?> payload) =>
        'e30.${base64Url.encode(utf8.encode(jsonEncode(payload))).replaceAll('=', '')}.sig';

    test('user_id becomes user:<id>', () {
      expect(driverQueueTagFromToken(jwt({'user_id': 7})), _me);
      expect(driverQueueTagFromToken(jwt({'user_id': '7'})), _me);
    });

    test('no user_id, or not a token: none', () {
      expect(driverQueueTagFromToken(jwt({'exp': 1})), isNull);
      expect(driverQueueTagFromToken('not-a-token'), isNull);
      expect(driverQueueTagFromToken(null), isNull);
    });
  });

  group('submitting and sending', () {
    test('a new check is tagged with the signed-in driver', () async {
      final h = _Harness();

      final result = await h.controller.submit(h.submission(h.now));

      expect(result.event.driverId, _me);
      expect(h.gateway.bodies, hasLength(1));
    });

    test("another driver's queued check is never sent", () async {
      final h = _Harness();
      await h.queue.enqueue(h.queued(h.now, driver: _other, id: 'theirs'));
      await h.queue.enqueue(h.queued(h.now, driver: _me, id: 'mine'));

      await h.controller.syncQueuedSubmissions();

      expect(h.gateway.keys, ['mine']);
      expect(await h.queue.eventById('theirs'), isNotNull);
    });

    test('submitted_at is UTC and ends in Z', () {
      final local = DateTime(2026, 11, 7, 9, 30);

      final sent = h0.submission(local).toJson()['submitted_at'];

      expect(sent, local.toUtc().toIso8601String());
      expect(sent, endsWith('Z'));
    });
  });

  group("the server's day (Accra = UTC)", () {
    test("yesterday's queued check is not sent and is deleted", () async {
      final h = _Harness(now: DateTime.utc(2026, 11, 7, 9));
      await h.queue.enqueue(
        h.queued(DateTime.utc(2026, 11, 6, 20), driver: _me, id: 'old'),
      );

      await h.controller.syncQueuedSubmissions();

      expect(h.gateway.bodies, isEmpty);
      expect(await h.queue.eventById('old'), isNull);
    });

    test('5 min before midnight is still sent after midnight', () async {
      final h = _Harness(now: DateTime.utc(2026, 11, 7, 0, 3));
      await h.queue.enqueue(
        h.queued(DateTime.utc(2026, 11, 6, 23, 55), driver: _me, id: 'late'),
      );

      await h.controller.syncQueuedSubmissions();

      expect(h.gateway.keys, ['late']);
    });

    test('11 min before midnight is not', () async {
      final h = _Harness(now: DateTime.utc(2026, 11, 7, 0, 3));
      await h.queue.enqueue(
        h.queued(DateTime.utc(2026, 11, 6, 23, 49), driver: _me, id: 'old'),
      );

      await h.controller.syncQueuedSubmissions();

      expect(h.gateway.bodies, isEmpty);
    });

    test('409 shift_check_stale on submit: stale, not submitted', () async {
      final h = _Harness()..gateway.answer = _stale();

      final result = await h.controller.submit(h.submission(h.now));

      expect(result.submitted, isFalse);
      expect(result.stale, isTrue);
      expect(result.message, _staleText);
      expect(await h.queue.eventById(result.event.id), isNull);
      expect(h.retry.scheduled, isEmpty);
    });

    test('409 shift_check_stale when sending a queued one: deleted, not '
        'synced', () async {
      final h = _Harness()..gateway.answer = _stale();
      await h.queue.enqueue(h.queued(h.now, driver: _me, id: 'mine'));

      await h.controller.syncQueuedSubmissions();

      expect(await h.queue.eventById('mine'), isNull);
      expect(h.queue.syncedIds, isEmpty);
    });

    test(
      'another 409 (same day, different answers) is still submitted',
      () async {
        final h = _Harness()
          ..gateway.answer = ApiResponse.apiFailure(
            const AsmApiException(
              type: AsmApiExceptionType.badResponse,
              message: 'conflict',
              statusCode: 409,
              cause: {'code': 'shift_check_conflict'},
            ),
          );

        final result = await h.controller.submit(h.submission(h.now));

        expect(result.submitted, isTrue);
      },
    );
  });

  group('housekeeping', () {
    final now = DateTime.utc(2026, 11, 7, 9);

    test(
      'deletes untagged checks from older builds, keeps tagged ones',
      () async {
        final queue = _CleanableQueue();
        final h = _Harness(queue: queue);
        await queue.enqueue(
          h.queued(
            now,
            driver: driverShiftCheckQueueDriverIdentity,
            id: 'old-build',
          ),
        );
        await queue.enqueue(h.queued(now, driver: _other, id: 'theirs'));

        await driverQueueHousekeeping(queue, now: now);

        expect(await queue.eventById('old-build'), isNull);
        expect(await queue.eventById('theirs'), isNotNull);
      },
    );

    test(
      "at sign-in, another driver's checks go; mine and trip actions stay",
      () async {
        final queue = _CleanableQueue();
        final h = _Harness(queue: queue);
        await queue.enqueue(h.queued(now, driver: _other, id: 'theirs'));
        await queue.enqueue(h.queued(now, driver: _me, id: 'mine'));
        await queue.enqueue(
          _tripAction('trip-action', driver: 'DRV-8', at: now),
        );

        await driverQueueHousekeeping(queue, now: now, signedInTag: _me);

        expect(await queue.eventById('theirs'), isNull);
        expect(await queue.eventById('mine'), isNotNull);
        expect(await queue.eventById('trip-action'), isNotNull);
      },
    );

    test('every event older than 7 days goes, whatever it is', () async {
      final queue = _CleanableQueue();
      final h = _Harness(queue: queue);
      final eightDays = now.subtract(const Duration(days: 7, minutes: 1));
      final sixDays = now.subtract(const Duration(days: 6, hours: 23));
      await queue.enqueue(
        h.queued(eightDays, driver: _me, id: 'old-check', createdAt: eightDays),
      );
      await queue.enqueue(
        _tripAction('old-action', driver: 'DRV-7', at: eightDays),
      );
      await queue.enqueue(
        _tripAction('recent-action', driver: 'DRV-7', at: sixDays),
      );

      await driverQueueHousekeeping(queue, now: now, signedInTag: _me);

      expect(await queue.eventById('old-check'), isNull);
      expect(await queue.eventById('old-action'), isNull);
      expect(await queue.eventById('recent-action'), isNotNull);
    });

    test('the age limit is 7 days', () {
      expect(driverQueueMaxAge, const Duration(days: 7));
    });

    test('a queue that cannot delete is left alone', () async {
      final queue = _PlainQueue();
      await queue.enqueue(
        _tripAction('a', driver: 'DRV-7', at: DateTime.utc(2020)),
      );

      await driverQueueHousekeeping(queue, now: now, signedInTag: _me);

      expect(await queue.eventById('a'), isNotNull);
    });
  });

  test('the app wires the tag and the clock into the real controller', () {
    final source = File('lib/main.dart').readAsStringSync();
    final factory = source.substring(
      source.indexOf(
        'DriverShiftCheckSubmissionController? _driverShiftCheckControllerFor(',
      ),
    );
    final body = factory.substring(0, factory.indexOf('\n}\n'));

    expect(body, contains('currentDriverTag:'));
    expect(body, contains('now: DateTime.now'));
  });
}

final h0 = _Harness();

ApiResponse<Object?> _stale() => ApiResponse.apiFailure(
  const AsmApiException(
    type: AsmApiExceptionType.badResponse,
    message: 'conflict',
    statusCode: 409,
    cause: {'detail': _staleText, 'code': 'shift_check_stale'},
  ),
);

QueuedEvent _tripAction(
  String id, {
  required String driver,
  required DateTime at,
}) => QueuedEvent(
  id: id,
  eventType: '/api/driver/trips/TRIP-1/arrived/',
  tripReference: 'TRIP-1',
  driverId: driver,
  payloadJson: const {'action': 'arrived'},
  idempotencyKey: 'KEY-$id',
  deviceTimestamp: at,
  createdAt: at,
);

final class _Harness {
  _Harness({DateTime? now, _CleanableQueue? queue})
    : now = now ?? DateTime.utc(2026, 11, 7, 9),
      queue = queue ?? _CleanableQueue() {
    controller = DriverShiftCheckSubmissionController(
      queue: this.queue,
      gateway: gateway,
      isOnline: () async => true,
      retryDelay: retry.call,
      currentDriverTag: () async => _me,
      now: () => this.now,
    );
  }

  final DateTime now;
  final _CleanableQueue queue;
  final gateway = _Gateway();
  final retry = _Retry();
  late final DriverShiftCheckSubmissionController controller;

  DriverShiftCheckSubmission submission(DateTime at) =>
      DriverShiftCheckSubmission.fromReadiness(
        check: _complete(),
        batteryNeedsAttention: false,
        submittedAt: at,
      );

  QueuedEvent queued(
    DateTime at, {
    required String driver,
    required String id,
    DateTime? createdAt,
  }) => QueuedEvent(
    id: id,
    eventType: driverShiftCheckPath,
    tripReference: driverShiftCheckQueueReference,
    driverId: driver,
    payloadJson: submission(at).toJson(),
    idempotencyKey: id,
    deviceTimestamp: at,
    createdAt: createdAt ?? now,
  );
}

DriverReadinessCheck _complete() {
  var check = DriverReadinessCheck.empty();
  for (final item in DriverReadinessItem.values) {
    check = check.toggle(item);
  }
  return check;
}

final class _Gateway implements DriverShiftCheckGateway {
  final bodies = <Map<String, Object?>>[];
  final keys = <String>[];
  ApiResponse<Object?> answer = ApiResponse<Object?>.success(
    const <String, Object?>{'ok': true},
    statusCode: 201,
  );

  @override
  Future<ApiResponse<Object?>> submit({
    required Map<String, Object?> body,
    required String idempotencyKey,
  }) async {
    bodies.add(body);
    keys.add(idempotencyKey);
    return answer;
  }
}

final class _Retry {
  final scheduled = <Duration>[];

  Future<void> call(Duration delay) async {
    scheduled.add(delay);
  }
}

/// A queue without deletion (most test fakes and older code).
class _PlainQueue implements DriverTripActionPersistentQueue {
  final Map<String, QueuedEvent> events = <String, QueuedEvent>{};
  final syncedIds = <String>[];

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
    syncedIds.add(id);
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
}

final class _CleanableQueue extends _PlainQueue implements DriverQueueCleanup {
  @override
  Future<int> removeWhere(bool Function(QueuedEvent event) test) async {
    final ids = events.values.where(test).map((e) => e.id).toList();
    for (final id in ids) {
      events.remove(id);
    }
    return ids.length;
  }
}
