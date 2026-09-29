import 'package:flutter/widgets.dart';

import 'dart:ui' show Tristate;

import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench_ui/ui/app_switch.dart';

import 'package:pinbench_ui/theme/testing.dart';

/// The switch is controlled, so the interesting property is that it never
/// disagrees with the app: tapping reports, and the thing it shows is whatever
/// it was last given, not what it remembers being tapped to.
void main() {
  testWidgets('reports a tap without flipping itself', (tester) async {
    final reported = <bool>[];
    await tester.pumpWidget(
      appTestApp(Center(child: AppSwitch(value: false, onChanged: reported.add))),
    );

    await tester.tap(find.byType(AppSwitch));
    await tester.pumpAndSettle();

    expect(reported, [true]);
  });

  // A switch that kept its own copy would render "on" here after the tap even
  // though the app refused the change. That drift is exactly why these
  // wrappers are controlled, so it is checked against what the switch actually
  // renders rather than against the value just handed to it.
  testWidgets('renders the value it is given, not the tap', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      appTestApp(
        StatefulBuilder(
          // Rebuilds on every tap but never changes the value: the app says no.
          builder: (context, setState) =>
              Center(child: AppSwitch(value: false, onChanged: (_) => setState(() {}))),
        ),
      ),
    );

    Tristate rendersOn() => tester.getSemantics(find.byType(AppSwitch)).flagsCollection.isToggled;

    expect(rendersOn(), Tristate.isFalse);

    await tester.tap(find.byType(AppSwitch));
    await tester.pumpAndSettle();

    expect(rendersOn(), Tristate.isFalse);
    handle.dispose();
  });

  // Pins the flag the test above leans on: it tracks the value, so reading
  // false there means "off", not "the flag is never set".
  testWidgets('renders as on when its value is on', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(appTestApp(Center(child: AppSwitch(value: true, onChanged: (_) {}))));

    expect(tester.getSemantics(find.byType(AppSwitch)).flagsCollection.isToggled, Tristate.isTrue);
    handle.dispose();
  });

  // The underlying switch is built to sit beside a label and reserves a gap
  // for one. This switch never has a label, and in the properties sidebar that
  // gap was wide enough to push "Flipped Horizontal" off the edge.
  testWidgets('reserves no room for a label it does not have', (tester) async {
    await tester.pumpWidget(appTestApp(Center(child: AppSwitch(value: false, onChanged: (_) {}))));

    expect(tester.getSize(find.byType(AppSwitch)).width, lessThan(64));
  });

  testWidgets('a disabled switch reports nothing', (tester) async {
    final reported = <bool>[];
    await tester.pumpWidget(
      appTestApp(Center(child: AppSwitch(value: false, enabled: false, onChanged: reported.add))),
    );

    await tester.tap(find.byType(AppSwitch), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(reported, isEmpty);
  });
}
