import 'package:asm_app_config/asm_app_config.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:driver_app/foundation/driver_foundation_widgets.dart';
import 'package:driver_app/ride_offer/driver_ride_offer_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('waiting state exposes Preview incoming offer action', (
    tester,
  ) async {
    var opened = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.driver,
        home: Scaffold(
          body: DriverWaitingForOfferPanel(
            onPreviewIncomingOffer: () => opened = true,
          ),
        ),
      ),
    );

    expect(find.text('Waiting for offers'), findsOneWidget);
    expect(find.text('WAITING FOR A RIDE OFFER NEARBY'), findsOneWidget);
    expect(find.text('Stay in your zone for faster matches.'), findsOneWidget);
    expect(find.text('Preview incoming offer'), findsOneWidget);

    await tester.tap(find.byKey(const Key('open-ride-offer-preview')));

    expect(opened, isTrue);
  });

  testWidgets('preview counts down and opens accepted detail state', (
    tester,
  ) async {
    await _pumpOfferPage(tester);

    expect(find.text('14s'), findsOneWidget);
    expect(find.text('New ride offer'), findsOneWidget);
    expect(find.text('Accra Mall → Accra Market'), findsOneWidget);
    expect(find.text('9.5 km'), findsOneWidget);
    expect(find.text('1.2 km away'), findsOneWidget);
    expect(find.text('View details'), findsOneWidget);
    expect(find.text('Accept'), findsNothing);
    expect(find.text('Decline'), findsNothing);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('13s'), findsOneWidget);

    await tester.tap(find.byKey(const Key('view-ride-offer-details')));
    await tester.pump();

    expect(find.byKey(const Key('ride-offer-detail-state')), findsOneWidget);
    expect(find.text('Ride offer'), findsWidgets);
    expect(find.text('Accra Mall'), findsWidgets);
    expect(find.text('Accra Market'), findsWidgets);
    expect(find.text('23 min'), findsOneWidget);
    expect(find.text('Passengers'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('Accept'), findsOneWidget);
    expect(find.text('Decline'), findsOneWidget);

    await tester.tap(find.byKey(const Key('accept-ride-offer-preview')));
    await tester.pump();

    expect(find.byKey(const Key('ride-offer-accepted')), findsOneWidget);
    expect(find.text('Ride accepted'), findsOneWidget);
    expect(
      find.text('Head to Accra Mall to pick up your passenger.'),
      findsOneWidget,
    );
    expect(find.text('Back to home'), findsOneWidget);
  });

  testWidgets('detail supports the approved declined state', (tester) async {
    await _pumpOfferPage(tester);

    await tester.tap(find.byKey(const Key('view-ride-offer-details')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('decline-ride-offer-preview')));
    await tester.pump();

    expect(find.byKey(const Key('ride-offer-declined')), findsOneWidget);
    expect(find.text('Offer declined'), findsOneWidget);
    expect(
      find.text("You'll continue receiving new ride offers while online."),
      findsOneWidget,
    );
    expect(find.text('Back to home'), findsOneWidget);
  });

  testWidgets('14-second countdown reaches the approved expired state', (
    tester,
  ) async {
    await _pumpOfferPage(tester);

    await tester.pump(const Duration(seconds: 14));
    await tester.pump();

    expect(find.byKey(const Key('ride-offer-expired')), findsOneWidget);
    expect(find.text('Offer expired'), findsOneWidget);
    expect(
      find.text(
        "You didn't respond in time, so this ride was offered to "
        'another driver nearby.',
      ),
      findsOneWidget,
    );
    expect(find.text('Accept'), findsNothing);
    expect(find.text('Decline'), findsNothing);
    expect(find.text('Back to home'), findsOneWidget);
  });
}

Future<void> _pumpOfferPage(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AsmThemes.driver,
      home: const DriverRideOfferPage(market: MarketConfig.ghanaAccra),
    ),
  );
  await tester.pump();
}
