import 'package:flutter/widgets.dart';

/// "Back to Work" from a screen opened over the driver shell: closes the
/// screens above it and selects the Work tab, whichever tab was open.
abstract final class DriverBackToWork {
  /// Set by the driver shell while it is shown.
  static VoidCallback? selectWorkTab;

  static void go(BuildContext context) {
    Navigator.of(context).popUntil((route) => route.isFirst);
    selectWorkTab?.call();
  }
}
