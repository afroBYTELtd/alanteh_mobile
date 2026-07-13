import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';

const driverDutyPath = '/api/driver/me/';
const driverTripsPath = '/api/driver/trips/';
const driverEmptyValue = 'Not assigned yet';
const driverTripsEmptyTitle = 'No assigned trips yet.';
const driverTripsEmptyMessage =
    'When the Control Center assigns a trip, it will appear here.';
const driverSessionExpiredMessage =
    'Session expired. Please sign in again to continue.';

enum DriverDutyApiFailureType {
  sessionExpired,
  notFound,
  unavailable,
  badResponse,
}

final class DriverDutyApiException implements Exception {
  const DriverDutyApiException(this.type, this.message);

  final DriverDutyApiFailureType type;
  final String message;

  bool get isSessionExpired => type == DriverDutyApiFailureType.sessionExpired;

  @override
  String toString() => 'DriverDutyApiException(type=$type)';
}

abstract interface class DriverDutyGateway {
  Future<DriverDutySummary> fetchDuty();
  Future<List<DriverAssignedTrip>> fetchTrips();
  Future<DriverAssignedTrip> fetchTripDetail(String tripReference);
}

final class AsmDriverDutyGateway implements DriverDutyGateway {
  const AsmDriverDutyGateway(this.client);

  final AsmApiClient client;

  @override
  Future<DriverDutySummary> fetchDuty() async {
    final response = await client.get<DriverDutySummary>(
      driverDutyPath,
      decoder: DriverDutySummary.fromJson,
    );
    return _successOrThrow(response);
  }

  @override
  Future<List<DriverAssignedTrip>> fetchTrips() async {
    final response = await client.get<List<DriverAssignedTrip>>(
      driverTripsPath,
      decoder: DriverAssignedTrip.decodeListResponse,
    );
    return _successOrThrow(response);
  }

  @override
  Future<DriverAssignedTrip> fetchTripDetail(String tripReference) async {
    final cleanReference = tripReference.trim();
    if (cleanReference.isEmpty) {
      throw const DriverDutyApiException(
        DriverDutyApiFailureType.badResponse,
        'Trip reference is missing.',
      );
    }

    final response = await client.get<DriverAssignedTrip>(
      '$driverTripsPath${Uri.encodeComponent(cleanReference)}/',
      decoder: DriverAssignedTrip.fromJson,
    );
    return _successOrThrow(response);
  }

  T _successOrThrow<T>(ApiResponse<T> response) {
    final data = response.data;
    if (response.isSuccess && data != null) {
      return data;
    }

    final error = response.error;
    if (error?.type == AsmApiExceptionType.authentication ||
        response.statusCode == 401) {
      throw const DriverDutyApiException(
        DriverDutyApiFailureType.sessionExpired,
        driverSessionExpiredMessage,
      );
    }

    if (error?.type == AsmApiExceptionType.notFound ||
        response.statusCode == 404) {
      throw const DriverDutyApiException(
        DriverDutyApiFailureType.notFound,
        'The requested trip was not found.',
      );
    }

    if (error?.type == AsmApiExceptionType.network ||
        error?.type == AsmApiExceptionType.timeout ||
        error?.type == AsmApiExceptionType.server) {
      throw const DriverDutyApiException(
        DriverDutyApiFailureType.unavailable,
        'Driver information is temporarily unavailable.',
      );
    }

    throw const DriverDutyApiException(
      DriverDutyApiFailureType.badResponse,
      'Driver information could not be loaded.',
    );
  }
}

final class DriverDutySummary {
  const DriverDutySummary({
    this.displayName,
    this.driverReference,
    this.phone,
    this.status,
    this.assignedVehicleReference,
    this.canReceiveAssignments,
    this.activeTripCount,
    this.assignedTripCount,
  });

  factory DriverDutySummary.empty() => const DriverDutySummary();

  final String? displayName;
  final String? driverReference;
  final String? phone;
  final String? status;
  final String? assignedVehicleReference;
  final bool? canReceiveAssignments;
  final int? activeTripCount;
  final int? assignedTripCount;

