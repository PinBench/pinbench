import 'package:flutter/foundation.dart' show immutable, listEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinbench_parts/models/part_model.dart';

// The app, as a side panel sees it.
//
// Each provider here is an override placeholder: the app binds all of them in
// its root scope (`app/edition_host_bindings.dart`), and a panel reads them
// like any other provider. A panel therefore never imports the app — which it
// could not do anyway, since the app depends on it.

/// The open workspace, or an empty one when none is open.
@immutable
class HostWorkspace {
  const HostWorkspace({
    this.path,
    this.mainCircuitPath,
    this.mainSketchPath,
    this.filePaths = const [],
  });

  /// The workspace folder, or null when no project is open.
  final String? path;

  /// The `.cdl` the project nominates as its circuit, if it does.
  final String? mainCircuitPath;

  /// The `.ino` the project nominates as its sketch, if it does.
  final String? mainSketchPath;

  /// Every file in the workspace, in the explorer's (alphabetical) order.
  final List<String> filePaths;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HostWorkspace &&
          other.path == path &&
          other.mainCircuitPath == mainCircuitPath &&
          other.mainSketchPath == mainSketchPath &&
          listEquals(other.filePaths, filePaths);

  @override
  int get hashCode => Object.hash(path, mainCircuitPath, mainSketchPath, Object.hashAll(filePaths));
}

/// A problem the app is reporting — from the circuit validator or the
/// compiler.
@immutable
class HostProblem {
  const HostProblem({required this.severity, required this.message, this.detail});

  /// `error`, `warning` or `info`.
  final String severity;
  final String message;
  final String? detail;
}

/// What a side panel may ask the app to do.
abstract interface class HostActions {
  /// Opens a new, temporary blank project if none is open.
  Future<void> ensureWorkspace();

  /// Writes [fileName] into the open workspace and returns the path written,
  /// or null when no workspace is open.
  Future<String?> writeWorkspaceFile(String fileName, String content);

  /// The live text of [path] in the editor, including unsaved edits, or null
  /// when it is not open.
  String? editorText(String path);

  /// Leaves the welcome screen for the open project.
  void closeWelcome();

  /// Reveals the side panel's pane.
  void showSidePanel();

  /// Opens the settings tab, where the panel's `SidePanel.settings` is shown.
  void openSettings();

  /// A persisted setting, or null when unset.
  String? readSetting(String key);

  /// Persists a setting.
  Future<void> writeSetting(String key, String value);

  /// Reports an error to the app's log and crash reporting.
  void logError(String category, String message, {Object? error, StackTrace? stackTrace});
}

Never _unbound(String name) => throw UnimplementedError(
  '$name has no binding. The app overrides it in its root scope; a test that '
  'renders a side panel must override it too.',
);

final hostWorkspaceProvider = Provider<HostWorkspace>((ref) => _unbound('hostWorkspaceProvider'));

final hostProblemsProvider = Provider<List<HostProblem>>((ref) => _unbound('hostProblemsProvider'));

/// The part catalog: every part the canvas can place.
final hostPartsProvider = FutureProvider<List<PartModel>>((ref) => _unbound('hostPartsProvider'));

final hostActionsProvider = Provider<HostActions>((ref) => _unbound('hostActionsProvider'));
