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

/// A part dropped on a breadboard has to land *in* holes, not near them, and
/// the canvas grid alone can't always finish the job: the power rails skip a
/// row between each block of five, so a leg aimed at the blank moulding has to
/// be pulled into a neighbouring block.
///
/// Rotation used to be the second case. While the board's outline was pinned
/// to the real part's millimetres it was not a whole number of hole pitches,
/// and that remainder shifted every hole once the board was turned. Both sides
/// are derived from the lattice now, so a turned board stays on it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  PartModel modelNamed(String name) => standardParts.firstWhere((m) => m.name == name);

  final config = BreadboardConfig.half();
  final rail = PowerRailConfig(config);

  ComponentInstance boardAt(Offset position, {double rotation = 0}) {
    final board = ComponentInstance(
      position: Offset.zero,
      part: modelNamed(PartNames.breadboardHalf),
    ).copyWith(rotationAngle: rotation);
    return board.copyWith(position: SnapGuideHelper.snapNodeToLattice(board, position));
  }

  ComponentInstance ledAt(Offset position, {double rotation = 0}) {
    final led = ComponentInstance(
      position: Offset.zero,
      part: modelNamed(PartNames.led),
    ).copyWith(rotationAngle: rotation);
    return led.copyWith(position: SnapGuideHelper.snapNodeToLattice(led, position));
  }

  /// Places [led] the way the canvas does for every drag and drop: the board
  /// decides if a hole is in reach of where the pointer wants it, and the
  /// canvas grid decides otherwise.
  ComponentInstance place(ComponentInstance led, ComponentInstance board) {
    final toHole = BreadboardSnapHelper.holeAdjustment(
      node: led,
      position: led.position,
      boards: [board],
    );
    return toHole == null ? led : led.copyWith(position: led.position + toHole);
  }

  /// How far each of [led]'s legs is from the nearest hole of [board], for the
  /// legs that are over the board at all.
  List<double> legErrors(ComponentInstance led, ComponentInstance board) {
    final painter = board.part.getPainter()! as PortProvider;
    final errors = <double>[];
    for (final port in led.ports) {
      final leg = led.position + led.getPortOffset(port.id)!;
      final hole = painter.getPortAt(board.absoluteToLocal(leg));
      if (hole == null) continue;
      errors.add(((board.position + board.getPortOffset(hole.id)!) - leg).distance);
    }
    return errors;
  }

  group('rotated board', () {
    for (final quarters in [0, 1, 2, 3]) {
      test('a part lands exactly in the holes of a board at ${quarters * 90}°', () {
        final board = boardAt(const Offset(320, 160), rotation: quarters * math.pi / 2);
        final hole = board.position + board.getPortOffset('sig_left_a_5')!;

        // Aimed a few pixels off, the way a hand does it.
        final led = place(ledAt(hole - ledAt(Offset.zero).getPortOffset('cathode')!), board);

        final errors = legErrors(led, board);
        expect(errors, isNotEmpty, reason: 'no leg found a hole at ${quarters * 90}°');
        for (final error in errors) {
          expect(error, closeTo(0, 1e-9), reason: 'leg sits $error px off its hole');
        }
      });
    }

    test('a half-turned board keeps its holes on the lattice', () {
      // This assertion used to run the other way. `boardBreadth` was pinned to
      // the real 55 mm — not a whole number of pitches — so at 180° every hole
      // came off the lattice by the rounding, and only BreadboardSnapHelper
      // could seat a leg. The old test guarded that shortfall and said, in so
      // many words, that a zero here would mean the geometry had changed.
      //
      // It has: deriving boardBreadth from the band stack put both outline
      // dimensions at ≡8 mod 16, and a hole at y ≡4 mod 16 therefore maps to
      // `size - y` ≡4 mod 16 when the board is turned over. The plain grid
      // snap now reaches a rotated board on its own.
      //
      // The helper is still doing work — the power rails punch their holes in
      // staggered blocks of five that no uniform lattice describes, which the
      // `power rails` group below covers.
      for (final board in [BreadboardConfig.half(), BreadboardConfig.full()]) {
        for (final side in [board.boardLength, board.boardBreadth]) {
          expect(
            side % GridSystem.pitch,
            closeTo(GridSystem.pitch / 2, 1e-9),
            reason:
                'a turned-over board only stays on the lattice if each side '
                'is a whole number of pitches plus a half',
          );
        }
      }

      final board = boardAt(const Offset(320, 160), rotation: math.pi);
      final hole = board.position + board.getPortOffset('sig_left_a_5')!;
      final led = ledAt(hole - ledAt(Offset.zero).getPortOffset('cathode')!);

      expect(
        legErrors(led, board).every((error) => error < 1e-9),
        isTrue,
        reason: 'the grid alone should reach a half-turned board',
      );
      expect(legErrors(place(led, board), board).every((error) => error < 1e-9), isTrue);
    });
  });

  group('power rails', () {
    /// Where rail [row] of the top rail is, on the canvas. Asks the rail via
    /// [PowerRailConfig.holeX] rather than using the terminal strips' row
    /// formula: on a half board the rail's blocks are staggered half a pitch
    /// so they centre along the board, exactly as a real one's are.
    Offset railHole(ComponentInstance board, int row) =>
        board.position + Offset(rail.holeX(row), config.topPowerRailY + rail.plusHoleOffset);

    /// An LED aimed at [target] and placed the way a drag places it.
    ComponentInstance ledAimedAt(ComponentInstance board, Offset target) {
      final base = ledAt(Offset.zero);
      final aimed = base.copyWith(position: target - base.getPortOffset('cathode')!);
      return place(aimed, board);
    }

    Offset legOf(ComponentInstance led) => led.position + led.getPortOffset('cathode')!;

    test('a leg aimed at the blank between two blocks lands in one of them', () {
      final board = boardAt(const Offset(320, 160));
      final blankRow = rail.firstHoleRow + PowerRailConfig.holesPerGroup;
      expect(rail.hasHoleAtRow(blankRow), isFalse);

      final leg = legOf(ledAimedAt(board, railHole(board, blankRow)));

      expect(
        leg.dy,
        anyOf(
          closeTo(railHole(board, blankRow - 1).dy, 1e-9),
          closeTo(railHole(board, blankRow + 1).dy, 1e-9),
        ),
        reason: 'ended on the moulding rather than in a neighbouring block',
      );
    });

    test('a leg aimed at a rail hole lands exactly in it, stagger and all', () {
      final board = boardAt(const Offset(320, 160));
      final target = railHole(board, rail.firstHoleRow + 1);

      final led = ledAimedAt(board, target);
      final leg = legOf(led);
      expect(leg.dx, closeTo(target.dx, 1e-9));
      expect(leg.dy, closeTo(target.dy, 1e-9));

      // And once there it stays: snapping again moves nothing.
      expect(
        BreadboardSnapHelper.holeAdjustment(node: led, position: led.position, boards: [board]),
        Offset.zero,
      );
    });
  });

  test('a part nowhere near a board hands back to the grid', () {
    final board = boardAt(const Offset(320, 160));
    final led = ledAt(const Offset(-400, -400));

    // Null, not zero: "no hole here, use the grid" is a different answer from
    // "over a hole and already in it".
    expect(
      BreadboardSnapHelper.holeAdjustment(node: led, position: led.position, boards: [board]),
      isNull,
    );
  });
}
