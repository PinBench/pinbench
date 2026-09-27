import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../services/editor_state_controller.dart';
import 'dirty_files_provider.dart';

part 'editor_state_provider.g.dart';

/// The open editor buffers, and the bridge that publishes their dirty/open
/// state into Riverpod.
///
/// This lives under `workspace/` rather than `editor/` because the workspace is
/// what reads it: saving, cloud sync, tab lifecycle and the explorer all ask
/// which files are open and what is in them. The editor owns two tab widgets
/// that read it back, which is the ordinary direction for a feature to depend
/// on the one below it.
@Riverpod(keepAlive: true)
EditorStateController editorStateController(Ref ref) {
  final controller = EditorStateController();
  // Bridge per-file dirty / open state into Riverpod so tabs and the File menu
  // can react to unsaved-edit state.
  controller.onDirtyChanged = (path, isDirty) {
    ref.read(dirtyFilesProvider.notifier).setDirty(path, isDirty);
  };
  controller.onOpenFilesChanged = (paths) {
    ref.read(openEditorFilesProvider.notifier).setPaths(paths);
  };
  ref.onDispose(controller.dispose);
  return controller;
}
