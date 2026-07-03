import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passenger_app/main.dart';
import 'package:passenger_app/passenger_shell.dart';

void main() {
  testWidgets('renders and validates the Passenger phone PIN shell', (
    tester,
  ) async {
    _useSurface(tester, const Size(430, 900));
    await tester.pumpWidget(const PassengerApp(showLoginShell: true));

    expect(find.text('Passenger access'), findsOneWidget);
    expect(find.byKey(const Key('passenger-phone-field')), findsOneWidget);
    expect(find.text('phone number'), findsOneWidget);
    expect(find.byKey(const Key('passenger-pin-field')), findsOneWidget);
    expect(find.text('PIN'), findsOneWidget);
    expect(find.text('Pilot access'), findsOneWidget);
    expect(
      find.text('Enter your phone number and PIN to continue.'),
      findsOneWidget,
    );
    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('Clear form'), findsOneWidget);
    expect(find.text('Create account'), findsNothing);
    expect(find.text('Open public account'), findsNothing);
    expect(find.text('Email'), findsNothing);
    expect(find.text('email'), findsNothing);
    expect(find.text('Password'), findsNothing);
    expect(find.text('password'), findsNothing);

    await tester.tap(find.byKey(const Key('passenger-continue-local-demo')));
    await tester.pumpAndSettle();
    expect(find.text('Phone number cannot be blank.'), findsOneWidget);
    expect(find.text('PIN cannot be blank.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('passenger-phone-field')),
      '0550000000',
    );
    await tester.enterText(
      find.byKey(const Key('passenger-pin-field')),
      '1234',
    );
    await tester.tap(find.byKey(const Key('passenger-clear-form')));
    await tester.pumpAndSettle();
    expect(find.text('0550000000'), findsNothing);
    expect(find.text('1234'), findsNothing);
    expect(find.text('Phone number cannot be blank.'), findsNothing);
    expect(find.text('PIN cannot be blank.'), findsNothing);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('passenger-phone-field')))
          .controller
          ?.text,
      isEmpty,
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('passenger-pin-field')))
          .controller
          ?.text,
      isEmpty,
    );

    await tester.enterText(
      find.byKey(const Key('passenger-phone-field')),
      '0550000000',
    );
    await tester.enterText(
      find.byKey(const Key('passenger-pin-field')),
      '1234',
    );
    await tester.tap(find.byKey(const Key('passenger-continue-local-demo')));
    await tester.pumpAndSettle();

    expect(find.text('ALANTEH'), findsOneWidget);
    expect(find.text('Map preview unavailable.'), findsOneWidget);
    expect(find.text('Book a ride'), findsOneWidget);
    expect(find.text('Where are you?'), findsOneWidget);
    expect(find.text('Where to?'), findsOneWidget);
    expect(find.text('LOCAL DEMO'), findsNothing);
  });

  testWidgets('confirms Passenger login controls do not submit live auth', (
    tester,
  ) async {
    _useSurface(tester, const Size(430, 900));
    await tester.pumpWidget(const PassengerApp(showLoginShell: true));

    expect(find.text('Passenger access'), findsOneWidget);
    expect(find.byKey(const Key('passenger-phone-field')), findsOneWidget);
    expect(find.byKey(const Key('passenger-pin-field')), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('Clear form'), findsOneWidget);
    expect(find.text('Submit credentials'), findsNothing);
    expect(find.text('Login'), findsNothing);
    expect(find.text('Request ride'), findsNothing);
    expect(find.textContaining('api/auth'), findsNothing);
    expect(find.textContaining('token'), findsNothing);
  });

  testWidgets('navigates the simplified passenger shell', (tester) async {
    _useSurface(tester, const Size(430, 900));
    await tester.pumpWidget(const PassengerApp());
    await _openPassengerAccess(tester);

    expect(find.text('ALANTEH'), findsOneWidget);
    expect(find.text('Map preview unavailable.'), findsOneWidget);
    expect(find.text('Book a ride'), findsOneWidget);
    expect(find.text('Where are you?'), findsOneWidget);
    expect(find.text('Where to?'), findsOneWidget);
    expect(find.text('GHANA PILOT'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('continue-local-draft')))
          .onPressed,
      isNull,
    );

    await tester.tap(find.byKey(const Key('choose-pickup')));
    await tester.pumpAndSettle();
    expect(find.text('Choose pickup'), findsWidgets);
    expect(
      find.text('Local description only. No map search is connected.'),
      findsOneWidget,
    );
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('choose-destination')));
    await tester.pumpAndSettle();
    expect(find.text('Where to?'), findsWidgets);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Trips'));
    await tester.pumpAndSettle();
    expect(find.text('No trips connected'), findsOneWidget);
    expect(find.text('LOCAL DEMO'), findsNothing);

    await tester.tap(find.text('Support'));
    await tester.pumpAndSettle();
    expect(find.text('Support not connected'), findsOneWidget);
    expect(find.text('Support is not available yet.'), findsOneWidget);

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.text('Map preview unavailable.'), findsOneWidget);
  });

  testWidgets('map-first Home remains reachable on a small scaled screen', (
    tester,
  ) async {
    _useSurface(tester, const Size(320, 568));

    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: const PassengerShell(),
      ),
    );

    expect(find.text('LOCAL DEMO'), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('choose-pickup')));
    expect(find.byKey(const Key('choose-pickup')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('continue-local-draft')));
    expect(find.byKey(const Key('continue-local-draft')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('passenger shell hides internal and no live feature wording', (
    tester,
  ) async {
    _useSurface(tester, const Size(430, 900));
    await tester.pumpWidget(const PassengerApp());

    for (final removedText in _removedPassengerTexts) {
      expect(find.text(removedText), findsNothing);
    }

    for (final forbiddenText in _noLiveFeatureTexts) {
      expect(find.textContaining(forbiddenText), findsNothing);
    }
  });
}

const _removedPassengerTexts = [
  'ASM PASSENGER',
  'ASM DRIVER',
  'Africa Solar Mobility',
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

Future<void> _openPassengerAccess(WidgetTester tester) async {
  if (find.byKey(const Key('passenger-phone-field')).evaluate().isEmpty) {
    return;
  }

  await tester.enterText(
    find.byKey(const Key('passenger-phone-field')),
    '0550000000',
  );
  await tester.enterText(find.byKey(const Key('passenger-pin-field')), '1234');
  await tester.tap(find.byKey(const Key('passenger-continue-local-demo')));
  await tester.pumpAndSettle();
}

void _useSurface(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
