import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench/app/simulation/workspace_simulation_diagnostics.dart';
import 'package:pinbench/features/workspace/providers/problems_provider.dart';

/// The running circuit's warnings — a supply rail past its rating — reach the
/// Problems pane as warnings of their own source, and go with the run.
void main() {
  late ProviderContainer container;
  late WorkspaceSimulationDiagnostics diagnostics;

  setUp(() {
    container = ProviderContainer();
    diagnostics = container.read(Provider(WorkspaceSimulationDiagnostics.new));
  });
  tearDown(() => container.dispose());

  const overload =
      "The Arduino Uno's 3.3V supply is delivering 330 mA, more than the 150 mA it is rated for.";

  test('each warning is a simulation warning in the Problems pane', () {
    diagnostics.reportCircuitWarnings(const [overload]);

    final problem = container.read(problemsProvider).single;
    expect(problem.severity, ProblemSeverity.warning);
    expect(problem.source, ProblemSource.simulation);
    expect(problem.message, overload);
  });

  test('an empty list clears them', () {
    diagnostics.reportCircuitWarnings(const [overload]);
    diagnostics.reportCircuitWarnings(const []);
    expect(container.read(problemsProvider), isEmpty);
  });

  test("a new run starts without the last run's warnings", () {
    diagnostics.reportCircuitWarnings(const [overload]);
    diagnostics.clearRunLogs();
    expect(container.read(problemsProvider), isEmpty);
  });

  test('they sit beside, and do not replace, a compile error', () {
    diagnostics.reportCompileError(Exception('error: x'));
    diagnostics.reportCircuitWarnings(const [overload]);
    expect(
      container.read(problemsProvider).map((p) => p.source),
      containsAll([ProblemSource.compiler, ProblemSource.simulation]),
    );
  });
}
