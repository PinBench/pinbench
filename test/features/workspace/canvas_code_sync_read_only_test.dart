import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:pinbench/features/canvas/providers/canvas_controller_provider.dart';
import 'package:pinbench/features/workspace/providers/editor_state_provider.dart';
import 'package:pinbench/features/workspace/providers/canvas_code_sync_provider.dart';
import 'package:pinbench/app/canvas_sync_bindings.dart';

/// Regression test for the bug fixed in 68f81e7: while a simulation is
/// running, the canvas's nodes carry transient runtime state (LED `isOn`,
/// brightness, voltages) merged in every frame. `syncCanvasToCodeSync` used
/// to regenerate the `.cdl` from that live state unconditionally, so a
/// running simulation silently overwrote the source file with a snapshot of
/// runtime values and flipped the tab to "unsaved" — even though the user
/// never edited anything.
///
/// Invariant under test: `syncCanvasToCodeSync` must be a no-op whenever
/// `canvasController.isReadOnly` is true (the flag set while a sim runs).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('syncCanvasToCodeSync does not touch the .cdl buffer while read-only', () {
    final container = ProviderContainer(overrides: [...canvasSyncBindings]);
    addTearDown(container.dispose);

    const path = 'circuit.cdl';
    const untouchedText = 'Circuit {\n}\n';

    final editorState = container.read(editorStateControllerProvider);
    final controller = editorState.openFile(path, untouchedText);

    final service = container.read(canvasCodeSyncServiceProvider);
    service.attachCdlListener(path, controller);

    final canvasController = container.read(canvasControllerProvider.notifier);
    canvasController.isReadOnly = true;

    service.syncCanvasToCodeSync();

    expect(
      controller.text,
      untouchedText,
      reason: 'a read-only (simulating) canvas must never overwrite the .cdl source',
    );
  });

  test('syncCanvasToCodeSync regenerates the .cdl buffer once writable again', () {
    final container = ProviderContainer(overrides: [...canvasSyncBindings]);
    addTearDown(container.dispose);

    const path = 'circuit.cdl';
    const staleText = 'not a real circuit';

    final editorState = container.read(editorStateControllerProvider);
    final controller = editorState.openFile(path, staleText);

    final service = container.read(canvasCodeSyncServiceProvider);
    service.attachCdlListener(path, controller);

    final canvasController = container.read(canvasControllerProvider.notifier);
    canvasController.isReadOnly = false;

    service.syncCanvasToCodeSync();

    expect(controller.text, isNot(staleText));
    expect(controller.text, contains('Circuit {'));
  });
}
