import 'dart:async';

import 'package:asm_app_config/asm_app_config.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'map/passenger_map.dart';

const passengerHomePickupDefaultCenter = LatLng(5.6050, -0.1668);
const passengerHomePickupInitialZoom = 16.0;
const passengerHomePickupGeocodeDebounce = Duration(milliseconds: 400);
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
}

abstract interface class PassengerHomeDeviceLocationService {
  Future<LatLng?> getCurrentDevicePosition();

  Stream<LatLng> get devicePositionStream;
}

class GeolocatorPassengerHomeDeviceLocationService
    implements PassengerHomeDeviceLocationService {
  const GeolocatorPassengerHomeDeviceLocationService();

  Future<bool> _ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return false;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
  }

  @override
  Future<LatLng?> getCurrentDevicePosition() async {
    try {
      if (!await _ensurePermission()) {
        return null;
      }
      final position = await Geolocator.getCurrentPosition();
      return LatLng(position.latitude, position.longitude);
    } on Object {
      return null;
    }
  }

  @override
  Stream<LatLng> get devicePositionStream async* {
    try {
      if (!await _ensurePermission()) {
        return;
      }

      await for (final position in Geolocator.getPositionStream()) {
        yield LatLng(position.latitude, position.longitude);
      }
    } on Object {
      return;
    }
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
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final MapController _mapController = MapController();

  late final AnimationController _recenterAnimationController;
  Timer? _geocodeTimer;
  StreamSubscription<LatLng>? _positionSubscription;

  late LatLng _center;
  LatLng? _devicePosition;
  late String _address;
  bool _pinLifted = false;
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
    _recenterAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduleReverseGeocode(_center);
      _initializeDevicePosition();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _geocodeTimer?.cancel();
    _positionSubscription?.cancel();
    _recenterAnimationController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_initializeDevicePosition());
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
      await _positionSubscription?.cancel();
      _positionSubscription = null;
      return;
    }

    final initialPosition = await widget.deviceLocationService
        .getCurrentDevicePosition();
    if (!mounted) {
      return;
    }

    if (initialPosition != null) {
      setState(() {
        _devicePosition = initialPosition;
        _center = initialPosition;
        _address = _coordinateFallback(initialPosition);
      });
      _mapController.move(initialPosition, passengerHomePickupInitialZoom);
      if (mounted) {
        setState(() => _pinLifted = false);
      }
      _scheduleReverseGeocode(initialPosition);
    }

    await _positionSubscription?.cancel();
    _positionSubscription = widget.deviceLocationService.devicePositionStream
        .listen((position) {
          if (!mounted) {
            return;
          }
          setState(() => _devicePosition = position);
        });
  }

  void _handleMapEvent(MapEvent event) {
    if (event is MapEventMoveStart ||
        event is MapEventMove ||
        event is MapEventFlingAnimation) {
      if (!mounted) {
        return;
      }
      setState(() {
        _center = event.camera.center;
        _pinLifted = true;
      });
      return;
    }

    if (event is MapEventMoveEnd) {
      if (!mounted) {
        return;
      }
      final nextCenter = event.camera.center;
      setState(() {
        _center = nextCenter;
        _pinLifted = false;
      });
      _scheduleReverseGeocode(nextCenter);
    }
  }

  void _scheduleReverseGeocode(LatLng coordinates) {
    _geocodeTimer?.cancel();
    final generation = ++_geocodeGeneration;

    _geocodeTimer = Timer(passengerHomePickupGeocodeDebounce, () async {
      try {
        final resolved = (await widget.reverseGeocoder.reverseGeocode(
          coordinates,
        )).trim();
        if (!mounted || generation != _geocodeGeneration) {
          return;
        }
        setState(() {
          _address = resolved.isEmpty
              ? _coordinateFallback(coordinates)
              : resolved;
        });
      } on Object {
        if (!mounted || generation != _geocodeGeneration) {
          return;
        }
        setState(() => _address = _coordinateFallback(coordinates));
      }
    });
  }

  Future<void> _openLocationSearch() async {
    final selected = await widget.onOpenPickupSearch(_address);
    if (!mounted || selected == null || selected.trim().isEmpty) {
      return;
    }
    setState(() => _address = selected.trim());
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
    final permissionState = await _refreshLocationPermissionState();
    if (!mounted ||
        permissionState != PassengerHomeLocationPermissionState.granted) {
      return;
    }

    final devicePosition = await widget.deviceLocationService
        .getCurrentDevicePosition();
    if (!mounted || devicePosition == null) {
      return;
    }

    setState(() => _devicePosition = devicePosition);
    _animateMapTo(devicePosition);
  }

  void _animateMapTo(LatLng target) {
    _recenterAnimationController.stop();
    _recenterAnimationController.reset();

    final start = _mapController.camera.center;
    final zoom = _mapController.camera.zoom;

    void listener() {
      final t = Curves.easeOut.transform(_recenterAnimationController.value);
      final next = LatLng(
        start.latitude + (target.latitude - start.latitude) * t,
        start.longitude + (target.longitude - start.longitude) * t,
      );
      _mapController.move(next, zoom, id: 'passenger-home-recenter');
    }

    _recenterAnimationController.addListener(listener);
    _recenterAnimationController.forward().whenComplete(() {
      _recenterAnimationController.removeListener(listener);
      if (!mounted) {
        return;
      }
      setState(() {
        _center = target;
        _pinLifted = false;
      });
      _scheduleReverseGeocode(target);
    });
  }

  Future<void> _openLocationSettings() async {
    await widget.locationPermissionService.openAppSettings();
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
    final address = _address.trim();
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
              child: FlutterMap(
                key: const Key('passenger-home-flutter-map'),
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: widget.initialCenter,
                  initialZoom: passengerHomePickupInitialZoom,
                  minZoom: 5,
                  maxZoom: 18,
                  onMapEvent: _handleMapEvent,
                ),
                children: [
                  TileLayer(
                    urlTemplate: osmTileUrl,
                    userAgentPackageName: osmUserAgentPackageName,
                  ),
                  MarkerLayer(
                    key: const Key('passenger-home-device-marker-layer'),
                    markers: [
                      if (_devicePosition != null)
                        Marker(
                          point: _devicePosition!,
                          width: 30,
                          height: 30,
                          child: Container(
                            key: const Key('passenger-home-device-blue-dot'),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A73E8),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x33000000),
                                  blurRadius: 6,
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        Center(
          child: IgnorePointer(
            child: AnimatedSlide(
              offset: Offset(0, _pinLifted ? -0.22 : 0),
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOut,
              child: const Icon(
                Icons.location_pin,
                key: Key('passenger-home-centre-pin'),
                size: 52,
                color: AsmColors.brandDeepGreen,
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
                        'assets/brand/alanteh_header_dark.png',
                        width: 132,
                        height: 28,
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
                if (_locationPermissionDeniedForever) ...[
                  const SizedBox(height: AsmSpacing.space8),
                  _buildLocationRecoveryBanner(),
                ],
              ],
            ),
          ),
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
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
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
                    onPressed: _confirmPickup,
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
