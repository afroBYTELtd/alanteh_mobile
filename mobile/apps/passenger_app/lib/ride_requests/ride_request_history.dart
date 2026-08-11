import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_auth/asm_auth.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../network/ghana_network_resilience.dart';
import '../payment_rating/passenger_payment_rating_contract.dart';
import '../payment_rating/passenger_payment_rating_page.dart';

abstract interface class PassengerRideRequestHistoryRepository {
  Future<List<PassengerRideRequestRecord>> fetchRequests();

  Future<PassengerRideRequestRecord> fetchRequest(String requestReference);
}

abstract interface class PassengerTripLifecycleRepository {
  Future<PassengerTripRecord> fetchTrip(String tripReference);
}

abstract interface class PassengerRideRequestHistoryApiGateway {
  Future<ApiResponse<T>> get<T>(String path, {JsonDecoder<T>? decoder});
}

class AsmPassengerRideRequestHistoryApiGateway
    implements PassengerRideRequestHistoryApiGateway {
  const AsmPassengerRideRequestHistoryApiGateway(this.client);

  final AsmApiClient client;

  @override
  Future<ApiResponse<T>> get<T>(String path, {JsonDecoder<T>? decoder}) {
    return client.get<T>(path, decoder: decoder);
  }
}

class PassengerRideRequestRecord {
  const PassengerRideRequestRecord({
    required this.requestReference,
    required this.status,
    required this.pickupLocation,
    required this.destination,
    required this.passengerCount,
    required this.createdAt,
    required this.updatedAt,
    required this.hasMobileReceipt,
    required this.tripCreated,
    this.requestedPickupTime,
    this.latestStaffState,
    this.controlCenterMessage,
    this.tripReference,
    this.specialRequest,
    this.fareDisplay,
    this.plateNumber,
    this.vehicleLatitude,
    this.vehicleLongitude,
  });

  final String requestReference;
  final String status;
  final String pickupLocation;
  final String destination;
  final int passengerCount;
  final DateTime? requestedPickupTime;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final bool hasMobileReceipt;
  final bool tripCreated;
  final String? latestStaffState;
  final String? controlCenterMessage;
  final String? tripReference;
  final String? specialRequest;
  final String? fareDisplay;
  final String? plateNumber;
  final double? vehicleLatitude;
  final double? vehicleLongitude;

  LatLng? get vehiclePosition {
    final latitude = vehicleLatitude;
    final longitude = vehicleLongitude;
    return latitude == null || longitude == null
        ? null
        : LatLng(latitude, longitude);
  }

  String? get normalizedTripReference {
    final value = tripReference?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  PassengerRideState get passengerState => PassengerRideState.fromStatus(
    status,
    latestStaffState: latestStaffState,
    message: controlCenterMessage,
  );

  PassengerRideRequestRecord withTrip(PassengerTripRecord trip) {
    return PassengerRideRequestRecord(
      requestReference: requestReference,
      status: trip.status,
      pickupLocation: pickupLocation,
      destination: destination,
      passengerCount: passengerCount,
      createdAt: createdAt,
      updatedAt: updatedAt,
      hasMobileReceipt: hasMobileReceipt,
      tripCreated: true,
      requestedPickupTime: requestedPickupTime,
      latestStaffState: latestStaffState,
      controlCenterMessage: trip.controlCenterMessage ?? controlCenterMessage,
      tripReference: trip.tripReference,
      specialRequest: specialRequest,
      fareDisplay: fareDisplay,
      plateNumber: trip.plateNumber ?? plateNumber,
      vehicleLatitude: trip.vehicleLatitude ?? vehicleLatitude,
      vehicleLongitude: trip.vehicleLongitude ?? vehicleLongitude,
    );
  }

  bool get isTerminal =>
      passengerState == PassengerRideState.arrived ||
      passengerState == PassengerRideState.rejected;

  String get safeMessage {
    final preferred = controlCenterMessage?.trim();
    if (preferred != null &&
        preferred.isNotEmpty &&
        !_containsInternalWording(preferred)) {
      return preferred;
    }
    return passengerState.defaultMessage;
  }

  factory PassengerRideRequestRecord.fromJson(Object? json) {
    if (json is! Map) {
      throw const FormatException(
        'Ride request history item was not a JSON object.',
      );
    }

    final map = json.map((key, value) => MapEntry('$key', value));

    return PassengerRideRequestRecord(
      requestReference: _requiredString(map, 'request_reference'),
      status: _requiredString(map, 'status'),
      pickupLocation: _requiredString(map, 'pickup_location'),
      destination: _requiredString(map, 'destination'),
      passengerCount: _requiredInt(map, 'passenger_count'),
      requestedPickupTime: _optionalDateTime(map, 'requested_pickup_time'),
      createdAt: _optionalDateTime(map, 'created_at'),
      updatedAt: _optionalDateTime(map, 'updated_at'),
      hasMobileReceipt: _optionalBool(map, 'has_mobile_receipt'),
      tripCreated: _optionalBool(map, 'trip_created'),
      latestStaffState: _optionalString(map, 'latest_staff_state'),
      controlCenterMessage: _optionalString(map, 'control_center_message'),
      tripReference: _optionalString(map, 'trip_reference'),
      specialRequest:
          _optionalString(map, 'assistance_note') ??
          _optionalString(map, 'special_request'),
      fareDisplay:
          _optionalStringOrNumber(map, 'fare_display') ??
          _optionalStringOrNumber(map, 'fare'),
      plateNumber:
          _optionalString(map, 'plate_number') ??
          _optionalString(map, 'vehicle_plate_number'),
      vehicleLatitude:
          _optionalDouble(map, 'vehicle_latitude') ??
          _optionalDouble(map, 'last_known_vehicle_latitude'),
      vehicleLongitude:
          _optionalDouble(map, 'vehicle_longitude') ??
          _optionalDouble(map, 'last_known_vehicle_longitude'),
    );
  }

  static List<PassengerRideRequestRecord> listFromJson(Object? json) {
    if (json is! Map) {
      throw const FormatException(
        'Ride request history response was not a JSON object.',
      );
    }

    final results = json['results'];
    if (results is! List) {
      throw const FormatException(
        'Ride request history response did not include results.',
      );
    }

    return results
        .map(PassengerRideRequestRecord.fromJson)
        .toList(growable: false);
  }

  static String _requiredString(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('Ride request history field $key is missing.');
    }
    return value.trim();
  }

