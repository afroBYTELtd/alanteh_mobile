import 'dart:async';
import 'dart:math' as math;

import 'package:asm_app_config/asm_app_config.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:asm_maps/asm_maps.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'map/measured_height.dart';

const passengerHomePickupDefaultCenter = LatLng(5.6050, -0.1668);
const passengerHomePickupInitialZoom = 16.0;
const passengerHomePickupGeocodeDebounce = Duration(milliseconds: 400);
const _centrePinSize = 52.0;
// Icons.location_pin's tip sits at y = 22 on its 24-unit grid; lifting the
// icon by this much puts the tip, not the icon's middle, on the target.
const _centrePinTipLift = _centrePinSize * (22 / 24 - 1 / 2);
// Measured on the test phone indoors: a high-accuracy (GPS) fix never came,
// a balanced (Wi-Fi/cell) one in under 50 ms. So recenter answers from a
// recent known position or a balanced fix, then refines with GPS, each
// within a limit, and the blue dot follows a balanced stream.
const passengerHomeRecentPositionMaxAge = Duration(seconds: 60);
const passengerHomeRecentPositionMaxAccuracyMetres = 150.0;
const passengerHomeQuickFixLimit = Duration(seconds: 5);
const passengerHomePreciseFixLimit = Duration(seconds: 15);
const _refineMinDistanceMetres = 20.0;
const passengerHomeLocatingCopy = 'Finding your location…';
const passengerHomeLocationNotFoundCopy =
    "Couldn't find your location. Move the pin to your pickup.";
const passengerHomeLocationServicesOffCopy =
    'Location is turned off. Turn it on to find where you are.';
const passengerHomeLocationRecoveryCopy =
    'Location access is off.\n'
    'Tap to enable in Settings → ALANTEH → Location';

class PassengerPickupSelection {
  const PassengerPickupSelection({
    required this.coordinates,
    required this.address,
  });

  final LatLng coordinates;
  final String address;
}

abstract interface class PassengerHomeReverseGeocoder {
  Future<String> reverseGeocode(LatLng coordinates);
}

class PlatformPassengerHomeReverseGeocoder
    implements PassengerHomeReverseGeocoder {
  const PlatformPassengerHomeReverseGeocoder();

  @override
  Future<String> reverseGeocode(LatLng coordinates) async {
    final placemarks = await placemarkFromCoordinates(
      coordinates.latitude,
      coordinates.longitude,
    );
    if (placemarks.isEmpty) {
      throw StateError('No placemark returned.');
    }

    final placemark = placemarks.first;
    final values = <String?>[
      placemark.name,
      placemark.street,
      placemark.subLocality,
      placemark.locality,
      placemark.subAdministrativeArea,
      placemark.administrativeArea,
      placemark.country,
    ];

    final parts = <String>[];
    final seen = <String>{};
    for (final value in values) {
      final normalized = value?.trim() ?? '';
      if (normalized.isEmpty) {
        continue;
      }
      final dedupeKey = normalized.toLowerCase();
      if (seen.add(dedupeKey)) {
        parts.add(normalized);
      }
    }

    if (parts.isEmpty) {
      throw StateError('Placemark contained no usable address.');
    }
    return parts.join(', ');
  }
}

enum PassengerHomeLocationPermissionState {
  granted,
  denied,
  deniedForever,
  servicesDisabled,
}

abstract interface class PassengerHomeLocationPermissionService {
  Future<PassengerHomeLocationPermissionState> ensurePermission();

  Future<bool> openAppSettings();

  Future<bool> openLocationSettings();
}

class GeolocatorPassengerHomeLocationPermissionService
    implements PassengerHomeLocationPermissionService {
  const GeolocatorPassengerHomeLocationPermissionService();

  @override
  Future<PassengerHomeLocationPermissionState> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return PassengerHomeLocationPermissionState.servicesDisabled;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    return switch (permission) {
      LocationPermission.whileInUse ||
      LocationPermission.always => PassengerHomeLocationPermissionState.granted,
      LocationPermission.deniedForever =>
        PassengerHomeLocationPermissionState.deniedForever,
      _ => PassengerHomeLocationPermissionState.denied,
    };
  }

  @override
  Future<bool> openAppSettings() => Geolocator.openAppSettings();

  @override
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();
}

/// A device position and how good it is.
@immutable
class PassengerDevicePosition {
  const PassengerDevicePosition({
    required this.coordinates,
    required this.accuracyMetres,
    required this.timestamp,
  });

