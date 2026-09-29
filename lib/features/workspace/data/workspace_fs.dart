import 'workspace_fs_web.dart' if (dart.library.io) 'workspace_fs_io.dart';

/// Filesystem boundary for workspace files.
///
/// The concrete implementation is chosen at compile time: a real `dart:io`
/// implementation on native platforms, and an in-memory store on the web, where
/// the browser has no local filesystem. Keeping every workspace read/write
/// behind this interface lets the workspace, template, and explorer layers
/// compile and run on the web.
///
/// String path manipulation via `package:path` (`p.join`, `p.basename`,
/// `p.dirname`) works on the web, so callers keep using those freely. Note that
/// `FileSystemEntity.parent`/`.isDirectorySync` do NOT — they call
/// `Platform.isWindows` and throw on the web — so prefer `p.dirname` and
/// [isDirectory] here.
abstract interface class WorkspaceFs {
  /// Creates the platform-appropriate implementation.
  factory() = WorkspaceFsImpl;

  /// Base directory under which throwaway/temporary workspaces are created.
  /// On native this is the OS temp dir; on web it is a synthetic in-memory root.
  Future<String> tempBasePath();

  /// Whether a file exists at [path].
  bool existsFile(String path);

  /// Whether a directory exists at [path].
  bool existsDir(String path);

  /// Whether [path] refers to a directory (vs. a file).
  bool isDirectory(String path);

  /// Creates the directory [path] (and any missing parents).
  Future<void> createDir(String path);

  /// Writes [content] as UTF-8 to [path], creating parents as needed.
  Future<void> writeString(String path, String content);

  /// Writes raw [bytes] to [path], creating parents as needed.
  Future<void> writeBytes(String path, List<int> bytes);

  /// Reads raw bytes from [path].
  Future<List<int>> readBytes(String path);

  /// Deletes the file at [path]. No-op if it doesn't exist.
  Future<void> deleteFile(String path);

  /// Reads [path] as a UTF-8 string.
  Future<String> readString(String path);

  /// Synchronous variant of [readString].
  String readStringSync(String path);

  /// Recursively lists all file paths under [root].
  List<String> listFiles(String root);

  /// Restores a persisted workspace (web localStorage → in-memory). No-op on
  /// native (the filesystem already persists) and on first visit (no data).
  Future<void> restore() async {}

  /// Persists the current in-memory workspace to web localStorage. No-op on
  /// native where the filesystem is the persistence layer.
  Future<void> persist() async {}

  /// Clears any persisted web workspace data. No-op on native.
  Future<void> clearPersisted() async {}
}
