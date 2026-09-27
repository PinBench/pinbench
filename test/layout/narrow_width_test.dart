import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench/features/canvas/providers/canvas_controller_provider.dart';
import 'package:pinbench/features/canvas/widgets/properties/properties_view.dart';
import 'package:pinbench/layout/views/bottom/problems_view.dart';
import 'package:pinbench_parts/models/part_model.dart';
import 'package:pinbench/features/workspace/providers/problems_provider.dart';

import '../support/harness.dart';

/// The surfaces that carry content, at the window floor and below it.
///
/// The desktop runners refuse to go below 800x600, but the web has no such
/// floor, and this app has produced four overflow bugs in one stretch — the
/// colour list, the properties switch, a welcome tile, and the title bar.
/// Every one was found by eye, because only two test files in the suite
/// constrain the viewport and the rest run wider than the break.
///
/// Empty states are trivially narrow-safe, so these mount real content: a
/// selected part in the properties sidebar (which is where the 48px switch
/// overflow lived) and a problem whose message runs long.
void main() {
  for (final size in [const Size(800, 600), const Size(640, 480), const Size(400, 400)]) {
    final label = '${size.width.toInt()}x${size.height.toInt()}';

    testWidgets('properties with a selected part at $label', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(canvasControllerProvider.notifier);
      final node = ComponentInstance(
        key: const ValueKey('led1'),
        position: Offset.zero,
        part: PartModel(name: 'LED', size: const Size(40, 40)),
      );
      controller.updateState(nodes: [node], selectedNodes: [node]);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: appTestApp(
            // The real sidebar is a fixed-width pane, so give it one.
            const SizedBox(width: 260, child: PropertiesSidebarView()),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
    });

    testWidgets('problems with a long message at $label', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(problemsProvider.notifier).setForSource(ProblemSource.circuit, [
        const Problem(
          severity: ProblemSeverity.error,
          source: ProblemSource.circuit,
          message:
              'LED "led_red" has no current-limiting resistor between its anode and '
              'the 5V rail, which will draw far more current than the pin can supply',
          detail: 'Add a resistor of at least 220 ohms in series with the LED anode.',
        ),
      ]);

      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: appTestApp(const ProblemsView())),
      );
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
    });
  }
}