  final LatLng coordinates;
  final double accuracyMetres;
  final DateTime timestamp;
}

enum PassengerLocationFailure {
  permissionDenied,
  servicesOff,
  timedOut,
  unavailable,
}

class PassengerLocationException implements Exception {
  const PassengerLocationException(this.failure);

  final PassengerLocationFailure failure;

  @override
  String toString() => 'PassengerLocationException($failure)';
}

abstract interface class PassengerHomeDeviceLocationService {
  /// The device's last known position, at once; null when it has none.
  Future<PassengerDevicePosition?> lastKnownPosition();

  /// A fresh fix within [timeLimit]: balanced (Wi-Fi and cell, about
  /// 100 m) or [precise] (GPS). Fails with a [PassengerLocationException].
  Future<PassengerDevicePosition> currentPosition({
    required bool precise,
    required Duration timeLimit,
  });

  /// Balanced-accuracy updates for the blue dot; errors are
  /// [PassengerLocationException]s.
  Stream<PassengerDevicePosition> get positionStream;
}

class GeolocatorPassengerHomeDeviceLocationService
    implements PassengerHomeDeviceLocationService {
  const GeolocatorPassengerHomeDeviceLocationService();

  @override
  Future<PassengerDevicePosition?> lastKnownPosition() async {
    try {
      final position = await Geolocator.getLastKnownPosition();
      return position == null ? null : _devicePosition(position);
    } on Object {
      return null;
    }
  }

  @override
  Future<PassengerDevicePosition> currentPosition({
    required bool precise,
    required Duration timeLimit,
  }) async {
    try {
      // On timeout the plugin cancels the platform request too.
      final position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: precise ? LocationAccuracy.high : LocationAccuracy.medium,
          timeLimit: timeLimit,
        ),
      );
      return _devicePosition(position);
    } on Object catch (error) {
      throw _locationException(error);
    }
  }

  @override
  Stream<PassengerDevicePosition> get positionStream {
    return Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            distanceFilter: 10,
          ),
        )
        .map(_devicePosition)
        .handleError((Object error) => throw _locationException(error));
  }

  static PassengerDevicePosition _devicePosition(Position position) {
    return PassengerDevicePosition(
      coordinates: LatLng(position.latitude, position.longitude),
      accuracyMetres: position.accuracy,
      timestamp: position.timestamp,
    );
  }

  static PassengerLocationException _locationException(Object error) {
    return PassengerLocationException(switch (error) {
      PermissionDeniedException() => PassengerLocationFailure.permissionDenied,
      LocationServiceDisabledException() =>
        PassengerLocationFailure.servicesOff,
      TimeoutException() => PassengerLocationFailure.timedOut,
      _ => PassengerLocationFailure.unavailable,
    });
  }
}

typedef PassengerHomePickupSearch =
    Future<String?> Function(String currentAddress);

class PassengerHome extends StatefulWidget {
  const PassengerHome({
    required this.market,
    required this.localQaEnabled,
    required this.pickupDescription,
    required this.destinationDescription,
    required this.canContinue,
    required this.locationsMatch,
    required this.canSwap,
    required this.hasRoute,
    required this.onChoosePickup,
    required this.onChooseDestination,
    required this.onContinue,
    required this.onOpenRequests,
    required this.onSwap,
    required this.onClear,
    required this.onOpenPickupSearch,
    required this.onConfirmPickup,
    this.initialCenter = passengerHomePickupDefaultCenter,
    this.reverseGeocoder = const PlatformPassengerHomeReverseGeocoder(),
    this.deviceLocationService =
        const GeolocatorPassengerHomeDeviceLocationService(),
    this.locationPermissionService =
        const GeolocatorPassengerHomeLocationPermissionService(),
    super.key,
  });

  final MarketConfig market;
  final bool localQaEnabled;
  final String? pickupDescription;
  final String? destinationDescription;
  final bool canContinue;
  final bool locationsMatch;
  final bool canSwap;
  final bool hasRoute;
  final VoidCallback onChoosePickup;
  final VoidCallback onChooseDestination;
  final VoidCallback onContinue;
  final VoidCallback onOpenRequests;
  final VoidCallback onSwap;
  final VoidCallback onClear;
  final PassengerHomePickupSearch onOpenPickupSearch;
  final ValueChanged<PassengerPickupSelection> onConfirmPickup;
  final LatLng initialCenter;
  final PassengerHomeReverseGeocoder reverseGeocoder;
  final PassengerHomeDeviceLocationService deviceLocationService;
  final PassengerHomeLocationPermissionService locationPermissionService;

