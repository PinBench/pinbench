// Flutter imports:
import 'package:flutter/widgets.dart';

// Project imports:
import '../../../models/breadboard_state.dart';
import '../configs/breadboard_config.dart';
import '../configs/power_rail_config.dart';
import '../configs/terminal_strip_config.dart';

/// Which hole of a landscape board a point is on: rows run along x, the five
/// bands (rail, `a`–`e`, notch, `f`–`j`, rail) stack down y.
class BreadboardHitTester {
  /// How close to a hole's centre counts as being on it, when the caller
  /// doesn't say. Deliberately under half a hole pitch: at rest the gaps
  /// between holes are what you grab to drag the board itself.
  static double defaultHitRadius(BreadboardConfig config) => config.gridCellSize * 0.8;

  /// The hole at [localPosition], or null.
  ///
  /// [preciseColumns] is what a *pointer* wants: a terminal strip answers for
  /// any y across the bank by default, because the five holes of a row are one
  /// node and a leg anywhere along it is plugged into that row — which is right
  /// for the netlist working out what's connected, but makes a hover highlight
  /// fire while the pointer is plainly in the gap between two lettered lines.
  /// Set it to gate the distance to the nearest line too, the way the rails
  /// always gate the distance to the nearest hole.
  static BreadboardHoverState? hitTest(
    Offset localPosition,
    BreadboardConfig config, {
    double? hitRadius,
    bool preciseColumns = false,
  }) {
    final radius = hitRadius ?? defaultHitRadius(config);
    // 1. Check the power rails, top then bottom.
    final rail = PowerRailConfig(config);

    final topRailResult = _testPowerRail(
      localPosition,
      config,
      rail,
      isRight: false,
      hitRadius: radius,
    );
    if (topRailResult != null) return topRailResult;

    final bottomRailResult = _testPowerRail(
      localPosition,
      config,
      rail,
      isRight: true,
      hitRadius: radius,
    );
    if (bottomRailResult != null) return bottomRailResult;

    // 2. Check the terminal strips, a–e then f–j.
    final topStripResult = _testTerminalStrip(
      localPosition,
      config,
      TerminalStripConfig.left(config),
      stripOffsetY: config.topTerminalStripY,
      isRight: false,
      hitRadius: radius,
      preciseColumns: preciseColumns,
    );
    if (topStripResult != null) return topStripResult;

    final bottomStripResult = _testTerminalStrip(
      localPosition,
      config,
      TerminalStripConfig.right(config),
      stripOffsetY: config.bottomTerminalStripY,
      isRight: true,
      hitRadius: radius,
      preciseColumns: preciseColumns,
    );
    if (bottomStripResult != null) return bottomStripResult;

    return null;
  }

  static BreadboardHoverState? _testPowerRail(
    Offset localPosition,
    BreadboardConfig config,
    PowerRailConfig rail, {
    required bool isRight,
    required double hitRadius,
  }) {
    final baseOffsetY = isRight ? config.bottomPowerRailY : config.topPowerRailY;

    final localX = localPosition.dx;
    final localY = localPosition.dy - baseOffsetY;

    if (localX < config.firstRowX - hitRadius || localX > config.lastRowX + hitRadius) return null;

    // Nearest of the two rails, not the first within range: with a radius
    // wide enough to aim at comfortably the two overlap, and answering
    // "plus" for a pointer sitting on the minus rail wires up the wrong net.
    final toPlus = (localY - rail.plusHoleOffset).abs();
    final toMinus = (localY - rail.minusHoleOffset).abs();
    if (toPlus >= hitRadius && toMinus >= hitRadius) return null;

    // Rails are drilled in blocks of five, and blanks between blocks snap on
    // to the nearest drilled row. Measured from the rail's own rows, which are
    // staggered half a pitch off the terminal strips' on boards where the
    // blocks can't centre evenly.
    final rawRow = ((localX - config.firstRowX - rail.rowOffset) / config.gridCellStep).round();
    final row = rail.nearestHoleRow(rawRow.clamp(0, config.rowsCount - 1));

    // ...but only if that hole is actually within reach. This is the one gate
    // the rails were missing: the range check above only says "somewhere along
    // the board", so without this a pointer halfway between two rows — or
    // sitting on the blank moulding a whole pitch away from any hole — lit a
    // block up. The distance is measured to the hole finally answered, not to
    // the nearest lattice row, which is what keeps a wide wiring radius able
    // to reach across a blank while a tight hover radius can't.
    if ((localX - rail.holeX(row)).abs() >= hitRadius) {
      return null;
    }

    return BreadboardHoverState(
      channel: toPlus <= toMinus ? BreadboardChannel.plus : BreadboardChannel.minus,
      rowIndex: row,
      isRightSide: isRight,
    );
  }

  static BreadboardHoverState? _testTerminalStrip(
    Offset localPosition,
    BreadboardConfig config,
    TerminalStripConfig strip, {
    required double stripOffsetY,
    required bool isRight,
    required double hitRadius,
    bool preciseColumns = false,
  }) {
    final localX = localPosition.dx - config.firstRowX;
    final localY = localPosition.dy - stripOffsetY;

    // Without [preciseColumns], y is tested against the bank's whole band
    // rather than the distance to the nearest lettered line: the five holes of
    // a terminal strip are one node, so a leg anywhere across the strip is
    // plugged into that row, and that's what the netlist needs to hear.
    // (`getPortAt` rounds to a letter afterwards.) A pointer wants the other
    // answer — see [hitTest].
    if (preciseColumns) {
      final column = (localY / config.gridCellStep).round();
      if (column < 0 || column >= strip.holesPerStrip) return null;
      if ((localY - column * config.gridCellStep).abs() >= hitRadius) return null;
    }

    if (localY >= -hitRadius &&
        localY <= (strip.holesPerStrip - 1) * config.gridCellStep + hitRadius) {
      final row = (localX / config.gridCellStep).round();
      if ((localX - row * config.gridCellStep).abs() < hitRadius &&
          row >= 0 &&
          row < config.rowsCount) {
        return BreadboardHoverState(
          channel: BreadboardChannel.terminalStrip,
          rowIndex: row,
          isRightSide: isRight,
        );
      }
    }
    return null;
  }
}
