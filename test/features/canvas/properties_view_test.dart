import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol_finders/patrol_finders.dart';
import 'package:pinbench_ui/ui/app_switch.dart';

import 'package:pinbench_parts/cdl/circuit_parser.dart';
import 'package:pinbench_parts/part_registry.dart';
import 'package:pinbench/features/canvas/controller/canvas_controller.dart';
import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench/features/canvas/widgets/properties/properties_view.dart';
import 'package:pinbench_parts/models/part_model.dart';

import '../../support/harness.dart';

PartModel _model(String name) => standardParts.firstWhere((c) => c.name == name);

/// Blocked on a Flutter 3.47 framework regression, not on anything here.
///
/// `MergeSemantics` with a descendant that produces a sibling merge group —
/// which is every text field inside a forui overlay — trips
/// `'node.isMergedIntoParent': is not true` in `semantics.dart` while the
/// semantics tree is built. Filed as flutter/flutter#191095 on 2026-08-14 and
/// accepted as `c: regression` by team-accessibility. It reproduces with
/// Material's own `TextField` too, and it is what blocks forui's own 3.47
/// migration (duobaseio/forui#1159).
///
/// It is an assert, so it fires in debug only and the shipped app is
/// unaffected — but widget tests run in debug, so these cannot pass until the
/// fix lands. Checked against the pre-migration tree as well: this is not
/// fallout from moving off Material.
///
/// Delete this constant and the `skip:`s with it when Flutter ships the fix.
const upstreamSemanticsRegression = true;

void main() {
  // Regression test: PropertiesSidebarView only watched
  // `canvasControllerProvider.notifier` (the controller instance), never the
  // provider's state — so it never rebuilt when a field edit (e.g. the
  // "Flipped Horizontal"/"Flipped V" switches) changed `node.flipHorizontal`. The
  // switch would visually snap back to its old value since Flutter kept
  // rendering it with the stale `value:` from the last build.
  patrolWidgetTest('flipping "Flipped Horizontal" updates the switch after the toggle', ($) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final controller = container.read(canvasControllerProvider.notifier);
    final node = ComponentInstance(position: Offset.zero, part: _model(PartNames.led));
    controller.add(node);
    controller.selectedNodes = [node];

    await $.pumpWidgetAndSettle(
      UncontrolledProviderScope(
        container: container,
        child: appTestApp(const PropertiesSidebarView()),
      ),
    );

    Finder flippedHSwitchFinder() => find.byWidgetPredicate(
      (w) => w is AppSwitch && w.value == controller.selectedNodes.first.flipHorizontal,
    );

    expect(controller.selectedNodes.first.flipHorizontal, isFalse);
    // Locate the "Flipped Horizontal" row's switch by its position relative to the label.
    final label = find.text('Flipped Horizontal');
    expect(label, findsOneWidget);
    final switchFinder = find.descendant(
      of: find.ancestor(of: label, matching: find.byType(Row)),
      matching: find.byType(AppSwitch),
    );
    expect(switchFinder, findsOneWidget);
    expect($.tester.widget<AppSwitch>(switchFinder).value, isFalse);

    await $.tester.tap(switchFinder);
    await $.pumpAndSettle();

    expect(controller.selectedNodes.first.flipHorizontal, isTrue);
    expect(
      $.tester.widget<AppSwitch>(switchFinder).value,
      isTrue,
      reason: 'the switch must rebuild to reflect the new flip state',
    );
    expect(flippedHSwitchFinder(), findsOneWidget);
  }, skip: upstreamSemanticsRegression);

  // The properties sidebar is narrow and the switch is a fixed-size control,
  // so the label has to give way. It did not, and "Flipped Horizontal"
  // overflowed its row by 48 pixels.
  patrolWidgetTest('the switch rows fit a narrow sidebar', ($) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final controller = container.read(canvasControllerProvider.notifier);
    final node = ComponentInstance(position: Offset.zero, part: _model(PartNames.led));
    controller.add(node);
    controller.selectedNodes = [node];

    await $.pumpWidgetAndSettle(
      UncontrolledProviderScope(
        container: container,
        child: appTestApp(const SizedBox(width: 220, child: PropertiesSidebarView())),
      ),
    );

    expect($.tester.takeException(), isNull);
  });

  // Regression test: the properties panel's text fields committed only on
  // `onSubmitted`, i.e. only when Enter was pressed. Typing a new resistance and
  // clicking back onto the canvas — the ordinary way to do it — discarded the
  // edit silently, so the panel disagreed with the `.cdl`, the netlist and the
  // solver until the user happened to press Enter.
  patrolWidgetTest('editing a property commits when the field loses focus', ($) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final controller = container.read(canvasControllerProvider.notifier);
    final node = ComponentInstance(
      position: Offset.zero,
      part: _model(PartNames.resistor),
      properties: const {ComponentProps.resistance: '220'},
    );
    controller.add(node);
    controller.selectedNodes = [node];

    await $.pumpWidgetAndSettle(
      UncontrolledProviderScope(
        container: container,
        child: appTestApp(const SizedBox(width: 320, child: PropertiesSidebarView())),
      ),
    );

    final field = find.descendant(
      of: find.byKey(Key('${node.key}_${ComponentProps.resistance}')),
      matching: find.byType(EditableText),
    );
    expect(field, findsOneWidget);

    await $.tester.enterText(field, '470');
    // Deliberately NOT testTextInput.receiveAction(TextInputAction.done) — the
    // whole point is that focus loss alone must be enough.
    FocusManager.instance.primaryFocus?.unfocus();
    await $.pumpAndSettle();

    final updated = controller.nodes.firstWhere((n) => n.key == node.key);
    expect(updated.properties[ComponentProps.resistance], '470');

    // And the change must reach the file the solver reads.
    expect(
      CircuitParser.generate(controller.nodes, controller.wires),
      contains('resistance: 470;'),
    );
  }, skip: upstreamSemanticsRegression);
}
