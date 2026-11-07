import 'dart:async';
import 'dart:convert';

import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_auth/asm_auth.dart';
import 'package:asm_offline_queue/asm_offline_queue.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../network/driver_access_token_refresh_guard.dart';
import '../network/driver_trip_action_gateway.dart';
import '../network/driver_trip_action_resilience.dart';
import '../network/ghana_network_resilience.dart';
import 'driver_readiness_check.dart';

const driverShiftCheckPath = '/api/driver/shift-check/';
const driverShiftCheckQueueReference = 'driver-shift-check';
const driverShiftCheckQueueDriverIdentity = 'authenticated-driver';

final class DriverShiftCheckSubmission {
  const DriverShiftCheckSubmission({
    required this.vehicleCheck,
    required this.batteryCheck,
    required this.batteryAttentionFlag,
    required this.phoneAppCheck,
    required this.safetyCheck,
    required this.submittedAt,
  });

  factory DriverShiftCheckSubmission.fromReadiness({
    required DriverReadinessCheck check,
    required bool batteryNeedsAttention,
    required DateTime submittedAt,
  }) {
    return DriverShiftCheckSubmission(
      vehicleCheck: check.completedItems.contains(
        DriverReadinessItem.approvedShiftDetails,
      ),
      batteryCheck: check.completedItems.contains(
        DriverReadinessItem.vehicleExterior,
      ),
      batteryAttentionFlag: batteryNeedsAttention,
      phoneAppCheck: check.completedItems.contains(
        DriverReadinessItem.cabinSafety,
      ),
      safetyCheck: check.completedItems.contains(
        DriverReadinessItem.batteryStatus,
      ),
      submittedAt: submittedAt,
    );
  }

  final bool vehicleCheck;
  final bool batteryCheck;
  final bool batteryAttentionFlag;
  final bool phoneAppCheck;
  final bool safetyCheck;
  final DateTime submittedAt;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'vehicle_check': vehicleCheck,
      'battery_check': batteryCheck,
      'battery_attention_flag': batteryAttentionFlag,
      'phone_app_check': phoneAppCheck,
      'safety_check': safetyCheck,
      // UTC with "Z" (A3): the server reads the moment, not the phone's zone.
      'submitted_at': submittedAt.toUtc().toIso8601String(),
    };
  }
}

enum DriverShiftCheckSubmissionDisposition { submitted, queued, stale }

/// The driver a queued shift check belongs to (A3): `user:<user_id>` from
/// a sign-in token's payload, or null when the token does not say.
String? driverQueueTagFromToken(String? token) {
  final parts = token?.trim().split('.');
  if (parts == null || parts.length != 3) {
    return null;
  }
  try {
    final payload = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    );
    final userId = payload is Map ? payload['user_id'] : null;
    if (userId is int || (userId is String && userId.trim().isNotEmpty)) {
      return 'user:${'$userId'.trim()}';
    }
  } on Object {
    // Not a token the app can read.
  }
  return null;
}

/// Queued events older than this are deleted (A3), whatever they are.
const driverQueueMaxAge = Duration(days: 7);

/// The server accepts a shift check from before today's start by this much
/// (S5's tolerance); older ones are refused as stale, so the app does not
/// send them.
const driverShiftCheckDayGrace = Duration(minutes: 10);

/// Housekeeping at app start and at sign-in (A3): deletes every event older
/// than [driverQueueMaxAge], untagged shift checks from builds before the
/// tag, and, with [signedInTag], another driver's shift checks. A queue
/// that cannot delete is left as it is.
Future<void> driverQueueHousekeeping(
  DriverTripActionPersistentQueue queue, {
  required DateTime now,
  String? signedInTag,
}) async {
  if (queue is! DriverQueueCleanup) {
    return;
  }
  final oldest = now.toUtc().subtract(driverQueueMaxAge);
  await (queue as DriverQueueCleanup).removeWhere((event) {
    if (event.createdAt.toUtc().isBefore(oldest)) {
      return true;
    }
    if (!_isShiftCheckRecord(event)) {
      return false;
    }
    return event.driverId == driverShiftCheckQueueDriverIdentity ||
        (signedInTag != null && event.driverId != signedInTag);
  });
}