  static String? _optionalString(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value is! String) {
      return null;
    }

    final normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }

  static String? _optionalStringOrNumber(Map<String, Object?> map, String key) {
    final value = map[key];

    if (value is String) {
      final normalized = value.trim();
      return normalized.isEmpty ? null : normalized;
    }

    if (value is num && value.isFinite) {
      return value.toString();
    }

    return null;
  }

  static int _requiredInt(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    throw FormatException('Ride request history field $key is missing.');
  }

  static double? _optionalDouble(Map<String, Object?> map, String key) {
    final value = map[key];
    return value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '');
  }

  static bool _optionalBool(Map<String, Object?> map, String key) {
    final value = map[key];
    return value is bool ? value : false;
  }

  static DateTime? _optionalDateTime(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value is! String || value.trim().isEmpty) {
      return null;
    }
    return DateTime.tryParse(value.trim());
  }
}

final class PassengerTripRecord {
  const PassengerTripRecord({
    required this.tripReference,
    required this.status,
    this.controlCenterMessage,
    this.plateNumber,
    this.vehicleLatitude,
    this.vehicleLongitude,
  });

  final String tripReference;
  final String status;
  final String? controlCenterMessage;
  final String? plateNumber;
  final double? vehicleLatitude;
  final double? vehicleLongitude;

  String get normalizedStatus => status.trim().toLowerCase();

  bool get isTerminal =>
      normalizedStatus == 'completed_pending_review' ||
      normalizedStatus == 'completed_confirmed';

  PassengerRideState get passengerState =>
      PassengerRideState.fromStatus(status, message: controlCenterMessage);

  factory PassengerTripRecord.fromJson(
    Object? json, {
    required String expectedTripReference,
  }) {
    if (json is! Map) {
      throw const FormatException(
        'Trip detail response was not a JSON object.',
      );
    }

    final map = json.map((key, value) => MapEntry('$key', value));
    final expectedReference = expectedTripReference.trim();
    if (expectedReference.isEmpty) {
      throw const FormatException('Trip reference is missing.');
    }

    final returnedReference = _optionalString(map, 'trip_reference');
    if (returnedReference != null && returnedReference != expectedReference) {
      throw const FormatException('Trip reference did not match the request.');
    }

    return PassengerTripRecord(
      tripReference: returnedReference ?? expectedReference,
      status: _requiredString(map, 'trip_status'),
      controlCenterMessage: _optionalString(map, 'control_center_message'),
      plateNumber:
          _optionalString(map, 'plate_number') ??
          _optionalString(map, 'vehicle_plate_number'),
      vehicleLatitude:
          _optionalDouble(map, 'vehicle_latitude') ??
          _optionalDouble(map, 'last_known_vehicle_latitude'),
      vehicleLongitude:
          _optionalDouble(map, 'vehicle_longitude') ??
          _optionalDouble(map, 'last_known_vehicle_longitude'),
    );
  }

  static String _requiredString(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('Trip detail field $key is missing.');
    }
    return value.trim();
  }

  static String? _optionalString(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value is! String || value.trim().isEmpty) {
      return null;
    }
    return value.trim();
  }

  static double? _optionalDouble(Map<String, Object?> map, String key) {
    final value = map[key];
    return value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '');
  }
}

enum PassengerRideState {
  looking,
  driverAssigned,
  vehicleEnRoute,
  driverArrived,
  inProgress,
  arrived,
  reassigned,
  rejected;

