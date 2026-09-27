import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:re_editor/re_editor.dart';
import 'package:pinbench_cloud/project_model.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/cloud/project_providers.dart';
import '../../../core/platform/platform_capabilities.dart';
import '../../../core/utils/logger.dart';
import '../../../core/telemetry/telemetry_providers.dart';
import '../data/workspace_fs.dart';
import '../models/workspace_state.dart';
import '../services/cloud_project_sync.dart';
import '../services/workspace_export_service.dart';
import '../services/workspace_file_ops_service.dart';
import '../services/workspace_tab_lifecycle_service.dart';
import '../../../core/parts/part_registry_provider.dart';
import 'recent_workspaces_provider.dart';
import 'workspace_loading_provider.dart';
import 'editor_state_provider.dart';
import 'canvas_code_sync_provider.dart';
import '../../../core/chrome/chrome_commands.dart';

part 'workspace_files_provider.g.dart';

@Riverpod(keepAlive: true)
class WorkspaceFiles extends _$WorkspaceFiles {
  static const _log = AppLogger('app.workspace.files');

  final _fs = WorkspaceFs();
  StreamSubscription<FileSystemEvent>? _watchSubscription;
  Timer? _debounceTimer;
  Timer? _autoSaveTimer;
  var _autoSaveEnabled = false;

  /// Tracks the last-written content hash per file path so auto-save can skip
  /// unchanged files. Keyed by absolute file path.
  final _contentHashes = <String, int>{};
  var _hasUnsavedChanges = false;

  /// Owns the live cloud link for [WorkspaceState.cloudProjectId]:
  /// applying remote collaborators' edits to local disk/editor buffers as
  /// they arrive, and pushing local saves back out. See [CloudProjectSync].
  late final _cloudSync = CloudProjectSync(ref: ref, fs: _fs, contentHashes: _contentHashes);
  late final _fileOps = WorkspaceFileOpsService(_fs);
  late final _tabLifecycle = WorkspaceTabLifecycleService(ref);

  @override
  WorkspaceState build() {
    ref.onDispose(() async {
      await _watchSubscription?.cancel();
      await _cloudSync.unlink();
      _debounceTimer?.cancel();
      _autoSaveTimer?.cancel();
    });

    return const WorkspaceState();
  }

