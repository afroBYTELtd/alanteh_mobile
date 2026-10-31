import 'package:flutter/foundation.dart';

/// Something the driver's trips depend on changed: the pending offers, or a
/// trip push arrived with the app in front. Work's duty summary and the
/// Trips list reload on it.
final class DriverReloadSignal extends ChangeNotifier {
  void ping() => notifyListeners();
}
