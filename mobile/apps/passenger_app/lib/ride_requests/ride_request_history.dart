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
    this.fareAmount,
    this.plateNumber,
    this.pickupVerificationCode,
    this.vehicleLatitude,
    this.vehicleLongitude,
    this.driverName,
    this.vehicleType,
    this.vehicleColour,
    this.driverDistanceKm,
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
  // The Trip's live fare_amount (distinct from fareDisplay, which is a
  // separately-formatted historical value shown for completed trips).
  // Null until the trip reaches FARE_CONFIRMED - used to decide whether
  // "Concerned about the fare" belongs in the cancellation reason list.
  final String? fareAmount;
  final String? plateNumber;
  // The passenger's own pickup verification code - present only once a
  // driver is assigned and the trip's market has this enabled. The
  // driver never sees this value; they only see whether one is required.
  final String? pickupVerificationCode;
  final double? vehicleLatitude;
  final double? vehicleLongitude;
  final String? driverName;
  final String? vehicleType;
  final String? vehicleColour;
  final double? driverDistanceKm;

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

  bool get hasFare {
    final value = fareAmount?.trim();
    return value != null && value.isNotEmpty;
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
      // Deliberately NOT falling back to the pre-enrichment
      // controlCenterMessage here (unlike the other trip.x ?? x fields
      // above): that text was written for the RideRequest's own frozen
      // "converted" status, so once a trip is linked it's either replaced
      // by the trip's own current message or left null so callers fall
      // through to PassengerRideState's canonical, status-accurate default
      // - never a stale message describing a moment before the trip's
      // real, current outcome was known.
      controlCenterMessage: trip.controlCenterMessage,
      tripReference: trip.tripReference,
      specialRequest: specialRequest,
      fareDisplay: fareDisplay,
      fareAmount: trip.fareAmount ?? fareAmount,
      plateNumber: trip.plateNumber ?? plateNumber,
      pickupVerificationCode:
          trip.pickupVerificationCode ?? pickupVerificationCode,
      vehicleLatitude: trip.vehicleLatitude ?? vehicleLatitude,
      vehicleLongitude: trip.vehicleLongitude ?? vehicleLongitude,
      driverName: trip.driverName ?? driverName,
      vehicleType: trip.vehicleType ?? vehicleType,
      vehicleColour: trip.vehicleColour ?? vehicleColour,
      driverDistanceKm: trip.driverDistanceKm ?? driverDistanceKm,
    );
  }

  bool get isTerminal =>
      passengerState == PassengerRideState.arrived ||
      passengerState == PassengerRideState.cancelledByOperations ||
      passengerState == PassengerRideState.cancelledByPassenger ||
      passengerState == PassengerRideState.rejected;

  String get safeMessage {
    if (passengerState == PassengerRideState.cancelledByOperations) {
      return passengerState.defaultMessage;
    }

    // Unlike latestStaffState (see _historyStatusMessage), withTrip() keeps
    // controlCenterMessage fresh from the linked trip's own message when one
    // exists, so it's still trusted over the canonical default here.
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
    this.fareAmount,
    this.plateNumber,
    this.pickupVerificationCode,
    this.vehicleLatitude,
    this.vehicleLongitude,
    this.driverName,
    this.vehicleType,
    this.vehicleColour,
    this.driverDistanceKm,
  });

  final String tripReference;
  final String status;
  final String? controlCenterMessage;
  final String? fareAmount;
  final String? plateNumber;
  final String? pickupVerificationCode;
  final double? vehicleLatitude;
  final double? vehicleLongitude;
  final String? driverName;
  final String? vehicleType;
  final String? vehicleColour;
  final double? driverDistanceKm;

  String get normalizedStatus => status.trim().toLowerCase();

  bool get isTerminal =>
      normalizedStatus == 'completed_pending_review' ||
      normalizedStatus == 'completed_confirmed' ||
      normalizedStatus == 'cancelled_by_operations' ||
      normalizedStatus == 'cancelled_by_passenger';

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
      fareAmount: _optionalString(map, 'fare_amount'),
      plateNumber:
          _optionalString(map, 'plate_number') ??
          _optionalString(map, 'vehicle_plate_number'),
      pickupVerificationCode: _optionalString(
        map,
        'pickup_verification_code',
      ),
      vehicleLatitude:
          _optionalDouble(map, 'vehicle_latitude') ??
          _optionalDouble(map, 'last_known_vehicle_latitude'),
      vehicleLongitude:
          _optionalDouble(map, 'vehicle_longitude') ??
          _optionalDouble(map, 'last_known_vehicle_longitude'),
      driverName: _optionalString(map, 'driver_name'),
      vehicleType: _optionalString(map, 'vehicle_type'),
      vehicleColour: _optionalString(map, 'vehicle_colour'),
      driverDistanceKm: _optionalDouble(map, 'driver_distance_km'),
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
  cancelledByOperations,
  cancelledByPassenger,
  rejected;

  factory PassengerRideState.fromStatus(
    String status, {
    String? latestStaffState,
    String? message,
  }) {
    final canonicalState = _canonicalStateFor(status);
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

  // The full real Trip.TripStatus / RideRequest.RequestStatus enum, mapped
  // wherever a canonical (non-heuristic) meaning is known. Every status here
  // is trusted over a possibly-stale latest_staff_state/control_center_message
  // string by _statusLabel/_safeStatusMessage/safeMessage - see
  // hasCanonicalStatus. Deliberately NOT mapped: fare_confirmed,
  // awaiting_payment, payment_confirmed - no client code (driver or
  // passenger app) currently drives a trip through these, so there's no
  // evidence for what they should display; they fall through to the
  // heuristic default (looking) unchanged rather than guessing.
  static PassengerRideState? _canonicalStateFor(String status) {
    return switch (status.trim().toLowerCase()) {
      'assigned' => PassengerRideState.driverAssigned,
      'driver_offer_sent' => PassengerRideState.looking,
      'driver_accepted' || 'dispatched' || 'driver_en_route' =>
        PassengerRideState.vehicleEnRoute,
      'arrived_at_pickup' => PassengerRideState.driverArrived,
      // passenger_onboard is the driver-app stage between "arrived at
      // pickup" and "in_progress" (confirming the passenger is in the
      // vehicle) - closest passenger-facing state is inProgress, since the
      // passenger is already aboard.
      'in_progress' || 'passenger_onboard' => PassengerRideState.inProgress,
      'driver_declined' => PassengerRideState.rejected,
      'cancelled_by_operations' => PassengerRideState.cancelledByOperations,
      // no_show is a platform/operations determination, not a
      // passenger-initiated cancellation.
      'no_show' => PassengerRideState.cancelledByOperations,
      // 'cancelled' is the pre-conversion RideRequest status; 'canceled' is
      // an alternate spelling seen from some callers; 'cancelled_by_passenger'
      // is the post-conversion Trip status. All are written exclusively by
      // the passenger-initiated cancellation endpoints - never by any
      // staff/system path.
      'cancelled' ||
      'canceled' ||
      'cancelled_by_passenger' => PassengerRideState.cancelledByPassenger,
      // arrived_at_destination/review_overdue/disputed all mean the ride
      // portion of the trip has already happened; review_overdue is treated
      // as completed by the driver app's own visual-state mapping, and a
      // disputed trip is a completed trip under support review, not one
      // still being matched.
      'completed_pending_review' ||
      'completed_confirmed' ||
      'arrived_at_destination' ||
      'review_overdue' ||
      'disputed' => PassengerRideState.arrived,
      _ => null,
    };
  }

  /// True when [status] has a definitive, non-heuristic mapping above -
  /// safe for callers to trust this state's label/message over a possibly
  /// stale staff-entered string for that status.
  static bool hasCanonicalStatus(String status) =>
      _canonicalStateFor(status) != null;

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
    PassengerRideState.cancelledByOperations =>
      'Your trip was cancelled by ALANTEH support.',
    PassengerRideState.cancelledByPassenger => 'You cancelled this trip.',
    PassengerRideState.rejected =>
      'Please try booking again or contact support.',
  };

  /// Short chip/label text for the history list and detail page - kept
  /// separate from [defaultMessage] since chip wording is deliberately
  /// terser (e.g. "Active" covers several in-flight states).
  String get historyLabel => switch (this) {
    PassengerRideState.looking => 'Active',
    PassengerRideState.driverAssigned => 'Active',
    PassengerRideState.vehicleEnRoute => 'Active',
    PassengerRideState.driverArrived => 'Active',
    PassengerRideState.inProgress => 'Active',
    PassengerRideState.arrived => 'Completed',
    PassengerRideState.reassigned => 'Active',
    PassengerRideState.cancelledByOperations => 'Cancelled',
    PassengerRideState.cancelledByPassenger => 'Cancelled',
    PassengerRideState.rejected => 'Could not be accepted',
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
    'requested' ||
    'under_review' ||
    'accepted_for_trip' ||
    'converted' => true,
    _ => false,
  };
}

