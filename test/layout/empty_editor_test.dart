import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plat/plat.dart';

import 'package:pinbench/core/chrome/chrome_commands.dart';
import 'package:pinbench/features/editor/widgets/empty_editor_view.dart';
import 'package:pinbench/layout/controllers/app_layout_controller.dart';
import 'package:pinbench/layout/layout.dart';
import 'package:pinbench_ui/widgets/brand_logo.dart';

import '../support/harness.dart';

/// With every editor tab closed, the editor area shows the mark and a few
/// shortcuts, as VS Code's does — it used to show nothing at all.
void main() {
  Future<AppLayoutController> pumpLayout(WidgetTester tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final layout = container.read(appLayoutControllerProvider);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: appTestApp(
          PlatView(
            controller: layout.platController,
            slotBuilder: Layout.buildSlot,
            leafBuilder: (context, leaf) => Text('leaf ${leaf.id}'),
          ),
        ),
      ),
    );
    await tester.pump();
    return layout;
  }

  testWidgets('closing the last tab shows the empty editor', (tester) async {
    final layout = await pumpLayout(tester);
    expect(find.byType(EmptyEditorView), findsNothing, reason: 'the welcome tab is open');

    layout.closeTab(AppTabs.welcome);
    await tester.pump();

    expect(find.byType(EmptyEditorView), findsOneWidget);
  });

  testWidgets('opening a tab again puts the empty editor away', (tester) async {
    final layout = await pumpLayout(tester);
    layout.closeTab(AppTabs.welcome);
    await tester.pump();

    layout.openSettingsTab();
    await tester.pump();

    expect(find.byType(EmptyEditorView), findsNothing);
    expect(find.text('leaf settings'), findsOneWidget);
  });

  group('the empty editor', () {
    Future<void> pumpAt(WidgetTester tester, Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(appTestApp(const EmptyEditorView()));
    }

    testWidgets('lists shortcuts the app binds, and no others', (tester) async {
      await pumpAt(tester, const Size(1000, 800));

      for (final label in [
        'Open Folder',
        'New Untitled Text File',
        'Toggle Explorer',
        'Run Simulation',
        'Open Settings',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      // VS Code's, which this app never had.
      expect(find.text('Open Chat'), findsNothing);
      expect(find.text('Show All Commands'), findsNothing);
    });

    testWidgets('draws the mark when there is room', (tester) async {
      await pumpAt(tester, const Size(1000, 800));
      expect(find.byType(BrandMark), findsOneWidget);
    });

    testWidgets('drops the mark in a short pane, keeping the shortcuts', (tester) async {
      await pumpAt(tester, const Size(800, 400));
      expect(find.byType(BrandMark), findsNothing);
      expect(find.text('Open Folder'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('fits a narrow pane without overflowing', (tester) async {
      await pumpAt(tester, const Size(360, 300));
      expect(tester.takeException(), isNull);
    });
  });
}
