import 'package:path/path.dart' as p;

import '../data/workspace_fs.dart';

/// Tracks whether a template workspace's `.ino` source still matches the
/// pristine bundled template it was created from, so the web preview's
/// no-`COMPILE_API_URL` fallback can tell "unedited template" (safe to serve
/// the bundled precompiled hex) apart from "user edited the code" (serving
/// the old hex would silently run the wrong program).
abstract final class TemplateProvenanceService {
  /// Hash of each template's pristine `.ino` source, recorded by
  /// `TemplateService` when a workspace is created from a bundled template.
  ///
  /// This in-memory map is only populated for the lifetime of the app
  /// instance that created the workspace, so it's empty again after a
  /// reopen/hot-restart. [pristineHashFileName] is the on-disk fallback that
  /// survives that — see [pristineHashFor].
  static final Map<String, int> pristineSourceHashes = {};

  /// Sidecar file written next to a template workspace's `.ino`, holding the
  /// pristine source hash so it survives reopening the workspace or
  /// restarting the app (unlike [pristineSourceHashes]).
  static const pristineHashFileName = '.pristine_hash';

  static int? pristineHashFor(String directoryPath, WorkspaceFs fs) {
    final cached = pristineSourceHashes[directoryPath];
    if (cached != null) return cached;
    final sidecarPath = p.join(directoryPath, pristineHashFileName);
    if (fs.existsFile(sidecarPath)) {
      return int.tryParse(fs.readStringSync(sidecarPath));
    }
    return null;
  }
}