  factory PassengerRideState.fromStatus(
    String status, {
    String? latestStaffState,
    String? message,
  }) {
    final normalizedStatus = status.trim().toLowerCase();
    final canonicalState = switch (normalizedStatus) {
      'assigned' => PassengerRideState.driverAssigned,
      'driver_offer_sent' => PassengerRideState.looking,
      'driver_accepted' => PassengerRideState.vehicleEnRoute,
      'arrived_at_pickup' => PassengerRideState.driverArrived,
      'in_progress' => PassengerRideState.inProgress,
      'completed_pending_review' ||
      'completed_confirmed' => PassengerRideState.arrived,
      _ => null,
    };
    if (canonicalState != null) {
      return canonicalState;
    }

    final value = '$status ${latestStaffState ?? ''} ${message ?? ''}'
        .toLowerCase();
    if (value.contains('reassign')) return PassengerRideState.reassigned;
    if (value.contains('reject') ||
        value.contains('declin') ||
        value.contains('no driver')) {
      return PassengerRideState.rejected;
    }
    if (value.contains('complete') ||
        value.contains('arrived at destination') ||
        value.contains('trip ended')) {
      return PassengerRideState.arrived;
    }
    if (value.contains('in progress') ||
        value.contains('on trip') ||
        value.contains('started')) {
      return PassengerRideState.inProgress;
    }
    if (value.contains('driver arrived') ||
        value.contains('outside') ||
        value.contains('at pickup')) {
      return PassengerRideState.driverArrived;
    }
    if (value.contains('en route') ||
        value.contains('on the way') ||
        value.contains('dispatched')) {
      return PassengerRideState.vehicleEnRoute;
    }
    if (value.contains('assign') || value.contains('confirm')) {
      return PassengerRideState.driverAssigned;
    }
    return PassengerRideState.looking;
  }

  String get defaultMessage => switch (this) {
    PassengerRideState.looking =>
      'We are reviewing your request and matching a nearby vehicle.',
    PassengerRideState.driverAssigned =>
      'A driver has been assigned to your ride.',
    PassengerRideState.vehicleEnRoute =>
      'Your vehicle is travelling to the pickup point.',
    PassengerRideState.driverArrived =>
      'Please meet your driver at the pickup point.',
    PassengerRideState.inProgress => 'Enjoy your quiet solar-electric ride.',
    PassengerRideState.arrived => 'Thank you for riding with ALANTEH.',
    PassengerRideState.reassigned => 'A new vehicle is now handling your ride.',
    PassengerRideState.rejected =>
      'Please try booking again or contact support.',
  };
}

bool _containsInternalWording(String value) {
  final lower = value.toLowerCase();
  return lower.contains('control center') ||
      lower.contains('mobile receipt confirmed') ||
      lower.contains('passenger app request received') ||
      lower.contains('authorization') ||
      lower.contains('access token') ||
      lower.contains('refresh token');
}

class ApiPassengerRideRequestHistoryRepository
    implements
        PassengerRideRequestHistoryRepository,
        PassengerTripLifecycleRepository {
  const ApiPassengerRideRequestHistoryRepository(
    this.apiGateway, {
    required this.tokenStore,
    this.authService,
    this.connectionConfigured = true,
  });

  factory ApiPassengerRideRequestHistoryRepository.withDefaultClient({
    AuthTokenStore? tokenStore,
    String? baseUrl,
  }) {
    final store = tokenStore ?? SecureAuthTokenStore();
    final connectionConfigured = AsmApiBaseUrl.isUsable(baseUrl);
    final resolvedBaseUrl = connectionConfigured
        ? baseUrl!.trim()
        : 'http://127.0.0.1:8000';

    return ApiPassengerRideRequestHistoryRepository(
      AsmPassengerRideRequestHistoryApiGateway(
        GhanaResilientApiClient(
          baseUrl: resolvedBaseUrl,
          tokenProvider: _HistoryTokenProvider(store),
        ),
      ),
      tokenStore: store,
      authService: connectionConfigured
          ? AuthService.withApiClient(
              client: GhanaResilientApiClient(baseUrl: resolvedBaseUrl),
              tokenStore: store,
            )
          : null,
      connectionConfigured: connectionConfigured,
    );
  }

  static const listPath = '/api/rides/requests/';
  static const tripPath = '/api/trips/';

  final PassengerRideRequestHistoryApiGateway apiGateway;
  final AuthTokenStore tokenStore;
  final AuthService? authService;
  final bool connectionConfigured;

  @override
  Future<List<PassengerRideRequestRecord>> fetchRequests() {
    return _get<List<PassengerRideRequestRecord>>(
      listPath,
      PassengerRideRequestRecord.listFromJson,
    );
  }

  @override
  Future<PassengerRideRequestRecord> fetchRequest(String requestReference) {
    final normalized = requestReference.trim();
    if (normalized.isEmpty) {
      throw const PassengerRideRequestHistoryException.unknown();
    }

    return _get<PassengerRideRequestRecord>(
      '$listPath${Uri.encodeComponent(normalized)}/',
      PassengerRideRequestRecord.fromJson,
    );
  }

  @override
  Future<PassengerTripRecord> fetchTrip(String tripReference) {
    final normalized = tripReference.trim();
    if (normalized.isEmpty) {
      throw const PassengerRideRequestHistoryException.unknown();
    }

    return _get<PassengerTripRecord>(
      '$tripPath${Uri.encodeComponent(normalized)}/',
      (json) =>
          PassengerTripRecord.fromJson(json, expectedTripReference: normalized),
    );
  }

  Future<T> _get<T>(String path, JsonDecoder<T> decoder) async {
    final accessToken = (await tokenStore.readAccessToken())?.trim();

    if (accessToken == null || accessToken.isEmpty) {
      throw const PassengerRideRequestHistoryException.sessionExpired();
    }

    if (!connectionConfigured) {
      throw const PassengerRideRequestHistoryException.connectionNotConfigured();
    }

    final response = await apiGateway.get<T>(path, decoder: decoder);

    if (response.isSuccess && response.data != null) {
      return response.data as T;
    }

    if (response.statusCode == 401) {
      final refreshed = await _refreshAccessToken();
      if (!refreshed) {
        throw const PassengerRideRequestHistoryException.sessionExpired();
      }

      final retryResponse = await apiGateway.get<T>(path, decoder: decoder);

      if (retryResponse.isSuccess && retryResponse.data != null) {
        return retryResponse.data as T;
      }

      if (retryResponse.statusCode == 401) {
        await tokenStore.clearTokens();
      }

      throw PassengerRideRequestHistoryException.fromResponse(retryResponse);
    }

    throw PassengerRideRequestHistoryException.fromResponse(response);
  }

  Future<bool> _refreshAccessToken() async {
    final refreshToken = (await tokenStore.readRefreshToken())?.trim();

    final service = authService;

    if (refreshToken == null || refreshToken.isEmpty || service == null) {
      await tokenStore.clearTokens();
      return false;
    }

    try {
      final state = await service.refresh();
      if (state.isAuthenticated) {
        return true;
      }
    } on Object {
      // The user-facing state below remains intentionally generic.
    }

    await tokenStore.clearTokens();
    return false;
  }
}

