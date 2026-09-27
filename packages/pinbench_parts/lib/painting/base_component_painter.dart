import 'package:flutter/widgets.dart';

import 'paint_node.dart';
import 'port_provider.dart';

/// Base class for every component's [CustomPainter].
///
/// Subclasses implement [paintComponent] to draw the part, and override
/// [shouldRepaintComponent] to repaint only when their visual state changes.
/// [isOutline] requests a faded "ghost" rendering used for drag previews.
abstract class BaseComponentPainter extends CustomPainter {
  final bool isOutline;

  BaseComponentPainter({this.isOutline = false, super.repaint});

  @override
  void paint(Canvas canvas, Size size) {
    paintComponent(canvas, size);
  }

  /// Draws the component into [size]. Implemented by each component painter.
  void paintComponent(Canvas canvas, Size size);

  @override
  bool shouldRepaint(covariant BaseComponentPainter oldDelegate) =>
      !identical(this, oldDelegate) &&
      (oldDelegate.isOutline != isOutline || shouldRepaintComponent(oldDelegate));

  /// Override to report whether component-specific state changed since
  /// [oldDelegate] (e.g. an LED's `isOn`/brightness). Defaults to no-repaint.
  bool shouldRepaintComponent(covariant BaseComponentPainter oldDelegate) => false;

  /// The part's drawn body within [size], or null if it fills its bounds.
  ///
  /// A part's bounds are usually much bigger than the part: they stretch out
  /// to wherever its leads meet the connection lattice, so a 5 mm LED lives in
  /// a 56×56 box that is mostly air. Painters whose body is smaller than that
  /// say so here, in one line, and [hitArea] does the rest.
  Rect? bodyRect(Size size) => null;

  /// Where the pointer counts as being *on* this part: its [bodyRect] plus its
  /// legs, or the whole box for a part that fills its bounds.
  ///
  /// Hovering and clicking use this rather than the bounding box, so the empty
  /// air beside a part belongs to whatever is underneath it — usually a
  /// breadboard, whose holes stay hoverable right up to the part's legs. The
  /// part itself is still grabbable everywhere it's drawn.
  Rect hitArea(Size size) {
    final body = bodyRect(size);
    if (body == null) return Offset.zero & size;

    var area = body;
    if (this is PortProvider) {
      for (final port in (this as PortProvider).getPorts()) {
        area = area.expandToInclude(Rect.fromCircle(center: port.localOffset, radius: _legReach));
      }
    }
    return area;
  }

  /// How far around a leg still counts as the part. Half a cell: enough to
  /// grab a lead that's a couple of pixels wide, not so much that it swallows
  /// the neighbouring hole a full pitch away.
  static const _legReach = 4.0;
}

/// Mixin for [BaseComponentPainter]s that draw via a static [PaintNode] scene
/// graph (built once per painter instance) rather than issuing `Canvas` calls
/// directly in [paintComponent].
///
/// Every such painter used to repeat the same three lines — a `late final`
/// cached tree plus a one-line [paintComponent] that replays it. This hoists
/// that boilerplate: implement [buildTree] instead of [paintComponent].
mixin PaintTreeComponent on BaseComponentPainter {
  /// Builds this painter's scene graph. Called once per instance, the first
  /// time it's painted, and cached — same timing as before this was hoisted,
  /// since a new painter instance (with a rebuilt tree) is created whenever
  /// the part's properties change.
  PaintNode buildTree();

  late final PaintNode _tree = buildTree();

  @override
  void paintComponent(Canvas canvas, Size size) => _tree.paint(canvas, Offset.zero);
}
