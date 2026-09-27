// Package imports:
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:pinbench_parts/models/breadboard_state.dart';
import 'package:pinbench_parts/painters/breadboard_painter/breadboard_painter.dart';
import 'package:pinbench_parts/painters/breadboard_painter/configs/breadboard_config.dart';
import 'package:pinbench_parts/painters/breadboard_painter/configs/power_rail_config.dart';
import 'package:pinbench_parts/painters/breadboard_painter/logic/breadboard_hit_tester.dart';

void main() {
  group('power rail hole blocks', () {
    test('a full board rail is 10 blocks of five, centred on the board', () {
      final config = BreadboardConfig.full();
      final rail = PowerRailConfig(config);

      expect(rail.groupCount, 10);
      expect(rail.holeRows.length, 50);

      // Same margin at both ends, measured in pixels rather than in rows: the
      // leftover row count is odd on this board, so the blocks are centred
      // half a pitch over and the first and last hole are not the same whole
      // number of rows from their ends. The distance is still equal.
      expect(
        rail.holeX(rail.firstHoleRow) - config.firstRowX,
        closeTo(config.lastRowX - rail.holeX(rail.lastHoleRow), 1e-9),
      );
    });

    test('a half board rail is 5 blocks of five', () {
      final rail = PowerRailConfig(BreadboardConfig.half());

      expect(rail.groupCount, 5);
      expect(rail.holeRows.length, 25);
    });

    test('every sixth row is blank moulding', () {
      final config = BreadboardConfig.full();
      final rail = PowerRailConfig(config);

      for (var row = rail.firstHoleRow; row <= rail.lastHoleRow; row++) {
        final isBlank =
            (row - rail.firstHoleRow) % PowerRailConfig.rowsPerGroup ==
            PowerRailConfig.holesPerGroup;
        expect(rail.hasHoleAtRow(row), !isBlank, reason: 'row $row');
      }
    });

    test('holes are grouped in runs of exactly five', () {
      final rail = PowerRailConfig(BreadboardConfig.full());
      final rows = rail.holeRows.toList();

      for (var i = 0; i < rows.length; i++) {
        expect(rail.groupIndexForRow(rows[i]), i ~/ PowerRailConfig.holesPerGroup);
      }
    });
  });

  group('power rail hover', () {
    final config = BreadboardConfig.full();
    final rail = PowerRailConfig(config);

    // Ask the rail where its hole is rather than reusing the terminal strips'
    // row formula: when the leftover rows are odd the blocks are centred half
    // a pitch over, so the two disagree. That is now true of a full board as
    // well as a half one.
    Offset railPoint(int row) =>
        Offset(rail.holeX(row), config.topPowerRailY + rail.minusHoleOffset);

    test('hovering a hole reports the drilled row under the pointer', () {
      final row = rail.firstHoleRow + 2 * PowerRailConfig.rowsPerGroup + 1;
      final hover = BreadboardHitTester.hitTest(railPoint(row), config);

      expect(hover?.channel, BreadboardChannel.minus);
      expect(hover?.rowIndex, row);
      expect(rail.groupIndexForRow(hover!.rowIndex!), 2);
    });

    // A radius like the one a wire in flight uses: wide enough to reach the
    // next block across a blank row.
    final reachingRadius = config.gridCellStep * 1.2;

    test('blank moulding is out of reach at the default radius', () {
      final blank = rail.firstHoleRow + PowerRailConfig.holesPerGroup;

      // The nearest hole is a whole pitch away, so nothing lights up — the
      // moulding between blocks is board to grab, not a hole to wire to.
      expect(BreadboardHitTester.hitTest(railPoint(blank), config), isNull);

      // Reaching for it from a wire, though, snaps into the block above.
      final hover = BreadboardHitTester.hitTest(
        railPoint(blank),
        config,
        hitRadius: reachingRadius,
      );
      expect(hover?.rowIndex, blank - 1);
      expect(rail.groupIndexForRow(hover!.rowIndex!), 0);
    });

    test('a hole only answers while the pointer is on it', () {
      final row = rail.firstHoleRow + 1;
      final radius = BreadboardHitTester.defaultHitRadius(config);

      expect(BreadboardHitTester.hitTest(railPoint(row), config)?.rowIndex, row);
      // Halfway to the next row is nobody's hole.
      expect(
        BreadboardHitTester.hitTest(railPoint(row).translate(0, config.gridCellStep / 2), config),
        isNull,
      );
      // Same across the rail, between the plus and minus columns.
      expect(
        BreadboardHitTester.hitTest(railPoint(row).translate(-config.gridCellStep / 2, 0), config),
        isNull,
      );
      expect(
        BreadboardHitTester.hitTest(railPoint(row).translate(0, radius * 0.9), config)?.rowIndex,
        row,
      );
    });

    test('a port on the rail always lands on a drilled row', () {
      final painter = BreadboardPainter(config: config);

      for (var row = 0; row < config.rowsCount; row++) {
        // Anywhere along the drilled part of the rail a wire finds something,
        // blanks included. Past either end (the margin before the first block
        // and after the last) there is nothing to find, which is why this
        // doesn't assert a port for every row on the board.
        final port = painter.getPortAt(railPoint(row), hitRadius: reachingRadius);
        if (row < rail.firstHoleRow || row > rail.lastHoleRow) continue;
        expect(port, isNotNull, reason: 'row $row');

        // What a wire must never get back is a row with no hole in it.
        final portRow = int.parse(port!.id.split('_').last);
        expect(rail.hasHoleAtRow(portRow), isTrue, reason: 'row $row -> $portRow');
        // The rail's own x, stagger included — not the terminal strips'.
        expect(port.localOffset.dx, rail.holeX(portRow));
      }
    });
  });

  group('terminal strip hover', () {
    final config = BreadboardConfig.full();
    final painter = BreadboardPainter(config: config);

    Offset holePoint(int column, int row) =>
        Offset(config.rowX(row), config.topTerminalStripY + column * config.gridCellStep);

    // Half a pitch across the bank: between lettered lines b and c.
    final betweenColumns = holePoint(1, 4).translate(0, config.gridCellStep / 2);

    test('a pointer on a hole lights its row up', () {
      final hover = BreadboardHitTester.hitTest(holePoint(1, 4), config, preciseColumns: true);

      expect(hover?.channel, BreadboardChannel.terminalStrip);
      expect(hover?.rowIndex, 4);
    });

    test('the gaps between columns are board to grab, not holes to light up', () {
      // The rails have always behaved this way; the strips used to answer for
      // anywhere across the whole five-line band, so the row lit up while the
      // pointer was plainly between two of its holes.
      expect(BreadboardHitTester.hitTest(betweenColumns, config, preciseColumns: true), isNull);
      // Half a pitch along the board, between two numbered rows.
      expect(
        BreadboardHitTester.hitTest(
          holePoint(1, 4).translate(config.gridCellStep / 2, 0),
          config,
          preciseColumns: true,
        ),
        isNull,
      );
      // Past line a, out over the row numbers.
      expect(
        BreadboardHitTester.hitTest(
          holePoint(0, 4).translate(0, -config.gridCellStep),
          config,
          preciseColumns: true,
        ),
        isNull,
      );
    });

    test('the netlist still reads the whole row as one node', () {
      // Precision is for pointers only. A leg sitting between two columns is
      // still plugged into that row — which is what `getPortAt` is asked by
      // the netlist, and what the bundled templates rely on.
      expect(BreadboardHitTester.hitTest(betweenColumns, config)?.rowIndex, 4);
      expect(painter.getPortAt(betweenColumns), isNotNull);
    });

    test('a wire in flight can still land anywhere along the row', () {
      // Landing a wire stays forgiving: the caller passes preciseColumns only
      // while idle.
      expect(painter.getPortAt(betweenColumns, hitRadius: 18), isNotNull);
    });
  });
}
