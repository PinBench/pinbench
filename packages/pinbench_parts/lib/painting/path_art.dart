import 'package:flutter/widgets.dart';

import 'base_component_painter.dart';

/// One colour of a [PathArtPainter]'s artwork: its paths and their fill.
typedef PathArtLayer = (List<Path> paths, Color color);

/// Draws a part from flat-colour vector layers, the shape the Flutter Da
/// Vinci Figma plugin produces: one layer per colour, each exported on its own
/// and shifted back to where it sits in the part's Figma frame.
mixin PathArtPainter on BaseComponentPainter {
  /// The frame the artwork was drawn in; painting scales it onto the part.
  Size get designSize;

  /// The artwork, bottom layer first.
  List<PathArtLayer> get layers;

  /// One exported layer, moved to where it sits in the frame.
  ///
  /// Its paths stay separate rather than merged: each was filled on its own in
  /// Figma, and one nonzero fill over all of them would cancel wherever two
  /// with opposite winding overlap.
  static List<Path> layer(Offset offset, List<Path> paths) => [
    for (final path in paths) path.shift(offset),
  ];

  @override
  void paintComponent(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / designSize.width, size.height / designSize.height);
    // Ghost preview while dragging, matching the SVG-drawn parts.
    if (isOutline) canvas.saveLayer(null, Paint()..color = const Color(0x66FFFFFF));
    for (final (paths, color) in layers) {
      final paint = Paint()..color = color;
      for (final path in paths) {
        canvas.drawPath(path, paint);
      }
    }
    if (isOutline) canvas.restore();
    canvas.restore();
  }
}
