import 'package:flutter/widgets.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench_ui/ui/app_accordion.dart';

import 'package:pinbench_ui/theme/testing.dart';

/// Half an accordion's states are hidden by definition, and the palette's
/// sections all start open — a wrapper that quietly defaulted them shut would
/// still build, still render, and hide every part in the app.
///
/// A closed section keeps its content mounted and clips it to nothing, so
/// "hidden" has to be asked as "can you touch it", not "is it in the tree".
void main() {
  Widget accordion({bool initiallyExpanded = true}) => appTestApp(
    Center(
      child: SizedBox(
        width: 300,
        child: AppAccordion(
          initiallyExpanded: initiallyExpanded,
          sections: const [
            AppAccordionSection(title: 'Inputs', child: Text('a button')),
            AppAccordionSection(title: 'Outputs', child: Text('an LED')),
          ],
        ),
      ),
    ),
  );

  testWidgets('starts with every section open', (tester) async {
    await tester.pumpWidget(accordion());
    await tester.pumpAndSettle();

    expect(find.text('a button').hitTestable(), findsOneWidget);
    expect(find.text('an LED').hitTestable(), findsOneWidget);
  });

  testWidgets('starts closed when asked', (tester) async {
    await tester.pumpWidget(accordion(initiallyExpanded: false));
    await tester.pumpAndSettle();

    expect(find.text('a button').hitTestable(), findsNothing);
  });

  testWidgets('a header closes its own section', (tester) async {
    await tester.pumpWidget(accordion());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Inputs'));
    await tester.pumpAndSettle();

    expect(find.text('a button').hitTestable(), findsNothing);
    // And only its own: the palette lets you keep several open at once.
    expect(find.text('an LED').hitTestable(), findsOneWidget);
  });

  // forui draws a rule under every item unless told otherwise, and it cannot
  // be suppressed by width — the divider asserts on zero — so this checks the
  // thing that actually hides it.
  testWidgets('draws no visible rule between sections', (tester) async {
    await tester.pumpWidget(accordion());
    await tester.pumpAndSettle();

    final dividers = find.byWidgetPredicate((w) => w.runtimeType.toString() == 'FDivider');
    expect(dividers, findsWidgets, reason: 'forui draws one per item; they should be invisible');

    for (final divider in dividers.evaluate()) {
      final box = find.descendant(
        of: find.byWidget(divider.widget),
        matching: find.byType(DecoratedBox),
      );
      for (final painted in box.evaluate()) {
        final decoration = (painted.widget as DecoratedBox).decoration as BoxDecoration;
        expect(decoration.color?.a ?? 0, 0, reason: 'the rule should be invisible');
      }
    }
  });
}
