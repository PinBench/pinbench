import 'package:flutter/foundation.dart';

import 'package:re_editor/re_editor.dart';

/// Owns the live text editor controllers for every open file, keyed by path.
///
/// One [CodeLineEditingController] per file is created on first open and reused
/// afterwards, so edits and cursor position survive tab switches until the file
/// is closed (which disposes it).
///
/// Also tracks per-file "dirty" state (live text vs. the last-saved snapshot) so
/// the UI can show a VS Code-style unsaved indicator. Consumers subscribe via
/// [onDirtyChanged]/[onOpenFilesChanged]; the wiring to Riverpod lives in
/// `workspace_provider.dart`.
class EditorStateController {
  final Map<String, CodeLineEditingController> openFileControllers = {};

  /// Hash of the last-saved text per open file, used to derive dirty state.
  final Map<String, int> _savedHashes = {};
  final Map<String, VoidCallback> _dirtyListeners = {};

  /// Fired whenever a file's dirty state changes (edited, saved, reverted).
  // ignore: avoid_positional_boolean_parameters
  void Function(String path, bool isDirty)? onDirtyChanged;

  /// Fired whenever the set of open files changes (open/close).
  void Function(Set<String> openPaths)? onOpenFilesChanged;

  CodeLineEditingController openFile(String path, String initialText) {
    final existing = openFileControllers[path];
    if (existing != null) return existing;

    final controller = CodeLineEditingController.fromText(initialText);
    openFileControllers[path] = controller;
    _savedHashes[path] = initialText.hashCode;

    void listener() {
      onDirtyChanged?.call(path, controller.text.hashCode != (_savedHashes[path] ?? 0));
    }

    _dirtyListeners[path] = listener;
    controller.addListener(listener);
    onOpenFilesChanged?.call(openFileControllers.keys.toSet());
    return controller;
  }

  void closeFile(String path) {
    final controller = openFileControllers.remove(path);
    if (controller == null) return;
    final listener = _dirtyListeners.remove(path);
    if (listener != null) controller.removeListener(listener);
    controller.dispose();
    _savedHashes.remove(path);
    onDirtyChanged?.call(path, false);
    onOpenFilesChanged?.call(openFileControllers.keys.toSet());
  }

  /// Records [text] as the saved baseline for [path], clearing its dirty flag.
  void markSaved(String path, String text) {
    if (!openFileControllers.containsKey(path)) return;
    _savedHashes[path] = text.hashCode;
    onDirtyChanged?.call(path, false);
  }

  /// Whether [path] has unsaved edits relative to its last-saved snapshot.
  bool isDirty(String path) {
    final controller = openFileControllers[path];
    if (controller == null) return false;
    return controller.text.hashCode != (_savedHashes[path] ?? 0);
  }

  CodeLineEditingController? getActiveController(String activeTabId) =>
      openFileControllers[activeTabId];

  void dispose() {
    for (final entry in openFileControllers.entries) {
      final listener = _dirtyListeners[entry.key];
      if (listener != null) entry.value.removeListener(listener);
      entry.value.dispose();
    }
    openFileControllers.clear();
    _dirtyListeners.clear();
    _savedHashes.clear();
  }
}