bool _isCompletedTripStatus(String status) {
  return switch (status.trim().toLowerCase()) {
    'completed_confirmed' || 'completed_pending_review' => true,
    _ => false,
  };
}

bool _isCompletedHistoryStatus(String status) {
  return switch (status.trim().toLowerCase()) {
    'completed_confirmed' ||
    'completed_pending_review' ||
    'cancelled_by_operations' => true,
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
            .where((record) => _isCompletedHistoryStatus(record.status))
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

  // "converted" is the RideRequest's own terminal status - it never
  // changes again once a Trip exists, so every converted request would
  // otherwise render its list card (and any screen it hands its record
  // to, e.g. RideTrackingScreen's initialRecord) using a status neither
  // PassengerRideState nor the Active/Completed filters have a case
  // for - falling through to a wrong default rather than the trip's
  // real, current status. This fetches each *unique* linked trip
  // concurrently (not one request per card, and not sequentially - the
  // original version of this method awaited each fetch in turn, which
  // is what actually motivated removing it rather than the fetching
  // itself) so the wall-clock cost stays close to one round trip
  // regardless of how many converted trips are in the list.
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

    await Future.wait(
      uniqueTripReferences.map((tripReference) async {
        try {
          tripsByReference[tripReference] = await tripRepository.fetchTrip(
            tripReference,
          );
        } on Object {
          // History enrichment is deliberately fail-soft. The original
          // converted Ride Request card remains available to the
          // passenger - RideTrackingScreen's own "converted" handling
          // covers the case where this card is then opened.
        }
      }),
    );

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

  void _selectFilter(_TripsFilter filter) {
    if (_selectedFilter == filter) {
      return;
    }
    setState(() {
      _selectedFilter = filter;
    });
  }

  Future<void> _openDetail(
    PassengerRideRequestRecord record,
  ) async {
    // "converted" alone only ever matters as the pre-enrichment
    // placeholder (kept as a fallback in case enrichment failed for
    // this specific record) - once enrichment succeeds, record.status
    // is the trip's real status, so routing must be decided from
    // whether it's terminal, not from the literal status string.
    final isConvertedPlaceholder =
        record.status.trim().toLowerCase() == 'converted';
    final isActiveLinkedTrip =
        record.normalizedTripReference != null && !record.isTerminal;
    final hasActiveTrackingPath =
        _isActiveTripStatus(record.status) ||
        (isConvertedPlaceholder && record.tripReference != null) ||
        isActiveLinkedTrip;

    if (hasActiveTrackingPath) {
      final handler = widget.onOpenActiveTracking;
      if (handler != null) {
        await handler(record);
        return;
      }
    }

    if (!mounted) {
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PassengerRideRequestDetailPage(
          requestReference: record.requestReference,
          repository: widget.repository,
          paymentRatingRepository: widget.paymentRatingRepository,
          initialRecord: record,
        ),
      ),
    );
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

    final child = FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(label, softWrap: false),
    );

    return Expanded(
      child: selected
          ? FilledButton(
              key: Key('trip-filter-${filter.name}'),
              onPressed: () => onSelected(filter),
              child: child,
            )
          : OutlinedButton(
              key: Key('trip-filter-${filter.name}'),
              onPressed: () => onSelected(filter),
              child: child,
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
              if (completed && onReturn != null)
                Row(
                  key: const Key('history-card-completed-actions'),
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        key: const Key('history-card-return'),
                        onPressed: () => onReturn!(record),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 48),
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          textStyle: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        child: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('Return trip', maxLines: 1),
                        ),
                      ),
                    ),
                    const SizedBox(width: AsmSpacing.space4),
                    Expanded(
                      child: FilledButton(
                        key: const Key('history-card-book-again'),
                        onPressed: onBookAgain == null
                            ? null
                            : () => onBookAgain!(record),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 48),
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          textStyle: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        child: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('Book again', maxLines: 1),
                        ),
                      ),
                    ),
                    const SizedBox(width: AsmSpacing.space4),
                    Expanded(
                      child: TextButton(
                        key: const Key('history-card-view-details'),
                        onPressed: onTap,
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 48),
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          textStyle: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        child: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('View details', maxLines: 1),
                        ),
                      ),
                    ),
                  ],
                )
              else
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
    this.initialRecord,
    super.key,
  });

  final PassengerRideRequestHistoryRepository repository;
  final String requestReference;
  final VoidCallback? onSignInRequired;
  final PassengerPaymentRatingRepository? paymentRatingRepository;

  /// An already-fetched (and, if applicable, already trip-enriched) record
  /// for this request - typically the one the history list just rendered.
  /// Lets this page paint instantly instead of showing a spinner while it
  /// re-fetches, without skipping that re-fetch: [_load] always runs so the
  /// page still reflects the live, current status rather than a stale
  /// snapshot from whenever the list was loaded.
  final PassengerRideRequestRecord? initialRecord;

  @override
  State<PassengerRideRequestDetailPage> createState() =>
      _PassengerRideRequestDetailPageState();
}

