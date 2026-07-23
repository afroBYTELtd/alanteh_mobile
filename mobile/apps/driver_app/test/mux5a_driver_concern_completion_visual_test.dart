import 'package:asm_app_config/asm_app_config.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:driver_app/concern/driver_concern_page.dart';
import 'package:driver_app/trip_progress/driver_trip_visual_sequence.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('concern form reviews an explicitly unsent local draft', (
    tester,
  ) async {
    _useSurface(tester);

    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.driver,
        home: const DriverConcernPage(market: MarketConfig.ghanaAccra),
      ),
    );

    expect(find.text('Report an issue'), findsOneWidget);
    expect(find.text("What's the issue?"), findsOneWidget);
    expect(
      find.text('Select a category so ALANTEH can respond appropriately.'),
      findsOneWidget,
    );
    expect(find.text('Submit report'), findsOneWidget);

    await tester.tap(find.byKey(const Key('concern-category')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vehicle problem').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('concern-attention')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Urgent').last);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('concern-description')),
      'Battery draining fast',
    );

    await tester.ensureVisible(find.byKey(const Key('review-concern')));
    await tester.tap(find.byKey(const Key('review-concern')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('concern-review')), findsOneWidget);
    expect(find.text('Review report'), findsWidgets);
    expect(find.text('Review this local draft'), findsOneWidget);
    expect(find.text('Vehicle problem'), findsOneWidget);
    expect(find.text('Battery draining fast'), findsOneWidget);
    expect(find.text('Continue without sending'), findsOneWidget);
    expect(find.byKey(const Key('concern-market')), findsOneWidget);
    expect(find.byKey(const Key('concern-review-market')), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);

    await tester.tap(find.byKey(const Key('edit-concern')));
    await tester.pumpAndSettle();

    final description = tester.widget<TextFormField>(
      find.byKey(const Key('concern-description')),
    );

    expect(description.controller?.text, 'Battery draining fast');

    await tester.ensureVisible(find.byKey(const Key('review-concern')));
    await tester.tap(find.byKey(const Key('review-concern')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('confirm-concern')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('concern-submitted')), findsOneWidget);
    expect(find.text('Report not sent'), findsWidgets);
    expect(
      find.text(
        'This report is not sent from the app yet. '
        'Use an approved contact channel if operations follow-up '
        'is required.',
      ),
      findsOneWidget,
    );
    expect(find.text('Back to home'), findsOneWidget);
  });

  testWidgets('trip-completed detail uses the polished review wording', (
    tester,
  ) async {
    _useSurface(tester);

    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.driver,
        home: const DriverTripVisualSequencePage(),
      ),
    );
    await tester.pump();

    await _tapVisible(
      tester,
      find.byKey(const Key('driver-mark-arrived-pickup')),
    );
    await _tapVisible(
      tester,
      find.byKey(const Key('driver-open-onboard-confirmation')),
    );
    await _tapVisible(tester, find.byKey(const Key('driver-confirm-onboard')));
    await _tapVisible(
      tester,
      find.byKey(const Key('driver-mark-arrived-destination')),
    );
    await _tapVisible(tester, find.byKey(const Key('driver-complete-trip')));

    expect(find.byKey(const Key('driver-trip-completed')), findsOneWidget);
    expect(
      find.text('Trip completed — awaiting operations review'),
      findsWidgets,
    );
    expect(find.text('Awaiting operations review'), findsOneWidget);
    expect(find.text('Accra Mall → Accra Market'), findsOneWidget);
    expect(find.text('9.5 km'), findsOneWidget);
    expect(find.text('23 min'), findsOneWidget);
    expect(
      find.text(
        'Completion is not confirmed until ALANTEH operations reviews the trip.',
      ),
      findsOneWidget,
    );
    expect(find.text('Back to home'), findsOneWidget);
  });
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
}

void _useSurface(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(430, 1000);

  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });
}
