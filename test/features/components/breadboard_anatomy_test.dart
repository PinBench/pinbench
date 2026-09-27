// Package imports:
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:pinbench_parts/part_registry.dart';
import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/wire_model.dart';
import 'package:pinbench_parts/painting/grid_system.dart';
import 'package:pinbench_parts/painting/physical_scale.dart';
import 'package:pinbench_parts/painters/breadboard_painter/breadboard_painter.dart';
import 'package:pinbench_parts/painters/breadboard_painter/configs/breadboard_config.dart';
import 'package:pinbench_parts/painters/breadboard_painter/configs/power_rail_config.dart';
import 'package:pinbench_parts/painters/push_button_painter.dart';
import 'package:pinbench_sim/core/circuit_netlist.dart';
import 'package:pinbench_parts/models/port_model.dart';
import 'package:pinbench_parts/models/part_model.dart';

/// The board's three connection rules:
///  * a power rail connects down its whole length,
///  * a terminal strip connects a row of five across,
///  * the centre notch stops a row carrying from one strip to the other.
///
/// They belong to the board rather than to any one circuit, so they're checked
/// here against nothing but a bare board with probes touched to its holes.
void main() {
  final config = BreadboardConfig.full();
  final painter = BreadboardPainter(config: config);
  final rail = PowerRailConfig(config);

  final board = ComponentInstance(
    position: Offset.zero,
    part: standardParts.firstWhere((c) => c.name == PartNames.breadboardFull),
  );

  /// Are the two holes on the same net once the board's own strips are
  /// resolved? Each hole is touched by its own probe wire — the wires never
  /// touch each other, so any connection found is the board's doing.
  bool connected(String holeA, String holeB) {
    PortLocation probe(String hole) => PortLocation(nodeKey: ValueKey(hole), portId: 'probe');
    PortLocation hole(String id) => PortLocation(nodeKey: board.key, portId: id);

    final netlist = CircuitNetlist()
      ..buildStatic(
        [board],
        [
          WireModel(start: probe(holeA), end: hole(holeA)),
          WireModel(start: probe(holeB), end: hole(holeB)),
        ],
      );

    return netlist.findConnectedPorts(hole(holeA)).contains(hole(holeB));
  }

  group('power rails connect for the full length of the board', () {
    test('two holes in different blocks of five are one net', () {
      final rows = rail.holeRows.toList();
      expect(connected('rail_left_plus_${rows.first}', 'rail_left_plus_${rows.last}'), isTrue);
    });

    test('the two polarities stay apart', () {
      final row = rail.firstHoleRow;
      expect(connected('rail_left_plus_$row', 'rail_left_minus_$row'), isFalse);
    });

    test('so do the rails on opposite edges', () {
      final row = rail.firstHoleRow;
      expect(connected('rail_left_plus_$row', 'rail_right_plus_$row'), isFalse);
    });
  });

  group('terminal strips connect a row of five across', () {
    test('a and e of the same row are one net', () {
      expect(connected('sig_left_a_7', 'sig_left_e_7'), isTrue);
    });

    test('neighbouring rows are not', () {
      expect(connected('sig_left_a_7', 'sig_left_a_8'), isFalse);
    });

    test('the centre notch splits the row: a–e never reaches f–j', () {
      expect(connected('sig_left_e_7', 'sig_right_f_7'), isFalse);
    });
  });

  group('the centre notch', () {
    test('sits between line e and line f', () {
      expect(config.centerNotchCenterY, greaterThan(config.topTerminalStripEndY));
      expect(config.centerNotchCenterY, lessThan(config.bottomTerminalStripY));
    });

    test('holds no holes — aiming at it finds nothing to plug into', () {
      final middleRowX = config.rowX(config.rowsCount ~/ 2);
      expect(painter.getPortAt(Offset(middleRowX, config.centerNotchCenterY)), isNull);
    });

    test('is 0.3" across, so a part that straddles it lands in e and f', () {
      final eToF = config.bottomTerminalStripY - config.topTerminalStripEndY;
      expect(PhysicalScale.toMm(eToF), closeTo(7.62, 0.001));

      // The thing that has to fit: a tactile switch's legs are 0.3" apart, so
      // a button dropped across the notch must reach e and f exactly. Any
      // narrower and its far legs overshoot into g.
      const legSpan = PushButtonPainter.height - GridSystem.cellCenter * 2;
      expect(legSpan, eToF);
    });
  });
}