class _PassengerRideRequestDetailPageState
    extends State<PassengerRideRequestDetailPage> {
  late bool _loading = widget.initialRecord == null;
  late PassengerRideRequestRecord? _record = widget.initialRecord;
  PassengerRideRequestHistoryException? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  PassengerTripLifecycleRepository? get _tripRepository {
    final repository = widget.repository;
    return repository is PassengerTripLifecycleRepository
        ? repository as PassengerTripLifecycleRepository
        : null;
  }

  // Mirrors RideTrackingScreen._load()'s enrichment sequence: a "converted"
  // request record is only the RideRequest's own frozen placeholder status,
  // so it's resolved to the linked Trip's real, current status before
  // being shown - the same fix applied to the history list, so this page
  // stays correct for any future entry point that doesn't already hand it
  // an enriched initialRecord.
  Future<void> _load() async {
    setState(() {
      _loading = _record == null;
      _error = null;
    });

    try {
      final requestRecord = await widget.repository.fetchRequest(
        widget.requestReference,
      );

      if (!mounted) {
        return;
      }

      final tripReference =
          requestRecord.status.trim().toLowerCase() == 'converted'
          ? requestRecord.normalizedTripReference
          : null;
      final tripRepository = _tripRepository;

      if (tripReference != null && tripRepository != null) {
        try {
          final trip = await tripRepository.fetchTrip(tripReference);
          if (!mounted) {
            return;
          }

          setState(() {
            _loading = false;
            _record = requestRecord.withTrip(trip);
            _error = null;
          });
          return;
        } on Object {
          // Enrichment is fail-soft, same as the history list - fall back
          // to the unenriched request record below rather than treating a
          // trip-fetch failure as a failure to load the request at all.
        }
      }

      setState(() {
        _loading = false;
        _record = requestRecord;
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

  // latestStaffState is a ride-request-level field that withTrip() (see
  // PassengerRideRequestRecord.withTrip) deliberately leaves unchanged once
  // a record is enriched with its linked trip's real status - so once the
  // real status is confidently known, it's trusted over that now-stale
  // text rather than the other way around. This is unlike controlCenterMessage
  // (used by _safeStatusMessage's other callers), which withTrip() does keep
  // fresh from the trip's own message.
  if (PassengerRideState.hasCanonicalStatus(record.status)) {
    return record.passengerState.defaultMessage;
  }

  return _safeStatusMessage(
    record.status,
    preferredMessage: record.latestStaffState,
  );
}

String _safeStatusMessage(String status, {String? preferredMessage}) {
  if (status.trim().toLowerCase() == 'cancelled_by_operations') {
    return PassengerRideState.cancelledByOperations.defaultMessage;
  }

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

  if (PassengerRideState.hasCanonicalStatus(status)) {
    return PassengerRideState.fromStatus(status).defaultMessage;
  }

  return switch (status.trim().toLowerCase()) {
    'requested' => 'Request received.',
    'under_review' => 'Being reviewed.',
    'accepted' ||
    'approved' ||
    'accepted_for_trip' => 'Accepted for trip preparation.',
    'rejected' || 'declined' => 'Could not be accepted.',
    'trip_created' => 'Trip record created.',
    _ => 'Request update available.',
  };
}

String _statusLabel(String status) {
  if (PassengerRideState.hasCanonicalStatus(status)) {
    return PassengerRideState.fromStatus(status).historyLabel;
  }

  return switch (status.trim().toLowerCase()) {
    'requested' => 'Received by ALANTEH',
    'under_review' => 'Being reviewed',
    'accepted' || 'approved' || 'accepted_for_trip' => 'Accepted',
    'rejected' || 'declined' => 'Could not be accepted',
    'trip_created' => 'Trip record created',
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
