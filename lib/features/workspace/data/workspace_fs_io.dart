import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'workspace_fs.dart';

/// Native [WorkspaceFs] backed by `dart:io`.
class WorkspaceFsImpl implements WorkspaceFs {
  @override
  Future<String> tempBasePath() async => (await getTemporaryDirectory()).path;

  @override
  bool existsFile(String path) => File(path).existsSync();

  @override
  bool existsDir(String path) => Directory(path).existsSync();

  @override
  bool isDirectory(String path) => FileSystemEntity.isDirectorySync(path);

  @override
  Future<void> createDir(String path) async {
    await Directory(path).create(recursive: true);
  }

  @override
  Future<void> writeString(String path, String content) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
  }

  @override
  Future<void> writeBytes(String path, List<int> bytes) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
  }

  @override
  Future<List<int>> readBytes(String path) => File(path).readAsBytes();

  @override
  Future<void> deleteFile(String path) async {
    final file = File(path);
    if (file.existsSync()) await file.delete();
  }

  @override
  Future<String> readString(String path) => File(path).readAsString();

  @override
  String readStringSync(String path) => File(path).readAsStringSync();

  @override
  List<String> listFiles(String root) {
    final dir = Directory(root);
    if (!dir.existsSync()) return [];
    return dir.listSync(recursive: true).whereType<File>().map((f) => f.path).toList();
  }

  @override
  Future<void> restore() async {} // no-op on native (filesystem persists)

  @override
  Future<void> persist() async {} // no-op on native (filesystem persists)

  @override
  Future<void> clearPersisted() async {} // no-op on native
}
