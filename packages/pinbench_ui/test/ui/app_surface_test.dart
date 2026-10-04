import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench_ui/theme/app_colors.dart';
import 'package:pinbench_ui/theme/testing.dart';
import 'package:pinbench_ui/ui/app_surface.dart';

/// A surface given `onTap` is a button, and says so under the pointer; one
/// without stays a plain block.
void main() {
  Future<Color?> fillUnderPointer(WidgetTester tester, {VoidCallback? onTap}) async {
    await tester.pumpWidget(
      appTestApp(
        Center(
          child: AppSurface(onTap: onTap, child: const Text('surface')),
        ),
      ),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('surface')));
    await tester.pump();

    final box = tester.widget<Container>(
      find.ancestor(of: find.text('surface'), matching: find.byType(Container)).first,
    );
    return (box.decoration! as BoxDecoration).color;
  }

  testWidgets('a tappable surface fills on hover', (tester) async {
    final color = await fillUnderPointer(tester, onTap: () {});
    expect(color, tester.element(find.text('surface')).appColors.muted);
  });

  testWidgets('a plain surface does not', (tester) async {
    final color = await fillUnderPointer(tester);
    expect(color, tester.element(find.text('surface')).appColors.surface);
  });

  testWidgets('a tappable surface still answers a tap', (tester) async {
    var taps = 0;
    await fillUnderPointer(tester, onTap: () => taps++);
    await tester.tap(find.text('surface'));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });
}
