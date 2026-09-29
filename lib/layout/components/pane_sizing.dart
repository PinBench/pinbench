import 'package:flutter/widgets.dart';

import 'package:plat/plat.dart';

/// A side pane that can be dragged away and dragged back.
///
/// Almost nothing happens here any more, and that is the point. `plat` grew
/// collapsible slots: a slot marked [PlatSlot.collapsible] is laid out at zero
/// extent when it closes *without leaving the tree*, so its divider stays put
/// and stays draggable, and the same gesture that pushed the pane away pulls it
/// back. The slot's own size is what it reopens at, so the round trip is exact.
///
/// This app had grown its own answer to all of that — a width it owned, a sash
/// widget that drew the seam and ran the drag, and a gutter widget to hold a
/// lane open for the sash once the pane was gone. All of it is deleted. What is
/// left is this description of the two panes and the one rule the layout engine
/// has no way to know: that a window can be too narrow to hold them at all.
class const CollapsiblePane({
  /// The collapsible slot in the layout tree this describes.
  required final String id,

  /// What the pane opens at, and what it reopens at after a collapse. Over
  /// [minWidth], so it never opens already sitting on its own floor.
  required final double initialWidth,

  /// The narrowest the pane is drawn before the divider stops. Below this its
  /// contents stop being readable rather than merely cramped — a properties row
  /// is a label beside a 70px field, so under this the label has nowhere to go
  /// and breaks mid-word ("Colo / r").
  required final double minWidth,
  required final double maxWidth,

  /// Which edge the pane's contents stay pinned to while it is narrower than
  /// [minWidth] — the edge it hinges on. The sidebar closes leftwards, so its
  /// contents slide out under their own left edge; the side panel closes the
  /// other way. See [PaneContentFloor].
  required final Alignment contentAlignment,
}) {
  /// How far past the stop the drag has to insist before the pane closes.
  ///
  /// Half the minimum is `plat`'s own default and is about right: far enough
  /// that an overshot resize is not a disappearance, close enough that meaning
  /// it is one movement rather than a shove. It doubles as the distance back
  /// out that reopens a collapsed pane.
  PlatExtent get collapseThreshold => .pixel(minWidth / 2);

  /// The size the layout tree gives this pane.
  ///
  /// Pixels rather than a fraction of the window: sibling fractions that add up
  /// past the window are scaled back to fit, and that scaling runs *after* each
  /// pane's minimum — which is how the sidebar once ended up drawn narrower than
  /// the minimum it declared, and unable to be dragged narrower because the
  /// drag clamped back into `min..max`. Beside an auto-sized centre, a pixel
  /// claim is exactly what it says.
  ///
  /// Resizable rather than fixed, because a fixed slot locks its divider — and
  /// the divider is the handle.
  PlatSize get size => PlatSize.resizable(
    initial: .pixel(initialWidth),
    min: .pixel(minWidth),
    max: .pixel(maxWidth),
  );

  /// Whether the pane is out of the way — collapsed, hidden, or not in the tree
  /// at all.
  ///
  /// Collapsed and hidden are different states in `plat` and only one of them
  /// leaves a divider behind, but to everything that asks about a side pane —
  /// the activity bar's highlight, the title bar's toggles — the question is
  /// the same one: is it there or not.
  bool isCollapsed(PlatController controller) => switch (controller.snapshot(id)) {
    final SlotSnapshot slot => slot.collapsed || slot.hidden,
    final PlatSnapshot node => node.hidden,
    null => true,
  };

  void collapse(PlatController controller) => controller.setCollapsed(id, collapsed: true);

  /// Opens the pane, at the width it was last dragged to.
  void reveal(PlatController controller) => controller.setCollapsed(id, collapsed: false);
}

/// The activity bar's slot. All four of its panes (explorer, parts, properties,
/// account) share it, so this is the slot's width rather than any one pane's.
const sidebarPane = CollapsiblePane(
  id: 'left_slot',
  initialWidth: 240,
  minWidth: 200,
  maxWidth: 500,
  contentAlignment: Alignment.centerLeft,
);

/// The right-hand pane, holding an edition's side panel when there is one.
/// Wider than the sidebar throughout: a panel there is a working surface, not
/// a list, and a sidebar's width would make it unusable.
const sidePanelPane = CollapsiblePane(
  id: 'right_pane',
  initialWidth: 320,
  minWidth: 300,
  maxWidth: 600,
  contentAlignment: Alignment.centerRight,
);

/// The leaves that live inside a side pane, and the pane each one is in.
///
/// A leaf does not otherwise know which slot holds it — `plat` hands the
/// builder an id and nothing else — and [PaneContentFloor] needs the pane's
/// width to know what it is protecting the contents from.
CollapsiblePane? paneForLeaf(String leafId) => switch (leafId) {
  'explorer' || 'parts' || 'properties' || 'account' => sidebarPane,
  'side_panel' => sidePanelPane,
  _ => null,
};