bool _isShiftCheckRecord(QueuedEvent event) =>
    event.eventType == driverShiftCheckPath &&
    event.tripReference == driverShiftCheckQueueReference;

/// True when [submittedAt] is before the start of [now]'s day (UTC, the
/// server's Accra day) by more than the server's grace.
bool _fromAnEarlierDay(DateTime submittedAt, DateTime now) {
  final utcNow = now.toUtc();
  final dayStart = DateTime.utc(utcNow.year, utcNow.month, utcNow.day);
  return submittedAt.toUtc().isBefore(
    dayStart.subtract(driverShiftCheckDayGrace),
  );
}

bool _isStale(ApiResponse<Object?> response) {
  final body = response.error?.cause;
  return response.statusCode == 409 &&
      body is Map &&
      body['code'] == 'shift_check_stale';
}

/// What the driver reads when a check made just now is refused as stale:
/// it carried the phone's own time, so the phone's clock is wrong (lead,
/// 7 Nov).
const driverShiftCheckPhoneClockMessage =
    "Your phone's date or time looks wrong. Set it to automatic and try again.";

/// What the driver reads when the server refuses a check as stale (S5).
const driverShiftCheckStaleMessage =
    "This shift check was done on an earlier day. Do today's shift check.";

String _staleMessage(ApiResponse<Object?> response) {
  final body = response.error?.cause;
  final detail = body is Map ? body['detail'] : null;
  return detail is String && detail.trim().isNotEmpty
      ? detail
      : driverShiftCheckStaleMessage;
}

final class DriverShiftCheckSubmissionResult {
  const DriverShiftCheckSubmissionResult({
    required this.disposition,
    required this.event,
    this.message,
  });

  /// The server's words for [stale].
  final String? message;

  /// The server refused it as a check from an earlier day: not submitted.
  bool get stale => disposition == DriverShiftCheckSubmissionDisposition.stale;

  final DriverShiftCheckSubmissionDisposition disposition;
  final QueuedEvent event;

  bool get submitted =>
      disposition == DriverShiftCheckSubmissionDisposition.submitted;

  bool get queued =>
      disposition == DriverShiftCheckSubmissionDisposition.queued;
}

abstract interface class DriverShiftCheckGateway {
  Future<ApiResponse<Object?>> submit({
    required Map<String, Object?> body,
    required String idempotencyKey,
  });
}

final class ApiDriverShiftCheckGateway implements DriverShiftCheckGateway {
  ApiDriverShiftCheckGateway({
    required this.client,
    required AuthTokenStore tokenStore,
    required DriverAccessTokenRefresh? refreshAccessToken,
    DateTime Function()? utcNow,
  }) : _tokenGuard = DriverAccessTokenRefreshGuard(
         tokenStore: tokenStore,
         refreshAccessToken: refreshAccessToken,
         utcNow: utcNow,
       );

  final AsmApiClient client;
  final DriverAccessTokenRefreshGuard _tokenGuard;

  bool _forceRefreshBeforeNextPost = false;

  @override
  Future<ApiResponse<Object?>> submit({
    required Map<String, Object?> body,
    required String idempotencyKey,
  }) async {
    final resolution = await _tokenGuard.resolve(
      forceRefresh: _forceRefreshBeforeNextPost,
    );

    _forceRefreshBeforeNextPost = false;

    final response = await client.post<Object?>(
      driverShiftCheckPath,
      data: body,
      headers: <String, String>{
        'Authorization': 'Bearer ${resolution.accessToken}',
        'Content-Type': 'application/json',
        'Idempotency-Key': idempotencyKey,
      },
    );

    if (response.statusCode == 401) {
      _forceRefreshBeforeNextPost = true;
    }

    return response;
  }
}

typedef DriverShiftCheckOnlineCheck = Future<bool> Function();
typedef DriverShiftCheckRetryDelay = Future<void> Function(Duration delay);

final class DriverShiftCheckSubmissionController {
  DriverShiftCheckSubmissionController({
    required this.queue,
    required this.gateway,
    required this.isOnline,
    this.connectivitySource,
    DriverShiftCheckRetryDelay? retryDelay,
    this.currentDriverTag,
    this.now,
  }) : _retryDelay = retryDelay ?? ((delay) => Future<void>.delayed(delay));