  Future<void> setWorkspace({required String workspacePath, bool isTemporary = false}) async {
    // On web, restore any persisted workspace data from localStorage.
    // No-op on native and on first visit.
    await _fs.restore();

    if (!_fs.existsDir(workspacePath)) return;

    final files = _scanFiles(workspacePath);

    // Update recent workspaces only if not temporary
    if (!isTemporary) {
      await ref.read(recentWorkspacesProvider.notifier).addWorkspace(workspacePath);
    }
    // Segment usage by how the project was entered (template vs saved workspace).
    ref.read(analyticsProvider).setEntryMode(isTemporary ? 'template' : 'workspace');

    state = state.copyWith(
      workspacePath: workspacePath,
      files: files,
      isTemporary: isTemporary,
      // A fresh workspace has its own (or no) main-file / hex config.
      clearMainInoPath: true,
      clearMainCdlPath: true,
      clearPrecompiledHexPath: true,
    );

    // Setup file watcher. The web in-memory store emits no filesystem events, so
    // there is nothing to watch there.
    if (kIsWeb) return;
    await _watchSubscription?.cancel();
    _watchSubscription = Directory(workspacePath).watch(recursive: true).listen((event) {
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 200), () {
        _refreshFiles(workspacePath);
      });
    });
  }

  List<FileSystemEntity> _scanFiles(String dirPath) => _fileOps.scanFiles(dirPath);

  void _refreshFiles(String path) {
    if (!_fs.existsDir(path)) return;

    final files = _scanFiles(path);
    state = state.copyWith(files: files);

    final editorState = ref.read(editorStateControllerProvider);
    for (final entry in editorState.openFileControllers.entries) {
      if (_fs.existsFile(entry.key)) {
        final newContent = _fs.readStringSync(entry.key);
        if (entry.value.text != newContent) {
          entry.value.text = newContent;
          final lines = newContent.split('\n');
          final lastLineIndex = lines.isEmpty ? 0 : lines.length - 1;
          final lastLineLength = lines.isEmpty ? 0 : lines.last.length;
          entry.value.selection = CodeLineSelection(
            baseIndex: lastLineIndex,
            baseOffset: lastLineLength,
            extentIndex: lastLineIndex,
            extentOffset: lastLineLength,
          );
        }
      }
    }
  }

  void setActiveFile(String path) {
    state = state.copyWith(activeFilePath: path);
  }

  // ---------------------------------------------------------------------------
  // Run configuration: which sketch/circuit runs, and optional prebuilt hex.
  // ---------------------------------------------------------------------------

  /// Sets the `.ino` sketch that compile/simulate should use (null = auto-pick
  /// the first open `.ino`).
  void setMainInoPath(String? path) {
    state = path == null
        ? state.copyWith(clearMainInoPath: true)
        : state.copyWith(mainInoPath: path);
  }

  /// Sets the `.cdl` circuit the simulation should run. Also makes it the
  /// active circuit on the canvas so the two stay in sync.
  Future<void> setMainCdlPath(String? path) async {
    state = path == null
        ? state.copyWith(clearMainCdlPath: true)
        : state.copyWith(mainCdlPath: path);
    if (path != null) {
      await openSingleFile(path);
      ref.read(chromeCommandsProvider).focusTab(AppTabs.canvas(path));
    }
  }

  /// Registers a user-supplied precompiled `.hex`: subsequent runs load this
  /// HEX directly and skip compilation. [path] is kept for display only.
  void loadPrecompiledHex({required String path, required String content}) {
    state = state.copyWith(precompiledHexPath: path, precompiledHexContent: content);
  }

  /// Clears any loaded precompiled hex so runs compile the sketch again.
  void clearPrecompiledHex() {
    state = state.copyWith(clearPrecompiledHexPath: true);
  }

  void clearWorkspaceState() {
    unawaited(_watchSubscription?.cancel());
    unawaited(_cloudSync.unlink());
    _debounceTimer?.cancel();
    state = const WorkspaceState();
  }

  /// Links the current workspace to cloud project [projectId]: subsequent
  /// [saveWorkspace] calls also push each changed file to the backend, and
  /// other collaborators' edits are pulled in live
  /// (last-write-wins, per [ProjectFile]'s concurrency model). See
  /// [CloudProjectSync].
  Future<void> linkCloudProject(String projectId) async {
    // Clearing the shared-view state is part of linking, not an afterthought:
    // the two are mutually exclusive by design (a live link means you can
    // write; a shared view means you cannot). "Save a copy" goes through here,
    // and without this the visitor would keep being told they are viewing
    // someone else's project while editing their own copy.
    state = state.copyWith(cloudProjectId: projectId, clearViewingShared: true);
    await _cloudSync.link(
      projectId: projectId,
      workspacePath: () => state.workspacePath,
      onFilesChanged: _refreshFiles,
    );
  }

  /// Subscribes a **read-only** shared view to the original project's files, so
  /// an embed reflects the author's edits without the reader reloading.
  ///
  /// Deliberately not [linkCloudProject]: that also sets `cloudProjectId`,
  /// which is the flag every save path checks before pushing to the cloud.
  /// Leaving it null keeps writing structurally impossible while still pulling
  /// — `CloudProjectSync.link` only ever writes remote changes to local disk,
  /// the push side lives in [saveWorkspace].
  Future<void> watchSharedProject(String projectId) async {
    await _cloudSync.link(
      projectId: projectId,
      workspacePath: () => state.workspacePath,
      onFilesChanged: _refreshFiles,
    );
  }

  Future<void> openWorkspace(String path, {bool isTemporary = false}) async {
    ref.read(workspaceLoadingProvider.notifier).begin();
    try {
      await _openWorkspaceInner(path, isTemporary: isTemporary);
    } finally {
      ref.read(workspaceLoadingProvider.notifier).end();
    }
  }

  Future<void> _openWorkspaceInner(String path, {bool isTemporary = false}) async {
    _tabLifecycle.closeAllOpenTabs();
    await _cloudSync.unlink();
    // Clear both cloud associations. `viewingShared` in particular has to go:
    // it drives a "you are viewing someone else's project" banner, and leaving
    // it set would mislabel the next workspace opened. `openCloudProject` sets
    // whichever of the two applies *after* this runs.
    state = state.copyWith(clearCloudProjectId: true, clearViewingShared: true);
    await setWorkspace(workspacePath: path, isTemporary: isTemporary);

    // If the folder didn't exist, setWorkspace left the workspace unset — stay on
    // the welcome screen rather than pretending a folder is open.
    if (state.workspacePath != path) return;

    // A real folder is now open: drop the welcome tab so it can't linger as the
    // active view alongside the workspace.
    ref.read(chromeCommandsProvider).closeTab(AppTabs.welcome);

    final workspaceState = state;
    final filesToOpen = workspaceState.files.where((f) {
      final isRoot = p.dirname(f.path) == path;
      return isRoot &&
          (f.path.endsWith('.ino') || f.path.endsWith('.pdl') || f.path.endsWith('.cdl'));
    }).toList();

    // Sort to ensure .cdl files are opened first
    filesToOpen.sort((a, b) {
      if (a.path.endsWith('.cdl') && !b.path.endsWith('.cdl')) return -1;
      if (!a.path.endsWith('.cdl') && b.path.endsWith('.cdl')) return 1;
      return a.path.compareTo(b.path);
    });

    final chrome = ref.read(chromeCommandsProvider);
    chrome.setPaneVisible(AppPane.left, visible: true);
    chrome.setPaneVisible(AppPane.bottom, visible: true);
    chrome.focusTab(AppTabs.serialMonitor);

    if (filesToOpen.isNotEmpty) {
      await ref.read(partRegistryProvider.future);
    }

    for (final f in filesToOpen) {
      final filePath = f.path;
      final contents = await _fs.readString(filePath);
      _tabLifecycle.openFileController(filePath, contents);

      if (filePath.endsWith('.cdl')) {
        chrome.openCanvasTab(filePath);
        chrome.openEditorTab(filePath);
        // The canvas is *not* re-opened here to bring it back to the front.
        // Every open and focus is a layout mutation that rebuilds the whole
        // pane tree, and the block below already focuses whichever tab should
        // end up active — so doing it here as well was two extra rebuilds per
        // `.cdl` file, on the path between picking a template and seeing it.
      } else {
        chrome.openEditorTab(filePath);
      }
    }

    if (filesToOpen.isNotEmpty) {
      // Focus the canvas if it exists, otherwise the first file
      final fileToActivate = filesToOpen.firstWhere(
        (f) => f.path.endsWith('.cdl'),
        orElse: () => filesToOpen.first,
      );
      if (fileToActivate.path.endsWith('.cdl')) {
        chrome.focusTab(AppTabs.canvas(fileToActivate.path));
      } else {
        chrome.focusTab(AppTabs.editor(fileToActivate.path));
      }
    }
  }

  /// Saves all open files to their respective locations in the workspace.
  Future<void> saveAll() async {
    ref.read(analyticsProvider).fileSaved('all');
    final workspaceState = state;
    if (workspaceState.workspacePath != null) {
      await saveWorkspace(workspaceState.workspacePath!);
    }
  }

  /// Saves the current workspace.
  ///
  /// A temporary workspace (e.g. one created from a template) or one with no
  /// location yet is promoted by prompting for a destination — see
  /// [saveWorkspaceToLocation]. A normal saved workspace is written in place.
  Future<void> saveCurrentWorkspace() async {
    ref.read(analyticsProvider).fileSaved('current');
    ref.read(milestonesProvider).fireOnce('first_file_save');
    final workspaceState = state;
    final workspacePath = workspaceState.workspacePath;

    if (workspacePath != null && !workspaceState.isTemporary) {
      await saveWorkspace(workspacePath);
    } else {
      await saveWorkspaceToLocation();
    }
  }

  /// Prompts for a parent directory, copies the current files into a project
  /// folder there, and switches to it as a permanent (non-temporary) workspace —
  /// which is what finally adds it to the recent list. Returns true if saved.
  ///
  /// Used for "Save As…" and for saving a temporary template workspace.
  Future<bool> saveWorkspaceToLocation() async {
    ref.read(analyticsProvider).fileSaved('as');
    final parentDir = await getDirectoryPath();
    if (parentDir == null) return false;

    // Preserve the project folder name (Arduino requires the sketch folder name
    // to match the .ino file), creating it under the chosen parent directory.
    final currentPath = state.workspacePath;
    final projectName = currentPath != null ? p.basename(currentPath) : 'sketch';
    final targetDir = p.join(parentDir, projectName);

    await saveWorkspace(targetDir);
    // Re-open as a normal workspace; openWorkspace -> setWorkspace adds a
    // non-temporary workspace to the recent list.
    await openWorkspace(targetDir);
    return true;
  }

  /// Saves the current workspace to the specified directory. When the
  /// workspace is linked to a cloud project (see [linkCloudProject]), each
  /// changed file is also pushed to the cloud so it's saved online and
  /// visible to collaborators in real time.
  Future<void> saveWorkspace(String dirPath) async {
    final editorStateController = ref.read(editorStateControllerProvider);
    final canvasSyncService = ref.read(canvasCodeSyncServiceProvider);

    canvasSyncService.syncCanvasToCodeSync();

    if (!_fs.existsDir(dirPath)) {
      await _fs.createDir(dirPath);
    }

    final cloudProjectId = state.cloudProjectId;
    final uid = ref.read(authServiceProvider).currentUser?.uid;

    for (final entry in editorStateController.openFileControllers.entries) {
      String filePath;
      if (p.isAbsolute(entry.key)) {
        if (entry.key.startsWith(dirPath)) {
          filePath = entry.key;
        } else {
          final fileName = entry.key.split(RegExp(r'[/\\]')).last;
          filePath = '$dirPath/$fileName';
        }
      } else {
        filePath = '$dirPath/${entry.key}';
      }

      final hash = entry.value.text.hashCode;
      // The editor buffer now matches what's on disk either way, so clear its
      // dirty indicator even when the write itself is skipped as unchanged.
      editorStateController.markSaved(entry.key, entry.value.text);
      if (_contentHashes[filePath] == hash) continue; // skip unchanged
      await _fs.writeString(filePath, entry.value.text);
      _contentHashes[filePath] = hash;

      if (cloudProjectId != null && uid != null) {
        final relativePath = p.relative(filePath, from: dirPath).replaceAll(r'\', '/');
        _cloudSync.pushFile(
          projectId: cloudProjectId,
          relativePath: relativePath,
          content: entry.value.text,
          uid: uid,
        );
      }
    }
    _hasUnsavedChanges = false;
  }

  // ---------------------------------------------------------------------------
  // File / workspace operations backing the File menu
  // ---------------------------------------------------------------------------

  /// Opens a single file as an editor tab (and a canvas tab if it is a `.cdl`),
  /// without changing the active workspace. Used by "Open…".
  Future<void> openSingleFile(String filePath) async {
    if (!_fs.existsFile(filePath)) return;
    final contents = await _fs.readString(filePath);

    if (filePath.endsWith('.cdl')) {
      await ref.read(partRegistryProvider.future);
    }
    _tabLifecycle.openFileController(filePath, contents);

    final chrome = ref.read(chromeCommandsProvider);
    if (filePath.endsWith('.cdl')) {
      chrome.openCanvasTab(filePath);
    }
    chrome.openEditorTab(filePath);
  }

  /// Creates [fileName] in the current workspace root (with starter content for
  /// `.ino` files), refreshes the tree and opens it. Returns the new path, or
  /// null if there is no workspace open or the name is empty.
  Future<String?> createFile(String fileName) async {
    final wsPath = state.workspacePath;
    if (wsPath == null || fileName.trim().isEmpty) return null;

    final filePath = p.join(wsPath, fileName.trim());
    await _fileOps.writeStarterFileIfAbsent(filePath);

    _refreshFiles(wsPath);
    await openSingleFile(filePath);
    return filePath;
  }

  /// Writes [content] to [fileName] in the workspace root, overwriting any
  /// existing file, then refreshes the tree and shows the result: an already
  /// open file has its editor buffer replaced (which re-renders the canvas for
  /// a `.cdl`), a closed one is opened.
  ///
  /// The buffer is re-baselined as saved afterwards, because the text and the
  /// file on disk are identical at that point — leaving the tab marked unsaved
  /// would invite the user to "save" a file that is already written.
  ///
  /// Returns the path written, or null if no workspace is open. Backs
  /// `HostActions.writeWorkspaceFile`, an edition side panel's way to write
  /// into the project; see `app/edition_host_bindings.dart`.
  Future<String?> writeWorkspaceFile(String fileName, String content) async {
    final wsPath = state.workspacePath;
    if (wsPath == null || fileName.trim().isEmpty) return null;

    final filePath = p.join(wsPath, fileName.trim());
    final isNewFile = !_fs.existsFile(filePath);
    await _fs.writeString(filePath, content);
    _contentHashes[filePath] = content.hashCode;
    if (isNewFile) _refreshFiles(wsPath);

    final editorState = ref.read(editorStateControllerProvider);
    final controller = editorState.openFileControllers[filePath];
    if (controller == null) {
      await openSingleFile(filePath);
    } else {
      controller.text = content;
      editorState.markSaved(filePath, content);
    }
    return filePath;
  }

  /// Creates a new auto-named `untitled-N.txt` in the workspace and opens it.
  Future<void> createUntitledTextFile() async {
    final wsPath = state.workspacePath;
    if (wsPath == null) return;
    var n = 1;
    while (_fs.existsFile(p.join(wsPath, 'untitled-$n.txt'))) {
      n++;
    }
    await createFile('untitled-$n.txt');
  }

  /// Reloads the active/open file's content from disk, discarding unsaved edits.
  Future<void> revertFile(String filePath) async {
    final editorState = ref.read(editorStateControllerProvider);
    final controller = editorState.openFileControllers[filePath];
    if (controller == null || !_fs.existsFile(filePath)) return;
    final content = await _fs.readString(filePath);
    controller.text = content;
    editorState.markSaved(filePath, content);
  }

  /// Deletes [filePath] from disk and refreshes the explorer tree. Used to
  /// clean up throwaway empty `untitled-*.txt` files when their tab is closed.
  Future<void> deleteWorkspaceFile(String filePath) async {
    if (_fs.existsFile(filePath)) {
      await _fs.deleteFile(filePath);
      _contentHashes.remove(filePath);
    }
    final wsPath = state.workspacePath;
    if (wsPath != null) _refreshFiles(wsPath);
  }

  /// Closes every open tab, clears the workspace and returns to the welcome
  /// screen. Backs "Close Folder".
  void closeFolder() {
    _tabLifecycle.closeAllOpenTabs();
    clearWorkspaceState();
    ref.read(chromeCommandsProvider).resetToWelcome();
    // Safety net: an in-flight (or stuck) open shouldn't leave the loading
    // spinner stranded over the welcome screen once the user navigates away.
    ref.read(workspaceLoadingProvider.notifier).reset();
  }

  /// Copies the current workspace into a sibling `<name>-copy` folder under
  /// [parentDir] and opens it. Backs "Duplicate Workspace".
  Future<bool> duplicateWorkspace(String parentDir) async {
    if (!PlatformCapabilities.supportsLocalFilesystem) return false;
    final src = state.workspacePath;
    if (src == null) return false;

    await saveWorkspace(src); // persist current edits before copying
    final baseName = '${p.basename(src)}-copy';
    var dest = p.join(parentDir, baseName);
    var i = 2;
    while (Directory(dest).existsSync()) {
      dest = p.join(parentDir, '$baseName-$i');
      i++;
    }
    await Directory(dest).create(recursive: true);
    await _fileOps.copyDirectory(src, dest);
    await openWorkspace(dest);
    return true;
  }

  /// Creates a new cloud project from the currently open workspace,
  /// pushes every file in it there, links this workspace to the new project
  /// (see [linkCloudProject]), and returns the new project id — or `null` if
  /// there's no workspace open or the caller isn't signed in.
  Future<String?> saveWorkspaceToCloud() async {
    final wsPath = state.workspacePath;
    if (wsPath == null) return null;
    final repo = ref.read(projectRepositoryProvider);
    final uid = ref.read(authServiceProvider).currentUser?.uid;
    if (repo == null || uid == null) return null;

    await saveWorkspace(wsPath); // flush open editors to disk first
    final project = await repo.createProject(name: p.basename(wsPath), ownerId: uid);
    await linkCloudProject(project.id);
    await _cloudSync.pushAllFiles(
      projectId: project.id,
      workspacePath: wsPath,
      uid: uid,
      scanFilePaths: (path) => [for (final entity in _scanFiles(path)) entity.path],
    );
    unawaited(repo.addRecent(uid, project.id));
    return project.id;
  }

  static String _sanitizeFolderName(String name) {
    final cleaned = name.trim().replaceAll(RegExp('[^A-Za-z0-9_]'), '_');
    return cleaned.isEmpty ? 'project' : cleaned;
  }

  /// Downloads cloud project [projectId] into a fresh local workspace
  /// directory, opens it, and links it (see [linkCloudProject]) so edits sync
  /// back live. Returns `false` if the project can't be loaded (no
  /// repository, or the project doesn't exist / isn't accessible).
  Future<bool> openCloudProject(String projectId, {bool live = false}) async {
    ref.read(workspaceLoadingProvider.notifier).begin();
    try {
      // Bounded so a stalled network cannot leave the spinner up
      // indefinitely. This is a multi-request sequence (fetch the project,
      // then its files) with no deadline of its own, so without a ceiling here
      // the UI has no upper limit at all — the failure mode is a loading
      // overlay that never resolves and never explains itself.
      return await _openCloudProjectInner(
        projectId,
        live: live,
      ).timeout(const Duration(seconds: 25));
    } catch (e, st) {
      // A denied read throws rather than returning null: `getProject` maps
      // only a 404 to null and rethrows everything else, permission failures
      // included. That is the normal outcome for a share link to a private
      // project. Without this catch the exception escaped through the
      // `unawaited(...)` call in ProjectRoute and vanished: no toast, no
      // navigation, just the welcome screen, with nothing to explain it.
      //
      // Returning false routes it into the caller's existing "couldn't open
      // this project" toast, which is at least an answer.
      _log.error('openCloudProject failed for $projectId', error: e, stackTrace: st);
      return false;
    } finally {
      ref.read(workspaceLoadingProvider.notifier).end();
    }
  }

  Future<bool> _openCloudProjectInner(String projectId, {bool live = false}) async {
    final repo = ref.read(projectRepositoryProvider);
    if (repo == null) return false;
    final project0 = await repo.getProject(projectId);
    if (project0 == null) return false;
    final files = await repo.getFiles(projectId);

    final user = ref.read(authServiceProvider).currentUser;
    final uid = user?.uid;

    // An invitation only becomes access when the invitee opens the project:
    // clients cannot resolve an email to a uid, so the person who sent it
    // could not have granted it directly. Claiming it here — before deciding
    // whether to link — is what makes "invite by email" arrive as edit access
    // rather than as a read-only view.
    var project = project0;
    final email = user?.email;
    if (uid != null && email != null && project.inviteFor(email) != null) {
      final granted = await repo.claimInvite(projectId, uid, email);
      if (granted != null) {
        project = project.copyWith(
          collaborators: {...project.collaborators, uid: granted},
          pendingInvites: {...project.pendingInvites}..remove(email.trim().toLowerCase()),
        );
      }
    }

    // Arduino requires the sketch folder name to match its .ino file name.
    final inoFile = files.where((f) => f.path.endsWith('.ino') && !f.path.contains('/'));
    final dirName = inoFile.isNotEmpty
        ? p.basenameWithoutExtension(inoFile.first.path)
        : _sanitizeFolderName(project.name);

    final base = await _fs.tempBasePath();
    final workspaceDir = p.join(base, 'fap_cloud_${project.id}', dirName);
    await _fs.createDir(workspaceDir);

    if (files.isEmpty) {
      await _fs.writeString(
        p.join(workspaceDir, '$dirName.ino'),
        WorkspaceFileOpsService.blankInoTemplate,
      );
    } else {
      for (final f in files) {
        await _fs.writeString(p.join(workspaceDir, f.path), f.content);
      }
    }

    await openWorkspace(workspaceDir, isTemporary: true);

    // Owner and editors get the live two-way link. Everyone else — a viewer
    // collaborator, or a stranger who followed a share link — gets a detached
    // local copy.
    //
    // Read-only is enforced by *not linking* rather than by disabling save UI:
    // with no link there is no code path from a local save to the cloud, so a
    // missed button is not a data-loss bug. The security rules reject such a
    // write independently, so this is the inner of two locks, not the only one.
    final role = uid == null ? null : project.roleFor(uid);
    final canEdit = role == ProjectRole.owner || role == ProjectRole.editor;

    if (canEdit) {
      await linkCloudProject(project.id);
      if (uid != null) unawaited(repo.addRecent(uid, project.id));
    } else {
      state = state.copyWith(
        clearCloudProjectId: true,
        viewingSharedProjectId: project.id,
        viewingSharedProjectName: project.name,
      );
      // `?live=1` — the reader keeps a pull-only subscription so an author's
      // corrections reach a page that is already open. Opt-in per link because
      // it costs one open realtime subscription per reader; the plain link
      // stays a snapshot that refreshes on reload.
      if (live) await watchSharedProject(project.id);
    }
    return true;
  }

  /// Toggles periodic auto-save of all open files. Returns the new state.
  /// Returns true if any open file's content hash differs from the last-saved
  /// hash. Called by the auto-save timer so it can skip unchanged workspaces.
  bool _checkUnsavedChanges() {
    final editorState = ref.read(editorStateControllerProvider);
    for (final entry in editorState.openFileControllers.entries) {
      final saved = _contentHashes[entry.key];
      if (saved == null || saved != entry.value.text.hashCode) return true;
    }
    return false;
  }

  bool toggleAutoSave() {
    _autoSaveEnabled = !_autoSaveEnabled;
    _autoSaveTimer?.cancel();
    if (_autoSaveEnabled) {
      _autoSaveTimer = Timer.periodic(const Duration(seconds: 15), (_) {
        final s = state;
        if (s.workspacePath != null && !s.isTemporary) {
          _hasUnsavedChanges = _checkUnsavedChanges();
          if (_hasUnsavedChanges) unawaited(saveAll());
        }
      });
    }
    return _autoSaveEnabled;
  }

  /// Exports the current workspace to a zip archive at [savePath] using the
  /// platform's archiver. Returns true on success. Backs "Export to zip…".
  Future<bool> exportWorkspaceToZip(String savePath) async {
    if (!PlatformCapabilities.supportsLocalFilesystem) return false;
    final src = state.workspacePath;
    if (src == null) return false;
    await saveWorkspace(src);
    return WorkspaceExportService.zipDirectory(src, savePath);
  }
}
