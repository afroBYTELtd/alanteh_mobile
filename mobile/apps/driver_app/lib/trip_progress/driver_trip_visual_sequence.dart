import 'dart:async';

import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';

import '../network/driver_trip_action_resilience.dart';
import 'driver_trip_map.dart';
import 'driver_trip_route.dart';
import 'driver_trip_visual_state.dart';

class DriverTripVisualSequencePage extends StatefulWidget {
  const DriverTripVisualSequencePage({
    this.actionRecorder,
    this.initialStatus,
    this.onActionRejected,
    super.key,
  });

  final DriverTripActionResilienceController? actionRecorder;
  final String? initialStatus;
  final Future<void> Function(DriverTripActionRecordResult result)?
  onActionRejected;

  @override
  State<DriverTripVisualSequencePage> createState() =>
      _DriverTripVisualSequencePageState();
}

class _DriverTripVisualSequencePageState
    extends State<DriverTripVisualSequencePage> {
  late DriverTripVisualState _state;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _state = DriverTripVisualState.fromBackendStatus(widget.initialStatus);
  }

  Future<void> _applyResilientAction({
    required String eventType,
    required DriverTripVisualState Function(DriverTripVisualState state)
    transition,
  }) async {
    if (_isSubmitting) {
      return;
    }

    final recorder = widget.actionRecorder;
    if (recorder == null) {
      setState(() => _state = transition(_state));
      return;
    }

    setState(() => _isSubmitting = true);

    DriverTripActionRecordResult result;
    try {
      result = await recorder.recordAction(
        eventType: eventType,
        payload: const <String, Object?>{},
      );
    } on Object {
      if (!mounted) {
        return;
      }

      setState(() => _isSubmitting = false);
      _showActionMessage(
        'This action could not be confirmed. Check your connection and retry.',
      );
      return;
    }

    if (!mounted) {
      return;
    }

    if (!result.canAdvance) {
      setState(() => _isSubmitting = false);

      final rejectionHandler = widget.onActionRejected;
      if (rejectionHandler != null) {
        try {
          await rejectionHandler(result);
        } on Object {
          // The action remains unconfirmed even if refresh recovery fails.
        }
        if (!mounted) {
          return;
        }
      }

      if (result.queuedOffline) {
        _showActionMessage(
          'Saved on this device, but it is not confirmed by the server. '
          'Retry when the connection is stable.',
          key: const Key('driver-trip-action-queued-snackbar'),
        );
      } else {
        _showActionMessage(
          result.error?.message ??
              'This action was not confirmed. Refresh the trip and retry.',
        );
      }
      return;
    }

    setState(() {
      _state = transition(_state);
      _isSubmitting = false;
    });
  }

  void _showActionMessage(String message, {Key? key}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(key: key, content: Text(message)));
  }

  void _markArrivedAtPickup() {
    unawaited(
      _applyResilientAction(
        eventType: 'arrived-pickup',
        transition: (state) => state.markArrivedAtPickup(),
      ),
    );
  }

  void _openPassengerConfirmation() {
    if (_isSubmitting) {
      return;
    }
    setState(() => _state = _state.openPassengerOnboardConfirmation());
  }

  void _cancelPassengerConfirmation() {
    if (_isSubmitting) {
      return;
    }
    setState(() => _state = _state.cancelPassengerOnboardConfirmation());
  }

  void _confirmPassengerOnboard() {
    unawaited(
      _applyResilientAction(
        eventType: 'start-trip',
        transition: (state) => state.confirmPassengerOnboard(),
      ),
    );
  }

  void _markArrivedAtDestination() {
    if (_isSubmitting) {
      return;
    }
    setState(() => _state = _state.markArrivedAtDestination());
  }

  void _completeTrip() {
    unawaited(
      _applyResilientAction(
        eventType: 'complete-trip',
        transition: (state) => state.completeTrip(),
      ),
    );
  }

  void _backToHome() {
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final stage = _state.stage;

    return Scaffold(
      key: const Key('driver-trip-sequence-page'),
      appBar: AppBar(
        title: Text(switch (stage) {
          DriverTripVisualStage.navigatingToPickup => 'Navigate to pickup',
          DriverTripVisualStage.arrivedAtPickup => 'Pickup',
          DriverTripVisualStage.confirmingPassengerOnboard =>
            'Passenger onboard',
          DriverTripVisualStage.activeTrip => 'Active trip',
          DriverTripVisualStage.arrivedAtDestination => 'Destination',
          DriverTripVisualStage.completed =>
            'Trip completed — awaiting operations review',
        }),
      ),
      body: switch (stage) {
        DriverTripVisualStage.navigatingToPickup => _DriverMapStage(
          key: const Key('driver-navigate-to-pickup'),
          route: safeDriverPickupRouteFallback(),
          showPickup: true,
          showDestination: false,
          title: 'Heading to pickup',
          subtitle: 'Accra Mall',
          routeLabel: 'Pickup route',
          primaryLocationLabel: 'Pickup',
          primaryLocationValue: 'Accra Mall',
          secondaryLocationLabel: 'Next destination',
          secondaryLocationValue: 'Accra Market',
          actionKey: const Key('driver-mark-arrived-pickup'),
          actionLabel: "I've arrived",
          actionIcon: Icons.location_on_outlined,
          isActionPending: _isSubmitting,
          onAction: _markArrivedAtPickup,
        ),
        DriverTripVisualStage.arrivedAtPickup => _DriverStateScreen(
          key: const Key('driver-arrived-at-pickup'),
          icon: Icons.notifications_active_outlined,
          title: "You've arrived",
          message:
              "Let your passenger know you're here, then confirm once "
              "they're safely onboard.",
          primaryActionKey: const Key('driver-open-onboard-confirmation'),
          primaryActionLabel: 'Confirm passenger onboard',
          primaryActionIcon: Icons.people_alt_outlined,
          onPrimaryAction: _openPassengerConfirmation,
        ),
        DriverTripVisualStage.confirmingPassengerOnboard => _DriverStateScreen(
          key: const Key('driver-confirm-passenger-onboard'),
          icon: Icons.people_alt_outlined,
          title: 'Confirm passenger onboard',
          message:
              'Only start the trip after the passenger is safely seated '
              'and ready to travel.',
          primaryActionKey: const Key('driver-confirm-onboard'),
          primaryActionLabel: 'Start trip',
          primaryActionIcon: Icons.play_arrow_outlined,
          isPrimaryActionPending: _isSubmitting,
          onPrimaryAction: _confirmPassengerOnboard,
          secondaryActionKey: const Key('driver-cancel-onboard-confirmation'),
          secondaryActionLabel: 'Back',
          onSecondaryAction: _cancelPassengerConfirmation,
        ),
        DriverTripVisualStage.activeTrip => _DriverMapStage(
          key: const Key('driver-active-trip'),
          route: safeDriverDestinationRouteFallback(),
          showPickup: true,
          showDestination: true,
          title: 'Trip in progress',
          subtitle: 'Heading to Accra Market',
          routeLabel: 'Destination route',
          primaryLocationLabel: 'From',
          primaryLocationValue: 'Accra Mall',
          secondaryLocationLabel: 'To',
          secondaryLocationValue: 'Accra Market',
          actionKey: const Key('driver-mark-arrived-destination'),
          actionLabel: 'Arrived at destination',
          actionIcon: Icons.flag_outlined,
          onAction: _markArrivedAtDestination,
        ),
        DriverTripVisualStage.arrivedAtDestination => _DriverStateScreen(
          key: const Key('driver-arrived-at-destination'),
          icon: Icons.flag_circle_outlined,
          title: 'Arrived at destination',
          message: 'Confirm the ride has ended safely at Accra Market.',
          primaryActionKey: const Key('driver-complete-trip'),
          primaryActionLabel: 'Complete trip',
          primaryActionIcon: Icons.check_circle_outline,
          isPrimaryActionPending: _isSubmitting,
          onPrimaryAction: _completeTrip,
        ),
        DriverTripVisualStage.completed => _DriverTripCompletedScreen(
          onBackToHome: _backToHome,
        ),
      },
    );
  }
}

