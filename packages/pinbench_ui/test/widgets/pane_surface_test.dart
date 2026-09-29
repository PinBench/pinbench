import 'package:flutter/widgets.dart';
import 'package:flutter/rendering.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench_ui/theme/testing.dart';
import 'package:pinbench_ui/theme/tokens.dart';
import 'package:pinbench_ui/widgets/pane_surface.dart';

/// A pane holds views that paint outside their own rect on purpose — the
/// canvas draws an unbounded grid, a schematic runs past the viewport. If the
/// pane does not clip them, that ink lands on the explorer, the tab strip and
/// the bottom pane, and the window looks broken rather than layered.
///
/// This is a regression test: the rounded predecessor of this widget clipped
/// via `ClipRRect`, and the square rewrite dropped the clip along with the
/// radius. Nothing else in the tree puts it back.
void main() {
  testWidgets('clips content that paints past its own bounds', (tester) async {
    await tester.pumpWidget(
      appTestApp(
        Center(
          child: SizedBox(
            width: 100,
            height: 100,
            child: PaneSurface(
              child: OverflowBox(
                maxWidth: 400,
                maxHeight: 400,
                child: Container(width: 400, height: 400, color: const Color(0xFFFF0000)),
              ),
            ),
          ),
        ),
      ),
    );

    // The clip is the assertion: find a clipping render object between the
    // pane and its overflowing child, whatever widget Container uses to make
    // one for the current decoration.
    final clips = tester.allRenderObjects.where(
      (object) => object is RenderClipRect || object is RenderClipPath || object is RenderClipRRect,
    );

    expect(clips, isNotEmpty, reason: 'PaneSurface must clip its child to the pane rect');
  });

  testWidgets('squares the top-left corner only for an active first tab', (tester) async {
    // A first tab sits flush against the pane's left edge and brings its own
    // border straight down to meet it. Rounding there would curve away from
    // that border and leave a notch between two lines that are one line.
    Future<BorderRadius> radiusFor({required bool connectedTop, bool squareTopLeft = false}) async {
      await tester.pumpWidget(
        appTestApp(
          PaneSurface(
            connectedTop: connectedTop,
            squareTopLeft: squareTopLeft,
            child: const SizedBox.shrink(),
          ),
        ),
      );
      final decoration =
          tester.widget<Container>(find.byType(Container).first).decoration! as BoxDecoration;
      return decoration.borderRadius! as BorderRadius;
    }

    final flushFirstTab = await radiusFor(connectedTop: true, squareTopLeft: true);
    expect(flushFirstTab.topLeft, Radius.zero);
    expect([
      flushFirstTab.topRight,
      flushFirstTab.bottomLeft,
      flushFirstTab.bottomRight,
    ], everyElement(AppRadii.paneRadius));

    // Every other case rounds all four: under a tab strip the top corners are
    // where the strip's rule turns into the pane's sides, and on its own a
    // pane is simply an island.
    for (final connectedTop in [true, false]) {
      final radius = await radiusFor(connectedTop: connectedTop);
      expect(
        [radius.topLeft, radius.topRight, radius.bottomLeft, radius.bottomRight],
        everyElement(AppRadii.paneRadius),
        reason: 'connectedTop: $connectedTop',
      );
    }
  });
}
