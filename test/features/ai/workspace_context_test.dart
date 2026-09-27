import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench/features/ai/services/workspace_context.dart';
import 'package:pinbench/features/workspace/models/workspace_state.dart';
import 'package:pinbench/features/workspace/providers/problems_provider.dart';
import 'package:pinbench/features/workspace/providers/workspace_files_provider.dart';
import 'package:pinbench/features/workspace/providers/editor_state_provider.dart';
import 'package:pinbench/features/workspace/services/editor_state_controller.dart';

const _circuitPath = '/tmp/project/circuit.cdl';
const _sketchPath = '/tmp/project/project.ino';

class _FakeWorkspace extends WorkspaceFiles {
  _FakeWorkspace(this._state);

  final WorkspaceState _state;

  @override
  WorkspaceState build() => _state;
}

class _FakeProblems extends Problems {
  _FakeProblems(this._problems);

  final List<Problem> _problems;

  @override
  List<Problem> build() => _problems;
}

/// A container whose editors hold [open] as live buffers.
ProviderContainer _container({
  WorkspaceState state = const WorkspaceState(),
  Map<String, String> open = const {},
  List<Problem> problems = const [],
}) {
  final editors = EditorStateController();
  open.forEach(editors.openFile);

  final container = ProviderContainer(
    overrides: [
      workspaceFilesProvider.overrideWith(() => _FakeWorkspace(state)),
      editorStateControllerProvider.overrideWithValue(editors),
      problemsProvider.overrideWith(() => _FakeProblems(problems)),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(editors.dispose);
  return container;
}

/// `WorkspaceContext.build` wants a `Ref`, which only a provider has.
final _contextProvider = Provider<String>(WorkspaceContext.build);

void main() {
  test('says nothing when no project is open', () {
    expect(_container().read(_contextProvider), isEmpty);
  });

  test('says nothing when a project is open but empty', () {
    final context = _container(
      state: const WorkspaceState(workspacePath: '/tmp/project'),
    ).read(_contextProvider);

    expect(context, isEmpty);
  });

  test('includes the circuit and the sketch', () {
    final context = _container(
      state: const WorkspaceState(
        workspacePath: '/tmp/project',
        mainCdlPath: _circuitPath,
        mainInoPath: _sketchPath,
      ),
      open: {
        _circuitPath: 'Circuit {\n    uno := ArduinoUno {\n    }\n}',
        _sketchPath: 'void setup() {}\nvoid loop() {}',
      },
    ).read(_contextProvider);

    expect(context, contains('circuit.cdl'));
    expect(context, contains('uno := ArduinoUno'));
    expect(context, contains('project.ino'));
    expect(context, contains('void loop()'));
  });

  // The editor buffer, not the file on disk: an unsaved edit is what the user
  // is looking at, and answering about the saved version is worse than not
  // answering at all.
  test('reads the live editor buffer, including unsaved edits', () {
    final editors = EditorStateController()..openFile(_circuitPath, 'Circuit {\n}');
    addTearDown(editors.dispose);
    editors.openFileControllers[_circuitPath]!.text = 'Circuit {\n    led := LED {\n    }\n}';

    final container = ProviderContainer(
      overrides: [
        workspaceFilesProvider.overrideWith(
          () => _FakeWorkspace(
            const WorkspaceState(workspacePath: '/tmp/project', mainCdlPath: _circuitPath),
          ),
        ),
        editorStateControllerProvider.overrideWithValue(editors),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(_contextProvider), contains('led := LED'));
  });

  // What makes "why isn't this working?" answerable at all: these come from
  // the validator and the compiler, not from the user's description.
  test('passes on what the app is reporting as wrong', () {
    final context = _container(
      state: const WorkspaceState(workspacePath: '/tmp/project', mainCdlPath: _circuitPath),
      open: {_circuitPath: 'Circuit {\n}'},
      problems: const [
        Problem(
          severity: ProblemSeverity.error,
          source: ProblemSource.circuit,
          message: 'LED is short-circuited! Both legs are connected together.',
        ),
        Problem(
          severity: ProblemSeverity.error,
          source: ProblemSource.compiler,
          message: 'Sketch failed to compile',
          detail: "expected ';' before '}'\nsecond line",
        ),
      ],
    ).read(_contextProvider);

    expect(context, contains('short-circuited'));
    expect(context, contains('Sketch failed to compile'));
    // Detail is flattened: a newline inside a bullet breaks the list.
    expect(context, contains("expected ';' before '}' second line"));
  });

  test('truncates a runaway file rather than crowding out the catalog', () {
    final huge = 'x' * (WorkspaceContext.maxFileChars * 2);
    final context = _container(
      state: const WorkspaceState(workspacePath: '/tmp/project', mainCdlPath: _circuitPath),
      open: {_circuitPath: huge},
    ).read(_contextProvider);

    expect(context, contains('truncated'));
    expect(context.length, lessThan(huge.length));
  });

  // Most projects never nominate a main file — the blank project the assistant
  // creates certainly does not — so the file list is the usual path, not a
  // fallback for odd cases.
  test('finds the circuit when no main file has been nominated', () {
    final context = _container(
      state: WorkspaceState(workspacePath: '/tmp/project', files: [File(_circuitPath)]),
      open: {_circuitPath: 'Circuit {\n    led := LED {\n    }\n}'},
    ).read(_contextProvider);

    expect(context, contains('led := LED'));
  });
}
