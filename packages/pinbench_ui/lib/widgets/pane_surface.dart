import 'package:flutter/widgets.dart';

import '../theme/app_colors.dart';
import '../theme/tokens.dart';

/// Wraps a pane's content as a floating island: a rounded surface inset from
/// its neighbours by the window gutter, outlined by a hairline.
///
/// A border rather than a shadow. The shadow this replaced was doing the same
/// job — saying "this is a surface, and it ends here" — but said it with a
/// blur that only reads on a light background and gives every pane a soft edge
/// no other part of the chrome has. One line says it in both themes, at the
/// same weight as every other line in the window.
///
/// The gutter is not drawn here: it comes from the layout's own padding and the
/// margins on its splitters, so the panes are inset from each other rather than
/// each carrying a margin of its own.
class const PaneSurface({
  super.key,
  required final Widget child,

  /// True when a tab strip sits directly above this pane.
  ///
  /// The pane then leaves its top edge open — the strip's own bottom rule
  /// closes it — but still rounds the two top corners, so the rule and the
  /// pane's sides meet as one turned corner rather than a right angle.
  final bool connectedTop = false,

  /// Squares the top-left corner (only meaningful with [connectedTop]).
  ///
  /// Set when the *first* tab is the active one. That tab sits flush against
  /// this pane's left edge, and its border comes straight down to meet the
  /// pane's: a rounded corner there would curve away from the tab and leave a
  /// notch between two lines that are supposed to be one.
  final bool squareTopLeft = false,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final borderRadius = connectedTop
        ? BorderRadius.only(
            topLeft: squareTopLeft ? Radius.zero : AppRadii.paneRadius,
            topRight: AppRadii.paneRadius,
            bottomLeft: AppRadii.paneRadius,
            bottomRight: AppRadii.paneRadius,
          )
        : AppRadii.paneAll;

    return CustomPaint(
      foregroundPainter: _PaneOutline(
        color: colors.border,
        openTop: connectedTop,
        squareTopLeft: squareTopLeft,
      ),
      // The clip is not cosmetic, and leaving it out was a real bug: a pane's
      // content paints outside its own rect — the canvas draws an unbounded
      // grid and a schematic that runs past the viewport — and that ink landed
      // on the explorer, the tab strip and the bottom pane.
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: colors.surface, borderRadius: borderRadius),
        child: child,
      ),
    );
  }
}

/// Strokes the pane's outline, leaving the top edge open when a tab strip owns
/// it.
///
/// Painted rather than expressed as a `BoxDecoration` border: a `Border` may
/// only be combined with a `borderRadius` when all four of its sides are
/// present, and a pane under a tab strip needs exactly three of them.
class const _PaneOutline({
  required final Color color,
  required final bool openTop,
  final bool squareTopLeft = false,
}) extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Inset by half the stroke: a hairline drawn *on* the edge is half outside
    // the pane, where it is clipped away and reads as a half-weight line.
    const inset = AppChrome.hairline / 2;
    final rect = (Offset.zero & size).deflate(inset);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = AppChrome.hairline;

    if (!openTop) {
      canvas.drawRRect(RRect.fromRectAndRadius(rect, AppRadii.paneRadius), paint);
      return;
    }

    // In from the top-left, down the left, around the bottom, up the right and
    // back out at the top-right. The top *edge* is the gap: the strip's rule
    // closes it, and these turned corners are what that rule runs between.
    //
    // Corners are quadratics through the corner point: at this radius they are
    // indistinguishable from an arc, and unlike `arcToPoint` there is no sweep
    // direction to get backwards.
    const r = AppRadii.pane;
    final path = Path();
    if (squareTopLeft) {
      path.moveTo(rect.left, rect.top);
    } else {
      path
        ..moveTo(rect.left + r, rect.top)
        ..quadraticBezierTo(rect.left, rect.top, rect.left, rect.top + r);
    }
    path
      ..lineTo(rect.left, rect.bottom - r)
      ..quadraticBezierTo(rect.left, rect.bottom, rect.left + r, rect.bottom)
      ..lineTo(rect.right - r, rect.bottom)
      ..quadraticBezierTo(rect.right, rect.bottom, rect.right, rect.bottom - r)
      ..lineTo(rect.right, rect.top + r)
      ..quadraticBezierTo(rect.right, rect.top, rect.right - r, rect.top);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_PaneOutline old) =>
      old.color != color || old.openTop != openTop || old.squareTopLeft != squareTopLeft;
}