  @override
  State<PassengerHome> createState() => _PassengerHomeState();
}

class _PassengerHomeState extends State<PassengerHome>
    with WidgetsBindingObserver {
  AsmMapController? _mapController;
  Timer? _geocodeTimer;
  StreamSubscription<PassengerDevicePosition>? _positionSubscription;
  Timer? _streamRetryTimer;
  int _streamFailures = 0;
  PassengerDevicePosition? _deviceFix;
  bool _locating = false;
  String? _locationMessage;
  bool _locationMessageOffersSettings = false;
  bool _locationAccessLost = false;
  int _recenterGeneration = 0;

  late LatLng _center;
  LatLng? _devicePosition;
  late String _address;
  LatLng? _addressCoordinates;
  bool _pinLifted = false;
  bool _cameraMoving = false;
  double _bottomSheetHeight = 0;
  bool _mapPinConfirmationRequired = false;
  bool _locationPermissionDeniedForever = false;
  int _geocodeGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _center = widget.initialCenter;
    final initialDescription = widget.pickupDescription?.trim() ?? '';
    _address = initialDescription.isEmpty
        ? _coordinateFallback(_center)
        : initialDescription;
    _addressCoordinates = initialDescription.isEmpty ? _center : null;
    _mapPinConfirmationRequired = initialDescription.isNotEmpty;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduleReverseGeocode(_center);
      _initializeDevicePosition();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _geocodeTimer?.cancel();
    _recenterGeneration++;
    _stopPositionStream();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_initializeDevicePosition());
    } else if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      // No location requests while the app is out of sight; returning
      // starts exactly one stream again.
      _stopPositionStream();
    }
  }

  Future<PassengerHomeLocationPermissionState>
  _refreshLocationPermissionState() async {
    final permissionState = await widget.locationPermissionService
        .ensurePermission();
    if (mounted) {
      setState(() {
        _locationPermissionDeniedForever =
            permissionState ==
            PassengerHomeLocationPermissionState.deniedForever;
        if (permissionState == PassengerHomeLocationPermissionState.granted) {
          _locationAccessLost = false;
        }
      });
    }
    return permissionState;
  }

  Future<void> _initializeDevicePosition() async {
    final permissionState = await _refreshLocationPermissionState();
    if (!mounted) {
      return;
    }

    if (permissionState != PassengerHomeLocationPermissionState.granted) {
      _stopPositionStream();
      return;
    }

    // The stream starts at once; nothing waits on a fresh fix.
    _startPositionStream();
    final lastKnown = await widget.deviceLocationService.lastKnownPosition();
    if (!mounted || lastKnown == null || !_isRecent(lastKnown)) {
      return;
    }
    final current = _deviceFix;
    if (current == null || lastKnown.timestamp.isAfter(current.timestamp)) {
      _setDeviceFix(lastKnown);
    }
  }

  void _startPositionStream() {
    _streamRetryTimer?.cancel();
    _streamRetryTimer = null;
    unawaited(_positionSubscription?.cancel());
    _positionSubscription = widget.deviceLocationService.positionStream.listen(
      (fix) {
        _streamFailures = 0;
        if (mounted) {
          _setDeviceFix(fix);
        }
      },
      onError: _handlePositionStreamError,
      cancelOnError: true,
    );
  }

  void _stopPositionStream() {
    _streamRetryTimer?.cancel();
    _streamRetryTimer = null;
    unawaited(_positionSubscription?.cancel());
    _positionSubscription = null;
  }

  void _handlePositionStreamError(Object error) {
    _positionSubscription = null;
    if (!mounted) {
      return;
    }
    final failure = error is PassengerLocationException
        ? error.failure
        : PassengerLocationFailure.unavailable;
    switch (failure) {
      case PassengerLocationFailure.permissionDenied:
        // Revoked while running: same banner as denied forever, no retry.
        setState(() => _locationAccessLost = true);
      case PassengerLocationFailure.servicesOff:
        // Returning to the app checks again.
        break;
      case PassengerLocationFailure.timedOut:
      case PassengerLocationFailure.unavailable:
        final pause = Duration(seconds: math.min(60, 2 << _streamFailures));
        _streamFailures += 1;
        _streamRetryTimer = Timer(pause, () {
          if (mounted) {
            _startPositionStream();
          }
        });
    }
  }

  bool _isRecent(PassengerDevicePosition fix) {
    return DateTime.now().difference(fix.timestamp) <=
            passengerHomeRecentPositionMaxAge &&
        fix.accuracyMetres <= passengerHomeRecentPositionMaxAccuracyMetres;
  }

  void _setDeviceFix(PassengerDevicePosition fix) {
    setState(() {
      _deviceFix = fix;
      _devicePosition = fix.coordinates;
    });
  }

  /// Stops an unfinished recenter from moving the camera.
  void _cancelRecenter() {
    _recenterGeneration++;
    if (_locating) {
      setState(() => _locating = false);
    }
  }

  void _showLocationMessage(String message, {bool offersSettings = false}) {
    setState(() {
      _locating = false;
      _locationMessage = message;
      _locationMessageOffersSettings = offersSettings;
    });
  }

  void _clearLocationMessage() {
    if (_locationMessage != null) {
      setState(() => _locationMessage = null);
    }
  }

  bool get _canConfirmPickup =>
      !_pinLifted && !_mapPinConfirmationRequired;

  bool _coordinatesMatch(LatLng first, LatLng second) {
    return first.latitude == second.latitude &&
        first.longitude == second.longitude;
  }

  bool get _addressMatchesCurrentCenter {
    final coordinates = _addressCoordinates;
    return coordinates != null && _coordinatesMatch(coordinates, _center);
  }

  void _invalidateCurrentAddress() {
    _geocodeTimer?.cancel();
    _geocodeGeneration++;
    _addressCoordinates = null;
  }

  void _useCoordinateFallback(LatLng coordinates) {
    _address = _coordinateFallback(coordinates);
    _addressCoordinates = coordinates;
  }

  void _handleCameraMoveStarted() {
    if (!mounted) {
      return;
    }
    _clearLocationMessage();
    _cameraMoving = true;
    _invalidateCurrentAddress();
    setState(() {
      _pinLifted = true;
      _mapPinConfirmationRequired = true;
    });
  }

  void _handleCameraMove(AsmMapCamera camera) {
    if (!mounted) {
      return;
    }
    _invalidateCurrentAddress();
    setState(() => _center = camera.center);
  }

  void _handleCameraIdle(AsmMapCamera camera) {
    // The map also reports idle after loading, without having moved; only
    // the end of a real move sets the pickup.
    if (!mounted || !_cameraMoving) {
      return;
    }
    _cameraMoving = false;
    final nextCenter = camera.center;
    _invalidateCurrentAddress();
    setState(() {
      _center = nextCenter;
      _pinLifted = false;
      _mapPinConfirmationRequired = false;
      _useCoordinateFallback(nextCenter);
    });
    _scheduleReverseGeocode(nextCenter);
  }

  void _scheduleReverseGeocode(LatLng coordinates) {
    _geocodeTimer?.cancel();
    final generation = ++_geocodeGeneration;

    _geocodeTimer = Timer(passengerHomePickupGeocodeDebounce, () async {
      try {
        final resolved = (await widget.reverseGeocoder.reverseGeocode(
          coordinates,
        )).trim();
        if (!mounted ||
            generation != _geocodeGeneration ||
            !_coordinatesMatch(coordinates, _center)) {
          return;
        }
        setState(() {
          _address = resolved.isEmpty
              ? _coordinateFallback(coordinates)
              : resolved;
          _addressCoordinates = coordinates;
        });
      } on Object {
        if (!mounted ||
            generation != _geocodeGeneration ||
            !_coordinatesMatch(coordinates, _center)) {
          return;
        }
        setState(() => _useCoordinateFallback(coordinates));
      }
    });
  }

  Future<void> _openLocationSearch() async {
    final selected = await widget.onOpenPickupSearch(_address);
    if (!mounted || selected == null || selected.trim().isEmpty) {
      return;
    }

    _cancelRecenter();
    _invalidateCurrentAddress();
    setState(() {
      _address = selected.trim();
      _addressCoordinates = null;
      _mapPinConfirmationRequired = true;
    });
  }

  Future<void> _showFullAddress() {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pickup address'),
        content: Text(
          _address,
          key: const Key('passenger-home-pickup-full-address'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _recenter() async {
    final generation = ++_recenterGeneration;
    _clearLocationMessage();
    final permissionState = await _refreshLocationPermissionState();
    if (!mounted || generation != _recenterGeneration) {
      return;
    }
    switch (permissionState) {
      case PassengerHomeLocationPermissionState.servicesDisabled:
        _showLocationMessage(
          passengerHomeLocationServicesOffCopy,
          offersSettings: true,
        );
        return;
      case PassengerHomeLocationPermissionState.denied:
      case PassengerHomeLocationPermissionState.deniedForever:
        setState(() => _locationAccessLost = true);
        return;
      case PassengerHomeLocationPermissionState.granted:
        break;
    }
    // A stream stopped while location was off (or access was lost) comes
    // back here too, not only on returning to the app.
    if (_positionSubscription == null && _streamRetryTimer == null) {
      _startPositionStream();
    }

    // The camera moves only while it is where this recenter last left it,
    // so a drag by the passenger always wins.
    var leftAt = _center;
    var located = false;
    var accessLost = false;
    bool stillOurs() =>
        mounted &&
        generation == _recenterGeneration &&
        _samePlace(_center, leftAt);
    void moveTo(PassengerDevicePosition fix) {
      _setDeviceFix(fix);
      located = true;
      leftAt = fix.coordinates;
      if (_locating) {
        setState(() => _locating = false);
      }
      _animateMapTo(fix.coordinates);
    }

    Future<PassengerDevicePosition?> settle(
      Future<PassengerDevicePosition> request,
    ) async {
      try {
        return await request;
      } on PassengerLocationException catch (error) {
        if (error.failure == PassengerLocationFailure.permissionDenied) {
          accessLost = true;
        }
        return null;
      } on Object {
        return null;
      }
    }

    // A recent known position answers at once; otherwise a balanced fix
    // and a GPS fix are both asked for now, each within its limit.
    final service = widget.deviceLocationService;
    final known = _deviceFix;
    Future<PassengerDevicePosition?>? quick;
    if (known != null && _isRecent(known)) {
      moveTo(known);
    } else {
      setState(() => _locating = true);
      quick = settle(
        service.currentPosition(
          precise: false,
          timeLimit: passengerHomeQuickFixLimit,
        ),
      );
    }
    final precise = settle(
      service.currentPosition(
        precise: true,
        timeLimit: passengerHomePreciseFixLimit,
      ),
    );

    if (quick != null) {
      final fix = await quick;
      if (fix != null && stillOurs()) {
        moveTo(fix);
      }
    }
    final fix = await precise;
    if (!mounted || generation != _recenterGeneration) {
      return;
    }
    if (fix != null &&
        stillOurs() &&
        (!located ||
            _distanceMetres(leftAt, fix.coordinates) >=
                _refineMinDistanceMetres)) {
      moveTo(fix);
      return;
    }
    if (accessLost) {
      // Revoked while running: same banner as denied forever.
      setState(() {
        _locating = false;
        _locationAccessLost = true;
      });
      return;
    }
    if (!located && _samePlace(_center, leftAt)) {
      _showLocationMessage(passengerHomeLocationNotFoundCopy);
    } else if (_locating) {
      setState(() => _locating = false);
    }
  }

  void _animateMapTo(LatLng target) {
    // The camera events from the animation update the pickup.
    unawaited(_mapController?.animateTo(target));
  }

  Future<void> _openLocationSettings() async {
    await widget.locationPermissionService.openAppSettings();
  }

  Widget _buildLocationStatus() {
    final locating = _locating;
    return Material(
      key: Key(
        locating
            ? 'passenger-home-locating'
            : 'passenger-home-location-message',
      ),
      color: AsmColors.passengerCard,
      elevation: 2,
      borderRadius: BorderRadius.circular(AsmRadii.radius16),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AsmSpacing.space12,
          vertical: AsmSpacing.space8,
        ),
        child: Row(
          children: [
            if (locating) ...[
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: AsmSpacing.space8),
            ],
            Expanded(
              child: Text(
                locating ? passengerHomeLocatingCopy : _locationMessage!,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            if (!locating && _locationMessageOffersSettings)
              TextButton(
                key: const Key('passenger-home-location-settings-action'),
                onPressed: () =>
                    widget.locationPermissionService.openLocationSettings(),
                child: const Text('Turn on'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationRecoveryBanner() {
    return Material(
      key: const Key('passenger-home-location-recovery'),
      color: const Color(0xFFFFF4D6),
      borderRadius: BorderRadius.circular(AsmRadii.radius16),
      child: InkWell(
        key: const Key('passenger-home-location-recovery-action'),
        onTap: _openLocationSettings,
        borderRadius: BorderRadius.circular(AsmRadii.radius16),
        child: const Padding(
          padding: EdgeInsets.all(AsmSpacing.space12),
          child: Row(
            children: [
              Icon(
                Icons.location_off_outlined,
                color: AsmColors.brandDeepGreen,
              ),
              SizedBox(width: AsmSpacing.space8),
              Expanded(
                child: Text(
                  passengerHomeLocationRecoveryCopy,
                  style: TextStyle(
                    color: AsmColors.brandDeepGreen,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmPickup() {
    if (!_canConfirmPickup) {
      return;
    }

    _cancelRecenter();

    final address = _addressMatchesCurrentCenter ? _address.trim() : '';
    widget.onConfirmPickup(
      PassengerPickupSelection(
        coordinates: _center,
        address: address.isEmpty ? _coordinateFallback(_center) : address,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      key: const Key('passenger-home-full-screen-map-layout'),
      children: [
        Positioned.fill(
          child: SizedBox(
            key: const Key('passenger-map'),
            width: double.infinity,
            child: ColoredBox(
              color: const Color(0xFFE7F1EA),
              child: AsmMapView(
                key: const Key('passenger-home-flutter-map'),
                initialCamera: AsmMapCamera(
                  center: widget.initialCenter,
                  zoom: passengerHomePickupInitialZoom,
                ),
                // Keeps the Google logo above the bottom sheet; this also
                // moves the camera target to the middle of the open map.
                padding: EdgeInsets.only(bottom: _bottomSheetHeight),
                onMapCreated: (controller) => _mapController = controller,
                onCameraMoveStarted: _handleCameraMoveStarted,
                onCameraMove: _handleCameraMove,
                onCameraIdle: _handleCameraIdle,
                markers: [
                  if (_devicePosition != null)
                    AsmMapMarker(
                      id: 'passenger-home-device-blue-dot',
                      position: _devicePosition!,
                      style: AsmMapMarkerStyle.deviceLocation,
                    ),
                ],
              ),
            ),
          ),
        ),
        // The pickup is the camera target, so the pin's tip is drawn on it.
        Positioned(
          left: 0,
          top: 0,
          right: 0,
          bottom: _bottomSheetHeight,
          child: Center(
            child: Transform.translate(
              offset: const Offset(0, -_centrePinTipLift),
              child: IgnorePointer(
                child: AnimatedSlide(
                  offset: Offset(0, _pinLifted ? -0.22 : 0),
                  duration: const Duration(milliseconds: 140),
                  curve: Curves.easeOut,
                  child: const Icon(
                    Icons.location_pin,
                    key: Key('passenger-home-centre-pin'),
                    size: _centrePinSize,
                    color: AsmColors.brandDeepGreen,
                  ),
                ),
              ),
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AsmSpacing.space16),
            child: Column(
              key: const Key('passenger-home-safe-top-content'),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  key: const Key('passenger-home-floating-header'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      key: const Key('passenger-home-floating-logo'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AsmSpacing.space12,
                        vertical: AsmSpacing.space8,
                      ),
                      decoration: _floatingDecoration(),
                      child: Image.asset(
                        'assets/brand/alanteh-master-logo.png',
                        width: 168,
                        height: 35,
                        fit: BoxFit.contain,
                        semanticLabel: 'ALANTEH passenger logo',
                      ),
                    ),
                    const Spacer(),
                    Container(
                      key: const Key('passenger-home-floating-account'),
                      width: 44,
                      height: 44,
                      decoration: _floatingDecoration(shape: BoxShape.circle),
                      child: const Icon(Icons.person_outline),
                    ),
                  ],
                ),
                const SizedBox(height: AsmSpacing.space12),
                Container(
                  key: const Key('passenger-home-solar-banner'),
                  padding: const EdgeInsets.all(AsmSpacing.space12),
                  decoration: BoxDecoration(
                    color: AsmColors.brandDeepGreen,
                    borderRadius: BorderRadius.circular(AsmRadii.radius16),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 18,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.wb_sunny_outlined,
                        color: AsmColors.solarYellow,
                      ),
                      SizedBox(width: AsmSpacing.space8),
                      Expanded(
                        child: Text(
                          "Ghana's first solar electric ride service. Clean, quiet, and reliable.",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_locationPermissionDeniedForever ||
                    _locationAccessLost) ...[
                  const SizedBox(height: AsmSpacing.space8),
                  _buildLocationRecoveryBanner(),
                ],
              ],
            ),
          ),
        ),
        if (_locating || _locationMessage != null)
          Positioned(
            left: AsmSpacing.space16,
            right: 72,
            // Clear of the bottom sheet, whatever its height.
            bottom: math.max(248, _bottomSheetHeight + AsmSpacing.space8),
            child: _buildLocationStatus(),
          ),
        Positioned(
          right: AsmSpacing.space16,
          bottom: 248,
          child: FloatingActionButton.small(
            key: const Key('passenger-home-recenter'),
            heroTag: 'passenger-home-recenter',
            onPressed: _recenter,
            tooltip: 'Recenter on my location',
            child: const Icon(Icons.my_location),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: MeasuredHeight(
            onHeight: (height) {
              if (mounted && height != _bottomSheetHeight) {
                setState(() => _bottomSheetHeight = height);
              }
            },
            child: Container(
              key: const Key('passenger-home-bottom-sheet'),
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(
                AsmSpacing.space20,
                AsmSpacing.space12,
                AsmSpacing.space20,
                AsmSpacing.space20,
              ),
              decoration: const BoxDecoration(
                color: AsmColors.passengerCard,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(AsmRadii.radius28),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x26000000),
                    blurRadius: 28,
                    offset: Offset(0, -10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AsmColors.passengerLine,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(height: AsmSpacing.space12),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Request ride',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  const SizedBox(height: AsmSpacing.space8),
                  InkWell(
                    key: const Key('passenger-home-pickup-address-row'),
                    borderRadius: BorderRadius.circular(AsmRadii.radius16),
                    onTap: _openLocationSearch,
                    onLongPress: _showFullAddress,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AsmSpacing.space12,
                        vertical: AsmSpacing.space8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF4F7F4),
                        borderRadius: BorderRadius.circular(AsmRadii.radius16),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.location_on_outlined,
                            color: AsmColors.brandDeepGreen,
                          ),
                          const SizedBox(width: AsmSpacing.space8),
                          Expanded(
                            child: Text(
                              _truncateAddress(_address),
                              key: const Key(
                                'passenger-home-pickup-address-text',
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.clip,
                            ),
                          ),
                          IconButton(
                            key: const Key('passenger-home-edit-pickup'),
                            onPressed: _openLocationSearch,
                            icon: const Icon(Icons.edit_outlined),
                            tooltip: 'Edit pickup address',
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AsmSpacing.space8),
                  KeyedSubtree(
                    key: const Key('open-live-request'),
                    child: FilledButton(
                      key: const Key('confirm-pickup'),
                      onPressed: _canConfirmPickup ? _confirmPickup : null,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                      child: const Text('Confirm Pick Up'),
                    ),
                  ),
                  const SizedBox(height: AsmSpacing.space8),
                  OutlinedButton.icon(
                    key: const Key('open-ride-request-history'),
                    onPressed: widget.onOpenRequests,
                    icon: const Icon(Icons.route_outlined),
                    label: const Text('My Ride Requests'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  BoxDecoration _floatingDecoration({BoxShape shape = BoxShape.rectangle}) {
    return BoxDecoration(
      color: const Color(0xF2FFFFFF),
      shape: shape,
      borderRadius: shape == BoxShape.rectangle
          ? BorderRadius.circular(AsmRadii.radius20)
          : null,
      boxShadow: const [
        BoxShadow(
          color: Color(0x26000000),
          blurRadius: 16,
          offset: Offset(0, 6),
        ),
      ],
    );
  }
}

double _distanceMetres(LatLng a, LatLng b) {
  return const Distance().as(LengthUnit.Meter, a, b);
}

bool _samePlace(LatLng a, LatLng b) => _distanceMetres(a, b) < 1;

String _coordinateFallback(LatLng coordinates) {
  return '${coordinates.latitude.toStringAsFixed(5)}, '
      '${coordinates.longitude.toStringAsFixed(5)}';
}

String _truncateAddress(String address) {
  final runes = address.runes.toList(growable: false);
  if (runes.length <= 60) {
    return address;
  }
  return '${String.fromCharCodes(runes.take(57))}...';
}
