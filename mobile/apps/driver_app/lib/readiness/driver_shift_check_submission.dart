import 'dart:async';

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
      'submitted_at': submittedAt.toIso8601String(),
    };
  }
}

enum DriverShiftCheckSubmissionDisposition { submitted, queued }

final class DriverShiftCheckSubmissionResult {
  const DriverShiftCheckSubmissionResult({
    required this.disposition,
    required this.event,
  });

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
  }) : _retryDelay = retryDelay ?? ((delay) => Future<void>.delayed(delay));

  final DriverTripActionPersistentQueue queue;
  final DriverShiftCheckGateway gateway;
  final DriverShiftCheckOnlineCheck isOnline;
  final GhanaConnectivitySource? connectivitySource;
  final DriverShiftCheckRetryDelay _retryDelay;

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
        driverId: driverShiftCheckQueueDriverIdentity,
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

      if (response.isSuccess) {
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

    final events = await queue.pendingEvents();
    final shiftCheckEvents = events.where(_isShiftCheckEvent);
    var failedDelivery = false;

    for (final event in shiftCheckEvents) {
      final storedEvent = await queue.eventById(event.id);

      if (storedEvent == null ||
          storedEvent.syncStatus == QueueSyncStatus.synced ||
          storedEvent.syncStatus == QueueSyncStatus.permanentlyFailed) {
        continue;
      }

      try {
        final response = await gateway.submit(
          body: event.payloadJson,
          idempotencyKey: event.idempotencyKey,
        );

        if (response.isSuccess) {
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

  bool _isShiftCheckEvent(QueuedEvent event) {
    return event.eventType == driverShiftCheckPath &&
        event.tripReference == driverShiftCheckQueueReference &&
        event.driverId == driverShiftCheckQueueDriverIdentity;
  }

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
    final events = await queue.pendingEvents();
    return events.any(_isShiftCheckEvent);
  }
}
