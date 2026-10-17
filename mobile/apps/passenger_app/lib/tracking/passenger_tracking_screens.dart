import 'package:flutter/widgets.dart';

/// The one form in which ride request and trip references are compared on
/// the passenger side: trimmed, upper case.
String passengerReferenceKey(String reference) =>
    reference.trim().toUpperCase();

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
      _open[passengerReferenceKey(requestReference)];

  /// True while a booking form (or its sending step) is open.
  bool get bookingFlowOpen => _bookingFlows > 0;

  /// Marks [requestReference] as about to be opened; false if it already
  /// is. Callers check [screenFor] first; done in the same step as the
  /// push, so two pushes for one trip cannot both open it.
  bool claim(String requestReference) =>
      _claimed.add(passengerReferenceKey(requestReference));

  void release(String requestReference) =>
      _claimed.remove(passengerReferenceKey(requestReference));

  void register(String requestReference, PassengerOpenTrackingScreen screen) {
    final key = passengerReferenceKey(requestReference);
    _claimed.remove(key);
    _open[key] = screen;
    _openedAt[key] = _sequence += 1;
  }

  void unregister(String requestReference, PassengerOpenTrackingScreen screen) {
    final key = passengerReferenceKey(requestReference);
    if (identical(_open[key], screen)) {
      _open.remove(key);
      _openedAt.remove(key);
    }
  }

  /// True if another trip's screen opened after [requestReference]'s and is
  /// still open: it sits above it, and bringing this one to the top would
  /// close it.
  bool hasScreenAbove(String requestReference) {
    final key = passengerReferenceKey(requestReference);
    final mine = _openedAt[key];
    if (mine == null) {
      return false;
    }
    return _openedAt.entries.any(
      (entry) => entry.key != key && entry.value > mine,
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
