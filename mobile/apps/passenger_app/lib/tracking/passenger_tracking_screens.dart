import 'package:flutter/widgets.dart';

/// The tracking screens and booking flows that are open, so a push never
/// opens a second screen for a ride request and never navigates over a
/// booking. The screens register themselves; nobody who opens one has to
/// remember to.
final class PassengerTrackingScreens {
  final _open = <String, PassengerOpenTrackingScreen>{};
  final _openedAt = <String, int>{};
  final _claimed = <String>{};
  var _bookingFlows = 0;
  var _sequence = 0;

  /// The open screen for [requestReference], if any.
  PassengerOpenTrackingScreen? screenFor(String requestReference) =>
      _open[requestReference];

  /// True while a booking form (or its sending step) is open.
  bool get bookingFlowOpen => _bookingFlows > 0;

  /// Marks [requestReference] as about to be opened; false if it already
  /// is. Callers check [screenFor] first; done in the same step as the
  /// push, so two pushes for one trip cannot both open it.
  bool claim(String requestReference) => _claimed.add(requestReference);

  void release(String requestReference) => _claimed.remove(requestReference);

  void register(String requestReference, PassengerOpenTrackingScreen screen) {
    _claimed.remove(requestReference);
    _open[requestReference] = screen;
    _openedAt[requestReference] = _sequence += 1;
  }

  void unregister(String requestReference, PassengerOpenTrackingScreen screen) {
    if (identical(_open[requestReference], screen)) {
      _open.remove(requestReference);
      _openedAt.remove(requestReference);
    }
  }

  /// True if another trip's screen opened after [requestReference]'s and is
  /// still open: it sits above it, and bringing this one to the top would
  /// close it.
  bool hasScreenAbove(String requestReference) {
    final mine = _openedAt[requestReference];
    if (mine == null) {
      return false;
    }
    return _openedAt.entries.any(
      (entry) => entry.key != requestReference && entry.value > mine,
    );
  }

  void bookingFlowOpened() => _bookingFlows += 1;

  void bookingFlowClosed() {
    if (_bookingFlows > 0) {
      _bookingFlows -= 1;
    }
  }
}

final class PassengerOpenTrackingScreen {
  const PassengerOpenTrackingScreen({
    required this.route,
    required this.refresh,
  });

  final Route<Object?>? route;
  final VoidCallback refresh;
}

/// Holds the app's [PassengerTrackingScreens]; sits above the navigator.
class PassengerTrackingScope extends StatefulWidget {
  const PassengerTrackingScope({required this.child, super.key});

  final Widget child;

  static PassengerTrackingScreens? maybeOf(BuildContext context) => context
      .getInheritedWidgetOfExactType<_PassengerTrackingScopeData>()
      ?.screens;

  @override
  State<PassengerTrackingScope> createState() => _PassengerTrackingScopeState();
}

class _PassengerTrackingScopeState extends State<PassengerTrackingScope> {
  final _screens = PassengerTrackingScreens();

  @override
  Widget build(BuildContext context) =>
      _PassengerTrackingScopeData(screens: _screens, child: widget.child);
}

class _PassengerTrackingScopeData extends InheritedWidget {
  const _PassengerTrackingScopeData({
    required this.screens,
    required super.child,
  });

  final PassengerTrackingScreens screens;

  @override
  bool updateShouldNotify(_PassengerTrackingScopeData oldWidget) =>
      !identical(screens, oldWidget.screens);
}