  static DriverDutySummary fromJson(Object? json) {
    final map = _decodeMap(json, 'Driver duty response was not a JSON object.');
    return DriverDutySummary(
      displayName: _firstString(map, const [
        'display_name',
        'driver_display_name',
        'name',
        'full_name',
      ]),
      driverReference: _firstString(map, const [
        'driver_reference',
        'driver_code',
        'reference',
        'code',
      ]),
      phone: _firstString(map, const ['phone', 'phone_number', 'mobile']),
      status: _firstString(map, const ['driver_status', 'status']),
      assignedVehicleReference: _firstString(map, const [
        'assigned_vehicle_reference',
        'vehicle_reference',
        'vehicle',
      ]),
      canReceiveAssignments: _firstBool(map, const ['can_receive_assignments']),
      activeTripCount: _firstInt(map, const ['active_trip_count']),
      assignedTripCount: _firstInt(map, const ['assigned_trip_count']),
    );
  }
}

final class DriverAssignedTrip {
  const DriverAssignedTrip({
    required this.reference,
    this.status,
    this.pickupLocation,
    this.destination,
    this.requestedPickupTime,
    this.createdTime,
    this.updatedTime,
    this.vehicleReference,
    this.passengerCount,
    this.controlCenterMessage,
  });

  final String reference;
  final String? status;
  final String? pickupLocation;
  final String? destination;
  final String? requestedPickupTime;
  final String? createdTime;
  final String? updatedTime;
  final String? vehicleReference;
  final int? passengerCount;
  final String? controlCenterMessage;

  static DriverAssignedTrip fromJson(Object? json) {
    final map = _decodeMap(json, 'Trip response was not a JSON object.');
    final reference = _firstString(map, const [
      'trip_reference',
      'reference',
      'request_reference',
    ]);

    if (reference == null || reference.isEmpty) {
      throw const FormatException('Trip reference is missing.');
    }

    return DriverAssignedTrip(
      reference: reference,
      status: _firstString(map, const ['status', 'trip_status']),
      pickupLocation: _firstString(map, const [
        'pickup_location',
        'pickup',
        'pickup_description',
      ]),
      destination: _firstString(map, const ['destination', 'dropoff_location']),
      requestedPickupTime: _firstString(map, const [
        'requested_pickup_time',
        'pickup_time',
      ]),
      createdTime: _firstString(map, const ['created_at', 'created_time']),
      updatedTime: _firstString(map, const ['updated_at', 'updated_time']),
      vehicleReference: _firstString(map, const [
        'vehicle_reference',
        'assigned_vehicle_reference',
        'vehicle',
      ]),
      passengerCount: _firstInt(map, const ['passenger_count']),
      controlCenterMessage: _firstString(map, const [
        'control_center_message',
        'driver_message',
        'message',
      ]),
    );
  }

  static List<DriverAssignedTrip> decodeListResponse(Object? json) {
    final rawItems = switch (json) {
      List() => json,
      Map() =>
        json['results'] ?? json['trips'] ?? json['assigned_trips'] ?? const [],
      _ => throw const FormatException(
        'Trip list response was not a JSON list.',
      ),
    };

    if (rawItems is! List) {
      throw const FormatException('Trip list response was not a JSON list.');
    }

    return rawItems.map(DriverAssignedTrip.fromJson).toList(growable: false);
  }
}

String driverStatusLabel(String? status) {
  return switch (status?.trim()) {
    'assigned' => 'Assigned',
    'accepted_for_trip' => 'Accepted for trip preparation',
    'driver_en_route' => 'On the way to pickup',
    'arrived_at_pickup' => 'Arrived at pickup',
    'passenger_onboard' => 'Passenger onboard',
    'completed' => 'Completed',
    'cancelled' => 'Cancelled',
    final value? when value.isNotEmpty => _sentenceCase(
      value.replaceAll('_', ' '),
    ),
    _ => driverEmptyValue,
  };
}

String maskDriverPhone(String? phone) {
  final normalized = phone?.replaceAll(RegExp(r'[\s-]'), '').trim();
  if (normalized == null || normalized.isEmpty) {
    return driverEmptyValue;
  }

  final match = RegExp(
    r'^\+(\d{3})(\d{2})(\d{4})(\d{3})$',
  ).firstMatch(normalized);
  if (match == null) {
    return driverEmptyValue;
  }

  return '+${match.group(1)} ${match.group(2)} ****${match.group(4)}';
}

String _safeText(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? driverEmptyValue : trimmed;
}

String _safeCount(int? value) => value == null ? driverEmptyValue : '$value';