  final DriverTripActionPersistentQueue queue;
  final DriverShiftCheckGateway gateway;
  final DriverShiftCheckOnlineCheck isOnline;
  final GhanaConnectivitySource? connectivitySource;
  final DriverShiftCheckRetryDelay _retryDelay;

  /// The signed-in driver's tag (A3). Without it (older wiring and tests)
  /// checks use the old untagged identity.
  final Future<String?> Function()? currentDriverTag;

  /// The clock for the server-day rule (A3); without it the rule is off.
  final DateTime Function()? now;

  Future<String> _driverTag() async {
    final read = currentDriverTag;
    if (read == null) {
      return driverShiftCheckQueueDriverIdentity;
    }
    try {
      return await read() ?? 'unknown-driver';
    } on Object {
      return 'unknown-driver';
    }
  }

  bool _tooOldToSend(QueuedEvent event) {
    final clock = now;
    return clock != null && _fromAnEarlierDay(event.deviceTimestamp, clock());
  }

  Future<void> _remove(String eventId) async {
    final queue = this.queue;
    if (queue is DriverQueueCleanup) {
      await (queue as DriverQueueCleanup).removeWhere(
        (event) => event.id == eventId,
      );
    } else {
      await queue.markPermanentlyFailed(eventId);
    }
  }

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Future<DriverShiftCheckSubmissionResult>? _submissionInFlight;
  Future<void>? _syncInFlight;
  Future<void>? _retryChainInFlight;

  Future<DriverShiftCheckSubmissionResult> submit(
    DriverShiftCheckSubmission submission,
  ) {
    final existing = _submissionInFlight;
    if (existing != null) {
      return existing;
    }

    final operation = _submit(submission);
    _submissionInFlight = operation;

    operation.whenComplete(() {
      if (identical(_submissionInFlight, operation)) {
        _submissionInFlight = null;
      }
    });

    return operation;
  }

  Future<DriverShiftCheckSubmissionResult> _submit(
    DriverShiftCheckSubmission submission,
  ) async {
    final timestamp = submission.submittedAt;
    final timestampIdentity = timestamp.toUtc().microsecondsSinceEpoch;
    final idempotencyKey = 'DRIVER-SHIFT-CHECK-$timestampIdentity';

    final event = await queue.enqueue(
      QueuedEvent(
        id: 'driver-shift-check:$timestampIdentity',
        eventType: driverShiftCheckPath,
        tripReference: driverShiftCheckQueueReference,
        driverId: await _driverTag(),
        payloadJson: submission.toJson(),
        idempotencyKey: idempotencyKey,
        deviceTimestamp: timestamp,
      ),
    );

    if (!await _canSubmitNow()) {
      return DriverShiftCheckSubmissionResult(
        disposition: DriverShiftCheckSubmissionDisposition.queued,
        event: event,
      );
    }

    try {
      final response = await gateway.submit(
        body: event.payloadJson,
        idempotencyKey: event.idempotencyKey,
      );

      if (_isStale(response)) {
        await _remove(event.id);
        return DriverShiftCheckSubmissionResult(
          disposition: DriverShiftCheckSubmissionDisposition.stale,
          event: event,
          message: _staleMessage(response),
        );
      }

      if (response.isSuccess || response.statusCode == 409) {
        await queue.markSynced(event.id);
        return DriverShiftCheckSubmissionResult(
          disposition: DriverShiftCheckSubmissionDisposition.submitted,
          event: event,
        );
      }

      await _markInitialFailureExactlyOnce(event.id);
    } on Object {
      await _markInitialFailureExactlyOnce(event.id);
    }

    _scheduleFailedDeliveryRetries();

    return DriverShiftCheckSubmissionResult(
      disposition: DriverShiftCheckSubmissionDisposition.queued,
      event: event,
    );
  }

  Future<bool> _canSubmitNow() async {
    try {
      return await isOnline();
    } on Object {
      return false;
    }
  }

