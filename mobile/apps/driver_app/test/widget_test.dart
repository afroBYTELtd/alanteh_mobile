import 'package:asm_app_config/asm_app_config.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:driver_app/concern/driver_concern_page.dart';
import 'package:driver_app/main.dart';
import 'package:driver_app/readiness/driver_readiness_check.dart';
import 'package:driver_app/ride_offer/driver_ride_offer_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DriverReadinessCheck', () {
    test('starts empty and exposes an unmodifiable set', () {
      final check = DriverReadinessCheck.empty();

      expect(check.completedItems, isEmpty);
      expect(check.completedCount, 0);
      expect(check.isComplete, isFalse);
      expect(
        () =>
            check.completedItems.add(DriverReadinessItem.approvedShiftDetails),
        throwsUnsupportedError,
      );
    });

    test('toggle returns a new value and repeated toggle removes an item', () {
      final original = DriverReadinessCheck.empty();
      final selected = original.toggle(
        DriverReadinessItem.approvedShiftDetails,
      );
      final removed = selected.toggle(DriverReadinessItem.approvedShiftDetails);

      expect(original.completedItems, isEmpty);
      expect(selected.completedCount, 1);
      expect(removed.completedItems, isEmpty);
      expect(identical(original, selected), isFalse);
    });

    test('completion requires all four items and reset is immutable', () {
      final original = DriverReadinessCheck.empty();
      var complete = original;
      for (final item in DriverReadinessItem.values) {
        complete = complete.toggle(item);
      }
      final reset = complete.reset();

      expect(complete.completedCount, 4);
      expect(complete.isComplete, isTrue);
      expect(reset.completedItems, isEmpty);
      expect(reset.isComplete, isFalse);
      expect(complete.completedCount, 4);
      expect(original.completedItems, isEmpty);
    });
  });

  testWidgets('renders and validates the Driver access shell', (tester) async {
    _useSurface(tester, const Size(430, 1000));
    await tester.pumpWidget(const DriverApp(showLoginShell: true));

    expect(find.text('ALANTEH'), findsOneWidget);
    expect(find.byKey(const Key('driver-phone-field')), findsOneWidget);
    expect(find.text('Phone number'), findsOneWidget);
    expect(find.byKey(const Key('driver-pin-field')), findsOneWidget);
    expect(find.text('PIN'), findsOneWidget);
    expect(find.text('Driver access'), findsOneWidget);
    expect(
      find.text('Enter your phone number and PIN to continue.'),
      findsOneWidget,
    );
    expect(find.text('Continue without signing in'), findsOneWidget);
    expect(find.text('Clear form'), findsOneWidget);
    expect(find.text('Create account'), findsNothing);
    expect(find.text('Open public account'), findsNothing);
    expect(find.text('Email'), findsNothing);
    expect(find.text('email'), findsNothing);
    expect(find.text('Password'), findsNothing);
    expect(find.text('password'), findsNothing);

    await tester.tap(find.byKey(const Key('driver-continue-local-demo')));
    await tester.pumpAndSettle();
    expect(find.text('Phone number cannot be blank.'), findsOneWidget);
    expect(find.text('PIN cannot be blank.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('driver-phone-field')),
      '0550000000',
    );
    await tester.enterText(find.byKey(const Key('driver-pin-field')), '1234');
    await tester.tap(find.byKey(const Key('driver-clear-form')));
    await tester.pumpAndSettle();
    expect(find.text('0550000000'), findsNothing);
    expect(find.text('1234'), findsNothing);
    expect(find.text('Phone number cannot be blank.'), findsNothing);
    expect(find.text('PIN cannot be blank.'), findsNothing);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('driver-phone-field')))
          .controller
          ?.text,
      isEmpty,
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('driver-pin-field')))
          .controller
          ?.text,
      isEmpty,
    );

    await tester.enterText(
      find.byKey(const Key('driver-phone-field')),
      '0550000000',
    );
    await tester.enterText(find.byKey(const Key('driver-pin-field')), '1234');
    await tester.tap(find.byKey(const Key('driver-continue-local-demo')));
    await tester.pumpAndSettle();

    expect(find.text('ALANTEH'), findsOneWidget);
    expect(find.text('Off shift'), findsOneWidget);
    expect(find.text('Approved drivers only'), findsOneWidget);
  });

  testWidgets('navigates the configured approved-driver field shell', (
    tester,
  ) async {
    await tester.pumpWidget(
      const DriverApp(configuration: AsmAppConfig.localGhana),
    );
    await _openDriverLocalDemo(tester);

    expect(find.text('ALANTEH'), findsOneWidget);
    expect(find.text('Field workspace'), findsOneWidget);
    expect(find.text('Approved drivers only'), findsOneWidget);
    expect(find.text('Off shift'), findsOneWidget);
    expect(find.text('Accra, Ghana'), findsOneWidget);
    expect(find.text('Map coming soon'), findsOneWidget);
    expect(find.text('No trips yet'), findsOneWidget);
    expect(find.text('Start shift check'), findsOneWidget);
    expect(find.text('Report an issue'), findsOneWidget);
    expect(find.text('New trip'), findsWidgets);
    expect(find.byKey(const Key('open-ride-offer-preview')), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      0,
    );

    await tester.tap(find.text('Trips'));
    await tester.pumpAndSettle();
    expect(find.text('No trips yet'), findsOneWidget);
    expect(find.text('Trip assignments will appear here.'), findsOneWidget);
    expect(find.text('Earnings'), findsNothing);

    await tester.tap(find.text('Support'));
    await tester.pumpAndSettle();
    expect(find.text('Support not connected'), findsOneWidget);
    expect(find.text('Support is not available yet.'), findsOneWidget);

    await tester.tap(find.text('Work'));
    await tester.pumpAndSettle();
    expect(find.text('Approved drivers only'), findsOneWidget);
    expect(find.text('Map coming soon'), findsOneWidget);
  });

  testWidgets('Driver shell exposes existing field areas', (tester) async {
    _useSurface(tester, const Size(430, 1000));
    await tester.pumpWidget(const DriverApp());
    await _openDriverLocalDemo(tester);

    expect(find.byKey(const Key('open-readiness')), findsOneWidget);
    expect(find.byKey(const Key('open-concern')), findsOneWidget);
    expect(find.byKey(const Key('open-ride-offer-preview')), findsOneWidget);

    await tester.tap(find.byKey(const Key('open-readiness')));
    await tester.pumpAndSettle();
    expect(find.text('Shift check'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('open-concern')));
    await tester.pumpAndSettle();
    expect(find.text('Report an issue'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await _openRideOfferPreview(tester);
    await tester.pumpAndSettle();
    expect(find.text('New trip'), findsWidgets);
    _expectNoOperationalActions();
  });

  testWidgets('completes, resets, closes, and reopens the shift check', (
    tester,
  ) async {
    _useSurface(tester, const Size(430, 1000));
    await tester.pumpWidget(const DriverApp());
    await _openDriverLocalDemo(tester);

    await tester.tap(find.byKey(const Key('open-readiness')));
    await tester.pumpAndSettle();

    expect(find.text('Shift check'), findsOneWidget);
    expect(find.text('Accra, Ghana'), findsOneWidget);
    expect(find.text('Complete these checks before driving.'), findsOneWidget);
    for (final item in DriverReadinessItem.values) {
      expect(find.text(item.label), findsOneWidget);
    }
    expect(find.text('0 of 4 checks complete'), findsOneWidget);

    await tester.tap(find.byKey(const Key('readiness-approvedShiftDetails')));
    await tester.tap(find.byKey(const Key('readiness-vehicleExterior')));
    await tester.pumpAndSettle();
    expect(find.text('2 of 4 checks complete'), findsOneWidget);

    await tester.tap(find.byKey(const Key('readiness-cabinSafety')));
    await tester.tap(find.byKey(const Key('readiness-batteryStatus')));
    await tester.pumpAndSettle();
    expect(find.text('4 of 4 checks complete'), findsOneWidget);
    expect(find.text('Shift check complete'), findsOneWidget);
    expect(
      find.text('Review your vehicle and route before starting work.'),
      findsOneWidget,
    );
    _expectNoOperationalActions();

    await tester.ensureVisible(find.byKey(const Key('reset-readiness')));
    await tester.tap(find.byKey(const Key('reset-readiness')));
    await tester.pumpAndSettle();
    expect(find.text('0 of 4 checks complete'), findsOneWidget);
    expect(find.text('Shift check complete'), findsNothing);

    await tester.tap(find.byKey(const Key('readiness-approvedShiftDetails')));
    await tester.pumpAndSettle();
    expect(find.text('1 of 4 checks complete'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Approved drivers only'), findsOneWidget);

    await tester.tap(find.byKey(const Key('open-readiness')));
    await tester.pumpAndSettle();
    expect(find.text('0 of 4 checks complete'), findsOneWidget);
    expect(find.text('Report an issue'), findsOneWidget);
  });

  testWidgets('validates, reviews, edits, closes, and resets a concern draft', (
    tester,
  ) async {
    _useSurface(tester, const Size(430, 1000));
    await tester.pumpWidget(const DriverApp());
    await _openDriverLocalDemo(tester);

    await tester.tap(find.byKey(const Key('open-concern')));
    await tester.pumpAndSettle();
    expect(find.text('Report an issue'), findsOneWidget);
    expect(find.text('Accra, Ghana'), findsOneWidget);
    expect(
      find.text(
        'This report is not sent from the app yet. For emergencies, follow approved local safety procedures.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'If there is immediate danger, do not drive and follow approved local safety procedures.',
      ),
      findsOneWidget,
    );

    await _scrollToConcernReview(tester);
    await tester.tap(find.byKey(const Key('review-concern')));
    await tester.pumpAndSettle();
    expect(find.text('Choose what the issue is.'), findsOneWidget);
    expect(find.text('Choose how urgent this is.'), findsOneWidget);
    expect(find.text('Describe the issue.'), findsOneWidget);

    await _completeConcernForm(tester, description: '  Loose mirror  ');
    expect(find.text('No issue report has been sent.'), findsOneWidget);
    expect(find.text('Operating market'), findsOneWidget);
    expect(find.byKey(const Key('concern-market')), findsOneWidget);
    expect(find.text('Vehicle'), findsOneWidget);
    expect(find.text('Urgent'), findsOneWidget);
    expect(find.text('Loose mirror'), findsOneWidget);
    _expectNoOperationalActions();

    await tester.tap(find.byKey(const Key('edit-concern')));
    await tester.pumpAndSettle();
    final descriptionField = tester.widget<TextFormField>(
      find.byKey(const Key('concern-description')),
    );
    expect(descriptionField.controller!.text, '  Loose mirror  ');

    await _scrollToConcernReview(tester);
    await tester.tap(find.byKey(const Key('review-concern')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('close-concern')));
    await tester.pumpAndSettle();
    expect(find.text('Approved drivers only'), findsOneWidget);

    await tester.tap(find.byKey(const Key('open-concern')));
    await tester.pumpAndSettle();
    final reopenedField = tester.widget<TextFormField>(
      find.byKey(const Key('concern-description')),
    );
    expect(reopenedField.controller!.text, isEmpty);
    expect(find.text('No issue report has been sent.'), findsNothing);
    await tester.enterText(
      find.byKey(const Key('concern-description')),
      'x' * 241,
    );
    expect(reopenedField.controller!.text.length, 240);
  });

  testWidgets('concern flow preserves readiness without completing it', (
    tester,
  ) async {
    _useSurface(tester, const Size(430, 1000));
    await tester.pumpWidget(const DriverApp());
    await _openDriverLocalDemo(tester);

    await tester.tap(find.byKey(const Key('open-readiness')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('readiness-approvedShiftDetails')));
    await tester.pumpAndSettle();
    expect(find.text('1 of 4 checks complete'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('readiness-open-concern')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const Key('readiness-open-concern')));
    await tester.pumpAndSettle();
    await _completeConcernForm(tester, description: 'Battery warning noted');
    await tester.tap(find.byKey(const Key('close-concern')));
    await tester.pumpAndSettle();

    expect(find.text('Shift check'), findsOneWidget);
    expect(find.text('1 of 4 checks complete'), findsOneWidget);
    expect(find.text('Shift check complete'), findsNothing);
    expect(find.text('Report an issue'), findsOneWidget);
  });

  testWidgets('accepts a trip screen decision, closes, and reopens pending', (
    tester,
  ) async {
    _useSurface(tester, const Size(430, 1000));
    await tester.pumpWidget(const DriverApp());
    await _openDriverLocalDemo(tester);

    expect(find.byKey(const Key('open-ride-offer-preview')), findsOneWidget);
    await _openRideOfferPreview(tester);
    await tester.pumpAndSettle();

    _expectPendingRideOffer();
    await tester.tap(find.byKey(const Key('accept-ride-offer-preview')));
    await tester.pumpAndSettle();
    expect(find.text('Accepted'), findsWidgets);
    expect(find.text('Trip marked accepted on this screen.'), findsOneWidget);
    expect(find.text('Accept'), findsNothing);
    expect(find.text('Decline'), findsNothing);
    _expectNoRideOfferLiveContent();

    await tester.tap(find.byKey(const Key('close-ride-offer-preview')));
    await tester.pumpAndSettle();
    expect(find.text('Approved drivers only'), findsOneWidget);

    await _openRideOfferPreview(tester);
    await tester.pumpAndSettle();
    _expectPendingRideOffer();
    expect(find.text('Accepted'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Trips'));
    await tester.pumpAndSettle();
    expect(find.text('No trips yet'), findsOneWidget);
    expect(find.text('Trip assignments will appear here.'), findsOneWidget);
  });

  testWidgets('declines a trip screen decision and returns to Driver Home', (
    tester,
  ) async {
    _useSurface(tester, const Size(430, 1000));
    await tester.pumpWidget(const DriverApp());
    await _openDriverLocalDemo(tester);

    await _openRideOfferPreview(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('decline-ride-offer-preview')));
    await tester.pumpAndSettle();

    expect(find.text('Declined'), findsWidgets);
    expect(find.text('Trip marked declined on this screen.'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
    _expectNoRideOfferLiveContent();

    await tester.tap(find.byKey(const Key('close-ride-offer-preview')));
    await tester.pumpAndSettle();
    expect(find.text('Approved drivers only'), findsOneWidget);
    expect(find.byKey(const Key('open-readiness')), findsOneWidget);
    expect(find.byKey(const Key('open-concern')), findsOneWidget);
  });

  testWidgets('driver screens hide old brand and internal marker wording', (
    tester,
  ) async {
    _useSurface(tester, const Size(430, 1000));
    await tester.pumpWidget(const DriverApp(showLoginShell: true));

    for (final removedText in _removedDriverTexts) {
      expect(find.text(removedText), findsNothing);
    }

    await _openDriverLocalDemo(tester);
    for (final removedText in _removedDriverTexts) {
      expect(find.text(removedText), findsNothing);
    }
  });

  testWidgets('ride screen remains reachable on a small scaled screen', (
    tester,
  ) async {
    _useSurface(tester, const Size(320, 568));
    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.driver,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: const DriverRideOfferPage(market: MarketConfig.ghanaAccra),
      ),
    );

    expect(find.text('New trip'), findsWidgets);
    await tester.scrollUntilVisible(
      find.byKey(const Key('decline-ride-offer-preview')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.byKey(const Key('decline-ride-offer-preview')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('issue form remains reachable on a small scaled screen', (
    tester,
  ) async {
    _useSurface(tester, const Size(320, 568));
    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.driver,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: const DriverConcernPage(market: MarketConfig.ghanaAccra),
      ),
    );

    expect(find.text('Report an issue'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('review-concern')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('review-concern')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('readiness remains reachable on a small scaled screen', (
    tester,
  ) async {
    _useSurface(tester, const Size(320, 568));
    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.driver,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: const DriverShell(),
      ),
    );

    await tester.ensureVisible(find.byKey(const Key('open-readiness')));
    await tester.tap(find.byKey(const Key('open-readiness')));
    await tester.pumpAndSettle();
    expect(find.text('Shift check'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('readiness-batteryStatus')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.byKey(const Key('readiness-batteryStatus')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('reset-readiness')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.byKey(const Key('reset-readiness')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

const _removedDriverTexts = [
  'ASM DRIVER',
  'ASM PASSENGER',
  'Africa Solar Mobility',
  'LOCAL DEMO',
  'local demo',
  'ASM_DRIVER_APP_AUTOMATION_ACTIVE',
  'No live trips engineering warning',
  'No real offer',
  'demo preview',
  'Pre-shift readiness check',
  'Submit readiness',
  'Incoming ride offer',
  'Accept offer',
  'Report a vehicle concern',
  'Attention level',
  'Submit concern',
];

void _expectNoOperationalActions() {
  for (final label in [
    'Start Shift',
    'Go Online',
    'Accept Trip',
    'Submit',
    'Earnings',
    'Pay',
    'Send',
    'Notify operations',
    'Call support',
    'Upload',
  ]) {
    expect(find.text(label), findsNothing);
  }
}

void _expectPendingRideOffer() {
  expect(find.text('New trip'), findsWidgets);
  expect(find.text('Accra, Ghana'), findsOneWidget);
  expect(find.text('Review the route before accepting.'), findsOneWidget);
  expect(find.text('Airport connection'), findsOneWidget);
  expect(find.text('Solar Hotel'), findsOneWidget);
  expect(find.text('Accra Airport'), findsOneWidget);
  expect(find.text('Passengers'), findsOneWidget);
  expect(find.text('2'), findsOneWidget);
  expect(find.text('Accept'), findsOneWidget);
  expect(find.text('Decline'), findsOneWidget);
  _expectNoRideOfferLiveContent();
}

void _expectNoRideOfferLiveContent() {
  for (final label in [
    'Fare',
    'Earnings',
    'Customer name',
    'Phone number',
    'Map',
    'Active Assignment',
    'Enable Notifications',
    'Allow Notifications',
  ]) {
    expect(find.text(label), findsNothing);
  }
}

Future<void> _openDriverLocalDemo(WidgetTester tester) async {
  if (find.byKey(const Key('driver-phone-field')).evaluate().isEmpty) {
    return;
  }

  await tester.enterText(
    find.byKey(const Key('driver-phone-field')),
    '0550000000',
  );
  await tester.enterText(find.byKey(const Key('driver-pin-field')), '1234');
  await tester.tap(find.byKey(const Key('driver-continue-local-demo')));
  await tester.pumpAndSettle();
}

Future<void> _openRideOfferPreview(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.byKey(const Key('open-ride-offer-preview')),
    200,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.tap(find.byKey(const Key('open-ride-offer-preview')));
}

Future<void> _completeConcernForm(
  WidgetTester tester, {
  required String description,
}) async {
  await tester.tap(find.byKey(const Key('concern-category')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Vehicle').last);
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(const Key('concern-attention')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Urgent').last);
  await tester.pumpAndSettle();

  await tester.enterText(
    find.byKey(const Key('concern-description')),
    description,
  );
  await _scrollToConcernReview(tester);
  await tester.tap(find.byKey(const Key('review-concern')));
  await tester.pumpAndSettle();
}

Future<void> _scrollToConcernReview(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.byKey(const Key('review-concern')),
    200,
    scrollable: find.byType(Scrollable).last,
  );
}

void _useSurface(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
