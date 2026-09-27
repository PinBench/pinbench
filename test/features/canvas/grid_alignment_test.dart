import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench_parts/part_registry.dart';
import 'package:pinbench/features/canvas/managers/breadboard_snap_helper.dart';
import 'package:pinbench/features/canvas/managers/snap_guide_helper.dart';
import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/painting/grid_system.dart';
import 'package:pinbench_parts/painters/breadboard_painter/configs/breadboard_config.dart';
import 'package:pinbench_parts/painters/breadboard_painter/configs/power_rail_config.dart';
import 'package:pinbench_parts/painting/port_provider.dart';
import 'package:pinbench_parts/models/part_model.dart';

/// The one invariant the whole wiring system leans on: every connection point
/// (component port, breadboard hole) sits on the shared connection lattice —
/// ≡ cellCenter mod pitch in both axes of the part's own geometry. Node
/// positions snap in cell (half-pitch) steps, so any two grid-snapped parts
/// agree on the finer ≡ cellCenter mod cellSize sub-lattice — which is what
/// makes wires between them come out straight — and the board itself seats
/// legs into real holes on drop/drag (BreadboardSnapHelper). These tests pin
/// that invariant for every built-in component and the breadboard geometry,
/// so a future painter tweak can't silently knock a leg off grid.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  bool onHalfGrid(double v) => ((v % GridSystem.pitch) - GridSystem.cellCenter).abs() < 0.001;

  // Where a *snapped node's* legs may sit: positions snap in [snapStep] (one
  // cell) increments, so legs land on the finer ≡ cellCenter mod cellSize
  // sub-lattice. Any two snapped parts still agree on it, which is what keeps
  // wires between them straight; seating a leg in an actual breadboard hole
  // is BreadboardSnapHelper's job, not the grid's.
  bool onSnapLattice(double v) => ((v % GridSystem.cellSize) - GridSystem.cellCenter).abs() < 0.001;

  test('every built-in component port sits on half-grid centers (both axes)', () {
    final skipped = <String>[PartNames.breadboardHalf, PartNames.breadboardFull];
    for (final model in standardParts) {
      if (skipped.contains(model.name)) continue; // holes checked via config below
      final painter = model.getPainter();
      expect(painter, isA<PortProvider>(), reason: '${model.name} should expose ports');
      for (final port in (painter! as PortProvider).getPorts()) {
        expect(
          onHalfGrid(port.localOffset.dx),
          isTrue,
          reason:
              '${model.name}.${port.id} x=${port.localOffset.dx} is off the connection '
              'lattice (must be ≡${GridSystem.cellCenter} mod ${GridSystem.pitch})',
        );
        expect(
          onHalfGrid(port.localOffset.dy),
          isTrue,
          reason:
              '${model.name}.${port.id} y=${port.localOffset.dy} is off the connection '
              'lattice (must be ≡${GridSystem.cellCenter} mod ${GridSystem.pitch})',
        );
      }
    }
  });

  test('breadboard hole anchors sit on half-grid centers', () {
    for (final config in [BreadboardConfig.half(), BreadboardConfig.full()]) {
      // Every hole is an anchor + k * gridCellStep on each axis (rows from
      // firstRowX, bands from topPowerRailY / topTerminalStripY /
      // bottomTerminalStripY), and gridCellStep is a whole number of cells —
      // so each anchor being on a half-grid center puts every hole on one.
      expect(
        onHalfGrid(config.topPowerRailY),
        isTrue,
        reason: 'topPowerRailY=${config.topPowerRailY}',
      );
      expect(config.gridCellStep % GridSystem.pitch, 0);
      expect(onHalfGrid(config.firstRowX), isTrue, reason: 'firstRowX=${config.firstRowX}');
      expect(
        onHalfGrid(config.topTerminalStripY),
        isTrue,
        reason: 'topTerminalStripY=${config.topTerminalStripY}',
      );
      expect(
        onHalfGrid(config.bottomTerminalStripY),
        isTrue,
        reason: 'bottomTerminalStripY=${config.bottomTerminalStripY}',
      );
      expect(
        onHalfGrid(config.bottomPowerRailY),
        isTrue,
        reason: 'bottomPowerRailY=${config.bottomPowerRailY}',
      );

      // The rail's own hole lines, which is the one place this used to be
      // wrong: the holes sat half a pitch off their rail's origin, so no
      // grid-snapped part could ever land a leg in a rail hole.
      final rail = PowerRailConfig(config);
      for (final base in [config.topPowerRailY, config.bottomPowerRailY]) {
        for (final line in [rail.plusHoleOffset, rail.minusHoleOffset]) {
          expect(
            onHalfGrid(base + line),
            isTrue,
            reason: 'rail hole line at ${base + line} is off the lattice',
          );
        }
      }
    }
  });

  test('a quarter-turned part still has every leg on the lattice', () {
    // Rotation moves the legs relative to the bounding box by an amount that
    // depends on the part's own width and height, so snapping the box (which
    // is what the grid used to do) puts them somewhere arbitrary. Snapping a
    // *port* fixes that for the whole part at once: at a multiple of 90° the
    // vector between any two ports is still a whole number of pitches, so
    // landing one leg lands them all.
    for (final model in standardParts) {
      final node = ComponentInstance(position: Offset.zero, part: model);
      if (node.ports.isEmpty) continue; // breadboards discover holes dynamically

      for (final quarters in [1, 2, 3]) {
        final rotated = node.copyWith(rotationAngle: quarters * math.pi / 2);
        final placed = rotated.copyWith(
          position: SnapGuideHelper.snapNodeToLattice(rotated, const Offset(160, 96)),
        );

        for (final port in placed.ports) {
          final absolute = placed.position + placed.getPortOffset(port.id)!;
          expect(
            onSnapLattice(absolute.dx),
            isTrue,
            reason: '${model.name}.${port.id} x=${absolute.dx} at ${quarters * 90}°',
          );
          expect(
            onSnapLattice(absolute.dy),
            isTrue,
            reason: '${model.name}.${port.id} y=${absolute.dy} at ${quarters * 90}°',
          );
        }
      }
    }
  });

  test('a rotated part plugs into real breadboard holes', () {
    final config = BreadboardConfig.half();
    final board = ComponentInstance(
      position: const Offset(320, 160),
      part: standardParts.firstWhere((m) => m.name == PartNames.breadboardHalf),
    );
    final led = ComponentInstance(
      position: Offset.zero,
      part: standardParts.firstWhere((m) => m.name == PartNames.led),
    ).copyWith(rotationAngle: math.pi / 2);

    // Dropped anywhere over the strip, its legs end up in holes — not a hair
    // off them, exactly in them. Mirror the real drop path (see
    // `canvas_area.dart`): grid snap first, then the board's own holes decide
    // — the grid now stops at every cell, so on its own it can rest a part
    // half a pitch off the hole lattice.
    final hole = board.position + Offset(config.firstRowX, config.topTerminalStripY);
    final dropAt = hole + const Offset(37, 21);
    var position = SnapGuideHelper.snapNodeToLattice(led, dropAt);
    final toHole = BreadboardSnapHelper.holeAdjustment(
      node: led.copyWith(position: position),
      position: dropAt,
      boards: [board],
    );
    if (toHole != null) position = dropAt + toHole;
    final placed = led.copyWith(position: position);

    final boardPainter = board.part.getPainter()! as PortProvider;
    for (final port in placed.ports) {
      final absolute = placed.position + placed.getPortOffset(port.id)!;
      final local = board.absoluteToLocal(absolute);
      final landed = boardPainter.getPortAt(local);
      expect(landed, isNotNull, reason: '${port.id} landed on no hole');
      final reason = '${port.id} is near hole ${landed!.id} rather than in it';
      expect(landed.localOffset.dx, closeTo(local.dx, 1e-9), reason: reason);
      expect(landed.localOffset.dy, closeTo(local.dy, 1e-9), reason: reason);
    }
  });

  test('rail rows follow the rail, which need not follow the lattice', () {
    // The one deliberate exception to the invariant this file pins. A rail's
    // blocks of five are centred along the board; when the leftover rows are
    // odd that centring is half a pitch, so the rail's rows sit between the
    // terminal strips', exactly like the real part. Parts still land in these
    // holes because snapping asks the board where they are — see
    // breadboard_hole_snap_test.dart.
    //
    // Both boards stagger now. The full board used to centre on whole rows,
    // but that was a property of its old 63 rows; at 64 the leftover is odd,
    // which is the price of the numbering running a full 1…60 with two spare
    // rows at each end.
    for (final config in [BreadboardConfig.half(), BreadboardConfig.full()]) {
      expect(
        PowerRailConfig(config).rowOffset,
        (config.rowsCount % PowerRailConfig.rowsPerGroup).isEven ? GridSystem.pitch / 2 : 0,
        reason: 'rail centring must follow the leftover row parity',
      );
    }

    for (final config in [BreadboardConfig.half(), BreadboardConfig.full()]) {
      final rail = PowerRailConfig(config);
      // Whatever the stagger, the rows stay a whole pitch apart, so a part
      // that fits one rail hole fits them all.
      for (final row in rail.holeRows) {
        expect((rail.holeX(row) - rail.holeX(rail.firstHoleRow)) % GridSystem.pitch, 0);
      }
      // ...and the blocks are centred: the same margin at both ends.
      final startMargin = rail.holeX(rail.firstHoleRow) - config.firstRowX;
      final endMargin = config.lastRowX - rail.holeX(rail.lastHoleRow);
      expect(
        startMargin,
        closeTo(endMargin, 1e-9),
        reason: 'rail blocks are off-centre by ${startMargin - endMargin} px',
      );

      // Rails are drilled in blocks of five, so one lattice row in six is
      // blank — the snap has to move those to a real hole.
      for (var row = 0; row < config.rowsCount; row++) {
        expect(
          rail.hasHoleAtRow(rail.nearestHoleRowTo(row.toDouble())),
          isTrue,
          reason: 'row $row snapped to a blank',
        );
      }
      // Ties break toward the block the leg is actually nearer.
      final blank = rail.firstHoleRow + PowerRailConfig.holesPerGroup;
      if (rail.groupCount > 1) {
        expect(rail.nearestHoleRowTo(blank - 0.3), blank - 1);
        expect(rail.nearestHoleRowTo(blank + 0.3), blank + 1);
      }
    }
  });
}
