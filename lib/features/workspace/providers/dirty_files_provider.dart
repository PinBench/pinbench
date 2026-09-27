import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'dirty_files_provider.g.dart';

/// Tracks which open file paths have unsaved edits (a VS Code-style "dirty"
/// dot).
///
/// Fed by `EditorStateController` via the callbacks wired in
/// `workspace_provider.dart`: every editor controller reports whether its live
/// text differs from the last-saved snapshot.
// Kept alive because the things that drive it are: `editorStateControllerProvider`, which is keep-alive.
// A `@Riverpod(keepAlive: true)` provider reading an autoDispose one pins it
// through a `KeepAliveLink` anyway, so this is what already happens at
// runtime — saying it out loud is what `only_use_keep_alive_inside_keep_alive`
// asks for, and it stops the lifetime depending on who happens to be watching.
@Riverpod(keepAlive: true)
class DirtyFiles extends _$DirtyFiles {
  @override
  Set<String> build() => const {};

  /// Marks [path] dirty or clean, only emitting a new state when it changes so
  /// tabs don't rebuild on every keystroke of an already-dirty file.
  // ignore: avoid_positional_boolean_parameters
  void setDirty(String path, bool dirty) {
    final has = state.contains(path);
    if (dirty == has) return;
    final next = {...state};
    if (dirty) {
      next.add(path);
    } else {
      next.remove(path);
    }
    state = next;
  }

  bool isDirty(String path) => state.contains(path);
}

/// The set of file paths currently open in editor tabs. Lets the File menu
/// enable/disable Save actions based on whether anything is actually open.
// Kept alive because the things that drive it are: `editorStateControllerProvider`, which is keep-alive.
// A `@Riverpod(keepAlive: true)` provider reading an autoDispose one pins it
// through a `KeepAliveLink` anyway, so this is what already happens at
// runtime — saying it out loud is what `only_use_keep_alive_inside_keep_alive`
// asks for, and it stops the lifetime depending on who happens to be watching.
@Riverpod(keepAlive: true)
class OpenEditorFiles extends _$OpenEditorFiles {
  @override
  Set<String> build() => const {};

  void setPaths(Set<String> paths) => state = paths;
}
