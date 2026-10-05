import 'dart:async';

import 'package:asm_design_system/asm_design_system.dart';
import 'package:asm_maps/asm_maps.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Where the map opens when the trip has no pin and the phone no position.
const driverTripMapFallbackCenter = LatLng(5.6037, -0.1870);

/// The driver's own position, from the phone.
abstract interface class DriverDevicePositionSource {
  Stream<LatLng> positions();
}

/// Positions while the driver already allows location; this map never asks.
/// A failure just stops the dot - the pins and Navigate do not need it.
final class GeolocatorDriverDevicePositionSource
    implements DriverDevicePositionSource {
  const GeolocatorDriverDevicePositionSource();

  @override
  Stream<LatLng> positions() async* {
    final LocationPermission permission;
    try {
      permission = await Geolocator.checkPermission();
    } on Object {
      return;
    }
    if (permission != LocationPermission.always &&
        permission != LocationPermission.whileInUse) {
      return;
    }
    yield* Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            distanceFilter: 10,
          ),
        )
        .map((position) => LatLng(position.latitude, position.longitude))
        .handleError((Object _) {});
  }
}

/// The trip map: only real data. The pickup pin from the trip's
/// coordinates, the destination pin once the driver has accepted (the
/// trip data carries it from then), and the driver's own position. No
/// route, distance or time is drawn - Navigate gives the real ones.
///
/// A Google map (asm_maps); Google's EEA terms allow it with our own text
/// and coordinates on it, and nothing of Google's is put beside it.
class DriverTripMap extends StatefulWidget {
  const DriverTripMap({
    required this.pickup,
    required this.destination,
    required this.legTarget,
    required this.devicePositionSource,
    super.key,
  });

  final LatLng? pickup;
  final LatLng? destination;

  /// Where this leg goes: the camera keeps it and the driver in view.
  final LatLng? legTarget;
  final DriverDevicePositionSource devicePositionSource;

  @override
  State<DriverTripMap> createState() => _DriverTripMapState();
}

class _DriverTripMapState extends State<DriverTripMap> {
  AsmMapController? _controller;
  StreamSubscription<LatLng>? _positions;
  LatLng? _device;
  bool _fittedToDevice = false;

  @override
  void initState() {
    super.initState();
    _positions = widget.devicePositionSource.positions().listen((position) {
      if (!mounted) {
        return;
      }
      setState(() => _device = position);
      if (!_fittedToDevice) {
        // Once, so a driver looking around the map is not pulled back.
        _fittedToDevice = true;
        _fit();
      }
    });
  }

  @override
  void didUpdateWidget(DriverTripMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.legTarget != widget.legTarget) {
      _fit();
    }
  }

  @override
  void dispose() {
    unawaited(_positions?.cancel());
    super.dispose();
  }

  void _fit() {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    unawaited(controller.fitPoints([?widget.legTarget, ?_device]));
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      key: const Key('driver-trip-map'),
      color: AsmColors.driverCard,
      child: AsmMapView(
        initialCamera: AsmMapCamera(
          center:
              widget.legTarget ??
              widget.pickup ??
              widget.destination ??
              driverTripMapFallbackCenter,
          zoom: 15,
        ),
        onMapCreated: (controller) {
          _controller = controller;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _fit();
            }
          });
        },
        markers: [
          if (widget.pickup case final pickup?)
            AsmMapMarker(
              id: 'driver-trip-pickup',
              position: pickup,
              style: AsmMapMarkerStyle.pickup,
            ),
          if (widget.destination case final destination?)
            AsmMapMarker(
              id: 'driver-trip-destination',
              position: destination,
              style: AsmMapMarkerStyle.destination,
            ),
          if (_device case final device?)
            AsmMapMarker(
              id: 'driver-trip-device',
              position: device,
              style: AsmMapMarkerStyle.deviceLocation,
            ),
        ],
      ),
    );
  }
}
