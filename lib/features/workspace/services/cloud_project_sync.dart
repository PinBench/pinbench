import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:pinbench_cloud/project_model.dart';

import '../../../core/cloud/project_providers.dart';
import '../data/workspace_fs.dart';
import '../providers/editor_state_provider.dart';

/// Owns the live cloud link for a workspace: pulling collaborators'
/// remote edits onto local disk/editor buffers, and pushing local saves back
/// out. Extracted from `WorkspaceFiles` so the cloud-sync lifecycle
/// (subscribe/unsubscribe, self-echo suppression, last-write-wins content
/// merge) has one boundary instead of being interleaved with local file I/O.
///
/// Owned per-notifier by `WorkspaceFiles`; not itself a provider, since it
/// needs direct access to that notifier's `_contentHashes` cache to keep the
/// two staying in sync (a cloud pull must rebaseline the same hash a local
/// save would).
class CloudProjectSync({
  required final Ref ref,
  required final WorkspaceFs _fs,
  required final Map<String, int> _contentHashes,
}) {
  StreamSubscription<List<ProjectFile>>? _filesSubscription;

  /// Whether a project is currently linked (subscription active).
  bool get isLinked => _filesSubscription != null;

  /// Stops watching the currently linked project, if any.
  Future<void> unlink() async {
    await _filesSubscription?.cancel();
    _filesSubscription = null;
  }

  /// Starts watching cloud project [projectId]'s files, writing remote
  /// changes into [workspacePath] on local disk and into any open editor
  /// buffer for that file. Calls [onFilesChanged] with [workspacePath]
  /// whenever at least one file was updated, so the caller can refresh its
  /// file tree.
  Future<void> link({
    required String projectId,
    required String? Function() workspacePath,
    required void Function(String workspacePath) onFilesChanged,
  }) async {
    await unlink();

    final repo = ref.read(projectRepositoryProvider);
    if (repo == null) return;

    _filesSubscription = repo.watchFiles(projectId).listen((files) async {
      final wsPath = workspacePath();
      if (wsPath == null) return;
      final editorState = ref.read(editorStateControllerProvider);
      var changed = false;
      for (final file in files) {
        // Note: we deliberately do NOT skip on `updatedBy == uid`. The same user
        // signed in on two devices shares a uid, so filtering by it would drop
        // every cross-device edit (the reported "only updates after refresh"
        // bug). Self-echoes are instead suppressed by the content-hash check
        // below: our own write is already on local disk, so its hash matches.
        final filePath = p.join(wsPath, file.path);
        final localHash = _fs.existsFile(filePath) ? _fs.readStringSync(filePath).hashCode : null;
        if (localHash == file.content.hashCode) continue; // already up to date
        await _fs.writeString(filePath, file.content);
        _contentHashes[filePath] = file.content.hashCode;
        final controller = editorState.openFileControllers[filePath];
        if (controller != null && controller.text != file.content) {
          controller.text = file.content;
        }
        // The buffer now matches the cloud version, so it's clean — rebaseline
        // the dirty indicator instead of leaving the remote edit looking unsaved.
        editorState.markSaved(filePath, file.content);
        changed = true;
      }
      if (changed) onFilesChanged(wsPath);
    });
  }

  /// Pushes every file under [workspacePath] to cloud project
  /// [projectId], attributed to [uid]. Used to seed a newly-created cloud
  /// project with the workspace's current contents.
  Future<void> pushAllFiles({
    required String projectId,
    required String workspacePath,
    required String uid,
    required List<String> Function(String workspacePath) scanFilePaths,
  }) async {
    final repo = ref.read(projectRepositoryProvider);
    if (repo == null) return;
    for (final path in scanFilePaths(workspacePath)) {
      final relativePath = p.relative(path, from: workspacePath).replaceAll(r'\', '/');
      final content = _fs.readStringSync(path);
      await repo.updateFile(projectId, relativePath, content, updatedBy: uid);
    }
  }

  /// Pushes a single changed file to the cloud, if a project is linked.
  /// Fire-and-forget: callers don't block a local save on the cloud write.
  void pushFile({
    required String projectId,
    required String relativePath,
    required String content,
    required String uid,
  }) {
    final repo = ref.read(projectRepositoryProvider);
    if (repo == null) return;
    unawaited(repo.updateFile(projectId, relativePath, content, updatedBy: uid));
  }
}
