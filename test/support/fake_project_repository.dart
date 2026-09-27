import 'dart:async';

import 'package:pinbench_cloud/project_model.dart';
import 'package:pinbench_cloud/project_repository.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// An in-memory [ProjectRepository] for tests that exercise the cloud-project
/// open path.
///
/// Only the reads that path takes are implemented — everything else throws, so
/// a test that starts depending on a write fails loudly instead of silently
/// passing against a no-op. [filesStream] is a broadcast controller the test
/// drives itself, which is what makes it possible to assert that a live shared
/// view actually pulls a later edit.
class FakeProjectRepository implements ProjectRepository {
  FakeProjectRepository({required this.project, List<ProjectFile> files = const []})
    : _files = List.of(files);

  final Project project;
  List<ProjectFile> _files;

  /// Emits the project's file list. Kept open so a test can push an edit after
  /// the workspace is already open.
  final filesStream = StreamController<List<ProjectFile>>.broadcast();

  /// Number of live subscriptions taken out on [watchFiles] — a snapshot view
  /// must take none.
  var watchFilesCalls = 0;

  /// Pushes [files] as the project's new contents, to both the one-shot read
  /// and any live subscriber.
  void emit(List<ProjectFile> files) {
    _files = List.of(files);
    filesStream.add(_files);
  }

  Future<void> dispose() => filesStream.close();

  @override
  Future<Project?> getProject(String projectId) async => projectId == project.id ? project : null;

  @override
  Future<List<ProjectFile>> getFiles(String projectId) async => List.of(_files);

  @override
  Stream<List<ProjectFile>> watchFiles(String projectId) {
    watchFilesCalls++;
    return filesStream.stream;
  }

  @override
  Future<void> addRecent(String uid, String projectId) async {}

  // ── Not exercised by these tests ────────────────────────────────────────

  @override
  Never noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked; add it if a test needs it.');
}

/// Points `getTemporaryDirectory()` at [path] so the cloud-open path writes its
/// downloaded workspace somewhere the test controls and deletes afterwards.
class FakePathProvider extends PathProviderPlatform with MockPlatformInterfaceMixin {
  FakePathProvider(this.path);

  final String path;

  @override
  Future<String?> getTemporaryPath() async => path;

  @override
  Future<String?> getApplicationSupportPath() async => path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}
