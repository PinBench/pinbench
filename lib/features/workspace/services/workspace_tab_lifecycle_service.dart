import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_editor/re_editor.dart';

import '../providers/editor_state_provider.dart';
import '../providers/canvas_code_sync_provider.dart';
import '../../../core/chrome/chrome_commands.dart';

/// Shared editor/canvas tab-lifecycle mechanics for `WorkspaceFiles`: closing
/// every open tab, and opening a file's editor controller (attaching the
/// canvas/code-sync listener when it's a `.cdl`). Extracted to remove the
/// identical "read file → open editor controller → attach cdl listener"
/// logic that was duplicated between the bulk workspace-open loop and
/// `openSingleFile`.
///
/// Deliberately does NOT own tab-open/focus sequencing: the bulk workspace
/// open and the single-file "Open…" action have genuinely different focus
/// semantics (the bulk loop re-focuses the canvas tab per `.cdl` file as it
/// opens; a single ad-hoc open doesn't need that), so callers keep that
/// logic themselves rather than have it collapsed into one shared behavior.
class WorkspaceTabLifecycleService(final Ref _ref) {
  /// Closes every currently-open editor/canvas tab and disposes its
  /// controller, so opening a workspace always starts from a clean slate.
  /// Without this, opening a second workspace (or re-opening after `build()`
  /// auto-opened a recent one) accumulates duplicate tabs — every
  /// workspace's files share the same basenames (e.g. `circuit.cdl`,
  /// `blink.ino`), so they look identical.
  void closeAllOpenTabs() {
    final editorState = _ref.read(editorStateControllerProvider);
    final chrome = _ref.read(chromeCommandsProvider);
    final canvasSyncService = _ref.read(canvasCodeSyncServiceProvider);

    for (final openPath in editorState.openFileControllers.keys.toList()) {
      chrome.closeTab(AppTabs.editor(openPath));
      if (openPath.endsWith('.cdl')) {
        chrome.closeTab(AppTabs.canvas(openPath));
        canvasSyncService.detachCdlListener(openPath);
      }
      editorState.closeFile(openPath);
    }
  }

  /// Opens [filePath] (with pre-read [contents]) as an editor-state
  /// controller, attaching the canvas/code-sync listener if it's a `.cdl`.
  /// Callers must ensure the component registry is loaded before calling
  /// this for a `.cdl` file, and are responsible for their own tab-open/focus
  /// sequencing afterward.
  CodeLineEditingController openFileController(String filePath, String contents) {
    final editorState = _ref.read(editorStateControllerProvider);
    final controller = editorState.openFile(filePath, contents);
    if (filePath.endsWith('.cdl')) {
      _ref.read(canvasCodeSyncServiceProvider).attachCdlListener(filePath, controller);
    }
    return controller;
  }
}
