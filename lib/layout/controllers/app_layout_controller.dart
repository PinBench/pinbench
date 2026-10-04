import 'package:path/path.dart' as p;
import 'package:plat/plat.dart';
import 'package:pinbench_ui/strings.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/chrome/chrome_commands.dart';
import '../../core/edition/edition_provider.dart';
import '../../core/telemetry/analytics_service.dart';
import '../../core/telemetry/telemetry_providers.dart';
import '../../core/utils/logger.dart';
import '../bars/activity/activity_target.dart';
import '../components/pane_sizing.dart';
import '../providers/layout_provider.dart';

part 'app_layout_controller.g.dart';

/// Centralizes all high-level layout operations that interact with the [PlatController].
class AppLayoutController(
  final PlatController _platController,
  final AnalyticsService _analytics, {

  /// Whether this build has a right-hand pane — only when its edition supplies
  /// a side panel. From `editionPanelProvider`, the same answer the toolbar and
  /// menus use. Revealing or collapsing a pane that is not in the tree is
  /// already a no-op in the layout, so only [togglePane] needs this.
  required final bool hasSidePanel,
}) {
  static const _log = AppLogger('app.layout');

  /// Access to the underlying controller if natively needed by PlatView.
  PlatController get platController => _platController;

  /// Closes the welcome tab and reveals the chrome that belongs with an open
  /// project: the explorer, and the side panel if there is one.
  ///
  /// The side panel is hidden on the welcome screen because that screen
  /// carries the panel's own entry — two ways to the same thing, side by side.
  /// Every path off the welcome screen goes through here, so this and
  /// [resetToWelcome] are the only two places the rule is expressed.
  void closeWelcome() {
    _platController.close(AppTabs.welcome);
    sidebarPane.reveal(_platController);
    sidePanelPane.reveal(_platController);
  }

  /// Toggles the visibility of a specified pane slot.
  void togglePane(String paneId) {
    // The shortcut exists in every build; don't report toggling a pane that
    // isn't there.
    if (paneId == sidePanelPane.id && !hasSidePanel) return;
    _analytics.panelToggled(paneId);
    setPaneVisible(paneId, visible: isPaneHidden(paneId));
  }

  /// Sets whether a specific pane is explicitly visible.
  ///
  /// The two side panes collapse rather than hide: a collapsed slot keeps its
  /// place in the tree at zero extent, so the divider that reopens it is still
  /// there, and its width survives the round trip. Hiding takes both away.
  void setPaneVisible(String paneId, {required bool visible}) {
    final pane = _sidePane(paneId);
    if (pane == null) {
      _platController.setHidden(paneId, hidden: !visible);
      return;
    }
    visible ? pane.reveal(_platController) : pane.collapse(_platController);
  }

  /// Returns true if a specific pane is currently out of the way.
  bool isPaneHidden(String paneId) =>
      _sidePane(paneId)?.isCollapsed(_platController) ??
      _platController.snapshot(paneId)?.hidden ??
      true;

  CollapsiblePane? _sidePane(String paneId) => switch (paneId) {
    _ when paneId == sidebarPane.id => sidebarPane,
    _ when paneId == sidePanelPane.id => sidePanelPane,
    _ => null,
  };

  /// Closes a specific tab.
  void closeTab(String tabId) {
    _platController.remove(tabId);
  }

  /// Focuses a specific tab.
  void focusTab(String tabId) {
    _platController.focus(tabId);
  }

  /// Opens an editor file in the center pane.
  void openEditorTab(String filePath) {
    final fileName = p.basename(filePath);

    if (_platController.snapshot(filePath) != null) {
      _platController.focus(filePath);
    } else {
      final inserted = _platController.insertTab(
        tabGroupId: 'center_pane',
        tab: PlatTab.leaf(id: filePath, title: fileName, data: filePath),
      );

      if (!inserted) {
        _platController.setSlotChild(
          slotId: 'center_slot',
          child: Plat.tabs([
            PlatTab.leaf(id: filePath, title: fileName, data: filePath),
          ], id: 'center_pane'),
        );
      }

      _platController.focus(filePath);
    }
  }

  /// Opens app settings as a center-pane tab, or focuses it if already open.
  ///
  /// Carries no `data`: the leaf registry keys it off the tab id, and a
  /// `String` there would make every path that treats tab data as a file path
  /// (dirty tracking, close-and-clean-up) think settings were a document on
  /// disk.
  void openSettingsTab() {
    if (_platController.snapshot(AppTabs.settings) != null) {
      _platController.focus(AppTabs.settings);
      return;
    }

    final tab = PlatTab.leaf(id: AppTabs.settings, title: 'Settings');
    final inserted = _platController.insertTab(tabGroupId: 'center_pane', tab: tab);
    if (!inserted) {
      _platController.setSlotChild(
        slotId: 'center_slot',
        child: Plat.tabs([tab], id: 'center_pane'),
      );
    }
    _platController.focus(AppTabs.settings);
  }

  /// Opens the release notes as a center-pane tab, or focuses it if already
  /// open. [version] goes in the tab's title, as VS Code's does.
  void openReleaseNotesTab({String? version}) {
    if (_platController.snapshot(AppTabs.releaseNotes) != null) {
      _platController.focus(AppTabs.releaseNotes);
      return;
    }

    final tab = PlatTab.leaf(
      id: AppTabs.releaseNotes,
      title: AppStrings.releaseNotesTabTitle(version),
    );
    final inserted = _platController.insertTab(tabGroupId: 'center_pane', tab: tab);
    if (!inserted) {
      _platController.setSlotChild(
        slotId: 'center_slot',
        child: Plat.tabs([tab], id: 'center_pane'),
      );
    }
    _platController.focus(AppTabs.releaseNotes);
  }

  /// Whether the settings tab is open *and* the one on screen — the activity
  /// bar's settings button lights up on exactly that.
  bool isSettingsTabSelected() {
    final group = _platController.snapshot('center_pane');
    if (group is! TabGroupSnapshot) return false;
    final active = group.activeTab;
    return (active?.focusedLeaf ?? active?.firstLeaf)?.id == AppTabs.settings;
  }

  /// Opens the canvas for a specific CDL file alongside the center pane.
  void openCanvasTab(String cdlFilePath) {
    final canvasTabId = AppTabs.canvas(cdlFilePath);
    final fileName = cdlFilePath.split(RegExp(r'[/\\]')).last;

    if (_platController.snapshot(canvasTabId) != null) {
      _log.trace('Canvas tab already exists, focusing');
      _platController.focus(canvasTabId);
    } else {
      final inserted = _platController.insertTab(
        tabGroupId: 'center_pane',
        tab: PlatTab.leaf(id: canvasTabId, title: fileName, data: 'canvas_view'),
      );

      if (!inserted) {
        _platController.setSlotChild(
          slotId: 'center_slot',
          child: Plat.tabs([
            PlatTab.leaf(id: canvasTabId, title: fileName, data: 'canvas_view'),
          ], id: 'center_pane'),
        );
      }

      _platController.focus(canvasTabId);
    }
  }

  /// Opens or toggles an activity bar tab.
  void openActivityTab(ActivityBarTab target) {
    if (isActivityTabSelected(target)) {
      setPaneVisible(target.slotId, visible: false);
      return;
    }
    _platController.transaction(() {
      _platController.setSlotChild(slotId: target.slotId, child: target.pane);
      setPaneVisible(target.slotId, visible: true);
    });
  }

  /// Opens the welcome screen as a tab beside whatever is open, or focuses it
  /// if it already is — Help ▸ Welcome, as in VS Code. Unlike
  /// [resetToWelcome] it leaves the panes alone: a project may well be open,
  /// and asking to see the welcome screen is not asking to close it.
  void openWelcomeTab() {
    _platController.transaction(() {
      _insertWelcomeTab();
      _platController.focus(AppTabs.welcome);
    });
  }

  void _insertWelcomeTab() {
    if (_platController.snapshot(AppTabs.welcome) != null) return;
    final tab = PlatTab.leaf(id: AppTabs.welcome, title: 'Welcome');
    final inserted = _platController.insertTab(tabGroupId: 'center_pane', tab: tab);
    if (!inserted) {
      _platController.setSlotChild(
        slotId: 'center_slot',
        child: Plat.tabs([tab], id: 'center_pane'),
      );
    }
  }

  /// Resets the layout to its initial state, showing only the welcome screen.
  void resetToWelcome() {
    _platController.transaction(() {
      _insertWelcomeTab();

      sidebarPane.collapse(_platController);
      _platController.setHidden('bottom_pane', hidden: true);
      // The welcome screen carries the side panel's own entry, so the pane
      // would be a second one beside it. See [closeWelcome].
      sidePanelPane.collapse(_platController);
      _platController.focus('welcome');
    });
  }

  /// Checks if an activity bar tab is currently selected and visible.
  bool isActivityTabSelected(ActivityBarTab target) {
    final slot = _platController.snapshot(target.slotId);
    if (slot is! SlotSnapshot || slot.hidden) return false;
    final child = slot.child;
    if (child is! LeafSnapshot) return false;
    return child.id == target.leafId;
  }
}

@Riverpod(keepAlive: true)
AppLayoutController appLayoutController(Ref ref) {
  final platController = ref.watch(platControllerProvider);
  return AppLayoutController(
    platController,
    ref.watch(analyticsProvider),
    hasSidePanel: ref.read(editionPanelProvider) != null,
  );
}