class _DriverMapStage extends StatelessWidget {
  const _DriverMapStage({
    required super.key,
    required this.route,
    required this.showPickup,
    required this.showDestination,
    required this.title,
    required this.subtitle,
    required this.routeLabel,
    required this.primaryLocationLabel,
    required this.primaryLocationValue,
    required this.secondaryLocationLabel,
    required this.secondaryLocationValue,
    required this.actionKey,
    required this.actionLabel,
    required this.actionIcon,
    this.isActionPending = false,
    required this.onAction,
  });

  final DriverTripRouteEstimate route;
  final bool showPickup;
  final bool showDestination;
  final String title;
  final String subtitle;
  final String routeLabel;
  final String primaryLocationLabel;
  final String primaryLocationValue;
  final String secondaryLocationLabel;
  final String secondaryLocationValue;
  final Key actionKey;
  final String actionLabel;
  final IconData actionIcon;
  final bool isActionPending;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Expanded(
            flex: 6,
            child: DriverTripMap(
              route: route,
              showPickup: showPickup,
              showDestination: showDestination,
            ),
          ),
          Flexible(
            flex: 5,
            child: Container(
              key: const Key('driver-trip-details-sheet'),
              width: double.infinity,
              decoration: const BoxDecoration(
                color: AsmColors.driverCardElevated,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(AsmRadii.radius24),
                ),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AsmSpacing.space20,
                  AsmSpacing.space16,
                  AsmSpacing.space20,
                  AsmSpacing.space24,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AsmColors.driverLine,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                    const SizedBox(height: AsmSpacing.space16),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: AsmSpacing.space4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AsmColors.driverMintAction,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AsmSpacing.space16),
                    _DriverTripDetailRow(
                      label: primaryLocationLabel,
                      value: primaryLocationValue,
                      icon: Icons.trip_origin,
                    ),
                    _DriverTripDetailRow(
                      label: secondaryLocationLabel,
                      value: secondaryLocationValue,
                      icon: Icons.location_on_outlined,
                    ),
                    const SizedBox(height: AsmSpacing.space8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AsmSpacing.space12),
                      decoration: BoxDecoration(
                        color: AsmColors.driverCard,
                        borderRadius: BorderRadius.circular(AsmRadii.radius24),
                        border: Border.all(color: AsmColors.driverLine),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.route_outlined,
                            color: AsmColors.driverMintAction,
                          ),
                          const SizedBox(width: AsmSpacing.space12),
                          Expanded(
                            child: Text(
                              '$routeLabel · '
                              '${route.distanceKilometres.toStringAsFixed(1)} km '
                              '· about ${route.durationMinutes} min',
                              key: const Key(
                                'driver-trip-route-distance-duration',
                              ),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AsmSpacing.space16),
                    FilledButton.icon(
                      key: actionKey,
                      onPressed: isActionPending ? null : onAction,
                      icon: isActionPending
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(actionIcon),
                      label: Text(
                        isActionPending ? 'Confirming...' : actionLabel,
                      ),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(54),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DriverStateScreen extends StatelessWidget {
  const _DriverStateScreen({
    required super.key,
    required this.icon,
    required this.title,
    required this.message,
    required this.primaryActionKey,
    required this.primaryActionLabel,
    required this.primaryActionIcon,
    required this.onPrimaryAction,
    this.isPrimaryActionPending = false,
    this.secondaryActionKey,
    this.secondaryActionLabel,
    this.onSecondaryAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final Key primaryActionKey;
  final String primaryActionLabel;
  final IconData primaryActionIcon;
  final VoidCallback onPrimaryAction;
  final bool isPrimaryActionPending;
  final Key? secondaryActionKey;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;

  @override
  Widget build(BuildContext context) {
    return AsmScreenSurface(
      scrollable: true,
      expandToViewport: true,
      padding: const EdgeInsets.all(AsmSpacing.space24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 42,
              backgroundColor: AsmColors.driverCardElevated,
              foregroundColor: AsmColors.driverMintAction,
              child: Icon(icon, size: 44),
            ),
            const SizedBox(height: AsmSpacing.space20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 29, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: AsmSpacing.space12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AsmColors.driverTextSecondary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                height: 1.45,
              ),
            ),
            const SizedBox(height: AsmSpacing.space32),
            FilledButton.icon(
              key: primaryActionKey,
              onPressed: isPrimaryActionPending ? null : onPrimaryAction,
              icon: isPrimaryActionPending
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(primaryActionIcon),
              label: Text(
                isPrimaryActionPending ? 'Confirming...' : primaryActionLabel,
              ),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
              ),
            ),
            if (onSecondaryAction != null &&
                secondaryActionKey != null &&
                secondaryActionLabel != null) ...[
              const SizedBox(height: AsmSpacing.space8),
              OutlinedButton(
                key: secondaryActionKey,
                onPressed: isPrimaryActionPending ? null : onSecondaryAction,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                child: Text(secondaryActionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DriverTripCompletedScreen extends StatelessWidget {
  const _DriverTripCompletedScreen({required this.onBackToHome});

  final VoidCallback onBackToHome;

  @override
  Widget build(BuildContext context) {
    return AsmScreenSurface(
      key: const Key('driver-trip-completed'),
      scrollable: true,
      expandToViewport: true,
      padding: const EdgeInsets.all(AsmSpacing.space24),
      child: Column(
        children: [
          const SizedBox(height: AsmSpacing.space16),
          const CircleAvatar(
            radius: 42,
            backgroundColor: AsmColors.driverCardElevated,
            foregroundColor: AsmColors.driverMintAction,
            child: Icon(Icons.check_circle_outline, size: 45),
          ),
          const SizedBox(height: AsmSpacing.space20),
          const Text(
            'Trip completed — awaiting operations review',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 29, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: AsmSpacing.space8),
          const Text(
            'Awaiting operations review',
            style: TextStyle(
              color: AsmColors.driverMintAction,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: AsmSpacing.space20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AsmSpacing.space20),
            decoration: BoxDecoration(
              color: AsmColors.driverCardElevated,
              borderRadius: BorderRadius.circular(AsmRadii.radius24),
              border: Border.all(color: AsmColors.driverLine),
            ),
            child: const Column(
              children: [
                _DriverTripDetailRow(
                  label: 'Route',
                  value: 'Accra Mall → Accra Market',
                  icon: Icons.route_outlined,
                ),
                _DriverTripDetailRow(
                  label: 'Distance',
                  value: '9.5 km',
                  icon: Icons.straighten_outlined,
                ),
                _DriverTripDetailRow(
                  label: 'Duration',
                  value: '23 min',
                  icon: Icons.schedule_outlined,
                ),
                _DriverTripDetailRow(
                  label: 'Passengers',
                  value: '2',
                  icon: Icons.people_alt_outlined,
                ),
              ],
            ),
          ),
          const SizedBox(height: AsmSpacing.space16),
          const Text(
            'Completion is not confirmed until ALANTEH operations reviews the trip.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AsmColors.driverTextSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          const SizedBox(height: AsmSpacing.space24),
          OutlinedButton.icon(
            key: const Key('driver-trip-back-home'),
            onPressed: onBackToHome,
            icon: const Icon(Icons.arrow_back_outlined),
            label: const Text('Back to home'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
            ),
          ),
        ],
      ),
    );
  }
}

class _DriverTripDetailRow extends StatelessWidget {
  const _DriverTripDetailRow({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AsmSpacing.space12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AsmColors.driverMintAction, size: 22),
          const SizedBox(width: AsmSpacing.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AsmColors.driverTextSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AsmSpacing.space4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