String _safeBool(bool? value) {
  return switch (value) {
    true => 'Yes',
    false => 'No',
    null => driverEmptyValue,
  };
}

String _sentenceCase(String value) {
  if (value.isEmpty) {
    return value;
  }
  return value[0].toUpperCase() + value.substring(1);
}

Map<String, Object?> _decodeMap(Object? json, String message) {
  if (json is Map<String, Object?>) {
    return json;
  }
  if (json is Map) {
    return json.map((key, value) => MapEntry('$key', value));
  }
  throw FormatException(message);
}

String? _firstString(Map<String, Object?> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    if (value is num || value is bool) {
      final stringValue = '$value'.trim();
      if (stringValue.isNotEmpty) {
        return stringValue;
      }
    }
  }
  return null;
}

int? _firstInt(Map<String, Object?> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value.trim());
    }
  }
  return null;
}

bool? _firstBool(Map<String, Object?> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is bool) {
      return value;
    }
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true' || normalized == 'yes' || normalized == '1') {
        return true;
      }
      if (normalized == 'false' || normalized == 'no' || normalized == '0') {
        return false;
      }
    }
  }
  return null;
}

class DriverDutySummaryPanel extends StatefulWidget {
  const DriverDutySummaryPanel({required this.gateway, super.key});

  final DriverDutyGateway? gateway;

  @override
  State<DriverDutySummaryPanel> createState() => _DriverDutySummaryPanelState();
}

class _DriverDutySummaryPanelState extends State<DriverDutySummaryPanel> {
  late Future<DriverDutySummary> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadDuty();
  }

  @override
  void didUpdateWidget(covariant DriverDutySummaryPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gateway != widget.gateway) {
      _future = _loadDuty();
    }
  }

  Future<DriverDutySummary> _loadDuty() {
    final gateway = widget.gateway;
    if (gateway == null) {
      return Future<DriverDutySummary>.value(DriverDutySummary.empty());
    }
    return gateway.fetchDuty();
  }

  void _refresh() {
    setState(() {
      _future = _loadDuty();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DriverDutySummary>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _DriverCard(
            key: Key('driver-duty-loading'),
            child: _DriverLoadingContent(text: 'Loading driver duty...'),
          );
        }

        final error = snapshot.error;
        if (error is DriverDutyApiException && error.isSessionExpired) {
          return _DriverErrorCard(
            key: const Key('driver-duty-session-expired'),
            title: driverSessionExpiredMessage,
            onRetry: _refresh,
          );
        }

        if (error != null) {
          return _DriverErrorCard(
            key: const Key('driver-duty-error'),
            title: 'Driver duty could not be loaded.',
            onRetry: _refresh,
          );
        }

        return _DriverDutySummaryCard(
          summary: snapshot.data ?? DriverDutySummary.empty(),
          onRefresh: _refresh,
        );
      },
    );
  }
}

class _DriverDutySummaryCard extends StatelessWidget {
  const _DriverDutySummaryCard({
    required this.summary,
    required this.onRefresh,
  });

  final DriverDutySummary summary;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return _DriverCard(
      key: const Key('driver-duty-loaded'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.verified_user_outlined,
                color: AsmColors.driverMintAction,
                size: 32,
              ),
              SizedBox(width: AsmSpacing.space12),
              Expanded(
                child: Text(
                  'Driver duty summary',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: AsmSpacing.space16),
          _DriverDetailRow('Driver', _safeText(summary.displayName)),
          _DriverDetailRow(
            'Driver reference',
            _safeText(summary.driverReference),
          ),
          _DriverDetailRow('Phone', maskDriverPhone(summary.phone)),
          _DriverDetailRow('Status', driverStatusLabel(summary.status)),
          _DriverDetailRow(
            'Vehicle',
            _safeText(summary.assignedVehicleReference),
          ),
          _DriverDetailRow(
            'Can receive assignments',
            _safeBool(summary.canReceiveAssignments),
          ),
          _DriverDetailRow('Active trips', _safeCount(summary.activeTripCount)),
          _DriverDetailRow(
            'Assigned trips',
            _safeCount(summary.assignedTripCount),
          ),
          const SizedBox(height: AsmSpacing.space12),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('driver-duty-refresh'),
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_outlined),
              label: const Text('Refresh'),
            ),
          ),
        ],
      ),
    );
  }
}

