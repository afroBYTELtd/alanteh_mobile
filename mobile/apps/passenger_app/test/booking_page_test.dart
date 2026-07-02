import 'package:asm_app_config/asm_app_config.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passenger_app/booking/booking_page.dart';
import 'package:passenger_app/main.dart';

void main() {
  testWidgets('renders existing booking form controls without submission', (
    tester,
  ) async {
    _useSurface(tester, const Size(430, 1000));
    await tester.pumpWidget(_bookingTestApp());

    expect(find.byKey(const Key('booking-service-context')), findsOneWidget);
    expect(find.text('Approved service context'), findsOneWidget);
    expect(find.byKey(const Key('booking-pickup')), findsOneWidget);
    expect(find.text('Pickup description'), findsOneWidget);
    expect(find.byKey(const Key('booking-destination')), findsOneWidget);
    expect(find.text('Destination description'), findsOneWidget);
    expect(find.text('Passengers'), findsOneWidget);
    expect(find.byKey(const Key('passenger-count-decrease')), findsOneWidget);
    expect(find.byKey(const Key('passenger-count-increase')), findsOneWidget);
    expect(find.byKey(const Key('booking-assistance')), findsOneWidget);
    expect(find.text('Assistance note (optional)'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('review-local-draft')));
    expect(find.byKey(const Key('review-local-draft')), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('passenger-count-decrease')))
          .onPressed,
      isNull,
    );

    for (var count = 2; count <= 6; count++) {
      await tester.tap(find.byKey(const Key('passenger-count-increase')));
      await tester.pumpAndSettle();
    }

    expect(find.text('6'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('passenger-count-increase')))
          .onPressed,
      isNull,
    );
    expect(find.text('Submit'), findsNothing);
    expect(find.text('Request Ride'), findsNothing);
  });

  testWidgets('keeps empty booking validation and corrected assistance label', (
    tester,
  ) async {
    _useSurface(tester, const Size(430, 1000));
    await tester.pumpWidget(_bookingTestApp());

    expect(find.text('Assistance note (optional)'), findsOneWidget);
    expect(
      find.text('Accessibility or assistance note (optional)'),
      findsNothing,
    );

    await tester.ensureVisible(find.byKey(const Key('review-local-draft')));
    await tester.tap(find.byKey(const Key('review-local-draft')));
    await tester.pumpAndSettle();

    expect(find.text('Choose an approved service context.'), findsOneWidget);
    expect(find.text('Enter a pickup description.'), findsOneWidget);
    expect(find.text('Enter a destination description.'), findsOneWidget);
    expect(find.text('No ride request has been sent.'), findsNothing);
  });

  testWidgets('validates locations and completes the prefilled draft flow', (
    tester,
  ) async {
    _useSurface(tester, const Size(430, 1000));
    await tester.pumpWidget(const PassengerApp());

    FilledButton continueButton() => tester.widget<FilledButton>(
      find.byKey(const Key('continue-local-draft')),
    );
    IconButton swapButton() =>
        tester.widget<IconButton>(find.byKey(const Key('swap-route')));

    expect(continueButton().onPressed, isNull);
    expect(swapButton().onPressed, isNull);
    expect(find.byKey(const Key('clear-route')), findsNothing);
    await _selectLocation(
      tester,
      controlKey: 'choose-pickup',
      description: '  Solar Hotel  ',
    );
    expect(find.text('Solar Hotel'), findsOneWidget);
    expect(continueButton().onPressed, isNull);
    expect(swapButton().onPressed, isNull);
    expect(find.byKey(const Key('clear-route')), findsOneWidget);

    await tester.tap(find.byKey(const Key('choose-destination')));
    await tester.pumpAndSettle();
    expect(find.text('Recent this session'), findsOneWidget);
    expect(find.byKey(const Key('recent-location-0')), findsOneWidget);
    expect(find.text('Solar Hotel'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('location-description')),
      'solar hotel',
    );
    await tester.tap(find.byKey(const Key('use-location-description')));
    await tester.pumpAndSettle();

    expect(
      find.text('Pickup and destination must be different.'),
      findsOneWidget,
    );
    expect(continueButton().onPressed, isNull);

    await tester.tap(find.byKey(const Key('choose-destination')));
    await tester.pumpAndSettle();
    expect(find.text('Accra, Ghana'), findsOneWidget);
    expect(
      find.text('Local description only. No map search is connected.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('location-description')))
          .controller!
          .text,
      'solar hotel',
    );
    await tester.enterText(
      find.byKey(const Key('location-description')),
      'Accra Airport',
    );
    await tester.tap(find.byKey(const Key('use-location-description')));
    await tester.pumpAndSettle();

    expect(continueButton().onPressed, isNotNull);
    expect(swapButton().onPressed, isNotNull);

    await tester.tap(find.byKey(const Key('swap-route')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const Key('choose-pickup')),
        matching: find.text('Accra Airport'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('choose-destination')),
        matching: find.text('Solar Hotel'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('choose-pickup')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('recent-location-0')), findsOneWidget);
    expect(find.byKey(const Key('recent-location-1')), findsOneWidget);
    expect(find.byKey(const Key('recent-location-2')), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('swap-route')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('continue-local-draft')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('booking-pickup')))
          .controller!
          .text,
      'Solar Hotel',
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('booking-destination')))
          .controller!
          .text,
      'Accra Airport',
    );
    expect(find.text('Assistance note (optional)'), findsOneWidget);
    expect(
      find.text(
        'Local draft for the controlled pilot in Accra, Ghana (gh-accra).',
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('booking-service-context')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Airport connection').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('passenger-count-increase')));
    await tester.enterText(
      find.byKey(const Key('booking-assistance')),
      'Step-free access',
    );
    await tester.ensureVisible(find.byKey(const Key('review-local-draft')));
    await tester.tap(find.byKey(const Key('review-local-draft')));
    await tester.pumpAndSettle();

    expect(find.text('No ride request has been sent.'), findsOneWidget);
    expect(find.text('Operating market'), findsOneWidget);
    expect(find.text('Accra, Ghana'), findsOneWidget);
    expect(find.text('Airport connection'), findsOneWidget);
    expect(find.text('Solar Hotel'), findsOneWidget);
    expect(find.text('Accra Airport'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('Step-free access'), findsOneWidget);
    expect(find.text('Submit'), findsNothing);
    expect(find.text('Request Ride'), findsNothing);
    expect(find.text('Find Driver'), findsNothing);
    expect(find.text('Confirm Booking'), findsNothing);
    expect(find.text('Pay'), findsNothing);

    await tester.ensureVisible(find.byKey(const Key('edit-booking-draft')));
    await tester.tap(find.byKey(const Key('edit-booking-draft')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('booking-pickup')))
          .controller!
          .text,
      'Solar Hotel',
    );

    await tester.ensureVisible(find.byKey(const Key('review-local-draft')));
    await tester.tap(find.byKey(const Key('review-local-draft')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('close-booking-draft')));
    await tester.tap(find.byKey(const Key('close-booking-draft')));
    await tester.pumpAndSettle();

    expect(
      find.text('Map preview unavailable in this local demo.'),
      findsOneWidget,
    );
    expect(find.text('Choose pickup'), findsOneWidget);
    expect(find.text('Where to?'), findsOneWidget);
    expect(find.text('Solar Hotel'), findsNothing);
    expect(find.text('Accra Airport'), findsNothing);

    await tester.tap(find.byKey(const Key('choose-pickup')));
    await tester.pumpAndSettle();
    expect(find.text('Recent this session'), findsOneWidget);
    expect(find.byKey(const Key('recent-location-0')), findsOneWidget);
    expect(find.byKey(const Key('recent-location-1')), findsOneWidget);
    await tester.tap(find.byKey(const Key('recent-location-0')));
    await tester.pumpAndSettle();
    expect(find.text('Accra Airport'), findsOneWidget);
  });

  testWidgets('clear route preserves session locations', (tester) async {
    _useSurface(tester, const Size(430, 1000));
    await tester.pumpWidget(const PassengerApp());

    await _selectLocation(
      tester,
      controlKey: 'choose-pickup',
      description: 'Solar Hotel',
    );
    await _selectLocation(
      tester,
      controlKey: 'choose-destination',
      description: 'Accra Airport',
    );

    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('continue-local-draft')))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.byKey(const Key('clear-route')));
    await tester.pumpAndSettle();

    expect(find.text('Choose pickup'), findsOneWidget);
    expect(find.text('Where to?'), findsOneWidget);
    expect(find.byKey(const Key('clear-route')), findsNothing);
    expect(
      tester.widget<IconButton>(find.byKey(const Key('swap-route'))).onPressed,
      isNull,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('continue-local-draft')))
          .onPressed,
      isNull,
    );

    await tester.tap(find.byKey(const Key('choose-pickup')));
    await tester.pumpAndSettle();
    expect(find.text('Recent this session'), findsOneWidget);
    expect(find.text('Solar Hotel'), findsOneWidget);
    expect(find.text('Accra Airport'), findsOneWidget);
  });
}

Future<void> _selectLocation(
  WidgetTester tester, {
  required String controlKey,
  required String description,
}) async {
  await tester.tap(find.byKey(Key(controlKey)));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const Key('location-description')),
    description,
  );
  await tester.tap(find.byKey(const Key('use-location-description')));
  await tester.pumpAndSettle();
}

Widget _bookingTestApp() {
  return MaterialApp(
    theme: AsmThemes.passenger,
    home: const BookingPage(market: MarketConfig.ghanaAccra),
  );
}

void _useSurface(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
