import 'package:driver_app/offers/driver_offer_layer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The offer card's place depends on these counts: over the tabs while only
// the shell is open, at the top over a pushed screen, hidden under a sheet.
void main() {
  test('push, replace, remove and pop of screens and sheets end at zero', () {
    final counter = DriverOfferRouteObserver();
    final shell = _page();
    final detail = _page();
    final completed = _page();
    final sheet = _Popup();
    final dialog = _Popup();
    final seen = <(int, int)>[];
    void note() => seen.add((counter.pages.value, counter.popups.value));
    counter.pages.addListener(note);
    counter.popups.addListener(note);

    counter.didPush(shell, null);
    counter.didPush(detail, shell);
    counter.didPush(sheet, detail);
    expect((counter.pages.value, counter.popups.value), (2, 1));

    counter.didReplace(newRoute: completed, oldRoute: detail);
    expect((counter.pages.value, counter.popups.value), (2, 1));
    counter.didPush(dialog, completed);
    counter.didRemove(sheet, completed);
    counter.didPop(dialog, completed);
    expect((counter.pages.value, counter.popups.value), (2, 0));

    counter.didPop(completed, shell);
    counter.didRemove(shell, null);
    expect((counter.pages.value, counter.popups.value), (0, 0));
    expect(seen.every((counts) => counts.$1 >= 0 && counts.$2 >= 0), isTrue);
  });

  test('a route it never saw going away never takes a count below zero', () {
    final counter = DriverOfferRouteObserver();

    counter.didPop(_page(), null);
    counter.didRemove(_Popup(), null);
    counter.didReplace(newRoute: null, oldRoute: _page());

    expect(counter.pages.value, 0);
    expect(counter.popups.value, 0);
  });

  testWidgets('through a real navigator: pages and a sheet come back to the '
      'shell only', (tester) async {
    final counter = DriverOfferRouteObserver();
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: key,
        navigatorObservers: [counter],
        home: const Scaffold(body: Text('shell')),
      ),
    );
    expect((counter.pages.value, counter.popups.value), (1, 0));

    final navigator = key.currentState!;
    navigator.push(_page());
    await tester.pumpAndSettle();
    showModalBottomSheet<void>(
      context: key.currentContext!,
      builder: (_) => const Text('sheet'),
    );
    await tester.pumpAndSettle();
    expect((counter.pages.value, counter.popups.value), (2, 1));

    navigator.pop();
    await tester.pumpAndSettle();
    navigator.pushReplacement(_page());
    await tester.pumpAndSettle();
    expect((counter.pages.value, counter.popups.value), (2, 0));

    navigator.pop();
    await tester.pumpAndSettle();
    expect((counter.pages.value, counter.popups.value), (1, 0));
  });
}

MaterialPageRoute<void> _page() =>
    MaterialPageRoute<void>(builder: (_) => const Scaffold());

final class _Popup extends PopupRoute<void> {
  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => null;

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => const SizedBox.shrink();
}