class UnavailablePassengerRideRequestHistoryRepository
    implements PassengerRideRequestHistoryRepository {
  const UnavailablePassengerRideRequestHistoryRepository();

  @override
  Future<List<PassengerRideRequestRecord>> fetchRequests() {
    return Future<List<PassengerRideRequestRecord>>.error(
      const PassengerRideRequestHistoryException.connectionNotConfigured(),
    );
  }

  @override
  Future<PassengerRideRequestRecord> fetchRequest(String requestReference) {
    return Future<PassengerRideRequestRecord>.error(
      const PassengerRideRequestHistoryException.connectionNotConfigured(),
    );
  }
}

class EmptyPassengerRideRequestHistoryRepository
    implements PassengerRideRequestHistoryRepository {
  const EmptyPassengerRideRequestHistoryRepository();

  @override
  Future<List<PassengerRideRequestRecord>> fetchRequests() async {
    return const <PassengerRideRequestRecord>[];
  }

  @override
  Future<PassengerRideRequestRecord> fetchRequest(String requestReference) {
    return Future<PassengerRideRequestRecord>.error(
      const PassengerRideRequestHistoryException.notFound(),
    );
  }
}

class PassengerRideRequestHistoryException implements Exception {
  const PassengerRideRequestHistoryException(
    this.message, {
    this.requiresSignIn = false,
  });

  const PassengerRideRequestHistoryException.sessionExpired()
    : message = sessionExpiredMessage,
      requiresSignIn = true;

  const PassengerRideRequestHistoryException.connectionNotConfigured()
    : message = AsmApiClient.connectionNotConfiguredMessage,
      requiresSignIn = false;

  const PassengerRideRequestHistoryException.network()
    : message = networkMessage,
      requiresSignIn = false;

  const PassengerRideRequestHistoryException.server()
    : message = serverMessage,
      requiresSignIn = false;

  const PassengerRideRequestHistoryException.notFound()
    : message = notFoundMessage,
      requiresSignIn = false;

  const PassengerRideRequestHistoryException.unknown()
    : message = unknownMessage,
      requiresSignIn = false;

  static const sessionExpiredMessage =
      'Your session has expired. Please sign in again.';
  static const networkMessage =
      'Cannot reach the server. Check your connection and try again.';
  static const serverMessage =
      'Service is temporarily unavailable. Please try again later.';
  static const notFoundMessage = 'This ride request could not be found.';
  static const passengerRequiredMessage = 'Passenger account required.';
  static const unknownMessage = 'Something went wrong. Please try again.';

  final String message;
  final bool requiresSignIn;

  static PassengerRideRequestHistoryException fromResponse<T>(
    ApiResponse<T> response,
  ) {
    final error = response.error;
    final statusCode = response.statusCode;

    if (statusCode == 401) {
      return const PassengerRideRequestHistoryException.sessionExpired();
    }

    if (statusCode == 403) {
      return const PassengerRideRequestHistoryException(
        passengerRequiredMessage,
      );
    }

    if (statusCode == 404) {
      return const PassengerRideRequestHistoryException.notFound();
    }

    if (error?.type == AsmApiExceptionType.network ||
        error?.type == AsmApiExceptionType.timeout) {
      return const PassengerRideRequestHistoryException.network();
    }

    if (statusCode == 503 || error?.type == AsmApiExceptionType.server) {
      return const PassengerRideRequestHistoryException.server();
    }

    return const PassengerRideRequestHistoryException.unknown();
  }

  @override
  String toString() => message;
}

enum _TripsFilter { all, active, completed }

bool _isActiveTripStatus(String status) {
  return switch (status.trim().toLowerCase()) {
    'requested' || 'under_review' || 'accepted_for_trip' => true,
    _ => false,
  };
}

bool _isCompletedTripStatus(String status) {
  return switch (status.trim().toLowerCase()) {
    'completed_confirmed' || 'completed_pending_review' => true,
    _ => false,
  };
}

