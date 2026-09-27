import 'dart:io';

import 'package:pinbench_cloud/project_model.dart';
import 'package:pinbench/core/cloud/project_providers.dart';
import 'package:pinbench/core/utils/shared_preferences_provider.dart';
import 'package:pinbench/features/workspace/models/workspace_state.dart';
import 'package:pinbench/features/workspace/providers/workspace_files_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/chrome_commands.dart';
import '../../support/fake_project_repository.dart';
import 'package:pinbench/app/canvas_sync_bindings.dart';

/// Opening a share link gives a **detached local copy**: editable on disk, but
/// with no route back to the original project.
///
/// The enforcement is the absence of a cloud link, not a disabled button —
/// `cloudProjectId` is what every save path checks before pushing to the cloud,
/// so leaving it null means there is no code path from a visitor's edit to
/// someone else's project. These tests pin that, and pin that the two states
/// can never both be set.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late ProviderContainer container;
  late WorkspaceFiles workspace;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('shared_project_view_test_');
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        // Opening a file asks the chrome for a tab; nothing here asserts on
        // that, so a recording no-op is enough.
        ...fakeChromeBindings(),
        ...canvasSyncBindings,
      ],
    );
    workspace = container.read(workspaceFilesProvider.notifier);
  });

  tearDown(() {
    container.dispose();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  WorkspaceState read() => container.read(workspaceFilesProvider);

  group('WorkspaceState', () {
    test('a plain local workspace is neither linked nor a shared view', () {
      const state = WorkspaceState(workspacePath: '/tmp/x');
      expect(state.cloudProjectId, isNull);
      expect(state.viewingSharedProjectId, isNull);
      expect(state.isViewingShared, isFalse);
    });

    test('isViewingShared follows the project id', () {
      const viewing = WorkspaceState(
        workspacePath: '/tmp/x',
        viewingSharedProjectId: 'p1',
        viewingSharedProjectName: "Someone else's blink",
      );
      expect(viewing.isViewingShared, isTrue);
      // The point of the whole design: a viewer has no cloud link, so no save
      // path can reach the backend.
      expect(viewing.cloudProjectId, isNull);
    });

    test('clearViewingShared drops both id and name together', () {
      const viewing = WorkspaceState(
        viewingSharedProjectId: 'p1',
        viewingSharedProjectName: 'Blink',
      );
      final cleared = viewing.copyWith(clearViewingShared: true);
      expect(cleared.viewingSharedProjectId, isNull);
      expect(cleared.viewingSharedProjectName, isNull);
      expect(cleared.isViewingShared, isFalse);
    });

    test('an unrelated copyWith preserves the shared-view fields', () {
      const viewing = WorkspaceState(
        viewingSharedProjectId: 'p1',
        viewingSharedProjectName: 'Blink',
      );
      final renamed = viewing.copyWith(activeFilePath: '/tmp/other.ino');
      expect(renamed.viewingSharedProjectId, 'p1');
      expect(renamed.viewingSharedProjectName, 'Blink');
    });
  });

  _liveViewTests();

  group('opening another workspace', () {
    test('clears a stale shared-view banner', () async {
      // Regression: _openWorkspaceInner cleared cloudProjectId but not the
      // shared-view fields, so after viewing a share link every subsequently
      // opened folder claimed to be "someone else's project".
      File(p.join(tempDir.path, 'sketch.ino')).writeAsStringSync('void setup() {}');

      workspace.state = workspace.state.copyWith(
        viewingSharedProjectId: 'p1',
        viewingSharedProjectName: "Someone else's blink",
      );
      expect(read().isViewingShared, isTrue);

      await workspace.openWorkspace(tempDir.path);

      expect(
        read().isViewingShared,
        isFalse,
        reason: 'stale banner must not follow into a new workspace',
      );
      expect(read().viewingSharedProjectName, isNull);
      expect(read().workspacePath, tempDir.path);
    });

    test('leaves the workspace locally editable', () async {
      // Read-only means "cannot write back to the original", not "cannot
      // touch the files" — a visitor has to be able to poke at the circuit.
      File(p.join(tempDir.path, 'sketch.ino')).writeAsStringSync('void setup() {}');
      await workspace.openWorkspace(tempDir.path);

      workspace.state = workspace.state.copyWith(
        viewingSharedProjectId: 'p1',
        viewingSharedProjectName: 'Blink',
      );

      final created = await workspace.createFile('extra.ino');
      expect(created, isNotNull, reason: 'a shared view is still a real local workspace');
      expect(File(p.join(tempDir.path, 'extra.ino')).existsSync(), isTrue);
      // Still no cloud link, so that edit went nowhere near the original.
      expect(read().cloudProjectId, isNull);
    });
  });
}

/// A live embed pulls the author's edits, but must stay as unwritable as a
/// snapshot one. The guarantee is that `cloudProjectId` is never set: it is the
/// flag every save path checks before pushing to the cloud, so a viewer holding
/// a subscription still has no route back to the original.
///
/// These drive `openCloudProject` itself rather than asserting on state shapes:
/// `live` was threaded from the URL all the way down and then dropped on the
/// floor at both ends, which no amount of `WorkspaceState` assertions could
/// have caught.
void _liveViewTests() {
  late Directory tempDir;
  late FakeProjectRepository repo;
  late ProviderContainer container;
  late WorkspaceFiles workspace;

  final project = Project(
    id: 'p1',
    name: 'Blink',
    // Nobody is signed in, so this is the stranger-with-a-link case: no role,
    // hence a read-only view rather than a live two-way link.
    ownerId: 'someone-else',
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
    visibility: ProjectVisibility.unlisted,
  );

  ProjectFile ino(String content) => ProjectFile(
    id: 'f1',
    path: 'blink.ino',
    content: content,
    updatedAt: DateTime(2026),
    updatedBy: 'someone-else',
  );

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('live_shared_view_test_');
    PathProviderPlatform.instance = FakePathProvider(tempDir.path);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    repo = FakeProjectRepository(project: project, files: [ino('void setup() {}')]);
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        projectRepositoryProvider.overrideWithValue(repo),
        ...fakeChromeBindings(),
        ...canvasSyncBindings,
      ],
    );
    workspace = container.read(workspaceFilesProvider.notifier);
  });

  tearDown(() async {
    container.dispose();
    await repo.dispose();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  String openedSketch() {
    final path = p.join(container.read(workspaceFilesProvider).workspacePath!, 'blink.ino');
    return File(path).readAsStringSync();
  }

  group('live shared view', () {
    test('a plain share link takes no subscription', () async {
      expect(await workspace.openCloudProject('p1'), isTrue);
      expect(
        repo.watchFilesCalls,
        0,
        reason: 'a snapshot embed must not cost a realtime subscription per reader',
      );
    });

    test("?live=1 pulls the author's later edit into the open workspace", () async {
      expect(await workspace.openCloudProject('p1', live: true), isTrue);
      expect(repo.watchFilesCalls, 1);
      expect(openedSketch(), 'void setup() {}');

      repo.emit([ino('void setup() { corrected(); }')]);
      await pumpEventQueue();

      expect(
        openedSketch(),
        'void setup() { corrected(); }',
        reason: 'a live embed exists so a correction reaches a page already open',
      );
    });

    test('a live view is still read-only', () async {
      await workspace.openCloudProject('p1', live: true);
      final state = container.read(workspaceFilesProvider);
      // The distinction the whole read-only design rests on: pulling and
      // pushing are separate, and only pushing is gated on cloudProjectId.
      expect(state.viewingSharedProjectId, 'p1');
      expect(
        state.cloudProjectId,
        isNull,
        reason: 'a subscription must not become a route back to the original',
      );
    });

    test('a linked workspace is never simultaneously a shared view', () {
      // linkCloudProject clears the shared-view fields, so the two states are
      // mutually exclusive — "can write" and "is watching read-only" can never
      // both be true.
      const linked = WorkspaceState(workspacePath: '/tmp/x', cloudProjectId: 'p1');
      expect(linked.isViewingShared, isFalse);
    });
  });
}
