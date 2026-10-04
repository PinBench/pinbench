import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench_ui/theme/app_colors.dart';
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

  // There used to be a forui accordion under this, which drew a rule under
  // every item that had to be hidden. Built from parts now, there is none.
  testWidgets('draws no rule between sections', (tester) async {
    await tester.pumpWidget(accordion());
    await tester.pumpAndSettle();

    expect(find.byWidgetPredicate((w) => w.runtimeType.toString() == 'FDivider'), findsNothing);
  });

  Finder fill(WidgetTester tester) => find.byWidgetPredicate(
    (w) =>
        w is DecoratedBox &&
        w.decoration is BoxDecoration &&
        (w.decoration as BoxDecoration).color ==
            tester.element(find.text('Inputs')).appColors.muted,
  );

  testWidgets('a header fills while the pointer is over it', (tester) async {
    await tester.pumpWidget(accordion());
    await tester.pumpAndSettle();
    expect(fill(tester), findsNothing);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('Inputs')));
    await tester.pump();
    expect(fill(tester), findsOneWidget, reason: 'only the hovered header');

    await mouse.moveTo(Offset.zero);
    await tester.pump();
    expect(fill(tester), findsNothing);
  });

  testWidgets('the header says whether its section is open', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(accordion());
    await tester.pumpAndSettle();

    expect(
      tester.getSemantics(find.text('Inputs')),
      isSemantics(isExpanded: true, hasExpandedState: true, isButton: true, hasTapAction: true),
    );

    await tester.tap(find.text('Inputs'));
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.text('Inputs')),
      isSemantics(isExpanded: false, hasExpandedState: true, isButton: true, hasTapAction: true),
    );
    semantics.dispose();
  });
}
