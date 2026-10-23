import 'package:flutter/foundation.dart';

/// What a reload of the trip on the live screen found.
enum DriverLiveTripFinding {
  /// Still this driver's trip, in a live status.
  live,
  cancelledByPassenger,
  cancelledByOperations,

  /// The trip is no longer this driver's to act on.
  notAssigned,

  /// Dispatch recorded the trip as a no-show.
  noShow,

  /// The trip is over (completed or under review): reloads stop and the
  /// screen stays as it is.
  ended,

  /// A status this app does not know: nothing changes.
  unknown,
}

/// The trip screens that are open, by trip reference, so a cancel push
/// reaches every screen showing that trip: the live trip sequence and the
/// "Assigned trip detail" screen under it can both be open.
final class DriverLiveTripScreens {
  DriverLiveTripScreens._();

  static final instance = DriverLiveTripScreens._();

  final _open = <String, List<VoidCallback>>{};

  void register(String tripReference, VoidCallback checkNow) {
    final screens = _open.putIfAbsent(_key(tripReference), () => []);
    if (!screens.contains(checkNow)) {
      screens.add(checkNow);
    }
  }

  /// Removes [checkNow] for [tripReference] (a method tear-off is equal,
  /// not identical, to the one registered); other screens stay.
  void unregister(String tripReference, VoidCallback checkNow) {
    final key = _key(tripReference);
    final screens = _open[key];
    if (screens == null) {
      return;
    }
    screens.remove(checkNow);
    if (screens.isEmpty) {
      _open.remove(key);
    }
  }

  /// Asks every open screen for [tripReference] to reload its trip now;
  /// false when none is open.
  bool checkNow(String tripReference) {
    final screens = _open[_key(tripReference)];
    if (screens == null || screens.isEmpty) {
      return false;
    }
    for (final check in List<VoidCallback>.of(screens)) {
      check();
    }
    return true;
  }

  static String _key(String tripReference) =>
      tripReference.trim().toUpperCase();
}
