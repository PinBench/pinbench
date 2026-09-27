import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Where a run's output and failures go.
///
/// Three log channels, a compile-error surface, and the two numbers a finished
/// compile is reported with. The simulation used to write to the workspace's
/// log and problem providers directly, and — worse — did its own parsing of
/// compiler stderr to pick a line for the Problems pane and a category for
/// analytics. Reading gcc output is a diagnostics concern, so it moved to the
/// binding along with the providers it feeds.
abstract interface class SimulationDiagnostics {
  /// A line the sketch printed on the serial port, or a status line about the
  /// run itself. Both go to the Serial Monitor, which is what the user watches.
  void serial(String text);

  /// A line from the analog solver — the generated netlist, convergence
  /// warnings. Its own channel because it is per-run and verbose.
  void spice(String text);

  /// A line from the build/run machinery, as shown in the debug console.
  void debug(String text);

  /// Empties all three channels.
  ///
  /// Called at the start of a run, not the end: what these hold is the
  /// netlist, trace and serial output of *this* run, and leaving the last
  /// run's output up while a new one starts is how a stale error gets read as
  /// a fresh one.
  void clearRunLogs();

  /// Reports the compiler's verdict: the raw error output, or null when the
  /// build succeeded and any previous compile error should be cleared.
  void reportCompileError(String? error);

  /// How many problems are currently showing, from every source. Reported with
  /// each compile so a failure's blast radius is visible in analytics.
  int get problemCount;

  /// A coarse category for the current compile failure — `syntax_error`,
  /// `missing_header`, `linker_error` and so on — or null when the last
  /// compile succeeded. Analytics only; nothing branches on it.
  String? get compileErrorType;
}

/// The live diagnostics binding. Has no default — see `simulationCanvasProvider`
/// for why, and `lib/app/simulation/` for the implementation.
final simulationDiagnosticsProvider = Provider<SimulationDiagnostics>(
  (ref) => throw UnimplementedError(
    'simulationDiagnosticsProvider has no binding. Override it with the adapter in '
    'lib/app/simulation/, or with a fake from test/helpers/simulation_bindings.dart.',
  ),
);
