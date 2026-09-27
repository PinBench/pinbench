import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../workspace/providers/problems_provider.dart';
import '../../workspace/providers/workspace_files_provider.dart';
import '../../workspace/providers/editor_state_provider.dart';
import '../../workspace/services/editor_state_controller.dart';

/// Describes what the user is looking at, for the assistant to read.
///
/// Without this the assistant answers every question from the conversation
/// alone, so "why isn't this working?" is unanswerable and "add a second LED"
/// starts a fresh circuit rather than editing the one on screen.
///
/// Deliberately assembled from the **editor buffers** rather than the files on
/// disk: an unsaved edit is what the user can see, and answering about the
/// saved version of a file they have changed is worse than not answering.
abstract final class WorkspaceContext {
  /// Cap per file. Long enough for any circuit and most sketches, short enough
  /// that a runaway file cannot crowd the component catalog — and the whole
  /// thing out of a small local model's context window.
  static const maxFileChars = 6000;

  /// The section appended to the system prompt, or an empty string when there
  /// is nothing open to describe.
  static String build(Ref ref) {
    final state = ref.read(workspaceFilesProvider);
    if (state.workspacePath == null) return '';

    final editors = ref.read(editorStateControllerProvider);
    final circuit = _read(state.mainCdlPath ?? _firstWith(ref, '.cdl'), editors);
    final sketch = _read(state.mainInoPath ?? _firstWith(ref, '.ino'), editors);
    final problems = ref.read(problemsProvider);

    if (circuit == null && sketch == null && problems.isEmpty) return '';

    final buffer = StringBuffer('''


# What the user is looking at right now

This is the open project, as it stands including unsaved edits. When the user
asks for a change, treat this as the starting point: return the whole file with
the change applied, keeping the parts and ids that are already there. Do not
re-emit a file you did not change.
''');

    if (circuit != null) {
      buffer.write(
        '\n## ${circuit.name} — the circuit on the canvas\n\n```cdl\n${circuit.text}\n```\n',
      );
    }
    if (sketch != null) {
      buffer.write('\n## ${sketch.name} — the sketch\n\n```ino\n${sketch.text}\n```\n');
    }
    if (problems.isNotEmpty) {
      buffer.write(
        '\n## Problems the app is reporting\n\n'
        'These come from the circuit validator and the compiler, not from the '
        'user — they are the ground truth about what is wrong.\n\n',
      );
      for (final problem in problems) {
        buffer.write('- [${problem.severity.name}] ${problem.message}');
        if (problem.detail case final detail? when detail.isNotEmpty) {
          buffer.write(' — ${detail.replaceAll('\n', ' ')}');
        }
        buffer.write('\n');
      }
    }

    return buffer.toString();
  }

  /// The live text of [path], truncated if it is enormous.
  static ({String name, String text})? _read(String? path, EditorStateController editors) {
    if (path == null) return null;
    final text = editors.openFileControllers[path]?.text;
    if (text == null || text.trim().isEmpty) return null;

    return (
      name: p.basename(path),
      text: text.length <= maxFileChars
          ? text
          : '${text.substring(0, maxFileChars)}\n… (truncated)',
    );
  }

  /// The first open workspace file with [extension], for a project that has
  /// not nominated a main file.
  static String? _firstWith(Ref ref, String extension) {
    for (final file in ref.read(workspaceFilesProvider).files) {
      if (p.extension(file.path).toLowerCase() == extension) return file.path;
    }
    return null;
  }
}
