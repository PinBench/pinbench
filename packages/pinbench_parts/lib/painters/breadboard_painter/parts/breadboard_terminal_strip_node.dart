import 'package:flutter/widgets.dart';

import '../../../painting/paint_node.dart';
import '../../../models/breadboard_state.dart';
import '../breadboard_painter.dart';
import '../configs/terminal_strip_config.dart';
import 'breadboard_utils.dart';
import '../../../painting/part_palette.dart';

/// One bank of terminal strips — the `a`–`e` lines above the notch or the
/// `f`–`j` lines below it.
///
/// Each numbered row is a *terminal strip*: five holes connected across the
/// bank, which is what the highlight draws as a bar through the row. Rows do
/// not carry across the notch, so this bank's row 7 and the other bank's row 7
/// are separate nodes.
///
/// The node's origin is its first lettered line (`a` or `f`); rows run along x.
class BreadboardTerminalStripNode(
  final BreadboardPainter painter, {

  /// The `f`–`j` bank. Called "right" because that is what its port ids say.
  required final bool isRight,
}) extends PaintNode {
  final _paint = Paint();

  @override
  Size get size =>
      Size(painter.config.boardLength, painter.config.colsCount * painter.config.gridCellStep);

  @override
  void paint(Canvas canvas, Offset offset) {
    final config = painter.config;
    final strip = isRight ? TerminalStripConfig.right(config) : TerminalStripConfig.left(config);

    canvas.save();
    canvas.translate(offset.dx, offset.dy);

    int? highlightedRow;
    if (painter.hoverState != null &&
        painter.hoverState!.channel == BreadboardChannel.terminalStrip &&
        painter.hoverState!.isRightSide == isRight) {
      highlightedRow = painter.hoverState!.rowIndex;
    }

    // The highlight is the connection: a bar across the five holes of the
    // hovered row, stopping at this bank's edge because the notch does.
    if (highlightedRow != null) {
      _paint.style = PaintingStyle.stroke;
      _paint.color = PartPalette.green;
      _paint.strokeWidth = 2.0;
      _paint.strokeCap = StrokeCap.round;
      final x = config.rowX(highlightedRow);
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, (strip.holesPerStrip - 1) * config.gridCellStep),
        _paint,
      );
    }

    _paint.style = PaintingStyle.fill;
    for (var col = 0; col < strip.holesPerStrip; col++) {
      final y = col * config.gridCellStep;
      for (var row = 0; row < config.rowsCount; row++) {
        BreadboardUtils.drawHole(
          canvas,
          Offset(config.rowX(row), y),
          _paint,
          isHighlighted: row == highlightedRow,
        );
      }
    }

    // Column letters (A–E or F–J), printed at both ends like a real board.
    final columnLabels = strip.columnDisplayLabels;
    for (var i = 0; i < columnLabels.length; i++) {
      final y = i * config.gridCellStep;
      for (final x in [config.startLabelX, config.endLabelX]) {
        BreadboardUtils.drawLabel(canvas, columnLabels[i], x, y, config.gridCellSize);
      }
    }

    // Row numbers, only on the rows a real board prints — see
    // [BreadboardConfig.isLabelledRow].
    for (var row = 0; row < config.rowsCount; row++) {
      if (!config.isLabelledRow(row)) continue;
      BreadboardUtils.drawLabel(
        canvas,
        '${config.rowNumber(row)}',
        config.rowX(row),
        strip.rowLabelRelY,
        config.gridCellSize,
      );
    }

    canvas.restore();
  }
}
