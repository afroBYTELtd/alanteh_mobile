import 'package:asm_app_config/asm_app_config.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passenger_app/booking/booking_page.dart';
import 'package:passenger_app/main.dart';

void main() {
  testWidgets('renders simplified booking form without service context', (
    tester,
  ) async {
    _useSurface(tester, const Size(430, 1000));
    await tester.pumpWidget(_bookingTestApp());

    expect(find.text('Book a ride'), findsWidgets);
    expect(find.text('Where are you?'), findsOneWidget);
    expect(find.text('Where to?'), findsOneWidget);
    expect(find.text('How many passengers?'), findsOneWidget);
    expect(find.text('Special request (optional)'), findsOneWidget);
    expect(find.text('Request ride'), findsOneWidget);
    expect(find.byKey(const Key('booking-service-context')), findsNothing);
    expect(find.text('Approved service context'), findsNothing);

    expect(find.byKey(const Key('booking-pickup')), findsOneWidget);
    expect(find.byKey(const Key('booking-destination')), findsOneWidget);
    expect(find.byKey(const Key('booking-assistance')), findsOneWidget);
    expect(find.byKey(const Key('passenger-count-decrease')), findsOneWidget);
    expect(find.byKey(const Key('passenger-count-increase')), findsOneWidget);
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
  });

  testWidgets('keeps empty booking validation in passenger language', (
    tester,
  ) async {
    _useSurface(tester, const Size(430, 1000));
    await tester.pumpWidget(_bookingTestApp());

    await tester.ensureVisible(find.byKey(const Key('request-ride')));
    await tester.tap(find.byKey(const Key('request-ride')));
    await tester.pumpAndSettle();

    expect(find.text('Enter where you are.'), findsOneWidget);
    expect(find.text('Enter where to.'), findsOneWidget);
    expect(find.text('Choose an approved service context.'), findsNothing);
    expect(find.text('No ride request has been sent.'), findsNothing);
  });

  testWidgets('validates locations and completes simplified booking flow', (
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
    expect(find.text('Book a ride'), findsOneWidget);
    expect(find.text('Where are you?'), findsOneWidget);

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

    await tester.tap(find.byKey(const Key('swap-route')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('continue-local-draft')));
    await tester.pumpAndSettle();

    expect(find.text('Book a ride'), findsWidgets);
    expect(find.text('Where are you?'), findsOneWidget);
    expect(find.text('Where to?'), findsOneWidget);
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

    await tester.tap(find.byKey(const Key('passenger-count-increase')));
    await tester.enterText(
      find.byKey(const Key('booking-assistance')),
      'Step-free access',
    );
    await tester.ensureVisible(find.byKey(const Key('request-ride')));
    await tester.tap(find.byKey(const Key('request-ride')));
    await tester.pumpAndSettle();

    expect(find.text('Confirm your ride'), findsWidgets);
    expect(find.text('Pickup'), findsOneWidget);
    expect(find.text('Destination'), findsOneWidget);
    expect(find.text('Passenger count'), findsOneWidget);
    expect(find.text('Payment method'), findsOneWidget);
    expect(find.text('MTN MoMo'), findsOneWidget);
    expect(find.text('Edit details'), findsOneWidget);
    expect(find.text('Confirm and request'), findsOneWidget);
    expect(find.text('Solar Hotel'), findsOneWidget);
    expect(find.text('Accra Airport'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('Step-free access'), findsOneWidget);
    expect(find.text('Service context'), findsNothing);
    expect(find.text('Operating market'), findsNothing);
    expect(find.text('Close draft'), findsNothing);

    await tester.ensureVisible(find.byKey(const Key('edit-booking-details')));
    await tester.tap(find.byKey(const Key('edit-booking-details')));
    await tester.pumpAndSettle();
    expect(find.text('Request ride'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('booking-pickup')))
          .controller!
          .text,
      'Solar Hotel',
    );

    await tester.ensureVisible(find.byKey(const Key('request-ride')));
    await tester.tap(find.byKey(const Key('request-ride')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('confirm-and-request')));
    await tester.tap(find.byKey(const Key('confirm-and-request')));
    await tester.pumpAndSettle();

    expect(find.text('Map preview unavailable.'), findsOneWidget);
    expect(find.text('Book a ride'), findsOneWidget);
    expect(find.text('Where are you?'), findsOneWidget);
    expect(find.text('Where to?'), findsOneWidget);
    expect(find.text('Solar Hotel'), findsNothing);
    expect(find.text('Accra Airport'), findsNothing);
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

    expect(find.text('Book a ride'), findsOneWidget);
    expect(find.text('Where are you?'), findsOneWidget);
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

  testWidgets('removed internal booking wording stays absent', (tester) async {
    _useSurface(tester, const Size(430, 1000));
    await tester.pumpWidget(_bookingTestApp());

    for (final removedText in _removedPassengerTexts) {
      expect(find.text(removedText), findsNothing);
    }

    await tester.enterText(find.byKey(const Key('booking-pickup')), 'Osu');
    await tester.enterText(
      find.byKey(const Key('booking-destination')),
      'Airport',
    );
    await tester.ensureVisible(find.byKey(const Key('request-ride')));
    await tester.tap(find.byKey(const Key('request-ride')));
    await tester.pumpAndSettle();

    for (final removedText in _removedPassengerTexts) {
      expect(find.text(removedText), findsNothing);
    }
    for (final forbiddenText in _noLiveFeatureTexts) {
      expect(find.textContaining(forbiddenText), findsNothing);
    }
  });
}

const _removedPassengerTexts = [
  'Approved service context',
  'LOCAL DEMO',
  'Plan a demo ride',
  'Local draft',
  'local draft',
  'controlled pilot',
  'gh-accra',
  'This stays on this device',
  'No ride request has been sent',
  'Operating market',
  'Service context',
  'Close draft',
  'GHANA PILOT',
  'No ride service is connected',
];

const _noLiveFeatureTexts = [
  'request_reference',
  'Paystack',
  'GPS',
  'GoogleMap',
  'WebSocket',
];

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
