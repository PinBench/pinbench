import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plat/plat.dart';

import 'package:pinbench/features/workspace/models/workspace_state.dart';
import 'package:pinbench/features/workspace/providers/workspace_files_provider.dart';
import 'package:pinbench/layout/bars/title/workspace_title.dart';
import 'package:pinbench/layout/providers/layout_provider.dart';

import '../support/harness.dart';

/// The middle of the title bar names what the window is showing: the workspace,
/// and the document on top inside it. It replaced a "Temporary workspace" badge
/// that named a state instead, and only appeared while the workspace was in it.
class _FakeWorkspaceFiles(final String? workspacePath) extends WorkspaceFiles {
  @override
  WorkspaceState build() => WorkspaceState(workspacePath: workspacePath);
}

void main() {
  /// A centre pane holding [tabs], with the first one on top.
  PlatController panes(List<String> tabs) => PlatController(
    initialPlat: Plat.tabs([
      for (final tab in tabs) PlatTab.leaf(id: tab, title: tab),
    ], id: 'center_pane'),
  );

  Future<PlatController> pumpTitle(
    WidgetTester tester, {
    String? workspacePath = '/home/me/blink',
    List<String> tabs = const ['blink.ino'],
  }) async {
    final controller = panes(tabs);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workspaceFilesProvider.overrideWith(() => _FakeWorkspaceFiles(workspacePath)),
          platControllerProvider.overrideWith((ref) => controller),
        ],
        child: appTestApp(const Center(child: WorkspaceTitle())),
      ),
    );
    return controller;
  }

  testWidgets('names the workspace and the document on top of it', (tester) async {
    await pumpTitle(tester);

    expect(find.text('blink — blink.ino'), findsOneWidget);
  });

  testWidgets('follows the tab the user switches to', (tester) async {
    // The workspace does not change when the document does, so this only
    // updates if the layout controller is being listened to rather than read.
    final controller = await pumpTitle(tester, tabs: ['blink.ino', 'circuit.cdl']);

    controller.focus('circuit.cdl');
    await tester.pump();

    expect(find.text('blink — circuit.cdl'), findsOneWidget);
  });

  testWidgets('is the workspace alone when nothing is open', (tester) async {
    await pumpTitle(tester, tabs: []);

    expect(find.text('blink'), findsOneWidget);
  });

  testWidgets('says nothing at all before a workspace is opened', (tester) async {
    await pumpTitle(tester, workspacePath: null);

    expect(find.byType(Text), findsNothing);
  });
}
