import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pinbench/core/utils/shared_preferences_provider.dart';
import 'package:pinbench/features/workspace/providers/workspace_files_provider.dart';
import 'package:pinbench/features/workspace/providers/editor_state_provider.dart';

import '../../support/chrome_commands.dart';

import 'package:pinbench/app/canvas_sync_bindings.dart';

/// Characterization tests for [WorkspaceFiles] (see
/// docs/plans/radiant-mixing-pudding.md Phase 0), written before Phase 2
/// extracts zip-export, file-CRUD, and tab-lifecycle logic out into their own
/// services. `flutter test` runs on the native VM, so `WorkspaceFs()` resolves
/// to the real `dart:io` backend and these tests use a real temp directory
/// rather than the web in-memory store.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late ProviderContainer container;
  late WorkspaceFiles workspace;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('workspace_files_provider_test_');
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

  test('setWorkspace scans files under the given directory into state', () async {
    File(p.join(tempDir.path, 'sketch.ino')).writeAsStringSync('void setup() {}\nvoid loop() {}\n');
    File(p.join(tempDir.path, 'circuit.cdl')).writeAsStringSync('Circuit {\n}\n');

    await workspace.setWorkspace(workspacePath: tempDir.path);

    expect(container.read(workspaceFilesProvider).workspacePath, tempDir.path);
    final names = container
        .read(workspaceFilesProvider)
        .files
        .map((f) => p.basename(f.path))
        .toSet();
    expect(names, {'sketch.ino', 'circuit.cdl'});
  });

  test('setWorkspace is a no-op when the directory does not exist', () async {
    await workspace.setWorkspace(workspacePath: p.join(tempDir.path, 'does_not_exist'));

    expect(container.read(workspaceFilesProvider).workspacePath, isNull);
  });

  test('createFile writes starter content for a .ino and opens it as a tab', () async {
    await workspace.setWorkspace(workspacePath: tempDir.path);

    final path = await workspace.createFile('blink.ino');

    expect(path, isNotNull);
    expect(File(path!).existsSync(), isTrue);
    expect(File(path).readAsStringSync(), contains('void setup()'));
    expect(
      container.read(workspaceFilesProvider).files.map((f) => p.basename(f.path)),
      contains('blink.ino'),
    );
  });

  test('createFile returns null when no workspace is open', () async {
    final path = await workspace.createFile('blink.ino');
    expect(path, isNull);
  });

  test(
    'revertFile reloads on-disk content into the open editor buffer, discarding edits',
    () async {
      final filePath = p.join(tempDir.path, 'sketch.ino');
      File(filePath).writeAsStringSync('// original\n');
      await workspace.setWorkspace(workspacePath: tempDir.path);
      await workspace.openSingleFile(filePath);

      final editorState = container.read(editorStateControllerProvider);
      editorState.openFileControllers[filePath]!.text = '// edited but not saved\n';

      await workspace.revertFile(filePath);

      expect(editorState.openFileControllers[filePath]!.text, '// original\n');
    },
  );

  test('deleteWorkspaceFile removes the file from disk and from the file tree', () async {
    final filePath = p.join(tempDir.path, 'scratch.txt');
    File(filePath).writeAsStringSync('scratch');
    await workspace.setWorkspace(workspacePath: tempDir.path);

    await workspace.deleteWorkspaceFile(filePath);

    expect(File(filePath).existsSync(), isFalse);
    expect(
      container.read(workspaceFilesProvider).files.map((f) => f.path),
      isNot(contains(filePath)),
    );
  });

  group('autosave', () {
    test('toggleAutoSave flips and returns the new enabled state', () {
      final first = workspace.toggleAutoSave();
      expect(first, isTrue);

      final second = workspace.toggleAutoSave();
      expect(second, isFalse);
    });
  });

  group('saveWorkspace', () {
    test('writes open editor buffers to disk under the target directory', () async {
      final filePath = p.join(tempDir.path, 'sketch.ino');
      File(filePath).writeAsStringSync('// original\n');
      await workspace.setWorkspace(workspacePath: tempDir.path);
      await workspace.openSingleFile(filePath);

      final editorState = container.read(editorStateControllerProvider);
      editorState.openFileControllers[filePath]!.text = '// changed\n';

      await workspace.saveWorkspace(tempDir.path);

      expect(File(filePath).readAsStringSync(), '// changed\n');
    });

    test('skips rewriting a file whose content hash is unchanged since last save', () async {
      final filePath = p.join(tempDir.path, 'sketch.ino');
      File(filePath).writeAsStringSync('// original\n');
      await workspace.setWorkspace(workspacePath: tempDir.path);
      await workspace.openSingleFile(filePath);
      await workspace.saveWorkspace(tempDir.path);

      final mtimeBefore = File(filePath).lastModifiedSync();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await workspace.saveWorkspace(tempDir.path);

      expect(File(filePath).lastModifiedSync(), mtimeBefore);
    });
  });
}
