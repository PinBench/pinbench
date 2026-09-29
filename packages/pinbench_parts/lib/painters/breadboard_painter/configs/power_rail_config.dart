// Flutter imports:
import 'package:flutter/widgets.dart';

// Project imports:
import 'breadboard_config.dart';
import '../../../painting/part_palette.dart';

/// A `+`/`-` power rail pair along one edge of the board.
///
/// Electrically each rail is ONE node for the full length of the board — the
/// blocks of five below are moulding, not separate strips, unlike the terminal
/// strips where a group of five really is the node. That is why hovering a
/// rail lights the whole line rather than the block under the pointer.
class PowerRailConfig {
  /// Real rails punch their holes in blocks of five, with a pitch of blank
  /// moulding between blocks. The blanks sit on the lattice like the holes do,
  /// so one block costs [rowsPerGroup] rows.
  static const holesPerGroup = 5;
  static const rowsPerGroup = holesPerGroup + 1;

  /// Where the two polarity lines are drawn, and where the two hole lines are,
  /// measured across the board from the rail's own origin.
  ///
  /// The hole lines must be a WHOLE number of hole pitches out: the rail origin
  /// ([BreadboardConfig.topPowerRailY] / [BreadboardConfig.bottomPowerRailY])
  /// is on the connection lattice, so anything else puts rail holes off it and
  /// a grid-snapped part can never reach them — legs land half a pitch to the
  /// side of every rail hole no matter where you drop them. The lines flank
  /// the hole lines half a pitch out, which is drawing only.
  final double plusLineOffset;
  final double minusLineOffset;
  final double plusHoleOffset;
  final double minusHoleOffset;

  /// How many blocks of [holesPerGroup] fit along the board, and the row the
  /// first hole of the first block sits on. Whatever rows are left over after
  /// the last block are split evenly between the two ends, so the pattern
  /// reads as centred rather than running out at the bottom: a full board
  /// gets 10 blocks (50 holes) over 63 rows, a half board 5 (25 holes) over 30.
  final int groupCount;
  final int firstHoleRow;

  /// Half a row of stagger, when the rows left over at the ends are an odd
  /// number and so can't be split evenly between them — as on a half board,
  /// where 5 blocks span 28 of the 29 available row gaps.
  ///
  /// This is why a real breadboard's rails don't line up with its terminal
  /// strips: the blocks are centred along the board, and centring an odd
  /// leftover lands them half a pitch off the strips' rows. A full board's
  /// leftover is 4 rows, splits 2/2, and stays aligned.
  ///
  /// It's the one place a connection point deliberately leaves the shared
  /// lattice (see `GridSystem`). Parts still plug in exactly, because
  /// `BreadboardSnapHelper` asks the board where its holes are rather than
  /// assuming they're on the grid.
  final double rowOffset;

  /// Where hole [row] of this rail is drawn, along the board.
  double holeX(int row) => _firstRowX + row * _rowStep + rowOffset;

  final double _firstRowX;
  final double _rowStep;

  final Color plusColor = PartPalette.red;
  final Color minusColor = PartPalette.blue;

  PowerRailConfig(BreadboardConfig boardConfig)
    : plusLineOffset = -boardConfig.gridCellSize,
      minusLineOffset = boardConfig.gridCellStep + boardConfig.gridCellSize,
      plusHoleOffset = 0,
      minusHoleOffset = boardConfig.gridCellStep,
      groupCount = boardConfig.rowsCount ~/ rowsPerGroup,
      // Blocks span `groupCount * rowsPerGroup - 1` rows (the trailing blank
      // of the last block is not part of it), so the leftover is one more
      // than the plain remainder.
      firstHoleRow =
          (boardConfig.rowsCount - (boardConfig.rowsCount ~/ rowsPerGroup) * rowsPerGroup + 1) ~/ 2,
      rowOffset =
          (boardConfig.rowsCount - (boardConfig.rowsCount ~/ rowsPerGroup) * rowsPerGroup + 1).isOdd
          ? boardConfig.gridCellStep / 2
          : 0,
      _firstRowX = boardConfig.firstRowX,
      _rowStep = boardConfig.gridCellStep;

  int get lastHoleRow => firstHoleRow + (groupCount - 1) * rowsPerGroup + holesPerGroup - 1;

  /// Every row that carries a rail hole, in order.
  Iterable<int> get holeRows sync* {
    for (var group = 0; group < groupCount; group++) {
      for (var i = 0; i < holesPerGroup; i++) {
        yield firstHoleRow + group * rowsPerGroup + i;
      }
    }
  }

  bool hasHoleAtRow(int row) {
    if (row < firstHoleRow || row > lastHoleRow) return false;
    return (row - firstHoleRow) % rowsPerGroup < holesPerGroup;
  }

  /// Which block of five [row] belongs to, snapping blanks on to the block
  /// the pointer was over. Null when the rail has no blocks at all.
  int? groupIndexForRow(int row) {
    if (groupCount == 0) return null;
    return (nearestHoleRow(row) - firstHoleRow) ~/ rowsPerGroup;
  }

  /// The drilled row closest to the fractional row [row], for snapping a
  /// dragged part's legs: unlike [nearestHoleRow] this keeps the sub-row part
  /// of the position, so a leg on a blank goes to whichever neighbouring block
  /// it was actually closer to instead of always backing up to the one above.
  int nearestHoleRowTo(double row) {
    final rounded = row.round();
    if (groupCount == 0) return rounded;
    if (hasHoleAtRow(rounded)) return rounded;
    // Blanks are single rows and the leftovers at each end are shorter than a
    // block, so a drilled row is always within rowsPerGroup either way.
    for (var distance = 1; distance <= rowsPerGroup; distance++) {
      final above = rounded - distance;
      final below = rounded + distance;
      final hasAbove = hasHoleAtRow(above);
      final hasBelow = hasHoleAtRow(below);
      if (hasAbove && hasBelow) {
        return (row - above).abs() <= (below - row).abs() ? above : below;
      }
      if (hasAbove) return above;
      if (hasBelow) return below;
    }
    return rounded;
  }

  /// The drilled row closest to [row], so a pointer aimed at a blank between
  /// two blocks still lands in a hole instead of on the moulding.
  int nearestHoleRow(int row) {
    if (groupCount == 0) return row;
    if (row <= firstHoleRow) return firstHoleRow;
    if (row >= lastHoleRow) return lastHoleRow;
    final local = row - firstHoleRow;
    final indexInGroup = local % rowsPerGroup;
    if (indexInGroup < holesPerGroup) return row;
    // On a blank: equidistant from both neighbours, so stay in the block the
    // pointer was already over.
    return row - 1;
  }
}
