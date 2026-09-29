import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench_ui/theme/tokens.dart';
import 'package:pinbench_ui/ui/app_context_menu.dart';

import 'package:pinbench_ui/theme/testing.dart';

void main() {
  late AppContextMenuController controller;

  setUp(() => controller = AppContextMenuController());
  tearDown(() => controller.dispose());

  Widget menu({List<AppMenuEntry>? entries, Widget? child}) => appTestApp(
    Center(
      child: SizedBox(
        width: 400,
        height: 400,
        child: AppContextMenu(
          controller: controller,
          entries:
              entries ??
              [
                AppContextMenuItem(text: 'Rename', onPressed: () {}),
                const AppMenuSeparator(),
                AppContextMenuItem(text: 'Delete', onPressed: () {}),
              ],
          child: child ?? const ColoredBox(color: Color(0xFF000000)),
        ),
      ),
    ),
  );

  testWidgets('shows nothing until it is opened', (tester) async {
    await tester.pumpWidget(menu());
    await tester.pumpAndSettle();

    expect(find.text('Rename'), findsNothing);
  });

  testWidgets('opens with its corner at the point it was given', (tester) async {
    await tester.pumpWidget(menu());
    await tester.pumpAndSettle();

    const clicked = Offset(260, 240);
    controller.showAt(clicked);
    await tester.pumpAndSettle();

    expect(find.text('Rename'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);

    // Where you clicked, not where the trigger is: the whole reason this
    // wrapper exists, since the underlying menu anchors to a widget.
    final menuRect = tester.getRect(find.text('Rename'));
    expect(menuRect.left, greaterThan(clicked.dx - 40));
    expect(menuRect.top, greaterThan(clicked.dy - 40));
  });

  testWidgets('a click reports and closes', (tester) async {
    var pressed = 0;
    await tester.pumpWidget(
      menu(
        entries: [AppContextMenuItem(text: 'Rename', onPressed: () => pressed++)],
      ),
    );
    await tester.pumpAndSettle();

    controller.showAt(const Offset(200, 200));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();

    expect(pressed, 1);
    expect(controller.isOpen, isFalse);
  });

  // The bug this wrapper is written around: the previous menu returned its
  // child bare when it had no items and wrapped it when it had some, so the
  // child changed depth as the item list changed and was unmounted mid-drag —
  // taking the canvas's pointer handler with it, mid-gesture.
  //
  // Counted through a State rather than a GlobalKey: a GlobalKey is *designed*
  // to survive reparenting, so it would report this as fine even when it is
  // not. A plain State is rebuilt from scratch the moment its depth changes,
  // which is exactly the damage being guarded against.
  testWidgets('never rebuilds the child as the menu empties and fills', (tester) async {
    _MountCounter.mounts = 0;
    const child = _MountCounter();

    await tester.pumpWidget(menu(child: child));
    await tester.pumpAndSettle();
    expect(_MountCounter.mounts, 1);

    await tester.pumpWidget(menu(entries: const [], child: child));
    await tester.pumpAndSettle();
    expect(_MountCounter.mounts, 1, reason: 'emptying the menu must not remount the child');

    controller.showAt(const Offset(100, 100));
    await tester.pumpWidget(menu(child: child));
    await tester.pumpAndSettle();
    expect(_MountCounter.mounts, 1, reason: 'nor must opening it');

    controller.hide();
    await tester.pumpAndSettle();
    expect(_MountCounter.mounts, 1, reason: 'nor closing it');
  });

  testWidgets('closes itself once the pointer has left for long enough', (tester) async {
    await tester.pumpWidget(menu());
    await tester.pumpAndSettle();

    controller.showAt(const Offset(200, 200));
    await tester.pumpAndSettle();

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: const Offset(200, 200));
    await tester.pump();

    // Out of the trigger entirely.
    await mouse.moveTo(const Offset(5, 5));
    await tester.pump();
    expect(controller.isOpen, isTrue, reason: 'it should not vanish the instant you leave');

    await tester.pump(AppMotion.menuDismissDelay * 2);
    await tester.pumpAndSettle();

    expect(controller.isOpen, isFalse);
  });
}

/// Counts how many times it has been mounted, so a test can tell a rebuild
/// from a remount.
class _MountCounter extends StatefulWidget {
  const _MountCounter();

  static var mounts = 0;

  @override
  State<_MountCounter> createState() => _MountCounterState();
}

class _MountCounterState extends State<_MountCounter> {
  @override
  void initState() {
    super.initState();
    _MountCounter.mounts++;
  }

  @override
  Widget build(BuildContext context) => const ColoredBox(color: Color(0xFF000000));
}
