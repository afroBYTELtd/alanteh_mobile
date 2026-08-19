import 'package:asm_app_config/asm_app_config.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:driver_app/concern/driver_concern_page.dart';
import 'package:driver_app/network/driver_report_gateway.dart';
import 'package:driver_app/trip_progress/driver_trip_visual_sequence.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('concern form sends report and shows backend receipt', (
    tester,
  ) async {
    _useSurface(tester);
    final gateway = _Mux5aDriverReportGateway();

    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.driver,
        home: DriverConcernPage(
          market: MarketConfig.ghanaAccra,
          gateway: gateway,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Report an issue'), findsOneWidget);
    expect(find.text("What's the issue?"), findsOneWidget);
    expect(
      find.text('Select a category so ALANTEH can respond appropriately.'),
      findsOneWidget,
    );
    expect(find.text('Send'), findsOneWidget);
    expect(find.text('Review report'), findsNothing);
    expect(find.text('Continue without sending'), findsNothing);

    await tester.tap(find.byKey(const Key('concern-category')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vehicle concern').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('concern-attention')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Urgent').last);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('concern-description')),
      'Battery draining fast',
    );

    await tester.ensureVisible(find.byKey(const Key('send-concern')));
    await tester.tap(find.byKey(const Key('send-concern')));
    await tester.pumpAndSettle();

    expect(gateway.categoryCalls, 1);
    expect(gateway.submitCalls, 1);
    expect(gateway.submittedCategory, 'Vehicle concern');
    expect(gateway.submittedDescription, 'Battery draining fast');
    expect(gateway.submittedUrgency, 'urgent');

    expect(find.byKey(const Key('concern-submitted')), findsOneWidget);
    expect(find.text('Report sent'), findsWidgets);
    expect(find.text('Your report has been received.'), findsOneWidget);
    expect(find.text('RPT-MUX5A00001'), findsOneWidget);
    expect(find.text('Back to home'), findsOneWidget);
    expect(find.text('Continue without sending'), findsNothing);
  });

  testWidgets('trip-completed detail uses the polished review wording', (
    tester,
  ) async {
    _useSurface(tester);

    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.driver,
        home: const DriverTripVisualSequencePage(
          pickupLocation: 'Accra Mall',
          destination: 'Kotoka International Airport',
          passengerCount: 1,
        ),
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
    expect(
      find.text('Accra Mall → Kotoka International Airport'),
      findsOneWidget,
    );
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

final class _Mux5aDriverReportGateway implements DriverReportGateway {
  int categoryCalls = 0;
  int submitCalls = 0;
  String? submittedCategory;
  String? submittedDescription;
  String? submittedUrgency;

  @override
  Future<List<String>> fetchCategories({bool forceRefresh = false}) async {
    categoryCalls += 1;
    return const <String>[
      'Vehicle concern',
      'Safety issue',
      'Route issue',
      'Passenger concern',
      'Other',
    ];
  }

  @override
  Future<DriverReportReceipt> submit({
    required String category,
    required String description,
    required String urgency,
  }) async {
    submitCalls += 1;
    submittedCategory = category;
    submittedDescription = description;
    submittedUrgency = urgency;

    return const DriverReportReceipt(
      reportReference: 'RPT-MUX5A00001',
      status: 'received',
    );
  }

  @override
  void clearSessionCache() {}
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
