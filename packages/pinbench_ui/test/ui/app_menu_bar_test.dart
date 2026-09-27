import 'package:flutter/widgets.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench_ui/ui/app_context_menu.dart';
import 'package:pinbench_ui/ui/app_menu_bar.dart';

import 'package:pinbench_ui/theme/testing.dart';

/// A do-nothing handler, so a shared entry list can be `const`.
void _noop() {}

/// A menu bar shows five words until you click one, so everything it does
/// lives behind an interaction — including whether a disabled item is really
/// unclickable rather than merely grey.
void main() {
  var saved = 0;
  var quit = 0;

  setUp(() {
    saved = 0;
    quit = 0;
  });

  Widget bar({bool canSave = true}) => appTestApp(
    Align(
      alignment: Alignment.topLeft,
      child: AppMenuBar(
        menus: [
          AppMenu(
            label: 'File',
            entries: [
              AppContextMenuItem(
                text: 'Save',
                shortcut: '⌘S',
                enabled: canSave,
                onPressed: () => saved++,
              ),
              const AppMenuSeparator(),
              AppContextMenuItem(text: 'Quit', onPressed: () => quit++),
            ],
          ),
          AppMenu(
            label: 'Help',
            entries: [AppContextMenuItem(text: 'About', onPressed: () {})],
          ),
        ],
      ),
    ),
  );

  testWidgets('shows its menu names and nothing else', (tester) async {
    await tester.pumpWidget(bar());
    await tester.pumpAndSettle();

    expect(find.text('File'), findsOneWidget);
    expect(find.text('Help'), findsOneWidget);
    expect(find.text('Save'), findsNothing);
  });

  testWidgets('a click opens the menu, with its shortcuts', (tester) async {
    await tester.pumpWidget(bar());
    await tester.pumpAndSettle();

    await tester.tap(find.text('File'));
    await tester.pumpAndSettle();

    expect(find.text('Save'), findsOneWidget);
    expect(find.text('⌘S'), findsOneWidget);
    expect(find.text('Quit'), findsOneWidget);
    // Another menu's items stay shut.
    expect(find.text('About'), findsNothing);
  });

  testWidgets('choosing an item runs it and closes the menu', (tester) async {
    await tester.pumpWidget(bar());
    await tester.pumpAndSettle();

    await tester.tap(find.text('File'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(saved, 1);
    expect(find.text('Quit'), findsNothing, reason: 'the menu should close behind the choice');
  });

  // "Save" with nothing unsaved. Grey is not enough — it must not fire.
  testWidgets('a disabled item does nothing', (tester) async {
    await tester.pumpWidget(bar(canSave: false));
    await tester.pumpAndSettle();

    await tester.tap(find.text('File'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(saved, 0);
  });

  /// The row a piece of menu text sits in.
  ///
  /// Matched by runtime type rather than by importing the widget library,
  /// which `ui_library_boundary_test` forbids a test from doing — the same
  /// dodge the context-menu assertion below already uses.
  Finder rowContaining(String text) => find.ancestor(
    of: find.text(text),
    matching: find.byWidgetPredicate((w) => w.runtimeType.toString() == 'FItem'),
  );

  // Material sized its menus for touch: 48px rows, which read as a phone list
  // rather than a menu bar, and the old implementation pinned every row to
  // `AppChrome.menuRowHeight` to undo that. The kit's rows are desktop-sized
  // already, so what is left to hold is the ceiling — and the *name* in the
  // bar, which is the one measurement this file still sets itself.
  testWidgets('is sized like a desktop menu, not a touch target', (tester) async {
    await tester.pumpWidget(bar());
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byType(AppMenuBar)).height, lessThan(48));

    await tester.tap(find.text('File'));
    await tester.pumpAndSettle();

    expect(tester.getSize(rowContaining('Save')).height, lessThan(48));
    expect(tester.getSize(rowContaining('Quit')).height, lessThan(48));
  });

  // A three-letter menu next to a long one looked broken without a floor.
  testWidgets('a short menu is no narrower than a wide one starts', (tester) async {
    await tester.pumpWidget(bar());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Help'));
    await tester.pumpAndSettle();

    expect(tester.getSize(rowContaining('About')).width, greaterThanOrEqualTo(200));
  });

  // Only one menu is open at a time, and sliding along the bar with one open
  // follows the pointer rather than needing a second click. That is what a
  // menu bar does and a row of lone popovers does not, so it is hand-rolled
  // here and has to be checked.
  testWidgets('sliding across the bar moves the open menu', (tester) async {
    await tester.pumpWidget(bar());
    await tester.pumpAndSettle();

    await tester.tap(find.text('File'));
    await tester.pumpAndSettle();
    expect(find.text('Quit'), findsOneWidget);

    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(tester.getCenter(find.text('Help'))));
    await tester.pumpAndSettle();

    expect(find.text('About'), findsOneWidget, reason: 'the hovered menu should have opened');
    expect(find.text('Quit'), findsNothing, reason: 'and the previous one should have closed');
  });

  // Hovering a *closed* bar must not make menus appear under the pointer as it
  // crosses the title bar on its way somewhere else.
  testWidgets('hovering a closed bar opens nothing', (tester) async {
    await tester.pumpWidget(bar());
    await tester.pumpAndSettle();

    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(tester.getCenter(find.text('File'))));
    await tester.pumpAndSettle();

    expect(find.text('Quit'), findsNothing);
  });

  // The bar's menus and the right-click menus are the same menu as far as a
  // user is concerned, so the same entry must come out the same size in both.
  //
  // This test existed because the two were built on different libraries and
  // drifted. They are built from the same rows now, so it should be hard to
  // break — but "should be" is why the old one drifted, and the assertion is
  // free. It compares the two directly rather than against a number, so it
  // keeps meaning something if the kit retunes its row height.
  testWidgets('its rows match a context menu row', (tester) async {
    const entries = [
      AppContextMenuItem(text: 'Cut', onPressed: _noop),
      AppContextMenuItem(text: 'Paste', shortcut: '⌘V', onPressed: _noop),
    ];

    Size rowIn(WidgetTester tester, String text) => tester.getSize(rowContaining(text));

    await tester.pumpWidget(
      appTestApp(
        const Align(
          alignment: Alignment.topLeft,
          child: AppMenuBar(
            menus: [AppMenu(label: 'Edit', entries: entries)],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    final barPlain = rowIn(tester, 'Cut').height;
    final barShortcut = rowIn(tester, 'Paste').height;

    final controller = AppContextMenuController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      appTestApp(
        Center(
          child: SizedBox(
            width: 400,
            height: 400,
            child: AppContextMenu(
              controller: controller,
              entries: entries,
              child: const ColoredBox(color: Color(0xFF000000)),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    controller.showAt(const Offset(200, 200));
    await tester.pumpAndSettle();

    expect(rowIn(tester, 'Cut').height, barPlain);
    expect(rowIn(tester, 'Paste').height, barShortcut);
  });

  testWidgets('escape closes an open menu', (tester) async {
    await tester.pumpWidget(bar());
    await tester.pumpAndSettle();

    await tester.tap(find.text('File'));
    await tester.pumpAndSettle();
    expect(find.text('Quit'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('Quit'), findsNothing);
  });
}