class PassengerRideRequestHistoryPage extends StatefulWidget {
  const PassengerRideRequestHistoryPage({
    required this.repository,
    this.onSignInRequired,
    this.onBookRide,
    this.onBookAgain,
    this.onReturn,
    this.onOpenActiveTracking,
    this.paymentRatingRepository,
    super.key,
  });

  final PassengerRideRequestHistoryRepository repository;
  final VoidCallback? onSignInRequired;
  final VoidCallback? onBookRide;
  final ValueChanged<PassengerRideRequestRecord>? onBookAgain;
  final ValueChanged<PassengerRideRequestRecord>? onReturn;
  final Future<void> Function(PassengerRideRequestRecord)? onOpenActiveTracking;
  final PassengerPaymentRatingRepository? paymentRatingRepository;

  @override
  State<PassengerRideRequestHistoryPage> createState() =>
      _PassengerRideRequestHistoryPageState();
}

class _PassengerRideRequestHistoryPageState
    extends State<PassengerRideRequestHistoryPage> {
  bool _loading = true;
  List<PassengerRideRequestRecord> _records =
      const <PassengerRideRequestRecord>[];
  PassengerRideRequestHistoryException? _error;
  _TripsFilter _selectedFilter = _TripsFilter.all;

  List<PassengerRideRequestRecord> get _visibleRecords {
    return switch (_selectedFilter) {
      _TripsFilter.all => _records,
      _TripsFilter.active =>
        _records
            .where((record) => _isActiveTripStatus(record.status))
            .toList(growable: false),
      _TripsFilter.completed =>
        _records
            .where((record) => _isCompletedTripStatus(record.status))
            .toList(growable: false),
    };
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool showLoading = true}) async {
    if (showLoading && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final loadedRecords = List<PassengerRideRequestRecord>.of(
        await widget.repository.fetchRequests(),
      );
      final records = await _enrichConvertedRecords(loadedRecords);
      records.sort((left, right) {
        final leftCreatedAt = left.createdAt;
        final rightCreatedAt = right.createdAt;

        if (leftCreatedAt == null && rightCreatedAt == null) {
          return 0;
        }
        if (leftCreatedAt == null) {
          return 1;
        }
        if (rightCreatedAt == null) {
          return -1;
        }

        return rightCreatedAt.compareTo(leftCreatedAt);
      });

      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _records = records;
        _error = null;
      });
    } on PassengerRideRequestHistoryException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _records = const <PassengerRideRequestRecord>[];
        _error = error;
      });
    } on Object {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _records = const <PassengerRideRequestRecord>[];
        _error = const PassengerRideRequestHistoryException.unknown();
      });
    }
  }

  Future<List<PassengerRideRequestRecord>> _enrichConvertedRecords(
    List<PassengerRideRequestRecord> records,
  ) async {
    final repository = widget.repository;
    if (repository is! PassengerTripLifecycleRepository) {
      return records;
    }
    final tripRepository = repository as PassengerTripLifecycleRepository;

    final uniqueTripReferences = <String>{};

    for (final record in records) {
      if (record.status.trim().toLowerCase() != 'converted') {
        continue;
      }

      final tripReference = record.normalizedTripReference;
      if (tripReference != null) {
        uniqueTripReferences.add(tripReference);
      }
    }

    if (uniqueTripReferences.isEmpty) {
      return records;
    }

    final tripsByReference = <String, PassengerTripRecord>{};

    for (final tripReference in uniqueTripReferences) {
      try {
        tripsByReference[tripReference] = await tripRepository.fetchTrip(
          tripReference,
        );
      } on Object {
        // History enrichment is deliberately fail-soft. The original
        // converted Ride Request card remains available to the passenger.
      }
    }

    return records
        .map((record) {
          if (record.status.trim().toLowerCase() != 'converted') {
            return record;
          }

          final tripReference = record.normalizedTripReference;
          final trip = tripReference == null
              ? null
              : tripsByReference[tripReference];

          return trip == null ? record : record.withTrip(trip);
        })
        .toList(growable: false);
  }

  Future<void> _openDetail(PassengerRideRequestRecord record) {
    final openActiveTracking = widget.onOpenActiveTracking;
    final isConvertedRequest =
        record.status.trim().toLowerCase() == 'converted';
    final isActiveLinkedTrip =
        record.normalizedTripReference != null && !record.isTerminal;

    if ((isConvertedRequest || isActiveLinkedTrip) &&
        openActiveTracking != null) {
      return openActiveTracking(record);
    }

    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => PassengerRideRequestDetailPage(
          repository: widget.repository,
          requestReference: record.requestReference,
          paymentRatingRepository: widget.paymentRatingRepository,
          onSignInRequired: widget.onSignInRequired,
        ),
      ),
    );
  }

  void _selectFilter(_TripsFilter filter) {
    if (_selectedFilter == filter) {
      return;
    }
    setState(() => _selectedFilter = filter);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trips'),
        actions: [
          IconButton(
            key: const Key('ride-request-history-refresh'),
            onPressed: _loading ? null : () => _load(),
            tooltip: 'Refresh requests',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          _TripsFilterTabs(
            selectedFilter: _selectedFilter,
            onSelected: _selectFilter,
          ),
          Expanded(child: _buildBody(context)),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(
        key: Key('ride-request-history-loading'),
        child: CircularProgressIndicator(),
      );
    }

    final error = _error;
    if (error != null) {
      return _HistoryErrorState(
        error: error,
        onRetry: _load,
        onSignInRequired: widget.onSignInRequired,
      );
    }

    final visibleRecords = _visibleRecords;

    if (visibleRecords.isEmpty) {
      return _TripsEmptyState(
        filter: _selectedFilter,
        onBookRide: widget.onBookRide,
        onRefresh: () => _load(showLoading: false),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _load(showLoading: false),
      child: ListView.separated(
        key: const Key('ride-request-history-loaded'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AsmSpacing.space16),
        itemCount: visibleRecords.length,
        separatorBuilder: (_, _) => const SizedBox(height: AsmSpacing.space12),
        itemBuilder: (context, index) {
          final record = visibleRecords[index];

          return _RideRequestCard(
            record: record,
            onTap: () => _openDetail(record),
            onBookAgain: widget.onBookAgain,
            onReturn: widget.onReturn,
          );
        },
      ),
    );
  }
}

class _TripsFilterTabs extends StatelessWidget {
  const _TripsFilterTabs({
    required this.selectedFilter,
    required this.onSelected,
  });

  final _TripsFilter selectedFilter;
  final ValueChanged<_TripsFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AsmSpacing.space16,
        AsmSpacing.space8,
        AsmSpacing.space16,
        AsmSpacing.space12,
      ),
      child: Row(
        children: [
          _button(_TripsFilter.all, 'All'),
          const SizedBox(width: AsmSpacing.space8),
          _button(_TripsFilter.active, 'Active'),
          const SizedBox(width: AsmSpacing.space8),
          _button(_TripsFilter.completed, 'Completed'),
        ],
      ),
    );
  }

  Widget _button(_TripsFilter filter, String label) {
    final selected = selectedFilter == filter;

    return Expanded(
      child: selected
          ? FilledButton(
              key: Key('trip-filter-${filter.name}'),
              onPressed: () => onSelected(filter),
              child: Text(label),
            )
          : OutlinedButton(
              key: Key('trip-filter-${filter.name}'),
              onPressed: () => onSelected(filter),
              child: Text(label),
            ),
    );
  }
}

