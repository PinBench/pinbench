import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol_finders/patrol_finders.dart';

import 'package:pinbench/features/workspace/providers/problems_provider.dart';
import 'package:pinbench/layout/views/bottom/problems_view.dart';

import '../../support/harness.dart';

class _FakeProblems extends Problems {
  @override
  List<Problem> build() => const [
    Problem(
      severity: ProblemSeverity.error,
      source: ProblemSource.circuit,
      message: 'LED connected backwards',
    ),
    Problem(
      severity: ProblemSeverity.error,
      source: ProblemSource.compiler,
      message: 'Sketch failed to compile',
      detail: "expected ';' before '}'",
    ),
  ];
}

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
  patrolWidgetTest('ProblemsView shows the empty state when there are no problems', ($) async {
    await $.pumpWidgetAndSettle(ProviderScope(child: appTestApp(const ProblemsView())));

    expect($('No problems have been detected in the workspace.').exists, isTrue);
  });

  patrolWidgetTest('ProblemsView lists problems with their source labels', ($) async {
    await $.pumpWidgetAndSettle(
      _scope([problemsProvider.overrideWith(_FakeProblems.new)], const ProblemsView()),
    );

    expect($('LED connected backwards').exists, isTrue);
    expect($('Sketch failed to compile').exists, isTrue);
    expect($('Circuit').exists, isTrue);
    expect($('Compiler').exists, isTrue);
  });
}
