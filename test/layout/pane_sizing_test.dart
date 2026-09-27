import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:plat/plat.dart';

import 'package:pinbench/layout/components/pane_sizing.dart';
import 'package:pinbench/layout/providers/layout_provider.dart';

/// What it takes for a side pane to close and come back the way an editor's
/// does — which, since `plat` grew collapsible slots, is mostly a matter of
/// asking for them correctly.
///
/// This app spent two designs doing it by hand: first an invisible strip laid
/// over `plat`'s splitter, then a sash widget that owned the width outright and
/// a gutter widget to keep the editor out of the lane it needed once the pane
/// was gone. Both are deleted. A collapsible slot is laid out at zero extent
/// rather than removed, so its divider stays in place and stays draggable, and
/// that divider is the handle — out and back.
///
/// What is left to pin is the wiring (the flags without which none of it
/// happens, and which nothing else would fail on) and the one rule `plat` has
/// no way to know: that a window can be too narrow to hold these panes at all.
void main() {
  PlatController panes() => PlatController(
    initialPlat: .row(
      children: [
        .slot(
          id: sidebarPane.id,
          persistent: true,
          collapsible: true,
          collapseThreshold: sidebarPane.collapseThreshold,
          child: const .leaf(id: 'explorer'),
          size: sidebarPane.size,
        ),
        const .leaf(id: 'center', size: .auto()),
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

  // --- The wiring ----------------------------------------------------------

  test('both side panes are collapsible slots in the real layout tree', () {
    // The flags are the whole feature. Without `collapsible` the panes still
    // resize, still hide, and still look right in every screenshot — they just
    // cannot be closed by dragging, and a pane closed any other way takes its
    // divider with it and leaves nothing to reopen from. Nothing else in the
    // suite would notice.
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(platControllerProvider);

    for (final pane in [sidebarPane, assistantPane]) {
      final slot = controller.snapshot(pane.id);
      expect(slot, isA<SlotSnapshot>(), reason: '${pane.id} must be a slot: only slots collapse');
      expect((slot! as SlotSnapshot).collapsible, isTrue, reason: '${pane.id} must be collapsible');
      expect((slot as SlotSnapshot).collapseThreshold, pane.collapseThreshold);
    }
  });

  test('a resizable size is what keeps the divider draggable', () {
    // A fixed slot locks its divider, and the divider is the handle. Pixels
    // rather than a fraction, because sibling fractions get scaled back to fit
    // *after* each pane's minimum is applied — which is how the sidebar once
    // ended up drawn narrower than the minimum it declared.
    expect(
      sidebarPane.size,
      const PlatSize.resizable(initial: .pixel(240), min: .pixel(200), max: .pixel(500)),
    );
    expect(sidebarPane.initialWidth, greaterThan(sidebarPane.minWidth));
  });

  test('collapse and reveal round-trip through the slot', () {
    final c = panes();
    addTearDown(c.dispose);

    expect(sidebarPane.isCollapsed(c), isFalse);

    sidebarPane.collapse(c);
    expect(sidebarPane.isCollapsed(c), isTrue);
    expect(
      c.snapshot(sidebarPane.id)?.size,
      sidebarPane.size,
      reason: 'a collapsed slot keeps its size — that is what it reopens at',
    );

    sidebarPane.reveal(c);
    expect(sidebarPane.isCollapsed(c), isFalse);
  });

  test('a hidden pane counts as out of the way, not just a collapsed one', () {
    // Two different states in `plat`, one question everywhere else: the
    // activity bar's highlight and the title bar's toggles only ever ask
    // whether the pane is there.
    final c = panes();
    addTearDown(c.dispose);

    c.setHidden(assistantPane.id, hidden: true);
    expect(assistantPane.isCollapsed(c), isTrue);
  });

  // --- The window ----------------------------------------------------------

  final wide = sidebarPane.minWidth + assistantPane.minWidth + contentMinWidth + 100;
  final narrow = sidebarPane.minWidth + contentMinWidth - 1;

  /// Lays the pane region out at [width] and lets the post-frame measurement
  /// run.
  Future<void> resizeTo(WidgetTester tester, PlatController c, double width) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            height: 600,
            child: PaneFit(controller: c, child: const SizedBox.expand()),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('the assistant gives up its place before the sidebar', (tester) async {
    final c = panes();
    addTearDown(c.dispose);

    final roomForBoth = sidebarPane.minWidth + assistantPane.minWidth + contentMinWidth;

    await resizeTo(tester, c, roomForBoth + 100);
    expect(sidebarPane.isCollapsed(c), isFalse);
    expect(assistantPane.isCollapsed(c), isFalse);

    await resizeTo(tester, c, roomForBoth - 1);
    expect(assistantPane.isCollapsed(c), isTrue, reason: 'the wider pane goes first');
    expect(sidebarPane.isCollapsed(c), isFalse, reason: "and what it freed is the sidebar's");

    await resizeTo(tester, c, sidebarPane.minWidth + contentMinWidth - 1);
    expect(sidebarPane.isCollapsed(c), isTrue);

    // All the way back: each returns where it left, in reverse.
    await resizeTo(tester, c, roomForBoth - 1);
    expect(sidebarPane.isCollapsed(c), isFalse);
    expect(assistantPane.isCollapsed(c), isTrue);

    await resizeTo(tester, c, roomForBoth + 100);
    expect(assistantPane.isCollapsed(c), isFalse);
  });

  testWidgets('leaves a pane the user closed closed', (tester) async {
    final c = panes();
    addTearDown(c.dispose);

    await resizeTo(tester, c, wide);
    sidebarPane.collapse(c);

    await resizeTo(tester, c, narrow);
    await resizeTo(tester, c, wide);

    expect(
      sidebarPane.isCollapsed(c),
      isTrue,
      reason: 'widening should not open what the user shut',
    );
  });

  testWidgets('leaves a pane re-opened at a narrow width alone', (tester) async {
    // Asking for the sidebar from the activity bar is an answer to the same
    // question, given later and by the user — nothing should overrule it until
    // the width itself changes again.
    final c = panes();
    addTearDown(c.dispose);

    await resizeTo(tester, c, wide);
    await resizeTo(tester, c, narrow);
    expect(sidebarPane.isCollapsed(c), isTrue);

    sidebarPane.reveal(c);
    await resizeTo(tester, c, narrow - 20);

    expect(sidebarPane.isCollapsed(c), isFalse);
  });

  testWidgets('a window that starts narrow is not treated as one that shrank', (tester) async {
    final c = panes();
    addTearDown(c.dispose);

    await resizeTo(tester, c, narrow);

    expect(sidebarPane.isCollapsed(c), isFalse, reason: 'the first measurement is not a crossing');
  });

  // --- The contents --------------------------------------------------------

  /// A row that cannot be made narrower than [width] without overflowing —
  /// which is every sidebar header and every file row in the explorer.
  Widget unshrinkableRow(double width) => Row(
    children: [
      SizedBox(width: width, height: 20),
      const SizedBox(width: 20, height: 20),
    ],
  );

  Future<Size> layOutFloorAt(WidgetTester tester, double paneWidth) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: paneWidth,
            height: 600,
            child: PaneContentFloor(
              pane: sidebarPane,
              child: unshrinkableRow(sidebarPane.minWidth - 20),
            ),
          ),
        ),
      ),
    );
    return tester.getSize(find.byType(Row));
  }

  testWidgets('a closing pane slides its contents out rather than squeezing them', (tester) async {
    // The app opens with both panes collapsed and a collapsed slot still lays
    // its contents out — at zero width — so without this every start-up
    // reported a handful of overflows from the explorer.
    expect((await layOutFloorAt(tester, 0)).width, sidebarPane.minWidth);
    expect(tester.takeException(), isNull);

    expect((await layOutFloorAt(tester, sidebarPane.minWidth - 50)).width, sidebarPane.minWidth);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an open pane lays its contents out at its own width', (tester) async {
    // The floor is a floor, not a width: past the minimum the pane is in
    // charge, or dragging one wider would stop widening its contents.
    expect(
      (await layOutFloorAt(tester, sidebarPane.minWidth + 120)).width,
      sidebarPane.minWidth + 120,
    );
  });
}
