import 'dart:convert';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'workspace_fs.dart';

/// Web [WorkspaceFs] backed by an in-memory store with optional localStorage
/// persistence via [SharedPreferences].
///
/// Call [restore] during workspace initialisation to load the previous session's
/// files; call [persist] after each write to commit changes to localStorage so
/// they survive page refresh. The in-memory store alone works identically
/// (useful for ephemeral preview workspaces that shouldn't persist).
///
/// **Storage limit**: localStorage has a ~5 MB origin limit. Each file is stored
/// as a separate key-value pair so individual files can be evicted if the quota
/// is approached (not yet implemented — over-quota writes throw silently).
class WorkspaceFsImpl implements WorkspaceFs {
  static final Map<String, Uint8List> _files = {};
  static final Set<String> _dirs = {};
  static const _prefix = 'web_fs_';

  /// Restores a previously-persisted workspace from localStorage. No-op when
  /// no persisted data exists (first visit or cleared).
  @override
  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith(_prefix));
    for (final key in keys) {
      final storeKey = key.substring(_prefix.length);
      final json = prefs.getString(key);
      if (json != null) {
        final entry = jsonDecode(json) as Map<String, dynamic>;
        if (entry['type'] == 'dir') {
          _dirs.add(storeKey);
        } else {
          _files[storeKey] = Uint8List.fromList((entry['data'] as List<dynamic>).cast<int>());
        }
      }
    }
  }

  /// Persists the current workspace to localStorage so it survives page
  /// refresh. Call after every file write or directory creation.
  @override
  Future<void> persist() async {
    final prefs = await SharedPreferences.getInstance();
    // Clear stale keys first.
    final stale = prefs.getKeys().where((k) => k.startsWith(_prefix));
    for (final key in stale) {
      await prefs.remove(key);
    }
    // Write files.
    for (final entry in _files.entries) {
      await prefs.setString(
        '$_prefix${entry.key}',
        jsonEncode({'type': 'file', 'data': entry.value.toList()}),
      );
    }
    // Write directories.
    for (final dir in _dirs) {
      await prefs.setString('$_prefix$dir', jsonEncode({'type': 'dir'}));
    }
  }

  /// Clears all persisted data (call on workspace close or explicit "New").
  @override
  Future<void> clearPersisted() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith(_prefix));
    for (final key in keys) {
      await prefs.remove(key);
    }
  }

  @override
  Future<String> tempBasePath() async => '/playground';

  @override
  bool existsFile(String path) => _files.containsKey(_norm(path));

  @override
  bool existsDir(String path) {
    final n = _norm(path);
    if (_dirs.contains(n)) return true;
    final prefix = '$n/';
    return _files.keys.any((f) => f.startsWith(prefix)) || _dirs.any((d) => d.startsWith(prefix));
  }

  @override
  bool isDirectory(String path) => existsDir(path) && !existsFile(path);

  @override
  Future<void> createDir(String path) async {
    _dirs.add(_norm(path));
    await persist();
  }

  @override
  Future<void> writeString(String path, String content) async =>
      writeBytes(path, utf8.encode(content));

  @override
  Future<void> writeBytes(String path, List<int> bytes) async {
    final n = _norm(path);
    _files[n] = Uint8List.fromList(bytes);
    // Register every ancestor directory so existsDir/listing stay consistent.
    var dir = p.dirname(n);
    while (dir.isNotEmpty && dir != '/' && dir != '.') {
      _dirs.add(dir);
      final parent = p.dirname(dir);
      if (parent == dir) break;
      dir = parent;
    }
    await persist();
  }

  @override
  Future<List<int>> readBytes(String path) async {
    final bytes = _files[_norm(path)];
    if (bytes == null) {
      throw FileSystemException('No such file in web workspace', path);
    }
    return bytes;
  }

  @override
  Future<void> deleteFile(String path) async {
    _files.remove(_norm(path));
    await persist();
  }

  @override
  Future<String> readString(String path) async => readStringSync(path);

  @override
  String readStringSync(String path) {
    final bytes = _files[_norm(path)];
    if (bytes == null) {
      throw FileSystemException('No such file in web workspace', path);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  @override
  List<String> listFiles(String root) {
    final prefix = '${_norm(root)}/';
    return _files.keys.where((f) => f.startsWith(prefix)).toList()..sort();
  }

  static String _norm(String path) =>
      path.endsWith('/') && path.length > 1 ? path.substring(0, path.length - 1) : path;
}

/// Minimal stand-in for `dart:io`'s `FileSystemException`, so the web store can
/// signal a missing file without importing `dart:io`.
class FileSystemException implements Exception {
  final String message;
  final String path;
  FileSystemException(this.message, this.path);
  @override
  String toString() => 'FileSystemException: $message, path = $path';
}
