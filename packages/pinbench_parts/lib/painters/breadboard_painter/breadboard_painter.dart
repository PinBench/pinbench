import 'package:flutter/widgets.dart';

import '../../models/breadboard_state.dart';
import '../../painting/base_component_painter.dart';
import '../../painting/paint_node.dart';
import 'configs/breadboard_config.dart';
import 'configs/power_rail_config.dart';
import 'configs/terminal_strip_config.dart';
import 'logic/breadboard_hit_tester.dart';
import '../../painting/port_provider.dart';
import '../../models/port_model.dart';
import 'parts/breadboard_background_node.dart';
import 'parts/breadboard_center_notch_node.dart';
import 'parts/breadboard_power_rail_node.dart';
import 'parts/breadboard_terminal_strip_node.dart';

class BreadboardPainter({
  required final BreadboardConfig config,
  final BreadboardHoverState? hoverState,
  super.isOutline = false,
}) extends BaseComponentPainter implements PortProvider {
  @override
  List<ComponentPort> getPorts() => []; // Dynamic discovery used instead

  /// The holes nearest [localOffset] in the board's own space: the nearest one
  /// on a power rail, and the nearest one on a terminal strip.
  ///
  /// Band and row are chosen *independently*, so a point that is nowhere near
  /// the board on one axis still resolves the other: a part hovering beside
  /// the board, wired across into it, has to line up with a hole row even
  /// though it is bands away from any hole. That's what keeps the wire square,
  /// and it's why this can't be [getPortAt], which deliberately answers null
  /// once you're off a hole in either direction.
  ///
  /// Both are offered rather than just the closest, because the rails and the
  /// strips do not share a row grid — rails skip the blanks between their
  /// blocks of five, and on a half board they sit half a pitch off (see
  /// [PowerRailConfig.rowOffset]). Picking one region by whichever band is
  /// closer goes wrong exactly when the part is far from the board: the rails
  /// are its outermost bands, so a part hovering off the edge would be offered
  /// a rail row and land half a pitch from the strip hole it was about to be
  /// wired to. Let the caller take whichever is nearer on the axis it cares
  /// about.
  List<Offset> nearestHoles(Offset localOffset) {
    final rail = PowerRailConfig(config);

    double? nearestOf(Iterable<double> candidates) {
      double? best;
      for (final candidate in candidates) {
        if (best == null || (candidate - localOffset.dy).abs() < (best - localOffset.dy).abs()) {
          best = candidate;
        }
      }
      return best;
    }

    final holes = <Offset>[];

    final railLine = nearestOf([
      for (final base in [config.topPowerRailY, config.bottomPowerRailY])
        for (final hole in [rail.plusHoleOffset, rail.minusHoleOffset]) base + hole,
    ]);
    if (railLine != null && rail.groupCount > 0) {
      final row = rail.nearestHoleRowTo(
        (localOffset.dx - config.firstRowX - rail.rowOffset) / config.gridCellStep,
      );
      holes.add(Offset(rail.holeX(row), railLine));
    }

    final stripLine = nearestOf([
      for (final start in [config.topTerminalStripY, config.bottomTerminalStripY])
        for (var column = 0; column < config.colsCount; column++)
          start + column * config.gridCellStep,
    ]);
    if (stripLine != null) {
      final row = ((localOffset.dx - config.firstRowX) / config.gridCellStep).round().clamp(
        0,
        config.rowsCount - 1,
      );
      holes.add(Offset(config.rowX(row), stripLine));
    }

    return holes;
  }

  /// [preciseColumns] is for pointer callers — see [BreadboardHitTester.hitTest].
  /// It's an extra optional parameter on top of [PortProvider.getPortAt], so
  /// geometry callers (the netlist deciding which hole a leg is in) get the
  /// default and are unaffected.
  @override
  ComponentPort? getPortAt(Offset localOffset, {double? hitRadius, bool preciseColumns = false}) {
    // A board is nothing but holes, so a wide radius doesn't reach *past*
    // anything — the row/column are rounded to the nearest either way. It
    // just means a pointer that lands between holes still snaps to one.
    final hover = BreadboardHitTester.hitTest(
      localOffset,
      config,
      hitRadius: hitRadius,
      preciseColumns: preciseColumns,
    );
    if (hover == null) return null;

    final side = hover.isRightSide ? 'right' : 'left';
    String id;
    String name;
    Offset portOffset;

    final rail = PowerRailConfig(config);

    if (hover.channel == BreadboardChannel.plus || hover.channel == BreadboardChannel.minus) {
      final isPlus = hover.channel == BreadboardChannel.plus;
      // For rails, we need to know WHICH row specifically.
      // Although BreadboardHoverState doesn't store the row for rails yet,
      // we can calculate it from localOffset.
      // The hit tester already snapped this to a drilled row: rails are
      // punched in blocks of five, so the nearest lattice row may be a blank
      // and a port there would sit on moulding rather than in a hole.
      final row = hover.rowIndex;
      if (row == null || row < 0 || row >= config.rowsCount) return null;

      final channelName = isPlus ? 'plus' : 'minus';
      id = 'rail_${side}_${channelName}_$row';
      name = 'Power Rail $side ${isPlus ? '+' : '−'} row ${row + 1}';

      final railY =
          (hover.isRightSide ? config.bottomPowerRailY : config.topPowerRailY) +
          (isPlus ? rail.plusHoleOffset : rail.minusHoleOffset);
      portOffset = Offset(rail.holeX(row), railY);
    } else {
      final row = hover.rowIndex!;
      // Which of the strip's five holes: the whole row is one node, but the
      // port has to name the hole the leg is actually in.
      final stripY = hover.isRightSide ? config.bottomTerminalStripY : config.topTerminalStripY;
      final localY = localOffset.dy - stripY;
      final col = (localY / config.gridCellStep).round();
      if (col < 0 || col >= config.colsCount) return null;

      final strip = hover.isRightSide
          ? TerminalStripConfig.right(config)
          : TerminalStripConfig.left(config);
      final colName = strip.columnLabels[col];

      // The `sig_` id prefix is the on-disk wire format (`.cdl` templates and
      // saved projects reference these by name), so it stays put even though
      // the board calls this a terminal strip.
      id = 'sig_${side}_${colName}_$row';
      name = 'Terminal Strip $side ${colName.toUpperCase()}${row + 1}';
      portOffset = Offset(config.rowX(row), stripY + col * config.gridCellStep);
    }

    return ComponentPort(id: id, name: name, localOffset: portOffset);
  }

  @override
  Offset? getPortOffsetById(String id) {
    if (id.startsWith('rail_')) {
      final parts = id.split('_');
      if (parts.length < 4) return null;
      final isRightSide = parts[1] == 'right';
      final channel = parts[2] == 'plus' ? BreadboardChannel.plus : BreadboardChannel.minus;
      final row = int.tryParse(parts[3]) ?? 0;

      final rail = PowerRailConfig(config);
      final isPlus = channel == BreadboardChannel.plus;
      final holeOffset = isPlus ? rail.plusHoleOffset : rail.minusHoleOffset;

      final railY = isRightSide ? config.bottomPowerRailY : config.topPowerRailY;
      return Offset(rail.holeX(row), railY + holeOffset);
    } else if (id.startsWith('sig_')) {
      final parts = id.split('_');
      if (parts.length < 4) return null;
      final isRightSide = parts[1] == 'right';
      final colName = parts[2];
      final row = int.tryParse(parts[3]) ?? 0;

      final strip = isRightSide
          ? TerminalStripConfig.right(config)
          : TerminalStripConfig.left(config);
      final colIndex = strip.columnLabels.indexOf(colName);
      if (colIndex == -1) return null;

      final stripY = isRightSide ? config.bottomTerminalStripY : config.topTerminalStripY;
      return Offset(config.rowX(row), stripY + colIndex * config.gridCellStep);
    }
    return null;
  }

  late final PaintNode _breadboardTree = _buildCanvasTree();

  /// Where each band is *drawn*, top to bottom. These offsets have to be
  /// exactly the ones [getPortAt] / [getPortOffsetById] / [BreadboardHitTester]
  /// compute holes from, or the painted holes drift away from the real
  /// connection points — hover highlights the wrong hole and component legs
  /// stop landing in any. So: y from the same band offsets those use, and x
  /// left at 0, because each child already places its own rows from
  /// [BreadboardConfig.rowX]. Move the rows by changing `firstRowX`, never by
  /// nudging these.
  PaintNode _buildCanvasTree() => CanvasStack(
    size: config.boardSize,
    children: [
      CanvasPositioned(left: 0, top: 0, child: BreadboardBackgroundNode(this)),
      CanvasPositioned(
        left: 0,
        top: config.topPowerRailY,
        child: BreadboardPowerRailNode(this, isRight: false),
      ),
      CanvasPositioned(
        left: 0,
        top: config.bottomPowerRailY,
        child: BreadboardPowerRailNode(this, isRight: true),
      ),
      CanvasPositioned(
        left: 0,
        top: config.centerNotchCenterY - config.centerNotchThickness / 2,
        child: BreadboardCenterNotchNode(this),
      ),
      CanvasPositioned(
        left: 0,
        top: config.topTerminalStripY,
        child: BreadboardTerminalStripNode(this, isRight: false),
      ),
      CanvasPositioned(
        left: 0,
        top: config.bottomTerminalStripY,
        child: BreadboardTerminalStripNode(this, isRight: true),
      ),
    ],
  );

  @override
  void paintComponent(Canvas canvas, Size size) {
    _breadboardTree.paint(canvas, Offset.zero);
  }

  @override
  bool shouldRepaintComponent(covariant BreadboardPainter oldDelegate) =>
      !identical(this, oldDelegate) &&
      (config != oldDelegate.config || hoverState != oldDelegate.hoverState);
}
