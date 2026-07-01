import 'dart:async';
import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

enum QueueSyncStatus { pending, syncing, synced, failed, permanentlyFailed }

enum QueueValidationCode { blank, invalidPayload, invalidRetryCount }

enum QueueValidationField {
  eventType,
  tripReference,
  driverId,
  payloadJson,
  retryCount,
}

final class QueueValidationException implements Exception {
  const QueueValidationException({required this.code, required this.field});

  final QueueValidationCode code;
  final QueueValidationField field;

  @override
  String toString() =>
      'QueueValidationException(field: ${field.name}, code: ${code.name})';
}

final class QueuedEvent {
  factory QueuedEvent({
    String? id,
    required String eventType,
    required String tripReference,
    required String driverId,
    required Map<String, Object?> payloadJson,
    String? idempotencyKey,
    DateTime? deviceTimestamp,
    QueueSyncStatus syncStatus = QueueSyncStatus.pending,
    int retryCount = 0,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    final normalizedEventType = _requiredText(
      eventType,
      QueueValidationField.eventType,
    );
    final normalizedTripReference = _requiredText(
      tripReference,
      QueueValidationField.tripReference,
    );
    final normalizedDriverId = _requiredText(
      driverId,
      QueueValidationField.driverId,
    );
    if (retryCount < 0) {
      throw const QueueValidationException(
        code: QueueValidationCode.invalidRetryCount,
        field: QueueValidationField.retryCount,
      );
    }
    _validateJsonCompatible(payloadJson, QueueValidationField.payloadJson);

    final now = DateTime.now().toUtc();
    final normalizedCreatedAt = createdAt?.toUtc() ?? now;
    final normalizedUpdatedAt = updatedAt?.toUtc() ?? normalizedCreatedAt;

    return QueuedEvent._(
      id: _normalizeIdentifier(id),
      eventType: normalizedEventType,
      tripReference: normalizedTripReference,
      driverId: normalizedDriverId,
      payloadJson: _validatedJsonMap(payloadJson),
      idempotencyKey: _normalizeIdentifier(idempotencyKey),
      deviceTimestamp: (deviceTimestamp ?? now).toUtc(),
      syncStatus: syncStatus,
      retryCount: retryCount,
      createdAt: normalizedCreatedAt,
      updatedAt: normalizedUpdatedAt,
    );
  }

  const QueuedEvent._({
    required this.id,
    required this.eventType,
    required this.tripReference,
    required this.driverId,
    required this.payloadJson,
    required this.idempotencyKey,
    required this.deviceTimestamp,
    required this.syncStatus,
    required this.retryCount,
    required this.createdAt,
    required this.updatedAt,
  });

  static final _uuid = Uuid();

  final String id;
  final String eventType;
  final String tripReference;
  final String driverId;
  final Map<String, Object?> payloadJson;
  final String idempotencyKey;
  final DateTime deviceTimestamp;
  final QueueSyncStatus syncStatus;
  final int retryCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  QueuedEvent copyWith({
    QueueSyncStatus? syncStatus,
    int? retryCount,
    DateTime? updatedAt,
  }) {
    return QueuedEvent._(
      id: id,
      eventType: eventType,
      tripReference: tripReference,
      driverId: driverId,
      payloadJson: payloadJson,
      idempotencyKey: idempotencyKey,
      deviceTimestamp: deviceTimestamp,
      syncStatus: syncStatus ?? this.syncStatus,
      retryCount: retryCount ?? this.retryCount,
      createdAt: createdAt,
      updatedAt: (updatedAt ?? DateTime.now()).toUtc(),
    );
  }

  Map<String, Object?> toDatabaseMap() {
    return {
      'id': id,
      'event_type': eventType,
      'trip_reference': tripReference,
      'driver_id': driverId,
      'payload_json': jsonEncode(payloadJson),
      'idempotency_key': idempotencyKey,
      'device_timestamp': deviceTimestamp.toIso8601String(),
      'sync_status': syncStatus.name,
      'retry_count': retryCount,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  static QueuedEvent fromDatabaseMap(Map<String, Object?> row) {
    return QueuedEvent(
      id: row['id']! as String,
      eventType: row['event_type']! as String,
      tripReference: row['trip_reference']! as String,
      driverId: row['driver_id']! as String,
      payloadJson: _decodedPayload(row['payload_json']! as String),
      idempotencyKey: row['idempotency_key']! as String,
      deviceTimestamp: DateTime.parse(row['device_timestamp']! as String),
      syncStatus: QueueSyncStatus.values.byName(row['sync_status']! as String),
      retryCount: row['retry_count']! as int,
      createdAt: DateTime.parse(row['created_at']! as String),
      updatedAt: DateTime.parse(row['updated_at']! as String),
    );
  }

  static String _normalizeIdentifier(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      return _uuid.v4();
    }
    return normalized;
  }
}

final class QueueStatusSummary {
  const QueueStatusSummary({
    required this.pendingCount,
    required this.syncingCount,
    required this.failedRetryableCount,
    required this.permanentlyFailedCount,
    required this.syncedCount,
  });

  final int pendingCount;
  final int syncingCount;
  final int failedRetryableCount;
  final int permanentlyFailedCount;
  final int syncedCount;

  int get totalCount =>
      pendingCount +
      syncingCount +
      failedRetryableCount +
      permanentlyFailedCount +
      syncedCount;

  bool get hasPendingWork => pendingCount > 0;

  bool get hasRetryableFailures => failedRetryableCount > 0;

  bool get hasPermanentFailures => permanentlyFailedCount > 0;

  bool get isClear =>
      pendingCount == 0 &&
      failedRetryableCount == 0 &&
      permanentlyFailedCount == 0;
}

abstract class OfflineQueueSyncClient {
  Future<void> syncEvent(QueuedEvent event);
}

abstract class OfflineQueueConnectivity {
  Future<bool> get isOnline;
}

final class QueueManager {
  const QueueManager._(this._store);

  static const maxRetryCount = 3;

  final _OfflineQueueStore _store;

  static Future<QueueManager> open({String? databasePath}) async {
    final resolvedPath =
        databasePath ??
        p.join(await getDatabasesPath(), 'asm_offline_queue.sqlite');
    final store = await _SqfliteQueueStore.open(resolvedPath);
    return QueueManager._(store);
  }

  static Future<QueueManager> openInMemory() async {
    final store = await _SqfliteQueueStore.open(inMemoryDatabasePath);
    return QueueManager._(store);
  }

  Future<QueuedEvent> enqueue(QueuedEvent event) async {
    await _store.upsert(event);
    return event;
  }

  Future<QueuedEvent?> eventById(String id) => _store.findById(id);

  Future<List<QueuedEvent>> pendingEvents() async {
    final events = await _store.allOrdered();
    return events
        .where(
          (event) =>
              event.syncStatus == QueueSyncStatus.pending ||
              (event.syncStatus == QueueSyncStatus.failed &&
                  event.retryCount < maxRetryCount),
        )
        .toList(growable: false);
  }

  Future<QueueStatusSummary> statusSummary() async {
    var pendingCount = 0;
    var syncingCount = 0;
    var failedRetryableCount = 0;
    var permanentlyFailedCount = 0;
    var syncedCount = 0;

    final events = await _store.allOrdered();
    for (final event in events) {
      switch (event.syncStatus) {
        case QueueSyncStatus.pending:
          pendingCount += 1;
          break;
        case QueueSyncStatus.syncing:
          syncingCount += 1;
          break;
        case QueueSyncStatus.synced:
          syncedCount += 1;
          break;
        case QueueSyncStatus.failed:
          if (event.retryCount < maxRetryCount) {
            failedRetryableCount += 1;
          } else {
            permanentlyFailedCount += 1;
          }
          break;
        case QueueSyncStatus.permanentlyFailed:
          permanentlyFailedCount += 1;
          break;
      }
    }

    return QueueStatusSummary(
      pendingCount: pendingCount,
      syncingCount: syncingCount,
      failedRetryableCount: failedRetryableCount,
      permanentlyFailedCount: permanentlyFailedCount,
      syncedCount: syncedCount,
    );
  }

  Future<int> pendingBadgeCount() async {
    final summary = await statusSummary();
    return summary.pendingCount +
        summary.failedRetryableCount +
        summary.permanentlyFailedCount;
  }

  Future<bool> canAttemptSync(OfflineQueueConnectivity connectivity) {
    return connectivity.isOnline;
  }

  Future<bool> syncPendingWhenOnline(
    OfflineQueueSyncClient client,
    OfflineQueueConnectivity connectivity,
  ) async {
    if (!await canAttemptSync(connectivity)) {
      return false;
    }
    await syncPending(client);
    return true;
  }

  Future<void> markSyncing(String id) =>
      _updateStatus(id, QueueSyncStatus.syncing);

  Future<void> markSynced(String id) =>
      _updateStatus(id, QueueSyncStatus.synced);

  Future<void> markFailed(String id) => incrementRetry(id);

  Future<void> markPermanentlyFailed(String id) =>
      _updateStatus(id, QueueSyncStatus.permanentlyFailed);

  Future<void> incrementRetry(String id) async {
    final event = await _store.findById(id);
    if (event == null) {
      return;
    }
    final nextRetryCount = event.retryCount + 1;
    final nextStatus = nextRetryCount >= maxRetryCount
        ? QueueSyncStatus.permanentlyFailed
        : QueueSyncStatus.failed;
    await _store.upsert(
      event.copyWith(syncStatus: nextStatus, retryCount: nextRetryCount),
    );
  }

  Future<void> clearSynced() => _store.deleteSynced();

  Future<void> syncPending(OfflineQueueSyncClient client) async {
    final events = await pendingEvents();
    for (final event in events) {
      await markSyncing(event.id);
      try {
        await client.syncEvent(event);
        await markSynced(event.id);
      } catch (_) {
        await markFailed(event.id);
      }
    }
  }

  Future<void> close() => _store.close();

  Future<void> _updateStatus(String id, QueueSyncStatus status) async {
    final event = await _store.findById(id);
    if (event == null) {
      return;
    }
    await _store.upsert(event.copyWith(syncStatus: status));
  }
}

abstract interface class _OfflineQueueStore {
  Future<void> upsert(QueuedEvent event);
  Future<QueuedEvent?> findById(String id);
  Future<List<QueuedEvent>> allOrdered();
  Future<void> deleteSynced();
  Future<void> close();
}

final class _SqfliteQueueStore implements _OfflineQueueStore {
  const _SqfliteQueueStore(this._database);

  static const _table = 'queued_events';

  final Database _database;

  static Future<_SqfliteQueueStore> open(String path) async {
    final database = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
CREATE TABLE $_table (
  id TEXT PRIMARY KEY,
  event_type TEXT NOT NULL,
  trip_reference TEXT NOT NULL,
  driver_id TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  idempotency_key TEXT NOT NULL,
  device_timestamp TEXT NOT NULL,
  sync_status TEXT NOT NULL,
  retry_count INTEGER NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
)
''');
        await db.execute(
          'CREATE INDEX idx_queued_events_created_at ON $_table(created_at)',
        );
      },
    );
    return _SqfliteQueueStore(database);
  }

  @override
  Future<void> upsert(QueuedEvent event) async {
    await _database.insert(
      _table,
      event.toDatabaseMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<QueuedEvent?> findById(String id) async {
    final rows = await _database.query(
      _table,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return QueuedEvent.fromDatabaseMap(rows.single);
  }

  @override
  Future<List<QueuedEvent>> allOrdered() async {
    final rows = await _database.query(
      _table,
      orderBy: 'created_at ASC, id ASC',
    );
    return rows.map(QueuedEvent.fromDatabaseMap).toList(growable: false);
  }

  @override
  Future<void> deleteSynced() async {
    await _database.delete(
      _table,
      where: 'sync_status = ?',
      whereArgs: [QueueSyncStatus.synced.name],
    );
  }

  @override
  Future<void> close() => _database.close();
}

String _requiredText(String value, QueueValidationField field) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw QueueValidationException(
      code: QueueValidationCode.blank,
      field: field,
    );
  }
  return normalized;
}

Map<String, Object?> _decodedPayload(String encodedPayload) {
  final decoded = jsonDecode(encodedPayload);
  if (decoded is! Map) {
    throw const QueueValidationException(
      code: QueueValidationCode.invalidPayload,
      field: QueueValidationField.payloadJson,
    );
  }
  return _validatedJsonMap(decoded);
}

void _validateJsonCompatible(Object? value, QueueValidationField field) {
  try {
    _validatedJsonValue(value);
  } on QueueValidationException {
    rethrow;
  } catch (_) {
    throw QueueValidationException(
      code: QueueValidationCode.invalidPayload,
      field: field,
    );
  }
}

Map<String, Object?> _validatedJsonMap(Map<dynamic, dynamic> value) {
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is! String) {
      throw const QueueValidationException(
        code: QueueValidationCode.invalidPayload,
        field: QueueValidationField.payloadJson,
      );
    }
    result[key] = _validatedJsonValue(entry.value);
  }
  return Map<String, Object?>.unmodifiable(result);
}

Object? _validatedJsonValue(Object? value) {
  if (value == null || value is String || value is bool || value is num) {
    return value;
  }
  if (value is List) {
    return List<Object?>.unmodifiable(value.map(_validatedJsonValue));
  }
  if (value is Map) {
    return _validatedJsonMap(value);
  }
  throw const QueueValidationException(
    code: QueueValidationCode.invalidPayload,
    field: QueueValidationField.payloadJson,
  );
}
