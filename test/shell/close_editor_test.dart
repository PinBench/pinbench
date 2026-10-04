import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench/core/chrome/chrome_commands.dart';
import 'package:pinbench/features/workspace/providers/editor_state_provider.dart';
import 'package:pinbench/layout/controllers/app_layout_controller.dart';
import 'package:pinbench/shell/menus/shared_menu_actions.dart';

/// File ▸ Close Editor (⌘W) closes the tab on screen. It used to read
/// `activeTabProvider`, which switching tabs never updates, so it was usually
/// empty and the shortcut did nothing.
void main() {
  late WidgetRef ref;
  late ProviderContainer container;

  Future<AppLayoutController> pump(WidgetTester tester) async {
    container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (context, r, _) {
            ref = r;
            return const SizedBox();
          },
        ),
      ),
    );
    return container.read(appLayoutControllerProvider);
  }

  testWidgets('closes the active file, and its editor state with it', (tester) async {
    final layout = await pump(tester);
    container.read(editorStateControllerProvider).openFile('/ws/a.ino', 'void setup() {}');
    layout.openEditorTab('/ws/a.ino');

    closeActiveEditorTab(ref);

    expect(layout.platController.snapshot('/ws/a.ino'), isNull);
    expect(container.read(editorStateControllerProvider).openFileControllers, isEmpty);
  });

  testWidgets('closes the tab that is on screen, not another', (tester) async {
    final layout = await pump(tester);
    final editors = container.read(editorStateControllerProvider)
      ..openFile('/ws/a.ino', '')
      ..openFile('/ws/b.ino', '');
    layout
      ..openEditorTab('/ws/a.ino')
      ..openEditorTab('/ws/b.ino')
      ..focusTab('/ws/a.ino');

    closeActiveEditorTab(ref);

    expect(layout.platController.snapshot('/ws/a.ino'), isNull);
    expect(layout.platController.snapshot('/ws/b.ino'), isNotNull);
    expect(editors.openFileControllers.keys, ['/ws/b.ino']);
  });

  testWidgets("a circuit's canvas goes with its file", (tester) async {
    final layout = await pump(tester);
    container.read(editorStateControllerProvider).openFile('/ws/c.cdl', '');
    layout
      ..openCanvasTab('/ws/c.cdl')
      ..openEditorTab('/ws/c.cdl');

    closeActiveEditorTab(ref);

    expect(layout.platController.snapshot('/ws/c.cdl'), isNull);
    expect(layout.platController.snapshot(AppTabs.canvas('/ws/c.cdl')), isNull);
  });

  testWidgets('closes a tab that is not a file, as VS Code does', (tester) async {
    final layout = await pump(tester);
    layout.openSettingsTab();

    closeActiveEditorTab(ref);

    expect(layout.platController.snapshot(AppTabs.settings), isNull);
    expect(layout.platController.snapshot(AppTabs.welcome), isNotNull);
  });

  testWidgets('does nothing with no tab open', (tester) async {
    final layout = await pump(tester);
    layout.closeTab(AppTabs.welcome);
    expect(layout.activeCenterLeaf(), isNull);

    closeActiveEditorTab(ref);
  });
}
