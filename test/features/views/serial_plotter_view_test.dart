import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol_finders/patrol_finders.dart';

import 'package:pinbench/features/workspace/providers/serial_plotter_provider.dart';
import 'package:pinbench/layout/views/bottom/serial_plotter_view.dart';

import '../../support/harness.dart';

/// Overrides go through a [ProviderContainer] + [UncontrolledProviderScope]
/// rather than `ProviderScope(overrides: ...)`, which is what most of this
/// suite already does.
///
/// It is also the shape `scoped_providers_should_specify_dependencies` accepts:
/// the rule treats a bare `ProviderScope(overrides: ...)` as scoped unless it
/// sits syntactically inside `runApp` or flutter_test's `pumpWidget`, and
/// patrol's `pumpWidgetAndSettle` is neither. A container that is never given
/// a parent is not scoped, and the rule agrees.
/// A test root that applies [overrides] without `ProviderScope(overrides: ...)`.
Widget _scope(List<Override> overrides, Widget child) {
  final container = ProviderContainer(overrides: overrides);
  addTearDown(container.dispose);
  return UncontrolledProviderScope(container: container, child: appTestApp(child));
}

void main() {
  patrolWidgetTest('SerialPlotterView shows a hint when there is no numeric data', ($) async {
    await $.pumpWidgetAndSettle(
      _scope([
        serialPlotterDataProvider.overrideWithValue(const SerialPlotData([])),
      ], const SerialPlotterView()),
    );

    expect(find.textContaining('No numeric serial data'), findsOneWidget);
  });

  patrolWidgetTest('SerialPlotterView renders a chart when data is present', ($) async {
    await $.pumpWidgetAndSettle(
      _scope([
        serialPlotterDataProvider.overrideWithValue(
          const SerialPlotData([
            [1, 2, 3, 4],
            [4, 3, 2, 1],
          ]),
        ),
      ], const SerialPlotterView()),
    );

    expect($(LineChart).exists, isTrue);
  });
}
