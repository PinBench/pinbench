import 'package:flutter/widgets.dart';

import '../../../painting/paint_node.dart';
import '../../../models/breadboard_state.dart';
import '../breadboard_painter.dart';
import '../configs/power_rail_config.dart';
import 'breadboard_utils.dart';

/// One `+`/`-` rail pair, along the top or the bottom edge of the board.
///
/// The node's own origin is the rail's `+` hole line, so everything here is
/// measured across the board from there; rows run along x.
class BreadboardPowerRailNode extends PaintNode {
  final BreadboardPainter painter;

  /// The bottom rail. Called "right" because that is what its port ids say —
  /// see `BreadboardConfig`.
  final bool isRight;
  final _paint = Paint();

  BreadboardPowerRailNode(this.painter, {required this.isRight});

  @override
  Size get size =>
      Size(painter.config.boardLength, painter.config.gridCellStep * painter.config.powerRailCells);

  @override
  void paint(Canvas canvas, Offset offset) {
    final config = painter.config;
    final rail = PowerRailConfig(config);

    canvas.save();
    canvas.translate(offset.dx, offset.dy);

    final railStartX = config.firstRowX - config.gridCellSize;
    final railEndX = config.lastRowX + config.gridCellSize;

    // Polarity marks share the letter bands, centred in the board's margins.
    for (final signX in [config.startLabelX, config.endLabelX]) {
      _drawPolaritySymbol(canvas, signX, rail.plusLineOffset, rail.plusColor, isPlus: true);
      _drawPolaritySymbol(canvas, signX, rail.minusLineOffset, rail.minusColor, isPlus: false);
    }

    _paint.style = PaintingStyle.stroke;
    _paint.strokeWidth = 1.5;
    _paint.strokeCap = StrokeCap.round;

    _paint.color = rail.plusColor;
    canvas.drawLine(
      Offset(railStartX, rail.plusLineOffset),
      Offset(railEndX, rail.plusLineOffset),
      _paint,
    );

    _paint.color = rail.minusColor;
    canvas.drawLine(
      Offset(railStartX, rail.minusLineOffset),
      Offset(railEndX, rail.minusLineOffset),
      _paint,
    );

    var isPlusHighlighted = false;
    var isMinusHighlighted = false;

    final hover = painter.hoverState;
    if (hover != null && hover.isRightSide == isRight) {
      isPlusHighlighted = hover.channel == BreadboardChannel.plus;
      isMinusHighlighted = hover.channel == BreadboardChannel.minus;
    }

    // A rail is one node for the whole length of the board, so the highlight
    // runs the whole length too — from the first drilled hole to the last,
    // straight across the blank moulding between blocks. (The blocks of five
    // are how the plastic is punched; they are not separate strips the way a
    // terminal strip's group of five is.)
    if (isPlusHighlighted || isMinusHighlighted) {
      _paint.strokeWidth = 2.0;
      final startX = rail.holeX(rail.firstHoleRow);
      final endX = rail.holeX(rail.lastHoleRow);

      if (isPlusHighlighted) {
        _paint.color = rail.plusColor;
        canvas.drawLine(
          Offset(startX, rail.plusHoleOffset),
          Offset(endX, rail.plusHoleOffset),
          _paint,
        );
      }
      if (isMinusHighlighted) {
        _paint.color = rail.minusColor;
        canvas.drawLine(
          Offset(startX, rail.minusHoleOffset),
          Offset(endX, rail.minusHoleOffset),
          _paint,
        );
      }
    }

    _paint.style = PaintingStyle.fill;
    for (final row in rail.holeRows) {
      // The rail's own row origin: its blocks are centred along the board,
      // which on a half board puts them half a pitch past the strips' rows.
      final x = rail.holeX(row);
      BreadboardUtils.drawHole(
        canvas,
        Offset(x, rail.plusHoleOffset),
        _paint,
        isHighlighted: isPlusHighlighted,
        highlightColor: rail.plusColor,
      );
      BreadboardUtils.drawHole(
        canvas,
        Offset(x, rail.minusHoleOffset),
        _paint,
        isHighlighted: isMinusHighlighted,
        highlightColor: rail.minusColor,
      );
    }

    canvas.restore();
  }

  void _drawPolaritySymbol(Canvas canvas, double x, double y, Color color, {required bool isPlus}) {
    _paint.color = color;
    _paint.strokeWidth = 1.5;
    _paint.strokeCap = StrokeCap.round;
    _paint.style = PaintingStyle.stroke;

    canvas.save();
    canvas.translate(x, y);

    final symbolSize = painter.config.gridCellSize * 0.4;
    canvas.drawLine(Offset(-symbolSize, 0), Offset(symbolSize, 0), _paint);
    if (isPlus) {
      canvas.drawLine(Offset(0, -symbolSize), Offset(0, symbolSize), _paint);
    }

    canvas.restore();
  }
}
