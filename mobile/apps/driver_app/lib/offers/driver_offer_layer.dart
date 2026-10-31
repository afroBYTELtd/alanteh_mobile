import 'dart:math' as math;

import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../driver_back_to_work.dart';
import '../driver_duty_trips.dart';
import '../network/driver_offer_response_resilience.dart';
import 'driver_offer_coordinator.dart';
import 'driver_pending_offer_card.dart';
import 'driver_pending_offers_panel.dart';

/// What the app-wide offer card needs from the signed-in driver.
@immutable
final class DriverOfferLayerSource {
  const DriverOfferLayerSource({
    required this.coordinator,
    required this.controllerFactory,
    this.pickupTimeLookup,
    this.onAccepted,
  });

  final DriverOfferCoordinator coordinator;
  final DriverOfferResponseControllerFactory controllerFactory;
  final DriverOfferPickupTimeLookup? pickupTimeLookup;

  /// The driver accepted; open the trip.
  final ValueChanged<String>? onAccepted;
}

/// Counts the screens and the sheets or dialogs on the driver navigator,
/// for [DriverOfferLayer].
final class DriverOfferRouteObserver extends NavigatorObserver {
  /// Full screens: 1 while only the shell (its tabs) is open.
  final ValueNotifier<int> pages = ValueNotifier<int>(0);

  /// Sheets and dialogs over them.
  final ValueNotifier<int> popups = ValueNotifier<int>(0);

  // Never below zero: a route that went away before this observer saw it
  // arrive (or before the counts were reset) is not counted.
  void _count(Route<dynamic>? route, int by) {
    if (route is PageRoute) {
      pages.value = math.max(0, pages.value + by);
    } else if (route is PopupRoute) {
      popups.value = math.max(0, popups.value + by);
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _count(route, 1);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _count(route, -1);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _count(route, -1);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _count(oldRoute, -1);
    _count(newRoute, 1);
  }
}

/// The NavigationBar's height under the shell's tabs.
const driverOfferLayerTabBarHeight = 80.0;

/// How much of the tabs' page the offer card covers, from the top of the
/// tab bar up: 0 when no card shows on the tabs. The shell ends its page
/// this much higher, so the card covers nothing on it.
class DriverOfferTabsInset extends InheritedNotifier<ValueNotifier<double>> {
  const DriverOfferTabsInset({
    required ValueNotifier<double> super.notifier,
    required super.child,
    super.key,
  });

