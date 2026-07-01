import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('exposes the approved ASM tokens and distinct app themes', () {
    expect(AsmColors.green, const Color(0xFF086B52));
    expect(AsmColors.solarYellow, const Color(0xFFFFC928));
    expect(AsmColors.passengerScaffold, const Color(0xFFF5F7F2));
    expect(AsmColors.driverScaffold, const Color(0xFF151A1D));
    expect(AsmColors.driverPanelMuted, const Color(0xFF343026));
    expect(AsmColors.driverTextSecondary, const Color(0xFFB7C0C4));
    expect(AsmColors.driverWarningSurface, const Color(0xFFFFD968));

    expect(
      [
        AsmSpacing.space4,
        AsmSpacing.space8,
        AsmSpacing.space12,
        AsmSpacing.space16,
        AsmSpacing.space20,
        AsmSpacing.space24,
        AsmSpacing.space32,
      ],
      [4.0, 8.0, 12.0, 16.0, 20.0, 24.0, 32.0],
    );
    expect([AsmRadii.radius6, AsmRadii.radius8], [6.0, 8.0]);

    final passenger = AsmThemes.passenger;
    final driver = AsmThemes.driver;

    expect(passenger.useMaterial3, isTrue);
    expect(passenger.brightness, Brightness.light);
    expect(passenger.scaffoldBackgroundColor, AsmColors.passengerScaffold);
    expect(
      passenger.colorScheme.primary,
      ColorScheme.fromSeed(seedColor: AsmColors.green).primary,
    );

    expect(driver.useMaterial3, isTrue);
    expect(driver.brightness, Brightness.dark);
    expect(driver.scaffoldBackgroundColor, AsmColors.driverScaffold);
    expect(
      driver.colorScheme.primary,
      ColorScheme.fromSeed(
        seedColor: AsmColors.solarYellow,
        brightness: Brightness.dark,
      ).primary,
    );
    expect(passenger.colorScheme.primary, isNot(driver.colorScheme.primary));
  });

  testWidgets('renders public demo content in light and dark themes', (
    WidgetTester tester,
  ) async {
    Future<void> pumpPlaceholder(ThemeData theme) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const Scaffold(
            body: AsmDemoPlaceholder(
              icon: Icons.route_outlined,
              title: 'No trips connected',
              message: 'Services are unavailable in this local demo.',
            ),
          ),
        ),
      );
    }

    await pumpPlaceholder(AsmThemes.passenger);
    expect(find.byIcon(Icons.route_outlined), findsOneWidget);
    expect(find.text('LOCAL DEMO'), findsOneWidget);
    expect(find.text('No trips connected'), findsOneWidget);
    expect(
      find.text('Services are unavailable in this local demo.'),
      findsOneWidget,
    );

    await pumpPlaceholder(AsmThemes.driver);
    expect(find.text('LOCAL DEMO'), findsOneWidget);
    expect(find.text('No trips connected'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('local demo badge renders the default LOCAL DEMO label', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: const Scaffold(body: Center(child: AsmLocalDemoBadge())),
      ),
    );

    expect(find.text('LOCAL DEMO'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('local demo badge supports custom text and colors', (
    WidgetTester tester,
  ) async {
    const background = Color(0xFF123456);
    const foreground = Color(0xFFABCDEF);

    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.driver,
        home: const Scaffold(
          body: Center(
            child: AsmLocalDemoBadge(
              text: 'LOCAL ONLY',
              backgroundColor: background,
              foregroundColor: foreground,
              padding: EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              semanticLabel: 'Local only demo badge',
            ),
          ),
        ),
      ),
    );

    final badgeContainer = tester.widget<Container>(
      find.descendant(
        of: find.byType(AsmLocalDemoBadge),
        matching: find.byType(Container),
      ),
    );
    final decoration = badgeContainer.decoration! as BoxDecoration;
    final text = tester.widget<Text>(find.text('LOCAL ONLY'));

    expect(decoration.color, background);
    expect(text.style?.color, foreground);
    expect(find.text('LOCAL ONLY'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('local demo badge handles long text in a small layout', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(
              size: Size(96, 80),
              textScaler: TextScaler.linear(1.5),
            ),
            child: const SizedBox(
              width: 96,
              child: AsmLocalDemoBadge(text: 'LOCAL DEMO FOUNDATION ONLY'),
            ),
          ),
        ),
      ),
    );

    expect(find.text('LOCAL DEMO FOUNDATION ONLY'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('app brand mark renders the default icon', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: const Scaffold(body: Center(child: AsmAppBrandMark())),
      ),
    );

    expect(find.byIcon(Icons.wb_sunny_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('app brand mark renders a custom icon', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: const Scaffold(
          body: Center(
            child: AsmAppBrandMark(icon: Icons.electric_car_outlined),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.electric_car_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('app brand mark custom size color and radius render safely', (
    WidgetTester tester,
  ) async {
    const background = Color(0xFF123456);
    const iconColor = Color(0xFFABCDEF);

    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: const Scaffold(
          body: Center(
            child: AsmAppBrandMark(
              size: 52,
              backgroundColor: background,
              iconColor: iconColor,
              borderRadius: AsmRadii.radius6,
            ),
          ),
        ),
      ),
    );

    final container = tester.widget<Container>(
      find.descendant(
        of: find.byType(AsmAppBrandMark),
        matching: find.byType(Container),
      ),
    );
    final decoration = container.decoration! as BoxDecoration;
    final icon = tester.widget<Icon>(find.byIcon(Icons.wb_sunny_outlined));
    final borderRadius = decoration.borderRadius! as BorderRadius;

    expect(container.constraints?.minWidth, 52);
    expect(container.constraints?.maxWidth, 52);
    expect(container.constraints?.minHeight, 52);
    expect(container.constraints?.maxHeight, 52);
    expect(decoration.color, background);
    expect(icon.color, iconColor);
    expect(borderRadius.topLeft.x, AsmRadii.radius6);
    expect(tester.takeException(), isNull);
  });

  testWidgets('app brand mark remains presentational only', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: const Scaffold(body: Center(child: AsmAppBrandMark())),
      ),
    );

    expect(find.byType(AsmAppBrandMark), findsOneWidget);
    expect(find.byType(GestureDetector), findsNothing);
    expect(find.byType(InkWell), findsNothing);
    expect(find.byType(TextButton), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('screen header renders title, subtitle, and leading widget', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: const Scaffold(
          body: AsmScreenHeader(
            leading: Icon(Icons.wb_sunny_outlined),
            title: 'ASM PASSENGER',
            subtitle: 'Field workspace',
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.wb_sunny_outlined), findsOneWidget);
    expect(find.text('ASM PASSENGER'), findsOneWidget);
    expect(find.text('Field workspace'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('screen header renders a trailing widget', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.driver,
        home: const Scaffold(
          body: AsmScreenHeader(
            title: 'ASM DRIVER',
            trailing: AsmLocalDemoBadge(),
          ),
        ),
      ),
    );

    expect(find.text('ASM DRIVER'), findsOneWidget);
    expect(find.text('LOCAL DEMO'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('screen header long title and subtitle wrap without throwing', (
    WidgetTester tester,
  ) async {
    const longTitle =
        'Africa Solar Mobility field operations local demo workspace';
    const longSubtitle =
        'This compact shared header keeps app-specific screens readable on '
        'small displays.';

    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: const Scaffold(
          body: SizedBox(
            width: 180,
            child: AsmScreenHeader(
              leading: Icon(Icons.electric_car_outlined),
              title: longTitle,
              subtitle: longSubtitle,
              trailing: AsmLocalDemoBadge(text: 'LOCAL'),
            ),
          ),
        ),
      ),
    );

    expect(find.text(longTitle), findsOneWidget);
    expect(find.text(longSubtitle), findsOneWidget);
    expect(find.text('LOCAL'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('section label renders text', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: const Scaffold(
          body: AsmSectionLabel(text: 'Driver app foundation'),
        ),
      ),
    );

    expect(find.text('Driver app foundation'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('section label renders helper text', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: const Scaffold(
          body: AsmSectionLabel(
            text: 'Controlled pilot',
            helperText: 'Local planning only',
          ),
        ),
      ),
    );

    expect(find.text('Controlled pilot'), findsOneWidget);
    expect(find.text('Local planning only'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('section label renders an optional icon', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.driver,
        home: const Scaffold(
          body: AsmSectionLabel(
            icon: Icons.location_on_outlined,
            text: 'Accra, Ghana',
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.location_on_outlined), findsOneWidget);
    expect(find.text('Accra, Ghana'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('section label long text renders safely', (
    WidgetTester tester,
  ) async {
    const longText =
        'Africa Solar Mobility controlled local demo section label with extended '
        'copy for smaller layouts';
    const longHelper =
        'This helper remains presentational and does not connect any live service.';

    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: const Scaffold(
          body: SizedBox(
            width: 160,
            child: AsmSectionLabel(
              icon: Icons.info_outline,
              text: longText,
              helperText: longHelper,
            ),
          ),
        ),
      ),
    );

    expect(find.text(longText), findsOneWidget);
    expect(find.text(longHelper), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('screen surface renders its child', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: const Scaffold(
          body: AsmScreenSurface(child: Text('Surface content')),
        ),
      ),
    );

    expect(find.text('Surface content'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('screen surface applies padding and safe area safely', (
    WidgetTester tester,
  ) async {
    const padding = EdgeInsets.fromLTRB(7, 11, 13, 17);

    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: const Scaffold(
          body: AsmScreenSurface(
            padding: padding,
            child: Text('Padded content'),
          ),
        ),
      ),
    );

    final surfacePadding = tester.widget<Padding>(
      find.descendant(
        of: find.byType(AsmScreenSurface),
        matching: find.byWidgetPredicate(
          (widget) => widget is Padding && widget.padding == padding,
        ),
      ),
    );

    expect(find.byType(SafeArea), findsOneWidget);
    expect(surfacePadding.padding, padding);
    expect(find.text('Padded content'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('screen surface scrollable long content renders safely', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.driver,
        home: Scaffold(
          body: SizedBox(
            height: 100,
            child: AsmScreenSurface(
              safeArea: false,
              scrollable: true,
              expandToViewport: true,
              child: Column(
                children: List.generate(
                  18,
                  (index) => Text('Scrollable item $index'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(find.text('Scrollable item 0'), findsOneWidget);
    expect(find.text('Scrollable item 17'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('route input tile renders placeholder text', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: const Scaffold(
          body: AsmRouteInputTile(
            markerColor: AsmColors.green,
            placeholder: 'Choose pickup',
            onTap: null,
          ),
        ),
      ),
    );

    expect(find.text('Choose pickup'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('route input tile renders selected description text', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: const Scaffold(
          body: AsmRouteInputTile(
            markerColor: AsmColors.solarYellow,
            placeholder: 'Where to?',
            description: 'Solar Hub East',
            onTap: null,
          ),
        ),
      ),
    );

    expect(find.text('Solar Hub East'), findsOneWidget);
    expect(find.text('Where to?'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('route input tile enabled action fires callback', (
    WidgetTester tester,
  ) async {
    var tapCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: Scaffold(
          body: AsmRouteInputTile(
            key: const Key('route-input'),
            markerColor: AsmColors.green,
            placeholder: 'Choose pickup',
            onTap: () => tapCount += 1,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('route-input')));
    await tester.pump();

    expect(tapCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('route input tile disabled action does not fire callback', (
    WidgetTester tester,
  ) async {
    var tapCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: Scaffold(
          body: AsmRouteInputTile(
            key: const Key('disabled-route-input'),
            markerColor: AsmColors.green,
            placeholder: 'Choose pickup',
            enabled: false,
            onTap: () => tapCount += 1,
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const Key('disabled-route-input')),
      warnIfMissed: false,
    );
    await tester.pump();

    expect(tapCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('route input tile long selected text renders safely', (
    WidgetTester tester,
  ) async {
    const longDescription =
        'Solar mobility operations pickup point with a longer local field '
        'description for small screen route planning';

    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: const Scaffold(
          body: SizedBox(
            width: 180,
            child: AsmRouteInputTile(
              markerColor: AsmColors.green,
              placeholder: 'Choose pickup',
              description: longDescription,
              onTap: null,
            ),
          ),
        ),
      ),
    );

    expect(find.text(longDescription), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('route action row renders swap action', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: const Scaffold(
          body: AsmRouteActionRow(
            swapKey: Key('swap-action'),
            onSwapPressed: null,
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('swap-action')), findsOneWidget);
    expect(find.byIcon(Icons.swap_vert), findsOneWidget);
    expect(find.byTooltip('Swap pickup and destination'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('route action row renders clear action when shown', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: const Scaffold(
          body: AsmRouteActionRow(
            clearKey: Key('clear-action'),
            showClearAction: true,
            onSwapPressed: null,
            onClearPressed: null,
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('clear-action')), findsOneWidget);
    expect(find.byIcon(Icons.clear), findsOneWidget);
    expect(find.text('Clear route'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('route action row enabled callbacks fire', (
    WidgetTester tester,
  ) async {
    var swapCount = 0;
    var clearCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: Scaffold(
          body: AsmRouteActionRow(
            swapKey: const Key('swap-action'),
            clearKey: const Key('clear-action'),
            showClearAction: true,
            onSwapPressed: () => swapCount += 1,
            onClearPressed: () => clearCount += 1,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('swap-action')));
    await tester.tap(find.byKey(const Key('clear-action')));
    await tester.pump();

    expect(swapCount, 1);
    expect(clearCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('route action row disabled swap does not fire callback', (
    WidgetTester tester,
  ) async {
    var swapCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: Scaffold(
          body: AsmRouteActionRow(
            swapKey: const Key('disabled-swap-action'),
            swapEnabled: false,
            onSwapPressed: () => swapCount += 1,
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const Key('disabled-swap-action')),
      warnIfMissed: false,
    );
    await tester.pump();

    expect(swapCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('route action row can hide clear action', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: const Scaffold(
          body: AsmRouteActionRow(
            showClearAction: false,
            onSwapPressed: null,
            onClearPressed: null,
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.swap_vert), findsOneWidget);
    expect(find.text('Clear route'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('route planner panel renders pickup and destination content', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: const Scaffold(
          body: AsmRoutePlannerPanel(
            pickupInputTile: AsmRouteInputTile(
              markerColor: AsmColors.green,
              placeholder: 'Choose pickup',
              description: 'Solar Hub Pickup',
              onTap: null,
            ),
            destinationInputTile: AsmRouteInputTile(
              markerColor: AsmColors.solarYellow,
              placeholder: 'Where to?',
              description: 'Accra Central',
              onTap: null,
            ),
            actionRow: AsmRouteActionRow(onSwapPressed: null),
          ),
        ),
      ),
    );

    expect(find.text('Solar Hub Pickup'), findsOneWidget);
    expect(find.text('Accra Central'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('route planner panel displays action row content', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: const Scaffold(
          body: AsmRoutePlannerPanel(
            pickupInputTile: AsmRouteInputTile(
              markerColor: AsmColors.green,
              placeholder: 'Choose pickup',
              onTap: null,
            ),
            destinationInputTile: AsmRouteInputTile(
              markerColor: AsmColors.solarYellow,
              placeholder: 'Where to?',
              onTap: null,
            ),
            actionRow: AsmRouteActionRow(
              clearKey: Key('clear-action'),
              showClearAction: true,
              onSwapPressed: null,
              onClearPressed: null,
            ),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.swap_vert), findsOneWidget);
    expect(find.byKey(const Key('clear-action')), findsOneWidget);
    expect(find.text('Clear route'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('route planner panel displays validation notice', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: const Scaffold(
          body: AsmRoutePlannerPanel(
            pickupInputTile: AsmRouteInputTile(
              markerColor: AsmColors.green,
              placeholder: 'Choose pickup',
              onTap: null,
            ),
            destinationInputTile: AsmRouteInputTile(
              markerColor: AsmColors.solarYellow,
              placeholder: 'Where to?',
              onTap: null,
            ),
            actionRow: AsmRouteActionRow(onSwapPressed: null),
            validationNotice: AsmRouteValidationNotice(
              message: 'Pickup and destination must be different.',
            ),
          ),
        ),
      ),
    );

    expect(
      find.text('Pickup and destination must be different.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('route planner panel remains callback-driven', (
    WidgetTester tester,
  ) async {
    var pickupCount = 0;
    var destinationCount = 0;
    var swapCount = 0;
    var continueCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: Scaffold(
          body: AsmRoutePlannerPanel(
            pickupInputTile: AsmRouteInputTile(
              key: const Key('panel-pickup'),
              markerColor: AsmColors.green,
              placeholder: 'Choose pickup',
              onTap: () => pickupCount += 1,
            ),
            destinationInputTile: AsmRouteInputTile(
              key: const Key('panel-destination'),
              markerColor: AsmColors.solarYellow,
              placeholder: 'Where to?',
              onTap: () => destinationCount += 1,
            ),
            actionRow: AsmRouteActionRow(
              swapKey: const Key('panel-swap'),
              onSwapPressed: () => swapCount += 1,
            ),
            actionArea: AsmPrimaryActionButton(
              key: const Key('panel-continue'),
              label: 'Continue',
              onPressed: () => continueCount += 1,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('panel-pickup')));
    await tester.tap(find.byKey(const Key('panel-destination')));
    await tester.tap(find.byKey(const Key('panel-swap')));
    await tester.tap(find.byKey(const Key('panel-continue')));
    await tester.pump();

    expect(pickupCount, 1);
    expect(destinationCount, 1);
    expect(swapCount, 1);
    expect(continueCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('route validation notice renders message', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: const Scaffold(
          body: AsmRouteValidationNotice(
            message: 'Pickup and destination must be different.',
          ),
        ),
      ),
    );

    expect(
      find.text('Pickup and destination must be different.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('route validation notice renders configured icon', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: const Scaffold(
          body: AsmRouteValidationNotice(
            icon: Icons.error_outline,
            message: 'Route issue',
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(find.text('Route issue'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('route validation notice supports custom severity color', (
    WidgetTester tester,
  ) async {
    const customColor = Color(0xFFAA5500);

    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: const Scaffold(
          body: AsmRouteValidationNotice(
            icon: Icons.info_outline,
            severity: AsmRouteValidationSeverity.warning,
            color: customColor,
            message: 'Route warning',
          ),
        ),
      ),
    );

    final text = tester.widget<Text>(find.text('Route warning'));
    final icon = tester.widget<Icon>(find.byIcon(Icons.info_outline));

    expect(text.style?.color, customColor);
    expect(icon.color, customColor);
    expect(tester.takeException(), isNull);
  });

  testWidgets('route validation notice long text renders safely', (
    WidgetTester tester,
  ) async {
    const longMessage =
        'Pickup and destination must be different for this local route planning '
        'draft before continuing to the next local-only screen.';

    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: const Scaffold(
          body: SizedBox(
            width: 180,
            child: AsmRouteValidationNotice(
              icon: Icons.error_outline,
              message: longMessage,
            ),
          ),
        ),
      ),
    );

    expect(find.text(longMessage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('primary action button enabled action fires callback', (
    WidgetTester tester,
  ) async {
    var tapCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: Scaffold(
          body: AsmPrimaryActionButton(
            key: const Key('enabled-action'),
            label: 'Continue',
            onPressed: () => tapCount += 1,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('enabled-action')));
    await tester.pump();

    expect(tapCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('primary action button disabled action does not fire callback', (
    WidgetTester tester,
  ) async {
    var tapCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: Scaffold(
          body: AsmPrimaryActionButton(
            key: const Key('disabled-action'),
            label: 'Continue',
            enabled: false,
            onPressed: () => tapCount += 1,
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const Key('disabled-action')),
      warnIfMissed: false,
    );
    await tester.pump();

    expect(tapCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('primary action button renders icon and long label safely', (
    WidgetTester tester,
  ) async {
    const longLabel =
        'Review this local demo action before continuing through the field '
        'workflow';

    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.driver,
        home: const Scaffold(
          body: SizedBox(
            width: 180,
            child: AsmPrimaryActionButton(
              label: longLabel,
              icon: Icons.fact_check_outlined,
              onPressed: null,
              variant: AsmActionButtonVariant.outlined,
            ),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.fact_check_outlined), findsOneWidget);
    expect(find.text(longLabel), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty state panel renders title, message, and icon', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: const Scaffold(
          body: AsmEmptyStatePanel(
            icon: Icons.map_outlined,
            title: 'Map preview unavailable in this local demo.',
            message: 'No connected service is active.',
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.map_outlined), findsOneWidget);
    expect(
      find.text('Map preview unavailable in this local demo.'),
      findsOneWidget,
    );
    expect(find.text('No connected service is active.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty state panel renders an optional action child', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.driver,
        home: const Scaffold(
          body: AsmEmptyStatePanel(
            icon: Icons.cloud_off_outlined,
            title: 'Not connected',
            message: 'No live dispatch or driver services are active.',
            action: Text('Review local setup'),
          ),
        ),
      ),
    );

    expect(find.text('Not connected'), findsOneWidget);
    expect(
      find.text('No live dispatch or driver services are active.'),
      findsOneWidget,
    );
    expect(find.text('Review local setup'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty state panel long title and message render safely', (
    WidgetTester tester,
  ) async {
    const longTitle =
        'Local demo workspace placeholder with a longer controlled-service '
        'status title';
    const longMessage =
        'This shared empty state keeps static local messaging readable on small '
        'screens without connecting to live services.';

    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: const Scaffold(
          body: SizedBox(
            width: 180,
            child: AsmEmptyStatePanel(
              icon: Icons.route_outlined,
              title: longTitle,
              message: longMessage,
            ),
          ),
        ),
      ),
    );

    expect(find.text(longTitle), findsOneWidget);
    expect(find.text(longMessage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('local map preview surface renders the title', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: const Scaffold(
          body: AsmLocalMapPreviewSurface(
            title: 'Map preview unavailable in this local demo.',
          ),
        ),
      ),
    );

    expect(
      find.text('Map preview unavailable in this local demo.'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.map_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('local map preview surface renders an optional message', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: const Scaffold(
          body: AsmLocalMapPreviewSurface(
            title: 'Local map preview',
            message: 'Live maps are not connected in this local demo.',
          ),
        ),
      ),
    );

    expect(find.text('Local map preview'), findsOneWidget);
    expect(
      find.text('Live maps are not connected in this local demo.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('local map preview surface renders a custom icon', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: const Scaffold(
          body: AsmLocalMapPreviewSurface(
            icon: Icons.public_outlined,
            title: 'Local map preview',
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.public_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('local map preview surface custom styling renders safely', (
    WidgetTester tester,
  ) async {
    const background = Color(0xFFE8F5EF);
    const border = Color(0xFF086B52);

    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: const Scaffold(
          body: AsmLocalMapPreviewSurface(
            title: 'Local map preview',
            minHeight: 220,
            backgroundColor: background,
            borderColor: border,
            iconColor: AsmColors.green,
          ),
        ),
      ),
    );

    final container = tester.widget<Container>(
      find.descendant(
        of: find.byType(AsmLocalMapPreviewSurface),
        matching: find.byType(Container),
      ),
    );
    final decoration = container.decoration! as BoxDecoration;

    expect(container.constraints?.minHeight, 220);
    expect(decoration.color, background);
    expect(decoration.border?.top.color, border);
    expect(tester.takeException(), isNull);
  });

  testWidgets('local map preview surface remains presentational only', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: const Scaffold(
          body: AsmLocalMapPreviewSurface(title: 'Local map preview'),
        ),
      ),
    );

    expect(find.byType(AsmLocalMapPreviewSurface), findsOneWidget);
    expect(find.byType(GestureDetector), findsNothing);
    expect(find.byType(InkWell), findsNothing);
    expect(find.byType(TextButton), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ride detail row renders labels and values', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: const Scaffold(
          body: AsmRideDetailRow(
            icon: Icons.trip_origin,
            label: 'Pickup',
            value: 'Solar Hotel',
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.trip_origin), findsOneWidget);
    expect(find.text('Pickup'), findsOneWidget);
    expect(find.text('Solar Hotel'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pilot notice banner renders message text', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: const Scaffold(
          body: AsmPilotNoticeBanner(
            message:
                'GHANA PILOT · Accra local planning only. No ride service is connected.',
          ),
        ),
      ),
    );

    expect(
      find.text(
        'GHANA PILOT · Accra local planning only. No ride service is connected.',
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.info_outline), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pilot notice banner renders a custom icon', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: const Scaffold(
          body: AsmPilotNoticeBanner(
            icon: Icons.campaign_outlined,
            message: 'Pilot notice',
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.campaign_outlined), findsOneWidget);
    expect(find.text('Pilot notice'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pilot notice banner long text wraps safely', (
    WidgetTester tester,
  ) async {
    const longMessage =
        'GHANA PILOT · Accra local planning only. No ride service is connected. '
        'This controlled local notice can wrap across several lines on smaller '
        'screens without changing app behavior.';

    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: const Scaffold(
          body: SizedBox(
            width: 180,
            child: AsmPilotNoticeBanner(message: longMessage),
          ),
        ),
      ),
    );

    expect(find.text(longMessage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pilot notice banner custom colors and style render safely', (
    WidgetTester tester,
  ) async {
    const background = Color(0xFFE8F5EF);
    const iconColor = Color(0xFF123456);
    const textStyle = TextStyle(
      color: Color(0xFF654321),
      fontWeight: FontWeight.w800,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: const Scaffold(
          body: AsmPilotNoticeBanner(
            message: 'Pilot notice',
            backgroundColor: background,
            iconColor: iconColor,
            textStyle: textStyle,
          ),
        ),
      ),
    );

    final container = tester.widget<Container>(
      find.descendant(
        of: find.byType(AsmPilotNoticeBanner),
        matching: find.byType(Container),
      ),
    );
    final decoration = container.decoration! as BoxDecoration;
    final icon = tester.widget<Icon>(find.byIcon(Icons.info_outline));
    final text = tester.widget<Text>(find.text('Pilot notice'));

    expect(decoration.color, background);
    expect(icon.color, iconColor);
    expect(text.style?.color, textStyle.color);
    expect(text.style?.fontWeight, textStyle.fontWeight);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pilot notice banner remains presentational only', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: const Scaffold(
          body: AsmPilotNoticeBanner(message: 'Pilot notice'),
        ),
      ),
    );

    expect(find.byType(AsmPilotNoticeBanner), findsOneWidget);
    expect(find.byType(GestureDetector), findsNothing);
    expect(find.byType(InkWell), findsNothing);
    expect(find.byType(TextButton), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bottom navigation bar renders destination labels', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: const Scaffold(
          bottomNavigationBar: AsmBottomNavigationBar(
            selectedIndex: 0,
            onDestinationSelected: null,
            destinations: [
              AsmBottomNavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'Home',
              ),
              AsmBottomNavigationDestination(
                icon: Icon(Icons.route_outlined),
                selectedIcon: Icon(Icons.route),
                label: 'Trips',
              ),
              AsmBottomNavigationDestination(
                icon: Icon(Icons.support_agent_outlined),
                selectedIcon: Icon(Icons.support_agent),
                label: 'Support',
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Trips'), findsOneWidget);
    expect(find.text('Support'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bottom navigation bar passes through selected index', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: const Scaffold(
          bottomNavigationBar: AsmBottomNavigationBar(
            selectedIndex: 1,
            onDestinationSelected: null,
            destinations: [
              AsmBottomNavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'Home',
              ),
              AsmBottomNavigationDestination(
                icon: Icon(Icons.route_outlined),
                selectedIcon: Icon(Icons.route),
                label: 'Trips',
              ),
            ],
          ),
        ),
      ),
    );

    final navigationBar = tester.widget<NavigationBar>(
      find.descendant(
        of: find.byType(AsmBottomNavigationBar),
        matching: find.byType(NavigationBar),
      ),
    );

    expect(navigationBar.selectedIndex, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bottom navigation bar destination taps call callback', (
    WidgetTester tester,
  ) async {
    int? selectedIndex;

    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: Scaffold(
          bottomNavigationBar: AsmBottomNavigationBar(
            selectedIndex: 0,
            onDestinationSelected: (index) => selectedIndex = index,
            destinations: const [
              AsmBottomNavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'Home',
              ),
              AsmBottomNavigationDestination(
                icon: Icon(Icons.route_outlined),
                selectedIcon: Icon(Icons.route),
                label: 'Trips',
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.text('Trips'));
    await tester.pump();

    expect(selectedIndex, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bottom navigation bar renders icons and selected icons', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: const Scaffold(
          bottomNavigationBar: AsmBottomNavigationBar(
            selectedIndex: 0,
            onDestinationSelected: null,
            destinations: [
              AsmBottomNavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'Home',
              ),
              AsmBottomNavigationDestination(
                icon: Icon(Icons.route_outlined),
                selectedIcon: Icon(Icons.route),
                label: 'Trips',
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.home), findsOneWidget);
    expect(find.byIcon(Icons.route_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bottom navigation bar remains callback-driven', (
    WidgetTester tester,
  ) async {
    final selectedIndexes = <int>[];

    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.passenger,
        home: Scaffold(
          bottomNavigationBar: AsmBottomNavigationBar(
            selectedIndex: 0,
            onDestinationSelected: selectedIndexes.add,
            destinations: const [
              AsmBottomNavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'Home',
              ),
              AsmBottomNavigationDestination(
                icon: Icon(Icons.support_agent_outlined),
                selectedIcon: Icon(Icons.support_agent),
                label: 'Support',
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.text('Support'));
    await tester.pump();

    expect(selectedIndexes, [1]);
    expect(find.byType(AsmBottomNavigationBar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('local info panel and long detail text wrap without throwing', (
    WidgetTester tester,
  ) async {
    const longValue =
        'Solar Hotel reception entrance with additional local guidance for the '
        'driver preview and passenger draft summary.';
    const longMessage =
        'This local summary remains on this device and does not connect to any '
        'live ride service.';

    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.driver,
        home: const Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 220,
              child: Column(
                children: [
                  AsmRideDetailRow(
                    contained: true,
                    label: 'Pickup',
                    value: longValue,
                  ),
                  SizedBox(height: AsmSpacing.space12),
                  AsmLocalInfoPanel(message: longMessage),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Pickup'), findsOneWidget);
    expect(find.text(longValue), findsOneWidget);
    expect(find.text(longMessage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
