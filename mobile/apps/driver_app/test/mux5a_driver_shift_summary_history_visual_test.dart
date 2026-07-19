import 'package:asm_design_system/asm_design_system.dart';
import 'package:driver_app/driver_shell.dart';
import 'package:driver_app/shift/driver_shift_history.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _currentShift = DriverShiftRecord(
  id: 'today',
  dateLabel: 'Today, Tuesday',
  dutyLabel: 'Online',
  status: DriverShiftStatus.inProgress,
  onlineDurationLabel: 'In progress',
  completedTrips: 1,
  vehicleLabel: 'GR 4471-24 · ALANTEH Solar EV',
  serviceAreaLabel: 'Accra',
);

const _mondayShift = DriverShiftRecord(
  id: 'monday',
  dateLabel: 'Monday',
  dutyLabel: 'Online',
  status: DriverShiftStatus.completed,
  onlineDurationLabel: '6h 40m',
  completedTrips: 9,
  vehicleLabel: 'GR 4471-24 · ALANTEH Solar EV',
  serviceAreaLabel: 'Accra',
);

const _saturdayShift = DriverShiftRecord(
  id: 'saturday',
  dateLabel: 'Saturday',
  dutyLabel: 'Online',
  status: DriverShiftStatus.completed,
  onlineDurationLabel: '5h 05m',
  completedTrips: 7,
  vehicleLabel: 'GR 4471-24 · ALANTEH Solar EV',
  serviceAreaLabel: 'Accra',
);

void main() {
  testWidgets('shift summary shows approved safe read-only fields', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        const DriverShiftSummaryPage(
          currentShift: _currentShift,
          completedShifts: <DriverShiftRecord>[_mondayShift, _saturdayShift],
        ),
      ),
    );

    expect(
      find.byKey(const Key('driver-shift-summary-screen')),
      findsOneWidget,
    );
    expect(find.text('Shift summary'), findsOneWidget);
    expect(find.text('Current shift'), findsOneWidget);
    expect(find.text('Today, Tuesday'), findsOneWidget);
    expect(find.text('Online'), findsOneWidget);
    expect(find.text('In progress'), findsNWidgets(2));
    expect(find.text('Online time'), findsOneWidget);
    expect(find.text('1 so far'), findsOneWidget);
    expect(find.text('GR 4471-24 · ALANTEH Solar EV'), findsOneWidget);
    expect(find.text('Accra'), findsOneWidget);
    expect(find.byKey(const Key('open-shift-history')), findsOneWidget);

    _expectNoDriverMoneyWording(tester);
  });

  testWidgets('shift history matches approved current and completed records', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        const DriverShiftHistoryPage(
          currentShift: _currentShift,
          completedShifts: <DriverShiftRecord>[_mondayShift, _saturdayShift],
        ),
      ),
    );

    expect(
      find.byKey(const Key('driver-shift-history-screen')),
      findsOneWidget,
    );
    expect(find.text('Shift history'), findsOneWidget);
    expect(find.text('Today, Tuesday'), findsOneWidget);
    expect(find.text('1 so far'), findsOneWidget);
    expect(find.text('Monday'), findsOneWidget);
    expect(find.text('6h 40m'), findsOneWidget);
    expect(find.text('9 completed'), findsOneWidget);
    expect(find.text('Saturday'), findsOneWidget);
    expect(find.text('5h 05m'), findsOneWidget);
    expect(find.text('7 completed'), findsOneWidget);

    _expectNoDriverMoneyWording(tester);
  });

  testWidgets('completed shift record opens a read-only detail screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        const DriverShiftHistoryPage(
          currentShift: _currentShift,
          completedShifts: <DriverShiftRecord>[_mondayShift],
        ),
      ),
    );

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('driver-shift-record-monday')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('driver-shift-record-monday')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('driver-shift-detail-screen')), findsOneWidget);
    expect(find.text('Shift detail'), findsOneWidget);
    expect(find.text('Monday'), findsOneWidget);
    expect(find.text('Completed'), findsWidgets);
    expect(find.text('6h 40m'), findsOneWidget);
    expect(find.text('9'), findsOneWidget);
    expect(find.text('GR 4471-24 · ALANTEH Solar EV'), findsOneWidget);
    expect(find.text('Accra'), findsOneWidget);

    _expectNoDriverMoneyWording(tester);
  });

  testWidgets('shift history has an honest empty state', (tester) async {
    await tester.pumpWidget(_testApp(const DriverShiftHistoryPage()));

    expect(find.byKey(const Key('driver-shift-history-empty')), findsOneWidget);
    expect(find.text('No shift history yet'), findsOneWidget);
    expect(
      find.text('Completed shifts will appear here after they are recorded.'),
      findsOneWidget,
    );

    _expectNoDriverMoneyWording(tester);
  });

  testWidgets('Driver Home and Account open summary and history', (
    tester,
  ) async {
    await tester.pumpWidget(_testApp(const DriverShell()));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('driver-home-open-shift-summary')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const Key('driver-home-open-shift-summary')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('driver-shift-summary-screen')),
      findsOneWidget,
    );
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Not started'), findsWidgets);

    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Account'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('driver-account-screen')), findsOneWidget);
    expect(find.text('Driver account'), findsOneWidget);
    expect(find.text('Assigned vehicle'), findsOneWidget);
    expect(find.text('Shift history'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const Key('driver-account-open-shift-history')),
    );
    await tester.tap(
      find.byKey(const Key('driver-account-open-shift-history')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('driver-shift-history-screen')),
      findsOneWidget,
    );
    expect(find.text('Today'), findsOneWidget);
    expect(
      find.byKey(const Key('driver-shift-history-completed-empty')),
      findsOneWidget,
    );

    _expectNoDriverMoneyWording(tester);
  });
}

Widget _testApp(Widget home) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AsmThemes.driver,
    home: home,
  );
}

void _expectNoDriverMoneyWording(WidgetTester tester) {
  final visibleText = tester
      .widgetList<Text>(find.byType(Text))
      .map((widget) => widget.data ?? widget.textSpan?.toPlainText() ?? '')
      .join(' ')
      .toLowerCase();

  for (final prohibited in <String>[
    'fare',
    'earning',
    'commission',
    'payout',
    'wallet',
    'surge',
    'income',
    'payroll',
  ]) {
    expect(visibleText, isNot(contains(prohibited)));
  }
}