  Future<void> startAutomaticSync() async {
    await syncQueuedSubmissions();

    final source = connectivitySource;
    if (source == null || _connectivitySubscription != null) {
      return;
    }

    _connectivitySubscription = source.onConnectivityChanged.listen(
      (results) {
        final transport = GhanaNetworkClassifier.transportFor(results);
        if (transport != GhanaNetworkTransport.none) {
          unawaited(syncQueuedSubmissions());
        }
      },
      onError: (_) {
        unawaited(syncQueuedSubmissions());
      },
    );
  }

  Future<void> stopAutomaticSync() async {
    final subscription = _connectivitySubscription;
    _connectivitySubscription = null;
    await subscription?.cancel();
  }

  Future<void> syncQueuedSubmissions() {
    final existing = _syncInFlight;
    if (existing != null) {
      return existing;
    }

    final operation = _syncQueuedSubmissions();
    _syncInFlight = operation;

    operation.whenComplete(() {
      if (identical(_syncInFlight, operation)) {
        _syncInFlight = null;
      }
    });

    return operation;
  }

  Future<void> _syncQueuedSubmissions() async {
    if (!await _canSubmitNow()) {
      return;
    }

    final tag = await _driverTag();
    final events = await queue.pendingEvents();
    final shiftCheckEvents = events.where(
      (event) => _isShiftCheckEvent(event) && event.driverId == tag,
    );
    var failedDelivery = false;

    for (final event in shiftCheckEvents) {
      final storedEvent = await queue.eventById(event.id);

      if (storedEvent == null ||
          storedEvent.syncStatus == QueueSyncStatus.synced ||
          storedEvent.syncStatus == QueueSyncStatus.permanentlyFailed) {
        continue;
      }

      if (_tooOldToSend(storedEvent)) {
        // The server would refuse it as stale: never sent (A3).
        await _remove(event.id);
        continue;
      }

      try {
        final response = await gateway.submit(
          body: event.payloadJson,
          idempotencyKey: event.idempotencyKey,
        );

        if (_isStale(response)) {
          await _remove(event.id);
        } else if (response.isSuccess || response.statusCode == 409) {
          await _markSyncedExactlyOnce(event.id);
        } else {
          await _markInitialFailureExactlyOnce(event.id);
          failedDelivery = true;
        }
      } on Object {
        await _markInitialFailureExactlyOnce(event.id);
        failedDelivery = true;
      }
    }

    if (failedDelivery) {
      _scheduleFailedDeliveryRetries();
    }
  }

  bool _isShiftCheckEvent(QueuedEvent event) => _isShiftCheckRecord(event);

  Future<void> _markInitialFailureExactlyOnce(String eventId) async {
    final storedEvent = await queue.eventById(eventId);

    if (storedEvent?.syncStatus == QueueSyncStatus.pending) {
      await queue.markFailed(eventId);
    }
  }

  Future<void> _markSyncedExactlyOnce(String eventId) async {
    final storedEvent = await queue.eventById(eventId);

    if (storedEvent == null ||
        storedEvent.syncStatus == QueueSyncStatus.synced) {
      return;
    }

    await queue.markSynced(eventId);
  }

  void _scheduleFailedDeliveryRetries() {
    if (_retryChainInFlight != null) {
      return;
    }

    final operation = _runFailedDeliveryRetryChain();
    _retryChainInFlight = operation;

    unawaited(
      operation
          .whenComplete(() {
            if (identical(_retryChainInFlight, operation)) {
              _retryChainInFlight = null;
            }
          })
          .catchError((Object _) {}),
    );
  }

  Future<void> _runFailedDeliveryRetryChain() async {
    for (final delay in GhanaRequestPolicy.retryBackoffs) {
      await _retryDelay(delay);

      if (!await _hasQueuedShiftCheck()) {
        return;
      }

      await syncQueuedSubmissions();

      if (!await _hasQueuedShiftCheck()) {
        return;
      }
    }
  }

  Future<bool> _hasQueuedShiftCheck() async {
    final tag = await _driverTag();
    final events = await queue.pendingEvents();
    return events.any(
      (event) => _isShiftCheckEvent(event) && event.driverId == tag,
    );
  }
}