class DriverAssignedTripsScreen extends StatefulWidget {
  const DriverAssignedTripsScreen({required this.gateway, super.key});

  final DriverDutyGateway? gateway;

  @override
  State<DriverAssignedTripsScreen> createState() =>
      _DriverAssignedTripsScreenState();
}

class _DriverAssignedTripsScreenState extends State<DriverAssignedTripsScreen> {
  late Future<List<DriverAssignedTrip>> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadTrips();
  }

  @override
  void didUpdateWidget(covariant DriverAssignedTripsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gateway != widget.gateway) {
      _future = _loadTrips();
    }
  }

  Future<List<DriverAssignedTrip>> _loadTrips() {
    final gateway = widget.gateway;
    if (gateway == null) {
      return Future<List<DriverAssignedTrip>>.value(const []);
    }
    return gateway.fetchTrips();
  }

  void _refresh() {
    setState(() {
      _future = _loadTrips();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AsmScreenSurface(
      key: const Key('driver-assigned-trips-screen'),
      scrollable: true,
      padding: const EdgeInsets.fromLTRB(
        22,
        AsmSpacing.space20,
        22,
        AsmSpacing.space24,
      ),
      child: FutureBuilder<List<DriverAssignedTrip>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const _DriverCard(
              key: Key('driver-trips-loading'),
              child: _DriverLoadingContent(text: 'Loading assigned trips...'),
            );
          }

          final error = snapshot.error;
          if (error is DriverDutyApiException && error.isSessionExpired) {
            return _DriverErrorCard(
              key: const Key('driver-trips-session-expired'),
              title: driverSessionExpiredMessage,
              onRetry: _refresh,
            );
          }

          if (error != null) {
            return _DriverErrorCard(
              key: const Key('driver-trips-error'),
              title: 'Assigned trips could not be loaded.',
              onRetry: _refresh,
            );
          }

          final trips = snapshot.data ?? const <DriverAssignedTrip>[];
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'My Assigned Trips',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: AsmSpacing.space8),
              Text(
                'Read-only trip information from ALANTEH operations.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AsmColors.driverTextSecondary,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: AsmSpacing.space16),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const Key('driver-trips-refresh'),
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh_outlined),
                  label: const Text('Refresh'),
                ),
              ),
              const SizedBox(height: AsmSpacing.space8),
              if (trips.isEmpty)
                const AsmEmptyStatePanel(
                  key: Key('driver-trips-empty'),
                  compact: false,
                  icon: Icons.route_outlined,
                  iconColor: AsmColors.driverMintAction,
                  title: driverTripsEmptyTitle,
                  message: driverTripsEmptyMessage,
                )
              else
                for (final trip in trips) ...[
                  _DriverTripCard(
                    trip: trip,
                    onTap: () {
                      final gateway = widget.gateway;
                      if (gateway == null) {
                        return;
                      }

                      Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          builder: (_) => DriverTripDetailScreen(
                            gateway: gateway,
                            tripReference: trip.reference,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: AsmSpacing.space12),
                ],
            ],
          );
        },
      ),
    );
  }
}

class DriverTripDetailScreen extends StatefulWidget {
  const DriverTripDetailScreen({
    required this.gateway,
    required this.tripReference,
    super.key,
  });

  final DriverDutyGateway gateway;
  final String tripReference;

  @override
  State<DriverTripDetailScreen> createState() => _DriverTripDetailScreenState();
}

class _DriverTripDetailScreenState extends State<DriverTripDetailScreen> {
  late Future<DriverAssignedTrip> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.gateway.fetchTripDetail(widget.tripReference);
  }

  void _refresh() {
    setState(() {
      _future = widget.gateway.fetchTripDetail(widget.tripReference);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AsmColors.driverScaffold,
      appBar: AppBar(title: const Text('Assigned trip detail')),
      body: AsmScreenSurface(
        scrollable: true,
        padding: const EdgeInsets.fromLTRB(
          22,
          AsmSpacing.space20,
          22,
          AsmSpacing.space24,
        ),
        child: FutureBuilder<DriverAssignedTrip>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const _DriverCard(
                key: Key('driver-trip-detail-loading'),
                child: _DriverLoadingContent(text: 'Loading trip detail...'),
              );
            }

            final error = snapshot.error;
            if (error is DriverDutyApiException && error.isSessionExpired) {
              return _DriverErrorCard(
                key: const Key('driver-trip-detail-session-expired'),
                title: driverSessionExpiredMessage,
                onRetry: _refresh,
              );
            }

            if (error != null) {
              return _DriverErrorCard(
                key: const Key('driver-trip-detail-error'),
                title: 'Trip detail could not be loaded.',
                onRetry: _refresh,
              );
            }

            final trip = snapshot.data;
            if (trip == null) {
              return _DriverErrorCard(
                key: const Key('driver-trip-detail-error'),
                title: 'Trip detail could not be loaded.',
                onRetry: _refresh,
              );
            }

            return _DriverTripDetailCard(trip: trip, onRefresh: _refresh);
          },
        ),
      ),
    );
  }
}

