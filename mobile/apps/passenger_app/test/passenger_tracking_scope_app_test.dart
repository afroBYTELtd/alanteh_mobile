import 'package:asm_auth/asm_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passenger_app/main.dart';
import 'package:passenger_app/tracking/passenger_tracking_screens.dart';

// The app puts its tracking-screen list above the navigator, so every
// tracking screen and booking page registers, however it was opened.
void main() {
  testWidgets('the app installs the tracking scope above its navigator', (
    tester,
  ) async {
    final store = MemoryAuthTokenStore();
    await tester.pumpWidget(
      PassengerApp(showLoginShell: true, authTokenStore: store),
    );
    await tester.pump();

    final navigatorContext = tester.element(find.byType(Navigator).first);
    expect(PassengerTrackingScope.maybeOf(navigatorContext), isNotNull);
  });
}
