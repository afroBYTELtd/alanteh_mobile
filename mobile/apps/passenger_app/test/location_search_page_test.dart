import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passenger_app/location/location_search_page.dart';

void main() {
  testWidgets('renders location search input for local descriptions only', (
    tester,
  ) async {
    await tester.pumpWidget(_pageApp(kind: LocationSearchKind.pickup));

    expect(find.text('Choose pickup'), findsWidgets);
    expect(find.byKey(const Key('location-market-context')), findsOneWidget);
    expect(find.text('Accra, Ghana'), findsOneWidget);
    expect(find.byKey(const Key('location-description')), findsOneWidget);
    expect(find.text('Use this location description'), findsOneWidget);
    expect(
      find.text('Local description only. No map search is connected.'),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const Key('location-description')),
      'Osu local pickup point',
    );

    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('location-description')))
          .controller!
          .text,
      'Osu local pickup point',
    );
    expect(find.text('GPS'), findsNothing);
    expect(find.text('GoogleMap'), findsNothing);
  });

  testWidgets('rejects a blank local description', (tester) async {
    await tester.pumpWidget(_pageApp(kind: LocationSearchKind.pickup));

    expect(find.text('Choose pickup'), findsWidgets);
    expect(
      find.text('Local description only. No map search is connected.'),
      findsOneWidget,
    );
    expect(find.text('Recent this session'), findsNothing);
    await tester.enterText(
      find.byKey(const Key('location-description')),
      '   ',
    );
    await tester.tap(find.byKey(const Key('use-location-description')));
    await tester.pumpAndSettle();

    expect(find.text('Enter a location description.'), findsOneWidget);
  });

  testWidgets('shows recent entries and returns a selected description', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: const _SearchHarness(
          recentDescriptions: ['Accra Airport', 'Solar Hotel'],
        ),
      ),
    );
    await tester.tap(find.text('Open destination search'));
    await tester.pumpAndSettle();

    expect(find.text('Recent this session'), findsOneWidget);
    expect(find.byKey(const ValueKey('recent-location-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('recent-location-1')), findsOneWidget);
    expect(find.text('Accra Airport'), findsOneWidget);
    expect(find.text('Solar Hotel'), findsOneWidget);

    await tester.tap(find.text('Solar Hotel'));
    await tester.pumpAndSettle();

    expect(find.text('Result: Solar Hotel'), findsOneWidget);
  });

  testWidgets('trims and returns an accepted description', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AsmThemes.passenger, home: const _SearchHarness()),
    );
    await tester.tap(find.text('Open destination search'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('location-description')),
      '  Accra Airport  ',
    );
    await tester.tap(find.byKey(const Key('use-location-description')));
    await tester.pumpAndSettle();

    expect(find.text('Result: Accra Airport'), findsOneWidget);
  });

  testWidgets('preserves initial text and limits input to 160 characters', (
    tester,
  ) async {
    await tester.pumpWidget(
      _pageApp(
        kind: LocationSearchKind.destination,
        initialDescription: 'Previous destination',
      ),
    );

    final field = tester.widget<TextFormField>(
      find.byKey(const Key('location-description')),
    );
    expect(field.controller!.text, 'Previous destination');

    await tester.enterText(
      find.byKey(const Key('location-description')),
      List.filled(180, 'a').join(),
    );
    expect(field.controller!.text.length, 160);
  });
}

Widget _pageApp({
  required LocationSearchKind kind,
  String? initialDescription,
}) {
  return MaterialApp(
    theme: AsmThemes.passenger,
    home: LocationSearchPage(
      kind: kind,
      initialDescription: initialDescription,
    ),
  );
}

class _SearchHarness extends StatefulWidget {
  const _SearchHarness({this.recentDescriptions = const []});

  final List<String> recentDescriptions;

  @override
  State<_SearchHarness> createState() => _SearchHarnessState();
}

class _SearchHarnessState extends State<_SearchHarness> {
  String? _result;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Result: ${_result ?? 'none'}'),
            FilledButton(
              onPressed: () async {
                final result = await Navigator.of(context).push<String>(
                  MaterialPageRoute<String>(
                    builder: (_) => LocationSearchPage(
                      kind: LocationSearchKind.destination,
                      recentDescriptions: widget.recentDescriptions,
                    ),
                  ),
                );
                if (result != null && mounted) {
                  setState(() => _result = result);
                }
              },
              child: const Text('Open destination search'),
            ),
          ],
        ),
      ),
    );
  }
}
