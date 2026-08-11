import 'dart:async';

import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../map/passenger_map.dart';

const pickupMapDefaultCenter = LatLng(5.6050, -0.1668);
const pickupMapInitialZoom = 16.0;
const pickupMapGeocodeDebounce = Duration(milliseconds: 400);

class PassengerPickupSelection {
  const PassengerPickupSelection({
    required this.coordinates,
    required this.address,
  });

  final LatLng coordinates;
  final String address;
}

abstract interface class PickupReverseGeocoder {
  Future<String> reverseGeocode(LatLng coordinates);
}

class PlatformPickupReverseGeocoder implements PickupReverseGeocoder {
  const PlatformPickupReverseGeocoder();

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

abstract interface class PickupDeviceLocationService {
  Future<LatLng?> getCurrentDevicePosition();

  Stream<LatLng> get devicePositionStream;
}

class GeolocatorPickupDeviceLocationService
    implements PickupDeviceLocationService {
  const GeolocatorPickupDeviceLocationService();

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

typedef PickupLocationSearch = Future<String?> Function(String currentAddress);

class PickupMapConfirmationPage extends StatefulWidget {
  const PickupMapConfirmationPage({
    required this.onOpenLocationSearch,
    required this.onConfirm,
    this.onCancel,
    this.initialCenter = pickupMapDefaultCenter,
    this.reverseGeocoder = const PlatformPickupReverseGeocoder(),
    this.deviceLocationService = const GeolocatorPickupDeviceLocationService(),
    super.key,
  });

  final PickupLocationSearch onOpenLocationSearch;
  final ValueChanged<PassengerPickupSelection> onConfirm;
  final VoidCallback? onCancel;
  final LatLng initialCenter;
  final PickupReverseGeocoder reverseGeocoder;
  final PickupDeviceLocationService deviceLocationService;

  @override
  State<PickupMapConfirmationPage> createState() =>
      _PickupMapConfirmationPageState();
}

class _PickupMapConfirmationPageState extends State<PickupMapConfirmationPage>
    with SingleTickerProviderStateMixin {
  final MapController _mapController = MapController();

  late final AnimationController _recenterAnimationController;
  Timer? _geocodeTimer;
  StreamSubscription<LatLng>? _positionSubscription;

  late LatLng _center;
  LatLng? _devicePosition;
  late String _address;
  bool _pinLifted = false;
  int _geocodeGeneration = 0;

  @override
  void initState() {
    super.initState();
    _center = widget.initialCenter;
    _address = _coordinateFallback(_center);
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
    _geocodeTimer?.cancel();
    _positionSubscription?.cancel();
    _recenterAnimationController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _initializeDevicePosition() async {
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
      _mapController.move(initialPosition, pickupMapInitialZoom);
      _scheduleReverseGeocode(initialPosition);
    }

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
      final nextCenter = event.camera.center;
      if (!mounted) {
        return;
      }
      setState(() {
        _center = nextCenter;
        _pinLifted = true;
      });
      return;
    }

    if (event is MapEventMoveEnd) {
      final nextCenter = event.camera.center;
      if (!mounted) {
        return;
      }
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
    _geocodeTimer = Timer(pickupMapGeocodeDebounce, () async {
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
    final selected = await widget.onOpenLocationSearch(_address);
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
        content: Text(_address, key: const Key('pickup-map-full-address')),
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
      _mapController.move(next, zoom, id: 'pickup-recenter');
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

  void _confirmPickup() {
    final address = _address.trim();
    widget.onConfirm(
      PassengerPickupSelection(
        coordinates: _center,
        address: address.isEmpty ? _coordinateFallback(_center) : address,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      key: const Key('pickup-map-confirmation-screen'),
      children: [
        Positioned.fill(
          child: FlutterMap(
            key: const Key('pickup-confirmation-flutter-map'),
            mapController: _mapController,
            options: MapOptions(
              initialCenter: widget.initialCenter,
              initialZoom: pickupMapInitialZoom,
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
                key: const Key('pickup-map-device-marker-layer'),
                markers: [
                  if (_devicePosition != null)
                    Marker(
                      point: _devicePosition!,
                      width: 30,
                      height: 30,
                      child: Container(
                        key: const Key('pickup-map-device-blue-dot'),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A73E8),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: const [
                            BoxShadow(color: Color(0x33000000), blurRadius: 6),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
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
                key: Key('pickup-map-centre-pin'),
                size: 52,
                color: AsmColors.brandDeepGreen,
              ),
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AsmSpacing.space16),
            child: Align(
              alignment: Alignment.topLeft,
              child: Material(
                color: const Color(0xF2FFFFFF),
                shape: const CircleBorder(),
                elevation: 2,
                child: IconButton(
                  key: const Key('pickup-map-cancel'),
                  onPressed: widget.onCancel,
                  icon: const Icon(Icons.arrow_back),
                  tooltip: 'Back',
                ),
              ),
            ),
          ),
        ),
        Positioned(
          right: AsmSpacing.space16,
          bottom: 154,
          child: FloatingActionButton.small(
            key: const Key('pickup-map-recenter'),
            heroTag: 'pickup-map-recenter',
            onPressed: _recenter,
            tooltip: 'Recenter on my location',
            child: const Icon(Icons.my_location),
          ),
        ),
        Positioned(
          left: AsmSpacing.space16,
          right: AsmSpacing.space16,
          bottom: AsmSpacing.space16,
          child: SafeArea(
            top: false,
            child: Material(
              color: Colors.white,
              elevation: 5,
              borderRadius: BorderRadius.circular(AsmRadii.radius20),
              child: Padding(
                padding: const EdgeInsets.all(AsmSpacing.space12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      key: const Key('pickup-map-address-row'),
                      borderRadius: BorderRadius.circular(AsmRadii.radius16),
                      onTap: _openLocationSearch,
                      onLongPress: _showFullAddress,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AsmSpacing.space12,
                          vertical: AsmSpacing.space12,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF4F7F4),
                          borderRadius: BorderRadius.circular(
                            AsmRadii.radius16,
                          ),
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
                                key: const Key('pickup-map-address-text'),
                                maxLines: 1,
                                overflow: TextOverflow.clip,
                              ),
                            ),
                            IconButton(
                              key: const Key('pickup-map-edit-address'),
                              onPressed: _openLocationSearch,
                              icon: const Icon(Icons.edit_outlined),
                              tooltip: 'Edit pickup address',
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: AsmSpacing.space12),
                    FilledButton(
                      key: const Key('confirm-pickup'),
                      onPressed: _confirmPickup,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                      child: const Text('Confirm Pick Up'),
                    ),
                  ],
                ),
              ),
            ),
          ),
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
