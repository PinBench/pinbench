import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinbench_edition_api/host.dart';

import '../core/chrome/chrome_commands.dart';
import '../core/parts/part_registry_provider.dart';
import '../core/utils/logger.dart';
import '../core/utils/shared_preferences_provider.dart';
import '../features/workspace/providers/editor_state_provider.dart';
import '../features/workspace/providers/problems_provider.dart';
import '../features/workspace/providers/workspace_files_provider.dart';
import '../features/workspace/services/template_service.dart';

/// Binds the host API an edition's side panel talks to (see
/// `package:pinbench_edition_api/host.dart`) to the app's own providers.
///
/// The panel is built outside the app and cannot import it, so this is the
/// whole of what it can see and do. Spread into the root scope alongside the
/// other bindings; see `bootstrap.dart`.
final editionHostBindings = [
  hostWorkspaceProvider.overrideWith((ref) {
    final state = ref.watch(workspaceFilesProvider);
    return HostWorkspace(
      path: state.workspacePath,
      mainCircuitPath: state.mainCdlPath,
      mainSketchPath: state.mainInoPath,
      filePaths: [for (final file in state.files) file.path],
    );
  }),
  hostProblemsProvider.overrideWith(
    (ref) => [
      for (final problem in ref.watch(problemsProvider))
        HostProblem(
          severity: problem.severity.name,
          message: problem.message,
          detail: problem.detail,
        ),
    ],
  ),
  hostPartsProvider.overrideWith((ref) => ref.watch(partRegistryProvider.future)),
  hostActionsProvider.overrideWith(_AppHostActions.new),
];

class _AppHostActions(final Ref _ref) implements HostActions {
  /// A blank workspace being created, so overlapping calls share it — the path
  /// stays null until `openWorkspace` finishes, and without this each caller
  /// would create its own and the second would close the first.
  Future<void>? _ensuring;

  /// A panel's settings live under their own prefix, so one can never read or
  /// overwrite the app's own (the consent answer, layout, milestones).
  static const _settingsPrefix = 'edition.';

  @override
  Future<void> ensureWorkspace() {
    if (_ref.read(workspaceFilesProvider).workspacePath != null) return Future.value();
    return _ensuring ??= _createBlankWorkspace().whenComplete(() => _ensuring = null);
  }

  Future<void> _createBlankWorkspace() async {
    final path = await _ref.read(templateServiceProvider).createBlankWorkspace();
    await _ref.read(workspaceFilesProvider.notifier).openWorkspace(path, isTemporary: true);
  }

  @override
  Future<String?> writeWorkspaceFile(String fileName, String content) =>
      _ref.read(workspaceFilesProvider.notifier).writeWorkspaceFile(fileName, content);

  @override
  String? editorText(String path) =>
      _ref.read(editorStateControllerProvider).openFileControllers[path]?.text;

  @override
  void closeWelcome() => _ref.read(chromeCommandsProvider).closeWelcome();

  @override
  void showSidePanel() =>
      _ref.read(chromeCommandsProvider).setPaneVisible(AppPane.right, visible: true);

  @override
  void openSettings() => _ref.read(chromeCommandsProvider).openSettingsTab();

  @override
  String? readSetting(String key) =>
      _ref.read(sharedPreferencesProvider).getString('$_settingsPrefix$key');

  @override
  Future<void> writeSetting(String key, String value) async {
    await _ref.read(sharedPreferencesProvider).setString('$_settingsPrefix$key', value);
  }

  @override
  void logError(String category, String message, {Object? error, StackTrace? stackTrace}) =>
      AppLogger(category).error(message, error: error, stackTrace: stackTrace);
}
