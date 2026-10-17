import 'package:flutter/foundation.dart';

/// What a reload of the trip on the live screen found.
enum DriverLiveTripFinding {
  /// Still this driver's trip, in a live status.
  live,
  cancelledByPassenger,
  cancelledByOperations,

  /// Cancelled, without saying by whom.
  cancelled,

  /// The trip is no longer this driver's to act on.
  notAssigned,
}

/// The live trip screens that are open, by trip reference, so a cancel
/// push reaches the screen for that trip.
final class DriverLiveTripScreens {
  DriverLiveTripScreens._();

  static final instance = DriverLiveTripScreens._();

  final _open = <String, VoidCallback>{};

  void register(String tripReference, VoidCallback checkNow) {
    _open[_key(tripReference)] = checkNow;
  }

  /// Removes [checkNow] if it is still the one registered (a method
  /// tear-off is equal, not identical, to the one registered).
  void unregister(String tripReference, VoidCallback checkNow) {
    final key = _key(tripReference);
    if (_open[key] == checkNow) {
      _open.remove(key);
    }
  }

  /// Asks the open screen for [tripReference] to reload its trip now;
  /// false when no such screen is open.
  bool checkNow(String tripReference) {
    final check = _open[_key(tripReference)];
    if (check == null) {
      return false;
    }
    check();
    return true;
  }

  static String _key(String tripReference) =>
      tripReference.trim().toUpperCase();
}
