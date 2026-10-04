import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plat/plat.dart';

import 'package:pinbench/core/chrome/chrome_commands.dart';
import 'package:pinbench/layout/controllers/app_layout_controller.dart';

/// Help ▸ Welcome brings the welcome screen back as a tab, the way VS Code
/// does — beside whatever is open, without closing the project around it. It
/// used to set two providers nothing reads, and did nothing.
void main() {
  late ProviderContainer container;
  late AppLayoutController layout;

  setUp(() {
    container = ProviderContainer();
    layout = container.read(appLayoutControllerProvider);
  });
  tearDown(() => container.dispose());

  TabGroupSnapshot centerPane() =>
      layout.platController.snapshot('center_pane')! as TabGroupSnapshot;
  List<String?> openTabs() => [for (final tab in centerPane().tabs) tab.firstLeaf?.id];

  test('reopens a closed welcome tab beside the open ones, and focuses it', () {
    layout
      ..closeWelcome()
      ..openSettingsTab()
      ..openWelcomeTab();

    expect(openTabs(), containsAll([AppTabs.settings, AppTabs.welcome]));
    expect(centerPane().activeTab?.firstLeaf?.id, AppTabs.welcome);
  });

  test('works with every tab closed', () {
    layout
      ..closeWelcome()
      ..openWelcomeTab();

    expect(openTabs(), [AppTabs.welcome]);
  });

  test('switches to the welcome tab when it is already open, without a second one', () {
    layout
      ..openSettingsTab()
      ..openWelcomeTab();

    expect(openTabs().where((id) => id == AppTabs.welcome), hasLength(1));
    expect(centerPane().activeTab?.firstLeaf?.id, AppTabs.welcome);
  });

  test("leaves the open project's panes as they are", () {
    layout.closeWelcome(); // opening a project reveals the explorer
    expect(layout.isPaneHidden('left_slot'), isFalse);

    layout.openWelcomeTab();

    expect(layout.isPaneHidden('left_slot'), isFalse);
  });
}
