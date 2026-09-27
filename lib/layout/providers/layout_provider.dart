import 'package:flutter/foundation.dart';

import 'package:plat/plat.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../bars/activity/activity_target.dart';
import '../components/pane_sizing.dart';

part 'layout_provider.g.dart';

/// Which tab the pointer is over, so the separator beside it can get out of
/// the way — see `Layout._buildSeparator`. A plain notifier rather than a
/// provider: it changes on every pointer move across the strip.
final hoveredTabNotifier = ValueNotifier<int?>(-1);

@Riverpod(keepAlive: true)
Raw<PlatController> platController(Ref ref) {
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
        // assistant has to close the same way the sidebar does, leaving its
        // divider behind to reopen it. The id stays on the slot: `right_pane`
        // is what the toggles, shortcuts and menu entries have always named.
        .slot(
          id: assistantPane.id,
          persistent: true,
          collapsible: true,
          collapseThreshold: assistantPane.collapseThreshold,
          size: assistantPane.size,
          child: const .leaf(id: 'assistant'),
        ),
      ],
    ),
  );

  // Collapsed rather than hidden, so the divider each one reopens from is in
  // the tree from the first frame.
  controller.setCollapsed(sidebarPane.id, collapsed: true);
  controller.setHidden('bottom_pane', hidden: true);
  // The app opens on the welcome screen, which has its own prompt box — the
  // assistant pane appears with the project, in `closeWelcome()`.
  controller.setCollapsed(assistantPane.id, collapsed: true);
  controller.focus('welcome');
  ref.onDispose(controller.dispose);
  return controller;
}
