import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench/features/workspace/services/editor_state_controller.dart';

void main() {
  group('EditorStateController', () {
    test('openFile returns the same controller for the same path', () {
      final state = EditorStateController();
      final a = state.openFile('/ws/a.ino', 'void setup() {}');
      final again = state.openFile('/ws/a.ino', 'IGNORED new text');

      expect(identical(a, again), isTrue);
      // The original content is preserved (not overwritten on re-open).
      expect(again.text, 'void setup() {}');
    });

    test('tracks multiple open files', () {
      final state = EditorStateController();
      state.openFile('/ws/a.ino', 'a');
      state.openFile('/ws/b.cdl', 'b');
      expect(state.openFileControllers.keys, containsAll(['/ws/a.ino', '/ws/b.cdl']));
    });

    test('closeFile removes and disposes the controller', () {
      final state = EditorStateController();
      state.openFile('/ws/a.ino', 'a');
      state.closeFile('/ws/a.ino');
      expect(state.openFileControllers.containsKey('/ws/a.ino'), isFalse);
    });

    test('getActiveController resolves by path', () {
      final state = EditorStateController();
      final c = state.openFile('/ws/a.ino', 'a');
      expect(identical(state.getActiveController('/ws/a.ino'), c), isTrue);
      expect(state.getActiveController('/ws/missing.ino'), isNull);
    });

    test('dispose clears all open files', () {
      final state = EditorStateController();
      state.openFile('/ws/a.ino', 'a');
      state.openFile('/ws/b.ino', 'b');
      state.dispose();
      expect(state.openFileControllers, isEmpty);
    });
  });
}
