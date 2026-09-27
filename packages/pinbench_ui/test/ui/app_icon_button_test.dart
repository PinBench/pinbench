import 'package:flutter/widgets.dart';
import 'dart:ui' show Tristate;

import 'package:flutter/semantics.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench_ui/theme/app_icons.dart';
import 'package:pinbench_ui/ui/app_icon_button.dart';

import 'package:pinbench_ui/theme/testing.dart';

/// An icon-only button has no text, so unless something names it a screen
/// reader announces bare "button". The tooltip is already that name, so the
/// button is expected to speak it.
void main() {
  Future<void> pumpButton(WidgetTester tester, Widget button) =>
      tester.pumpWidget(appTestApp(Center(child: button)));

  SemanticsData spokenAs(WidgetTester tester, String label) =>
      tester.getSemantics(find.bySemanticsLabel(label).first).getSemanticsData();

  testWidgets('announces its tooltip as its name', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpButton(
      tester,
      AppIconButton(icon: AppIcons.delete, tooltip: 'Delete', onPressed: () {}),
    );

    final semantics = spokenAs(tester, 'Delete');
    expect(semantics.flagsCollection.isButton, isTrue);
    expect(semantics.hasAction(SemanticsAction.tap), isTrue);

    handle.dispose();
  });

  testWidgets('an explicit label wins over the tooltip', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpButton(
      tester,
      AppIconButton(
        icon: AppIcons.close,
        tooltip: 'Close',
        semanticLabel: 'Remove collaborator',
        onPressed: () {},
      ),
    );

    expect(find.bySemanticsLabel('Remove collaborator'), findsWidgets);
    expect(find.bySemanticsLabel('Close'), findsNothing);

    handle.dispose();
  });

  testWidgets('a button with no tooltip can still be named', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpButton(
      tester,
      AppIconButton(icon: AppIcons.close, semanticLabel: 'Dismiss', onPressed: () {}),
    );

    expect(spokenAs(tester, 'Dismiss').hasAction(SemanticsAction.tap), isTrue);

    handle.dispose();
  });

  testWidgets('a disabled button says so rather than looking tappable', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpButton(tester, const AppIconButton(icon: AppIcons.run, tooltip: 'Run'));

    final semantics = spokenAs(tester, 'Run');
    expect(semantics.flagsCollection.isEnabled, Tristate.isFalse);
    expect(semantics.hasAction(SemanticsAction.tap), isFalse);

    handle.dispose();
  });
}
