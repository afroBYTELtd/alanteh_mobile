import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passenger_app/main.dart';
import 'package:passenger_app/tracking/ride_tracking_screen.dart';

void main() {
  testWidgets('Passenger splash matches the approved sequence', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: const PassengerSplashScreen(),
      ),
    );

    expect(find.byKey(const Key('passenger-splash-screen')), findsOneWidget);
    expect(find.byKey(const Key('passenger-splash-logo')), findsOneWidget);
    expect(
      find.text("Ghana's first solar electric ride service"),
      findsOneWidget,
    );
  });

  testWidgets('Passenger splash gate advances without changing auth', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: const PassengerSplashGate(
          duration: Duration(milliseconds: 20),
          child: Text('Passenger access ready'),
        ),
      ),
    );

    expect(find.byKey(const Key('passenger-splash-screen')), findsOneWidget);
    expect(find.text('Passenger access ready'), findsNothing);

    await tester.pump(const Duration(milliseconds: 25));

    expect(find.byKey(const Key('passenger-splash-screen')), findsNothing);
    expect(find.text('Passenger access ready'), findsOneWidget);
  });

  testWidgets('No-vehicles state matches the approved safe design', (
    tester,
  ) async {
    var retryPressed = false;
    var supportPressed = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: PassengerNoVehiclesAvailableState(
          onRetry: () => retryPressed = true,
          onContactSupport: () => supportPressed = true,
        ),
      ),
    );

    expect(
      find.byKey(const Key('passenger-no-vehicles-state')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('request-rejected-state')), findsOneWidget);
    // This screen now only shows for a request staff could not accept, so
    // it says that rather than "No vehicles available right now", and its
    // first button starts a fresh booking ("Book again", was "Try again").
    expect(find.text("We couldn't accept this ride request"), findsOneWidget);
    expect(
      find.text(
        "You can book again, or contact support if you'd like to know more.",
      ),
      findsOneWidget,
    );
    expect(find.text('No vehicles available right now'), findsNothing);
    expect(find.text('Book again'), findsOneWidget);
    expect(find.text('Contact support'), findsOneWidget);

    final retryButton = find.byKey(const Key('rejected-book-again'));
    await tester.ensureVisible(retryButton);
    await tester.pumpAndSettle();
    await tester.tap(retryButton);
    await tester.pump();
    expect(retryPressed, isTrue);

    final supportButton = find.byKey(const Key('rejected-contact-support'));
    await tester.ensureVisible(supportButton);
    await tester.pumpAndSettle();
    await tester.tap(supportButton);
    await tester.pump();
    expect(supportPressed, isTrue);
  });
}
