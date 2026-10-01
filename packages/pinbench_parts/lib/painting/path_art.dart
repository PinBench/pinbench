import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'base_component_painter.dart';

/// One colour of a [PathArtPainter]'s artwork: its paths and their fill.
typedef PathArtLayer = (List<Path> paths, Color color);

/// Draws a part from flat-colour vector layers, the shape the Flutter Da
/// Vinci Figma plugin produces: one layer per colour, each exported on its own
/// and shifted back to where it sits in the part's Figma frame.
///
/// A painter supplies the frame's [designSize] and its [layers], and draws
/// whatever changes with the part's state — a lit segment, a pressed button —
/// in [paintOverlay]. Scaling onto the part, and the faded ghost while it is
/// dragged, are done here, once, for all of them.
mixin PathArtPainter on BaseComponentPainter {
  /// The frame the artwork was drawn in; painting scales it onto the part.
  Size get designSize;

  /// The artwork, bottom layer first.
  ///
  /// Return a list kept in a static field, not one built per call: each list
  /// is recorded once and replayed (see [_pictures]), so a fresh list each
  /// time would record the same art again on every paint.
  List<PathArtLayer> get layers;

  /// Draws the words printed on the part — see `PartText` — over its art, in
  /// [designSize] coordinates. They are part of the part at rest, so the drag
  /// ghost shows them too.
  void paintText(Canvas canvas) {}

  /// Draws what changes with the part's state over its art, in [designSize]
  /// coordinates. Not called for the drag ghost, which shows the part at rest.
  void paintOverlay(Canvas canvas) {}

  /// One exported layer, moved to where it sits in the frame.
  ///
  /// Its paths stay separate rather than merged: each was filled on its own in
  /// Figma, and one nonzero fill over all of them would cancel wherever two
  /// with opposite winding overlap.
  static List<Path> layer(Offset offset, List<Path> paths) => [
    for (final path in paths) path.shift(offset),
  ];

  /// Each [layers] list recorded as a picture, the first time it is painted.
  ///
  /// The art never changes, so issuing every path again on each paint — some
  /// parts have over fifty — is work repeated for nothing: one picture per
  /// list, shared by every placed instance, is replayed instead.
  static final _pictures = Expando<ui.Picture>();

  static ui.Picture _record(List<PathArtLayer> layers) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    for (final (paths, color) in layers) {
      final paint = Paint()..color = color;
      for (final path in paths) {
        canvas.drawPath(path, paint);
      }
    }
    return recorder.endRecording();
  }

  @override
  void paintComponent(Canvas canvas, Size size) {
    final art = layers;
    canvas.save();
    canvas.scale(size.width / designSize.width, size.height / designSize.height);
    if (isOutline) {
      // Ghost preview while dragging, matching the SVG-drawn parts.
      canvas.saveLayer(null, Paint()..color = const Color(0x66FFFFFF));
      canvas.drawPicture(_pictures[art] ??= _record(art));
      paintText(canvas);
      canvas.restore();
    } else {
      canvas.drawPicture(_pictures[art] ??= _record(art));
      paintText(canvas);
      paintOverlay(canvas);
    }
    canvas.restore();
  }
}