/// Lays a side pane's contents out at [CollapsiblePane.minWidth] once the pane
/// itself is narrower than that, and clips what does not fit.
///
/// A collapsed slot is still in the tree — that is the whole point of it, since
/// its divider is how it reopens — and its contents are still laid out, at zero
/// width. Sidebar rows are not built to survive that: a title beside its
/// toolbar, a file name beside its icon, and each one reports the squeeze as an
/// overflow. The app opens with both panes closed, so this was every start-up.
///
/// So below the minimum the contents stop shrinking and start sliding out
/// instead, pinned to the edge the pane hinges on. Nothing changes above it:
/// the pane is laid out exactly as before, and this is not a place to say how
/// wide a pane is — the slot's own size does that.
class const PaneContentFloor({
  required final CollapsiblePane pane,
  required final Widget child,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth >= pane.minWidth) return child;
      return ClipRect(
        child: OverflowBox(
          alignment: pane.contentAlignment,
          minWidth: pane.minWidth,
          maxWidth: pane.minWidth,
          child: child,
        ),
      );
    },
  );
}

/// The narrowest the editor/canvas may be squeezed to before a side pane is
/// asked to give up its place entirely. Smaller than either pane's minimum:
/// whatever the window has left, the document the user is working on has a
/// better claim to it than the chrome beside it.
const contentMinWidth = 160.0;

/// Collapses the side panes when the window is too narrow to hold them, and
/// brings them back when there is room again.
///
/// The one thing a divider's minimum cannot do for itself: it governs a drag,
/// and this is the window getting smaller than the panes and the content
/// between them put together. Left alone the panes are drawn squashed — labels
/// breaking mid-word, number fields clipping their own values. A panel too
/// narrow to read is worse than no panel, and the space it takes is space the
/// canvas or editor needs more.
///
/// The side panel gives way before the sidebar: it is the wider of the two, and
/// the one whose absence costs the least while the window is this small. It is
/// also the last to come back, so a window worked down and back up ends where
/// it started.
///
/// Two rules keep it from fighting the user:
///
///  - It acts on the *crossing*, not on the condition. Re-opening a pane while
///    the window is narrow leaves it open — the user asked for it at this
///    width, and nothing re-decides until the width changes again.
///  - It only restores what it collapsed. A pane the user closed themselves
///    stays closed when the window grows back.
class const PaneFit({
  required final PlatController controller,
  required final Widget child,
  super.key,
}) extends StatefulWidget {
  @override
  State<PaneFit> createState() => _PaneFitState();
}

class _PaneFitState extends State<PaneFit> {
  /// Per pane: whether the last measurement had room for it, and whether it was
  /// this that closed it. `fits` starts absent so the first measurement is not
  /// read as a crossing — a window that opens narrow has not just shrunk.
  final _fits = <String, bool>{};
  final _closedByFit = <String, bool>{};

  /// The panes, in the order they are given up — last first.
  static const _keptLongest = [sidebarPane, sidePanelPane];

  /// What a pane needs to be worth drawing: room for itself, for the content
  /// beside it, and for everything the window keeps ahead of it.
  ///
  /// That last term is what puts the two panes in order, and it is deliberately
  /// not "whatever the other pane happens to be taking right now": a threshold
  /// that moves as its neighbour opens and closes gives back in the wrong
  /// order, since the side panel would clear its own bar on the way up while
  /// the sidebar it displaced was still under one raised by the panel's return.
  static double _needs(CollapsiblePane pane) {
    var width = contentMinWidth;
    for (final other in _keptLongest) {
      width += other.minWidth;
      if (other == pane) break;
    }
    return width;
  }

  void _measure(double width) {
    for (final pane in _keptLongest) {
      final fits = width >= _needs(pane);
      if (fits == _fits[pane.id]) continue;
      final crossed = _fits.containsKey(pane.id);
      _fits[pane.id] = fits;
      if (!crossed) continue;

      final collapsed = pane.isCollapsed(widget.controller);
      if (!fits && !collapsed) {
        _closedByFit[pane.id] = true;
        pane.collapse(widget.controller);
      } else if (fits && (_closedByFit[pane.id] ?? false)) {
        _closedByFit[pane.id] = false;
        pane.reveal(widget.controller);
      }
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      // After the frame: this runs during layout, and collapsing a pane lays
      // out the tree it is measuring. The width it reads is the region the
      // panes share, which collapsing one does not change, so there is nothing
      // here to oscillate.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _measure(constraints.maxWidth);
      });
      return widget.child;
    },
  );
}
