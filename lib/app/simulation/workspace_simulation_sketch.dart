import 'package:flutter/foundation.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinbench_sim/core/sketch_compiler.dart';

import '../../features/simulation/ports/simulation_sketch.dart';
import '../../features/workspace/providers/workspace_files_provider.dart';
import '../../features/workspace/providers/editor_state_provider.dart';
import '../../features/workspace/services/workspace_sketch_compiler.dart';

/// Binds the simulation's [SimulationSketch] port to the open workspace.
///
/// Everything here is a workspace question the simulation used to answer for
/// itself by reading four of the workspace's providers directly: which buffer
/// is the sketch, whether there is a directory to build, whether a template
/// shipped a prebuilt image, and when the whole workspace has been swapped.
class WorkspaceSimulationSketch(final Ref _ref) extends ChangeNotifier implements SimulationSketch {
  /// Read at call time rather than captured: a run starts against whatever is
  /// open *now*, and the adapter outlives any particular workspace.
  @override
  String get source {
    final editorState = _ref.read(editorStateControllerProvider);
    final mainIno = _ref.read(workspaceFilesProvider).mainInoPath;

    // Prefer the explicitly-configured main sketch; otherwise fall back to the
    // first open `.ino`.
    if (mainIno != null && editorState.openFileControllers.containsKey(mainIno)) {
      return editorState.openFileControllers[mainIno]!.text;
    }
    for (final entry in editorState.openFileControllers.entries) {
      if (entry.key.endsWith('.ino')) return entry.value.text;
    }
    return '';
  }

  @override
  String? get workspacePath => _ref.read(workspaceFilesProvider).workspacePath;

  @override
  String? get precompiledHex => _ref.read(workspaceFilesProvider).precompiledHexContent;

  @override
  SketchCompiler get compiler => workspaceSketchCompiler;

  @override
  Future<void> save() => _ref.read(workspaceFilesProvider.notifier).saveAll();

  @override
  Listenable get workspaceChanges => this;

  /// Called by the binding provider when a *different* workspace is opened.
  void onWorkspaceChanged() => notifyListeners();
}
