import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench/core/utils/logger.dart';

/// Folding a stack down to this app's own frames is the right default and a
/// trap at the edge: an error raised entirely inside the framework or a package
/// has none of ours on it, and folding leaves a single line — `dart:ui
/// _drawFrame` — which says only that the error happened during a frame.
///
/// That cost a real investigation. A build-phase assertion from inside the code
/// editor logged that one line every time, so the trace named nothing and the
/// cause had to be guessed at from the widget names in the message.
void main() {
  test('a trace with none of our frames on it is kept, not folded away', () {
    final foreign = StackTrace.fromString('''
#0      ChangeNotifier.notifyListeners (package:flutter/src/foundation/change_notifier.dart:414:24)
#1      _CodeLineEditingControllerDelegate.delegate= (package:re_editor/src/_code_line.dart:2100:5)
#2      _CodeEditorState.initState (package:re_editor/src/code_editor.dart:366:24)
''');

    final folded = foldStackTrace(foreign).toString();

    expect(folded, contains('re_editor'), reason: 'the only frames that can name the cause');
  });

  test('a trace with our frames on it still folds down to them', () {
    final ours = StackTrace.fromString('''
#0      ChangeNotifier.notifyListeners (package:flutter/src/foundation/change_notifier.dart:414:24)
#1      CanvasCodeSyncService.syncCanvasToCodeSync (package:pinbench/features/workspace/services/canvas_code_sync_service.dart:204:22)
#2      WorkspaceFiles.saveWorkspace (package:pinbench/features/workspace/providers/workspace_files_provider.dart:353:23)
''');

    final folded = foldStackTrace(ours).toString();

    expect(folded, contains('canvas_code_sync_service.dart'));
    expect(folded, isNot(contains('change_notifier.dart')));
  });
}
