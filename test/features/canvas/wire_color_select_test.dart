import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:pinbench/features/canvas/controller/canvas_controller.dart';
import 'package:pinbench_parts/models/wire_model.dart';
import 'package:pinbench/features/canvas/widgets/controls/wire_color_select.dart';
import 'package:pinbench_parts/models/port_model.dart';
import '../../support/harness.dart';
import 'package:pinbench_ui/theme/theme.dart';

/// Regression test: the wire color dropdown must rebuild when the canvas
/// selection changes. It used to watch only the controller (notifier), so the
/// displayed color froze at whatever it was first built with — and since a
/// select only reports a pick that differs from the value it is displaying,
/// re-picking the stale color was a silent no-op: the wire only changed after
/// choosing some OTHER color first.
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
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows the selected wire color, and follows a recolor', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(canvasControllerProvider.notifier);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: appTestApp(const WireColorSelect())),
    );

    expect(find.text('Auto'), findsOneWidget, reason: 'no wire selected, no default color');

    final wire = WireModel(
      id: WireModel.generateId(),
      start: const PortLocation(nodeKey: ValueKey('a'), portId: 'p1'),
      end: const PortLocation(nodeKey: ValueKey('b'), portId: 'p2'),
      color: AppPalette.blue,
    );
    controller.updateState(wires: [wire]);
    controller.selectWire(wire.id);
    await tester.pump();

    expect(
      find.text('Blue'),
      findsOneWidget,
      reason: 'selecting a blue wire must show Blue in the dropdown trigger',
    );

    controller.updateWireColor(AppPalette.red);
    await tester.pump();

    expect(
      find.text('Red'),
      findsOneWidget,
      reason: 'recoloring the selected wire must be reflected immediately',
    );
  }, skip: upstreamSemanticsRegression);
}
