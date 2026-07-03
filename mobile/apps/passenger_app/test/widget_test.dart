import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passenger_app/main.dart';
import 'package:passenger_app/passenger_shell.dart';

void main() {
  testWidgets('renders and validates the Passenger local demo login shell', (
    tester,
  ) async {
    _useSurface(tester, const Size(430, 900));
    await tester.pumpWidget(const PassengerApp(showLoginShell: true));

    expect(find.text('Passenger login shell'), findsOneWidget);
    expect(find.byKey(const Key('passenger-phone-field')), findsOneWidget);
    expect(find.text('phone number'), findsOneWidget);
    expect(find.byKey(const Key('passenger-pin-field')), findsOneWidget);
    expect(find.text('PIN'), findsOneWidget);
    expect(find.text('Local demo only'), findsOneWidget);
    expect(
      find.text(
        'Live login will connect after Control Center auth API is ready',
      ),
      findsOneWidget,
    );
    expect(find.text('Continue local demo'), findsOneWidget);
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

    expect(find.text('ASM PASSENGER'), findsOneWidget);
    expect(find.text('LOCAL DEMO'), findsOneWidget);
    expect(
      find.text('Map preview unavailable in this local demo.'),
      findsOneWidget,
    );
  });

  testWidgets('confirms Passenger login controls are local demo only', (
    tester,
  ) async {
    _useSurface(tester, const Size(430, 900));
    await tester.pumpWidget(const PassengerApp(showLoginShell: true));

    expect(find.text('Passenger login shell'), findsOneWidget);
    expect(find.byKey(const Key('passenger-phone-field')), findsOneWidget);
    expect(find.byKey(const Key('passenger-pin-field')), findsOneWidget);
    expect(find.text('Continue local demo'), findsOneWidget);
    expect(find.text('Clear form'), findsOneWidget);
    expect(
      find.textContaining('Live login will connect after'),
      findsOneWidget,
    );
    expect(find.text('Submit credentials'), findsNothing);
    expect(find.text('Login'), findsNothing);
    expect(find.text('Request ride'), findsNothing);
  });

  testWidgets('navigates the map-first controlled Ghana passenger shell', (
    tester,
  ) async {
    _useSurface(tester, const Size(430, 900));
    await tester.pumpWidget(const PassengerApp());
    await _openPassengerLocalDemo(tester);

    expect(find.text('ASM PASSENGER'), findsOneWidget);
    expect(find.text('LOCAL DEMO'), findsOneWidget);
    expect(
      find.text('Map preview unavailable in this local demo.'),
      findsOneWidget,
    );
    expect(find.text('Choose pickup'), findsOneWidget);
    expect(find.text('Where to?'), findsOneWidget);
    expect(find.textContaining('GHANA PILOT'), findsOneWidget);
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
    expect(find.text('LOCAL DEMO'), findsOneWidget);

    await tester.tap(find.text('Support'));
    await tester.pumpAndSettle();
    expect(find.text('Support not connected'), findsOneWidget);

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(
      find.text('Map preview unavailable in this local demo.'),
      findsOneWidget,
    );
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

    expect(find.text('LOCAL DEMO'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('choose-pickup')));
    expect(find.byKey(const Key('choose-pickup')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('continue-local-draft')));
    expect(find.byKey(const Key('continue-local-draft')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _openPassengerLocalDemo(WidgetTester tester) async {
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