class _TripsEmptyState extends StatelessWidget {
  const _TripsEmptyState({
    required this.filter,
    required this.onBookRide,
    required this.onRefresh,
  });

  final _TripsFilter filter;
  final VoidCallback? onBookRide;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final (message, showBookButton) = switch (filter) {
      _TripsFilter.all => ('No trips yet. Book your first ALANTEH ride.', true),
      _TripsFilter.active => ('No active rides right now.', true),
      _TripsFilter.completed => ('No completed trips yet.', false),
    };

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        key: Key(
          filter == _TripsFilter.all
              ? 'ride-request-history-empty'
              : 'ride-request-history-empty-${filter.name}',
        ),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AsmSpacing.space24),
        children: [
          const SizedBox(height: 120),
          Icon(
            Icons.electric_car_outlined,
            size: 56,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: AsmSpacing.space16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          if (showBookButton && onBookRide != null) ...[
            const SizedBox(height: AsmSpacing.space24),
            Center(
              child: FilledButton.icon(
                key: const Key('empty-history-book-ride'),
                onPressed: onBookRide,
                icon: const Icon(Icons.add_road_outlined),
                label: const Text('Book a ride'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RideRequestCard extends StatelessWidget {
  const _RideRequestCard({
    required this.record,
    required this.onTap,
    this.onBookAgain,
    this.onReturn,
  });

  final PassengerRideRequestRecord record;
  final VoidCallback onTap;
  final ValueChanged<PassengerRideRequestRecord>? onBookAgain;
  final ValueChanged<PassengerRideRequestRecord>? onReturn;

  @override
  Widget build(BuildContext context) {
    final completed = _isCompletedTripStatus(record.status);
    final fare = completed ? _formatTripFare(record.fareDisplay) : null;

    return Card(
      key: ValueKey<String>('ride-request-${record.requestReference}'),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AsmSpacing.space16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(AsmRadii.radius16),
                    ),
                    child: const Icon(Icons.electric_car_outlined),
                  ),
                  const SizedBox(width: AsmSpacing.space12),
                  Expanded(
                    child: Wrap(
                      spacing: AsmSpacing.space8,
                      runSpacing: AsmSpacing.space4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text(
                          'Electric Ride',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        _StatusChip(status: record.status),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AsmSpacing.space16),
              _TripRouteLine(label: 'From', value: record.pickupLocation),
              const SizedBox(height: AsmSpacing.space8),
              _TripRouteLine(label: 'To', value: record.destination),
              const SizedBox(height: AsmSpacing.space8),
              Text(
                '${record.pickupLocation} → ${record.destination}',
                key: const Key('trip-card-route-title'),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AsmSpacing.space12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _formatDateTime(record.createdAt),
                      key: ValueKey<String>(
                        'trip-card-date-${record.requestReference}',
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  if (fare != null) ...[
                    const SizedBox(width: AsmSpacing.space12),
                    Text(
                      fare,
                      key: const Key('history-card-fare'),
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: AsmSpacing.space8),
              Text(
                _historyStatusMessage(record),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AsmSpacing.space12),
              Wrap(
                spacing: AsmSpacing.space8,
                runSpacing: AsmSpacing.space4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilledButton(
                    key: const Key('history-card-book-again'),
                    onPressed: onBookAgain == null
                        ? null
                        : () => onBookAgain!(record),
                    child: const Text('Book again'),
                  ),
                  if (completed && onReturn != null)
                    OutlinedButton(
                      key: const Key('history-card-return'),
                      onPressed: () => onReturn!(record),
                      child: const Text('Return'),
                    ),
                  TextButton.icon(
                    key: const Key('history-card-view-details'),
                    onPressed: onTap,
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('View details'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TripRouteLine extends StatelessWidget {
  const _TripRouteLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 48,
          child: Text(
            '$label:',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class PassengerRideRequestDetailPage extends StatefulWidget {
  const PassengerRideRequestDetailPage({
    required this.repository,
    required this.requestReference,
    this.onSignInRequired,
    this.paymentRatingRepository,
    super.key,
  });

  final PassengerRideRequestHistoryRepository repository;
  final String requestReference;
  final VoidCallback? onSignInRequired;
  final PassengerPaymentRatingRepository? paymentRatingRepository;

  @override
  State<PassengerRideRequestDetailPage> createState() =>
      _PassengerRideRequestDetailPageState();
}

class _PassengerRideRequestDetailPageState
    extends State<PassengerRideRequestDetailPage> {
  bool _loading = true;
  PassengerRideRequestRecord? _record;
  PassengerRideRequestHistoryException? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final record = await widget.repository.fetchRequest(
        widget.requestReference,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _record = record;
        _error = null;
      });
    } on PassengerRideRequestHistoryException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _record = null;
        _error = error;
      });
    } on Object {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _record = null;
        _error = const PassengerRideRequestHistoryException.unknown();
      });
    }
  }

  Future<void> _openPaymentRating() {
    final repository = widget.paymentRatingRepository;

    if (repository == null) {
      return Future<void>.value();
    }

    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => PassengerPaymentRatingPage(
          repository: repository,
          requestReference: widget.requestReference,
          pickupDescription: _record?.pickupLocation,
          destinationDescription: _record?.destination,
          tripCompletedAt: _record?.updatedAt,
          onSignInRequired: widget.onSignInRequired,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Trip details')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        key: Key('ride-request-detail-loading'),
        child: CircularProgressIndicator(),
      );
    }

    final error = _error;
    if (error != null) {
      return _HistoryErrorState(
        error: error,
        onRetry: _load,
        onSignInRequired: widget.onSignInRequired,
      );
    }

    final record = _record;
    if (record == null) {
      return const SizedBox.shrink();
    }

    final controlCenterMessage = _safeStatusMessage(
      record.status,
      preferredMessage: record.controlCenterMessage,
    );

    return ListView(
      key: const Key('ride-request-detail-loaded'),
      padding: const EdgeInsets.all(AsmSpacing.space16),
      children: [
        _StatusChip(status: record.status),
        const SizedBox(height: AsmSpacing.space16),
        _DetailRow(label: 'From', value: record.pickupLocation),
        _DetailRow(label: 'To', value: record.destination),
        _DetailRow(label: 'Status', value: record.safeMessage),
        _DetailRow(label: 'Date', value: _formatDateTime(record.createdAt)),
        _DetailRow(label: 'Passengers', value: '${record.passengerCount}'),
        if (record.specialRequest != null)
          _DetailRow(label: 'Special request', value: record.specialRequest!),
        if (record.fareDisplay != null)
          _DetailRow(label: 'Fare', value: record.fareDisplay!),
        if (record.passengerState == PassengerRideState.arrived &&
            widget.paymentRatingRepository != null) ...[
          const SizedBox(height: AsmSpacing.space8),
          FilledButton.icon(
            key: const Key('open-payment-rating-from-history'),
            onPressed: _openPaymentRating,
            icon: const Icon(Icons.payments_outlined),
            label: const Text('Payment and rating'),
          ),
        ],
        const SizedBox(height: AsmSpacing.space8),
        Card(
          key: const Key('ride-request-control-center-message'),
          child: Padding(
            padding: const EdgeInsets.all(AsmSpacing.space16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ALANTEH update',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: AsmSpacing.space8),
                Text(controlCenterMessage),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final normalized = status.trim().toLowerCase();

    final (background, foreground) = switch (normalized) {
      'completed_confirmed' || 'completed_pending_review' => (
        const Color(0xFFE2F0E7),
        AsmColors.brandDeepGreen,
      ),
      'accepted_for_trip' ||
      'accepted' ||
      'approved' ||
      'assigned' ||
      'driver_offer_sent' ||
      'driver_accepted' ||
      'arrived_at_pickup' ||
      'in_progress' => (const Color(0xFFFFE7B0), const Color(0xFF725000)),
      _ => (const Color(0xFFE9ECEF), const Color(0xFF4B5563)),
    };

    return Chip(
      key: ValueKey<String>('ride-request-status-$normalized'),
      backgroundColor: background,
      side: BorderSide.none,
      visualDensity: VisualDensity.compact,
      label: Text(
        _statusLabel(status),
        style: TextStyle(color: foreground, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AsmSpacing.space12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: AsmSpacing.space4),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _HistoryErrorState extends StatelessWidget {
  const _HistoryErrorState({
    required this.error,
    required this.onRetry,
    this.onSignInRequired,
  });

  final PassengerRideRequestHistoryException error;
  final Future<void> Function() onRetry;
  final VoidCallback? onSignInRequired;

  @override
  Widget build(BuildContext context) {
    return Center(
      key: Key(
        error.requiresSignIn
            ? 'ride-request-history-session-expired'
            : 'ride-request-history-error',
      ),
      child: Padding(
        padding: const EdgeInsets.all(AsmSpacing.space24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              error.requiresSignIn
                  ? Icons.lock_clock_outlined
                  : Icons.error_outline,
              size: 52,
            ),
            const SizedBox(height: AsmSpacing.space16),
            Text(
              error.requiresSignIn
                  ? 'Session expired'
                  : 'Could not load requests',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: AsmSpacing.space8),
            Text(error.message, textAlign: TextAlign.center),
            const SizedBox(height: AsmSpacing.space16),
            if (error.requiresSignIn && onSignInRequired != null)
              FilledButton(
                key: const Key('ride-request-history-sign-in-again'),
                onPressed: onSignInRequired,
                child: const Text('Sign in again'),
              )
            else
              FilledButton.icon(
                key: const Key('ride-request-history-retry'),
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
          ],
        ),
      ),
    );
  }
}

String _historyStatusMessage(PassengerRideRequestRecord record) {
  if (_isCompletedTripStatus(record.status)) {
    return PassengerRideState.arrived.defaultMessage;
  }

  return _safeStatusMessage(
    record.status,
    preferredMessage: record.latestStaffState,
  );
}

String _safeStatusMessage(String status, {String? preferredMessage}) {
  final safePreferredMessage = preferredMessage?.trim();
  if (safePreferredMessage != null && safePreferredMessage.isNotEmpty) {
    final lower = safePreferredMessage.toLowerCase();
    final mentionsInternalOps = RegExp(
      r'control\s+center',
      caseSensitive: false,
    ).hasMatch(safePreferredMessage);
    final isPassengerAppReceipt = lower.contains(
      'passenger app request received',
    );
    final isMobileReceiptMessage = lower.contains('mobile receipt confirmed');

    if (isPassengerAppReceipt || isMobileReceiptMessage) {
      return 'Request received.';
    }

    if (mentionsInternalOps) {
      return safePreferredMessage.replaceAll(
        RegExp(r'control\s+center', caseSensitive: false),
        'ALANTEH',
      );
    }

    return safePreferredMessage;
  }

  return switch (status.trim().toLowerCase()) {
    'requested' => 'Request received.',
    'under_review' => 'Being reviewed.',
    'accepted' ||
    'approved' ||
    'accepted_for_trip' => 'Accepted for trip preparation.',
    'completed_confirmed' ||
    'completed_pending_review' => PassengerRideState.arrived.defaultMessage,
    'rejected' || 'declined' => 'Could not be accepted.',
    'cancelled' || 'canceled' => 'Cancelled.',
    'trip_created' => 'Trip record created.',
    _ => 'Request update available.',
  };
}

String _statusLabel(String status) {
  return switch (status.trim().toLowerCase()) {
    'requested' => 'Received by ALANTEH',
    'under_review' => 'Being reviewed',
    'accepted' || 'approved' || 'accepted_for_trip' => 'Accepted',
    'assigned' ||
    'driver_offer_sent' ||
    'driver_accepted' ||
    'arrived_at_pickup' ||
    'in_progress' => 'Active',
    'rejected' || 'declined' => 'Could not be accepted',
    'cancelled' || 'canceled' => 'Cancelled',
    'trip_created' => 'Trip record created',
    'completed_confirmed' || 'completed_pending_review' => 'Completed',
    _ => 'Request update',
  };
}

String _formatDateTime(DateTime? value) {
  if (value == null) {
    return 'Not available';
  }

  final local = value.toLocal();
  const months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  String twoDigits(int number) => number.toString().padLeft(2, '0');

  return '${local.day} ${months[local.month - 1]} ${local.year} '
      'at ${twoDigits(local.hour)}:${twoDigits(local.minute)}';
}

String? _formatTripFare(String? rawFare) {
  final raw = rawFare?.trim();
  if (raw == null || raw.isEmpty) {
    return null;
  }

  var normalized = raw.replaceAll(',', '');
  normalized = normalized.replaceFirst(
    RegExp(r'^(GH₵|GH¢|GHS)\s*', caseSensitive: false),
    '',
  );

  final value = double.tryParse(normalized.trim());
  if (value == null || !value.isFinite || value <= 0) {
    return null;
  }

  return 'GH₵${value.toStringAsFixed(2)}';
}

class _HistoryTokenProvider implements TokenProvider {
  const _HistoryTokenProvider(this.tokenStore);

  final AuthTokenStore tokenStore;

  @override
  Future<String?> getAccessToken() {
    return tokenStore.readAccessToken();
  }
}