class _DriverTripCard extends StatelessWidget {
  const _DriverTripCard({required this.trip, required this.onTap});

  final DriverAssignedTrip trip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _DriverCard(
      key: ValueKey<String>('driver-trip-${trip.reference}'),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.all(AsmSpacing.space4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                trip.reference,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: AsmSpacing.space8),
              _DriverDetailRow('Status', driverStatusLabel(trip.status)),
              _DriverDetailRow('Pickup', _safeText(trip.pickupLocation)),
              _DriverDetailRow('Destination', _safeText(trip.destination)),
              _DriverDetailRow(
                'Requested pickup',
                _safeText(trip.requestedPickupTime),
              ),
              _DriverDetailRow('Vehicle', _safeText(trip.vehicleReference)),
              _DriverDetailRow('Passengers', _safeCount(trip.passengerCount)),
              _DriverDetailRow('Message', _safeText(trip.controlCenterMessage)),
            ],
          ),
        ),
      ),
    );
  }
}

class _DriverTripDetailCard extends StatelessWidget {
  const _DriverTripDetailCard({required this.trip, required this.onRefresh});

  final DriverAssignedTrip trip;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return _DriverCard(
      key: const Key('driver-trip-detail-loaded'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Assigned trip detail',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: AsmSpacing.space16),
          _DriverDetailRow('Trip reference', trip.reference),
          _DriverDetailRow('Status', driverStatusLabel(trip.status)),
          _DriverDetailRow('Pickup', _safeText(trip.pickupLocation)),
          _DriverDetailRow('Destination', _safeText(trip.destination)),
          _DriverDetailRow(
            'Requested pickup',
            _safeText(trip.requestedPickupTime),
          ),
          _DriverDetailRow('Created', _safeText(trip.createdTime)),
          _DriverDetailRow('Updated', _safeText(trip.updatedTime)),
          _DriverDetailRow('Vehicle', _safeText(trip.vehicleReference)),
          _DriverDetailRow('Passengers', _safeCount(trip.passengerCount)),
          _DriverDetailRow('Message', _safeText(trip.controlCenterMessage)),
          const SizedBox(height: AsmSpacing.space12),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('driver-trip-detail-refresh'),
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_outlined),
              label: const Text('Refresh'),
            ),
          ),
        ],
      ),
    );
  }
}

class _DriverCard extends StatelessWidget {
  const _DriverCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AsmSpacing.space16),
      decoration: BoxDecoration(
        color: AsmColors.driverCard,
        borderRadius: BorderRadius.circular(AsmRadii.radius24),
        border: Border.all(color: AsmColors.driverLine),
      ),
      child: child,
    );
  }
}

class _DriverErrorCard extends StatelessWidget {
  const _DriverErrorCard({
    super.key,
    required this.title,
    required this.onRetry,
  });

  final String title;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return _DriverCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline,
            color: AsmColors.driverMintAction,
            size: 32,
          ),
          const SizedBox(height: AsmSpacing.space12),
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: AsmSpacing.space12),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_outlined),
            label: const Text('Refresh'),
          ),
        ],
      ),
    );
  }
}

class _DriverLoadingContent extends StatelessWidget {
  const _DriverLoadingContent({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox.square(
          dimension: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: AsmSpacing.space12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _DriverDetailRow extends StatelessWidget {
  const _DriverDetailRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AsmSpacing.space8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 128,
            child: Text(
              label,
              style: const TextStyle(
                color: AsmColors.driverTextSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: AsmSpacing.space8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w800, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }
}
