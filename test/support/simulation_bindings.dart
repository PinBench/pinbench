import 'package:flutter/foundation.dart';

import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/wire_model.dart';
import 'package:pinbench_sim/core/sketch_compiler.dart';

import 'package:pinbench/features/simulation/ports/simulation_canvas.dart';
import 'package:pinbench/features/simulation/ports/simulation_diagnostics.dart';
import 'package:pinbench/features/simulation/ports/simulation_sketch.dart';

/// Inert bindings for the simulation's three ports.
///
/// The ports have no default implementation on purpose — a missing binding
/// should fail loudly rather than simulate nothing — which means any test that
/// so much as *reads* `simulationProvider` has to supply one. Most of them
/// only render a play button and never start a run, so these do nothing at all.
///
/// Use `fakeSimulationBindings()` for those. A test that wants to assert on
/// what a run did should build the fakes itself and inspect them.
///
/// A closure rather than a function so the list type is *inferred*: Riverpod 3
/// does not export `Override`, so it cannot be written down as a return type.
/// Calling it still hands back fresh fakes, which matters — [FakeSimulationCanvas]
/// holds the read-only flag, and one shared across tests would leak.
// ignore: prefer_function_declarations_over_variables, see above
final fakeSimulationBindings = () => [
  simulationCanvasProvider.overrideWithValue(FakeSimulationCanvas()),
  simulationSketchProvider.overrideWithValue(FakeSimulationSketch()),
  simulationDiagnosticsProvider.overrideWithValue(FakeSimulationDiagnostics()),
];

/// An empty circuit whose read-only flag and change signal a test can drive.
class FakeSimulationCanvas extends ChangeNotifier implements SimulationCanvas {
  /// Empty unless a test places something.
  @override
  List<ComponentInstance> simulationNodes = const [];

  @override
  List<WireModel> get simulationWires => const [];

  @override
  void applyNodeUpdates(Map<LocalKey, Map<String, dynamic>> updates) {}

  @override
  var isReadOnly = false;

  @override
  Listenable get changes => this;

  /// Stands in for a part being moved, pressed or turned.
  void emitChange() => notifyListeners();

  /// Whether anything is still subscribed to [changes] — `hasListeners` is
  /// protected, so a test cannot ask directly.
  bool get isObserved => hasListeners;
}

/// An empty sketch whose compiler and workspace signal a test can drive.
///
/// [compiler] throws by default, so a run started by accident stops at the
/// compile step instead of spawning an emulator isolate inside a widget test.
class FakeSimulationSketch extends ChangeNotifier implements SimulationSketch {
  @override
  var source = '';

  @override
  String? workspacePath;

  @override
  String? precompiledHex;

  @override
  SketchCompiler compiler = ({workspacePath, required code, required board}) async =>
      throw StateError('no compiler in tests');

  var saveCount = 0;

  /// Runs inside [save], so a test can make flushing change what [source]
  /// returns — the only way to observe that saving happens *first*.
  void Function()? onSave;

  @override
  Future<void> save() async {
    saveCount++;
    onSave?.call();
  }

  @override
  Listenable get workspaceChanges => this;

  /// Stands in for a different project or template being opened.
  void emitWorkspaceChange() => notifyListeners();
}

/// Records nothing and reports a clean slate.
class FakeSimulationDiagnostics implements SimulationDiagnostics {
  @override
  void serial(String text) {}

  @override
  void spice(String text) {}

  @override
  void debug(String text) {}

  @override
  void clearRunLogs() {}

  @override
  void reportCompileError(Object? error) {}

  @override
  int get problemCount => 0;

  @override
  String? get compileErrorType => null;
}
