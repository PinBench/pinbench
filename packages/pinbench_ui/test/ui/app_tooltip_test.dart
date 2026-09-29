import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench_ui/ui/app_tooltip.dart';

import 'package:pinbench_ui/theme/testing.dart';

/// A tooltip shows nothing until you hover it, so its whole job lives in a
/// state no test reaches by accident — the same blind spot that let the select
/// ship with a list that tore the frame down when opened.
void main() {
  /// Moves a mouse onto [finder] and lets the tooltip's delay elapse.
  ///
  /// The wait has to be an explicit `pump(duration)`: the tooltip waits on a
  /// plain `Future.delayed` before showing, which schedules no frame, so
  /// `pumpAndSettle` alone returns with the clock untouched and nothing shown.
  Future<void> hover(WidgetTester tester, Finder finder) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await tester.pump();
    await mouse.moveTo(tester.getCenter(finder));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  }

  testWidgets('shows its message on hover', (tester) async {
    await tester.pumpWidget(
      appTestApp(
        const Center(
          child: AppTooltip(message: 'Export circuit', child: Text('target')),
        ),
      ),
    );

    expect(find.text('Export circuit'), findsNothing);

    await hover(tester, find.text('target'));

    expect(find.text('Export circuit'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows the shortcut beside the message', (tester) async {
    await tester.pumpWidget(
      appTestApp(
        const Center(
          child: AppTooltip(message: 'Export circuit', shortcutLabel: '⌘E', child: Text('target')),
        ),
      ),
    );

    await hover(tester, find.text('target'));

    expect(find.text('Export circuit'), findsOneWidget);
    expect(find.text('⌘E'), findsOneWidget);
  });

  // The side decides which way the tip is anchored. Getting it backwards is
  // exactly the mistake the enum exists to prevent, so check it lands on the
  // side asked for rather than merely rendering.
  testWidgets('sits to the right when asked', (tester) async {
    await tester.pumpWidget(
      appTestApp(
        const Center(
          child: AppTooltip(
            message: 'Parts',
            side: AppTooltipSide.right,
            child: SizedBox(width: 40, height: 40, child: Text('target')),
          ),
        ),
      ),
    );

    await hover(tester, find.text('target'));

    expect(
      tester.getCenter(find.text('Parts')).dx,
      greaterThan(tester.getCenter(find.text('target')).dx),
    );
  });
}
