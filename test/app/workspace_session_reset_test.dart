import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pinbench/app/canvas_sync_bindings.dart';
import 'package:pinbench/app/workspace_session_reset.dart';
import 'package:pinbench/core/services/logs_repository.dart';
import 'package:pinbench/core/utils/shared_preferences_provider.dart';
import 'package:pinbench/features/canvas/controller/canvas_controller.dart';
import 'package:pinbench/features/canvas/managers/canvas_commands.dart';
import 'package:pinbench/features/canvas/managers/canvas_context.dart';
import 'package:pinbench/features/workspace/providers/log_providers.dart';
import 'package:pinbench/features/workspace/providers/problems_provider.dart';
import 'package:pinbench/features/workspace/providers/workspace_files_provider.dart';

import '../support/chrome_commands.dart';

/// Does nothing, so the undo history can be filled without a circuit.
class _NoOpCommand implements CanvasCommand {
  @override
  void execute(CanvasContext controller) {}

  @override
  void undo(CanvasContext controller) {}
}

void main() {
  late Directory first;
  late Directory second;
  late ProviderContainer container;

  setUp(() async {
    first = Directory.systemTemp.createTempSync('workspace_session_reset_a_');
    second = Directory.systemTemp.createTempSync('workspace_session_reset_b_');
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        ...fakeChromeBindings(),
        ...canvasSyncBindings,
      ],
    );
  });

  tearDown(() {
    container.dispose();
    for (final dir in [first, second]) {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
  });

  Future<void> mount(WidgetTester tester) => tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const WorkspaceSessionReset(child: SizedBox()),
    ),
  );

  /// What a run of the first workspace leaves behind: output in every log
  /// pane, a compile error, and an edit to undo.
  void leaveOutputBehind() {
    final logs = container.read(logsRepositoryProvider);
    for (final channel in LogChannel.values) {
      logs.addLog(channel, 'Hello World');
    }
    container.read(problemsProvider.notifier).setForSource(ProblemSource.compiler, [
      const Problem(
        severity: ProblemSeverity.error,
        source: ProblemSource.compiler,
        message: 'Sketch failed to compile',
      ),
    ]);
    container
        .read(canvasControllerProvider.notifier)
        .historyManager
        .execute(_NoOpCommand(), container.read(canvasControllerProvider.notifier));
  }

  /// The log repository throttles its notifications on the *real* clock, so
  /// under the test's fake clock a throttled notification reschedules itself
  /// for ever and the test fails on a pending timer. Everything that writes or
  /// clears a log therefore runs on real time ([WidgetTester.runAsync]), and
  /// this lets the last throttled notification fire before the test ends.
  Future<void> drainLogNotifications(WidgetTester tester) =>
      tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));

  void expectNothingLeft() {
    final logs = container.read(logsRepositoryProvider);
    for (final channel in LogChannel.values) {
      expect(logs.getLogs(channel), isEmpty, reason: '$channel log');
    }
    expect(container.read(problemsProvider), isEmpty);
    expect(container.read(canvasControllerProvider.notifier).historyManager.canUndo, isFalse);
  }

  testWidgets("opening another workspace clears the last one's output, problems and undo history", (
    tester,
  ) async {
    await mount(tester);
    final workspace = container.read(workspaceFilesProvider.notifier);
    await tester.runAsync(
      () => workspace.setWorkspace(workspacePath: first.path, isTemporary: true),
    );
    await tester.runAsync(() async => leaveOutputBehind());

    await tester.runAsync(
      () => workspace.setWorkspace(workspacePath: second.path, isTemporary: true),
    );
    await tester.pump();

    expectNothingLeft();
    await drainLogNotifications(tester);
  });

  testWidgets('closing the folder clears them too', (tester) async {
    await mount(tester);
    final workspace = container.read(workspaceFilesProvider.notifier);
    await tester.runAsync(
      () => workspace.setWorkspace(workspacePath: first.path, isTemporary: true),
    );
    await tester.runAsync(() async => leaveOutputBehind());

    await tester.runAsync(() async => workspace.clearWorkspaceState());
    await tester.pump();

    expectNothingLeft();
    await drainLogNotifications(tester);
  });

  testWidgets('work inside the same workspace keeps its output', (tester) async {
    await mount(tester);
    final workspace = container.read(workspaceFilesProvider.notifier);
    await tester.runAsync(
      () => workspace.setWorkspace(workspacePath: first.path, isTemporary: true),
    );
    await tester.runAsync(() async => leaveOutputBehind());

    // Switching files is not switching workspaces.
    await tester.runAsync(() async => workspace.setActiveFile('${first.path}/sketch.ino'));
    await tester.pump();

    expect(container.read(logsRepositoryProvider).getLogs(LogChannel.serial), ['Hello World']);
    expect(container.read(problemsProvider), hasLength(1));
    expect(container.read(canvasControllerProvider.notifier).historyManager.canUndo, isTrue);
    await drainLogNotifications(tester);
  });
}
