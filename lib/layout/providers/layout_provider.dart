import 'package:flutter/foundation.dart';

import 'package:plat/plat.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/edition/edition_provider.dart';
import '../bars/activity/activity_target.dart';
import '../components/pane_sizing.dart';

part 'layout_provider.g.dart';

/// Which tab the pointer is over, so the separator beside it can get out of
/// the way — see `Layout._buildSeparator`. A plain notifier rather than a
/// provider: it changes on every pointer move across the strip.
final hoveredTabNotifier = ValueNotifier<int?>(-1);

@Riverpod(keepAlive: true)
Raw<PlatController> platController(Ref ref) {
  // The right-hand pane exists only for an edition's side panel. Read once:
  // the edition is fixed at startup, and rebuilding the controller would throw
  // away every open tab.
  final hasSidePanel = ref.read(editionPanelProvider) != null;
  final controller = PlatController(
    initialPlat: .row(
      children: [
        // Collapsible, which is what makes the divider beside it the way both
        // out and back: a collapsed slot stays in the tree at zero extent, so
        // its divider is still there to drag. See `CollapsiblePane`.
        .slot(
          id: 'left_slot',
          persistent: true,
          collapsible: true,
          collapseThreshold: sidebarPane.collapseThreshold,
          child: ActivityBarTab.explorer.pane,
          size: sidebarPane.size,
        ),
        // `auto`, not a fraction: it takes whatever the sized panes beside it
        // leave over. Fractions that add up past the window get scaled back to
        // fit, and that scaling runs after each pane's minimum — which is how
        // the sidebar ended up drawn narrower than the minimum it declared.
        .column(
          size: const .auto(),
          children: [
            // Persistent slot keeps center area alive even when all
            // editor tabs are closed, preventing bottom/side panes
            // from expanding to fill the vacated space.
            .slot(
              id: 'center_slot',
              persistent: true,
              child: .tabs([.leaf(id: 'welcome', title: 'Welcome')], id: 'center_pane'),
              size: const .resizable(initial: .fraction(0.7)),
            ),
            .tabs(id: 'bottom_pane', [
              .leaf(id: 'serial_monitor', title: 'Serial Monitor'),
              .leaf(id: 'serial_plotter', title: 'Serial Plotter'),
              .leaf(id: 'problems', title: 'Problems'),
              .leaf(id: 'terminal', title: 'Terminal'),
              .leaf(id: 'debug_console', title: 'Debug Console'),
              .leaf(id: 'spice_logs', title: 'SPICE Logs'),
            ]),
          ],
        ),
        // A slot, not a bare leaf, because only a slot collapses — and the
        // side panel has to close the same way the sidebar does, leaving its
        // divider behind to reopen it. The id stays on the slot: `right_pane`
        // is what the toggles, shortcuts and menu entries name.
        if (hasSidePanel)
          .slot(
            id: sidePanelPane.id,
            persistent: true,
            collapsible: true,
            collapseThreshold: sidePanelPane.collapseThreshold,
            size: sidePanelPane.size,
            child: const .leaf(id: 'side_panel'),
          ),
      ],
    ),
  );

  // Collapsed rather than hidden, so the divider each one reopens from is in
  // the tree from the first frame.
  controller.setCollapsed(sidebarPane.id, collapsed: true);
  controller.setHidden('bottom_pane', hidden: true);
  // The app opens on the welcome screen, which carries the side panel's own
  // entry — the pane itself appears with the project, in `closeWelcome()`.
  if (hasSidePanel) controller.setCollapsed(sidePanelPane.id, collapsed: true);
  controller.focus('welcome');
  ref.onDispose(controller.dispose);
  return controller;
}