  /// The inset above [context]; 0 when the app has no offer layer.
  static double of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<DriverOfferTabsInset>()
          ?.notifier
          ?.value ??
      0;
}

/// The one offer card for the whole app, on every tab and over every screen
/// the driver has open (seen 24 Oct: an offer ran out while the driver was
/// on the "Trip completed" screens, where no card showed). One card, so its
/// countdown and "Sending…" stay when the driver moves around.
///
/// On the tabs it sits above the tab bar, clear of the header's Sign out
/// and Go offline, and the page ends above it ([DriverOfferTabsInset]).
/// Over a pushed screen it sits at the top, clear of the
/// Emergency and Alert Dispatch buttons at the bottom of the trip screens.
/// While a sheet or dialog is open it is hidden (kept alive), so it never
/// covers the sheet's buttons.
///
/// It lives above the navigator, so the decline-reason sheet and "My
/// Assigned Trips" go through [navigatorKey].
class DriverOfferLayer extends StatefulWidget {
  const DriverOfferLayer({
    required this.navigatorKey,
    required this.routeCounter,
    required this.child,
    super.key,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final DriverOfferRouteObserver routeCounter;
  final Widget child;

  /// The layer above [context], if the app has one.
  static DriverOfferLayerState? maybeOf(BuildContext context) =>
      context.findAncestorStateOfType<DriverOfferLayerState>();

  @override
  State<DriverOfferLayer> createState() => DriverOfferLayerState();
}

class DriverOfferLayerState extends State<DriverOfferLayer> {
  DriverOfferLayerSource? _source;
  bool _offerScreenOpen = false;
  final _tabsInset = ValueNotifier<double>(0);
  double _cardHeight = 0;
  bool _insetUpdateScheduled = false;

  /// The signed-in driver's offers, or null when there is none to show.
  set source(DriverOfferLayerSource? source) {
    if (source == _source) {
      return;
    }
    setState(() => _source = source);
  }

  /// A full-screen offer (a push tap) shows its own card meanwhile.
  set offerScreenOpen(bool open) {
    if (open == _offerScreenOpen) {
      return;
    }
    setState(() => _offerScreenOpen = open);
  }

  @override
  void initState() {
    super.initState();
    // A new app: its navigator, built below, pushes its first screen next.
    widget.routeCounter.pages.value = 0;
    widget.routeCounter.popups.value = 0;
    widget.routeCounter.pages.addListener(_routesChanged);
    widget.routeCounter.popups.addListener(_routesChanged);
  }

  @override
  void dispose() {
    widget.routeCounter.pages.removeListener(_routesChanged);
    widget.routeCounter.popups.removeListener(_routesChanged);
    _tabsInset.dispose();
    super.dispose();
  }

  bool get _onTabs => widget.routeCounter.pages.value <= 1;

  // The card's height on the tabs, plus the gaps below and above it.
  double get _wantedTabsInset {
    if (_source == null || _offerScreenOpen || !_onTabs || _cardHeight <= 0) {
      return 0;
    }
    return _cardHeight + 2 * AsmSpacing.space8;
  }

  // After the frame: the shell is below this layer and must not be told to
  // rebuild while the layer builds.
  void _scheduleTabsInsetUpdate() {
    if (_insetUpdateScheduled) {
      return;
    }
    _insetUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _insetUpdateScheduled = false;
      if (mounted) {
        _tabsInset.value = _wantedTabsInset;
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _cardMeasured(double height) {
    if (height == _cardHeight) {
      return;
    }
    _cardHeight = height;
    _scheduleTabsInsetUpdate();
  }

  // The navigator can report a route during a build: rebuild after it.
  void _routesChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {});
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  BuildContext? get _navigatorContext => widget.navigatorKey.currentContext;

  Future<DriverDeclineChoice?> _pickDeclineReason(
    BuildContext _,
    ValueListenable<bool> offerEnded,
  ) async {
    final navigatorContext = _navigatorContext;
    if (navigatorContext == null) {
      return null;
    }
    return showDriverDeclineReasonSheet(navigatorContext, offerEnded);
  }

  void _openAssignedTrips(BuildContext _) {
    final navigatorContext = _navigatorContext;
    if (navigatorContext != null) {
      DriverBackToWork.goToAssignedTrips(navigatorContext);
    }
  }

  @override
  Widget build(BuildContext context) {
    _scheduleTabsInsetUpdate();
    final source = _source;
    if (source == null || _offerScreenOpen) {
      return DriverOfferTabsInset(notifier: _tabsInset, child: widget.child);
    }
    final onTabs = _onTabs;
    final padding = MediaQuery.paddingOf(context);
    const gap = AsmSpacing.space8;
    return Stack(
      children: [
        DriverOfferTabsInset(notifier: _tabsInset, child: widget.child),
        Positioned(
          left: AsmSpacing.space16,
          right: AsmSpacing.space16,
          top: onTabs ? null : padding.top + gap,
          bottom: onTabs
              ? padding.bottom + driverOfferLayerTabBarHeight + gap
              : null,
          child: Offstage(
            offstage: widget.routeCounter.popups.value > 0,
            child: Material(
              type: MaterialType.transparency,
              child: _HeightReporter(
                onHeight: _cardMeasured,
                child: DriverPendingOffersPanel(
                  key: const Key('driver-offer-layer'),
                  coordinator: source.coordinator,
                  controllerFactory: source.controllerFactory,
                  pickupTimeLookup: source.pickupTimeLookup,
                  onAccepted: source.onAccepted,
                  pickDeclineReason: _pickDeclineReason,
                  openAssignedTrips: _openAssignedTrips,
                  openPopups: widget.routeCounter.popups,
                  waitingPanel: const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Reports its child's height after each layout that changes it.
class _HeightReporter extends SingleChildRenderObjectWidget {
  const _HeightReporter({required this.onHeight, super.child});

  final ValueChanged<double> onHeight;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderHeightReporter(onHeight);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderHeightReporter renderObject,
  ) {
    renderObject.onHeight = onHeight;
  }
}

class _RenderHeightReporter extends RenderProxyBox {
  _RenderHeightReporter(this.onHeight);

  ValueChanged<double> onHeight;
  double? _reported;

  @override
  void performLayout() {
    super.performLayout();
    final height = size.height;
    if (height != _reported) {
      _reported = height;
      onHeight(height);
    }
  }
}
