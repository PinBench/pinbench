import 'package:flutter/widgets.dart';

import 'package:pinbench_terminal/terminal_view.dart';

import '../features/editor/widgets/editor_tab_view.dart';
import '../features/editor/widgets/empty_editor_view.dart';
import 'views/bottom/debug_console_view.dart';
import 'views/bottom/problems_view.dart';
import 'views/bottom/serial_monitor_view.dart';
import 'views/bottom/serial_plotter_view.dart';
import 'views/bottom/spice_logs_view.dart';
import 'views/center/canvas_view.dart';
import 'views/center/side_panel_view.dart';
import 'views/center/welcome_view.dart';
import '../features/workspace/widgets/account_view.dart';
import '../features/workspace/widgets/explorer_view.dart';
import '../features/canvas/widgets/components/parts_view.dart';
import '../features/canvas/widgets/properties/properties_view.dart';
import 'views/center/settings_tab_view.dart';

/// Maps `PlatView` leaf ids to their content widget and classifies each leaf
/// by its region (sidebar/right-pane, bottom pane, or center pane), decoupling
/// "which widget for which id" from `Layout`'s chrome-composition tree.
abstract final class LeafRegistry {
  // Single-leaf regions (no tab strip above them): the activity-bar sidebars
  // and the right pane. Everything else lives in a tab group, so its island
  // should merge with the tab strip rather than float free.
  // `side_panel`, not `right_pane`: `right_pane` is the collapsible *slot*
  // that holds it, and the id everything outside this file names when it
  // toggles the panel. The leaf inside it needs an id of its own.
  static const _untabbedLeaves = {'explorer', 'parts', 'properties', 'account', 'side_panel'};

  // Bottom-pane leaves (terminal, logs, monitors) — like the sidebars above,
  // these live outside `center_pane` and must stay clear of the loading
  // overlay, which only ever covers welcome/canvas/editor content.
  static const _bottomPaneLeaves = {
    'problems',
    'terminal',
    'debug_console',
    'serial_monitor',
    'serial_plotter',
    'spice_logs',
  };

  static bool isTabbed(String id) => !_untabbedLeaves.contains(id);

  /// Everything not in a sidebar or the bottom pane belongs to `center_pane`
  /// (welcome, canvas tabs, editor tabs) — the only place a workspace/template
  /// open ever affects, so it's the only place the loading overlay may show.
  static bool isCenterPaneLeaf(String id) =>
      !_untabbedLeaves.contains(id) && !_bottomPaneLeaves.contains(id);

  static Widget buildChild(String id, Object? data) => switch (id) {
    'welcome' => const WelcomeView(),
    'explorer' => const ExplorerSidebarView(),
    'parts' => const PartsSidebarView(),
    'properties' => const PropertiesSidebarView(),
    'account' => const AccountSidebarView(),
    // A center-pane document, matched on its id: the tab carries no `data`,
    // precisely so nothing mistakes it for a file. See `AppTabs.settings`.
    'settings' => const SettingsTabView(),
    'side_panel' => const SidePanelView(),
    'problems' => const ProblemsView(),
    'terminal' => const TerminalView(),
    'debug_console' => const DebugConsoleView(),
    'serial_monitor' => const SerialMonitorView(),
    'serial_plotter' => const SerialPlotterView(),
    'spice_logs' => const SpiceLogsView(),
    _ when data == 'canvas_view' => const CanvasView(),
    _ when data is String => EditorTabView(filePath: data),
    _ => const EmptyEditorView(),
  };
}
