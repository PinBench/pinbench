import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench_parts/painting/grid_system.dart';
import 'package:pinbench_parts/painting/physical_scale.dart';
import 'package:pinbench_parts/painters/arduino_painter/arduino_painter.dart';
import 'package:pinbench_parts/painters/breadboard_painter/configs/breadboard_config.dart';
import 'package:pinbench_parts/painters/breadboard_painter/configs/power_rail_config.dart';
import 'package:pinbench_parts/painters/capacitor_painter.dart';
import 'package:pinbench_parts/painters/ky037_mic_sensor_painter.dart';
import 'package:pinbench_parts/painters/led_painter.dart';
import 'package:pinbench_parts/painters/piezo_buzzer_painter.dart';
import 'package:pinbench_parts/painters/potentiometer_painter.dart';
import 'package:pinbench_parts/painters/push_button_painter.dart';
import 'package:pinbench_parts/painters/resistor_painter.dart';
import 'package:pinbench_parts/painters/servo_motor_painter.dart';

/// Components are drawn at the size they really are. The canvas scale is not
/// arbitrary: connection points sit on a 16 px lattice and that lattice is a
/// breadboard's 0.1" hole pitch, so 16 px ≡ 2.54 mm — which fixes the size of
/// everything else. These tests pin the published body dimensions of each
/// built-in part, so a painter tweak can't quietly drift off scale.
///
/// Note these check the *bodies*. A part's bounds are usually larger, because
/// they also hold the leads that run out to the connection lattice.
///
/// A few parts are deliberately drawn a little under their datasheet size so
/// they read well next to each other at canvas scale; those carry the real
/// figure alongside the drawn one, so the deviation stays a decision rather
/// than a drift.
void main() {
  /// Body sizes are exact, so this only absorbs float noise.
  void expectMm(double px, double expectedMm, String what) {
    expect(
      PhysicalScale.toMm(px),
      closeTo(expectedMm, 0.05),
      reason: '$what should be $expectedMm mm, is ${PhysicalScale.toMm(px)} mm',
    );
  }

  test('the canvas scale is one breadboard hole pitch per 2.54 mm', () {
    expect(PhysicalScale.mm(PhysicalScale.holePitchMm), closeTo(GridSystem.pitch, 1e-9));
    expect(PhysicalScale.toMm(GridSystem.pitch), closeTo(PhysicalScale.holePitchMm, 1e-9));
  });

  test('Arduino Uno R3 is 68.6 mm wide, drawn 52.07 (real 53.4) mm tall', () {
    // The height is trimmed on purpose: at the true 53.4 mm no on-lattice pair
    // of header offsets is symmetric, so the bottom header would sit ~1.3 mm
    // further from its edge than the top one. See ArduinoPainter.boardHeightMm.
    expectMm(ArduinoPainter.componentSize.width, 68.6, 'Uno width');
    expectMm(ArduinoPainter.componentSize.height, 52.07, 'Uno height');
  });

  test('the Uno headers are inset equally from the top and bottom edges', () {
    // Whether this can hold at all depends on the board height: two on-lattice
    // offsets (each ≡2 mod 8) sum to ≡4 mod 8, so the internal height must be
    // ≡4 mod 8 for a symmetric pair to exist. It has been broken twice by
    // nudging a header's y to line the art up — see ArduinoPainter's pin
    // offsets. Change the height and the offsets together, or not at all.
    final height = ArduinoPainter.internalSize.height;
    final topPad = ArduinoPainter.digitalHighPinsOffset.dy;
    final bottomPad = height - ArduinoPainter.powerPinsOffset.dy;

    expect(ArduinoPainter.digitalLowPinsOffset.dy, topPad, reason: 'top header is one row');
    expect(
      ArduinoPainter.analogPinsOffset.dy,
      ArduinoPainter.powerPinsOffset.dy,
      reason: 'bottom header is one row',
    );
    expect(bottomPad, closeTo(topPad, 0.05), reason: 'headers inset unequally');
    expect(height % 8, closeTo(4, 1e-9), reason: 'no symmetric on-lattice pair exists');
  });

  test('the Uno header pitch stays exactly one hole pitch', () {
    // The board is drawn in internal units and scaled up; the pins have to
    // come out of that on the same lattice as every breadboard hole.
    final scale = ArduinoPainter.componentSize.width / ArduinoPainter.internalSize.width;
    expect(ArduinoPainter.pinPitch * scale, GridSystem.pitch);
  });

  test('breadboards are drawn 54.61 (real 55) mm across, evenly padded all round', () {
    final half = BreadboardConfig.half();
    final full = BreadboardConfig.full();

    // Derived from the band stack, not pinned, so it comes out just under the
    // real 55 mm — the price of an equal margin at the top and bottom edges.
    expectMm(half.boardBreadth, 54.61, 'half breadboard width');
    expectMm(full.boardBreadth, 54.61, 'full breadboard width');

    // Length is derived from the padding, not set: hole rows have to land on
    // the connection lattice, so the padding is a whole number of hole
    // pitches and the board comes out near (not exactly) the real 82/165 mm.
    // The full board also carries one row more than the real part — see below.
    expectMm(half.boardLength, 85.1, 'half breadboard length');
    expectMm(full.boardLength, 171.45, 'full breadboard length');
    for (final config in [half, full]) {
      expect(
        config.boardLength - config.lastRowX,
        closeTo(config.firstRowX, 0.001),
        reason: 'padding before the first row must equal padding after the last',
      );
    }

    // Across the rows too: the top rail's ink must sit as far inside the top
    // edge as the bottom rail's does inside the bottom edge. This was the
    // lopsided one — boardBreadth was pinned to the real 55 mm while the bands
    // inside it were derived, so the whole mismatch fell on the bottom edge.
    for (final config in [half, full]) {
      final rail = PowerRailConfig(config);
      final topInk = config.topPowerRailY + rail.plusLineOffset;
      final bottomInk = config.bottomPowerRailY + rail.minusLineOffset;
      expect(
        config.boardBreadth - bottomInk,
        closeTo(topInk, 0.001),
        reason: 'rail ink must be inset equally from the top and bottom edges',
      );
    }

    // Row counts are what make those lengths right. The full board carries 64
    // rows, not the real part's 63: the printed numbering runs 1…60 with two
    // unnumbered rows spare at each end (BreadboardConfig.unnumberedEndRows),
    // which needs 64 to come out even.
    expect(half.rowsCount, 30);
    expect(full.rowsCount, 64);
    for (final config in [half, full]) {
      expect(
        config.lastRowX + config.gridCellStep,
        lessThan(config.boardLength),
        reason: 'every hole row must fit inside the real board outline',
      );
    }
  });

  test('5 mm LED lens is Ø5 mm, body drawn at 6.5 (real 8.7) mm', () {
    expectMm(LEDPainter.bodyWidth, 5.0, 'LED lens');
    expectMm(LEDPainter.bodyHeight, 6.5, 'LED body height');
  });

  test('resistor body is 6.3 mm long, drawn 1.6 (real ¼ W 2.3) mm thick', () {
    expectMm(ResistorPainter.bodyWidth, 6.3, 'resistor body length');
    expectMm(ResistorPainter.bodyHeight, 1.6, 'resistor body diameter');
  });

  test('tactile push button is 6 × 6 mm', () {
    expectMm(PushButtonPainter.bodySize, 6.0, 'push button body');
  });

  test('ceramic disc capacitor is Ø7 mm', () {
    expectMm(CapacitorPainter.bodyDiameter, 7.0, 'capacitor disc');
  });

  test('piezo buzzer is Ø15 mm', () {
    expectMm(PiezoBuzzerPainter.bodyDiameter, 15.0, 'buzzer can');
  });

  test('potentiometer is drawn 13 × 14 (real WH148 16 × 17) mm', () {
    expectMm(PotentiometerPainter.bodyWidth, 13.0, 'pot body width');
    expectMm(PotentiometerPainter.bodyHeight, 14.0, 'pot body height');
  });

  // Drawn face-on, so the visible face is the case's narrow 12.2 mm side —
  // not the 22.8 mm one. Both axes sit a little under the real face so the
  // cross horn reads as overhanging.
  test('SG90 servo is drawn 12 × 24 (real face 12.2 × 28.5) mm', () {
    expectMm(ServoMotorPainter.bodyWidth, 12.0, 'servo case width');
    expectMm(ServoMotorPainter.bodyHeight, 24.0, 'servo case height');
  });

  test('KY-037 module is 15 mm wide, drawn 34 (real 36) mm long', () {
    expectMm(Ky037MicSensorPainter.pcbHeight, 34.0, 'KY-037 length');
    expectMm(Ky037MicSensorPainter.pcbWidth, 15.0, 'KY-037 width');
  });

  test('every part body fits inside the bounds that hold its leads', () {
    expect(LEDPainter.bodyWidth, lessThanOrEqualTo(LEDPainter.width));
    expect(LEDPainter.bodyHeight, lessThan(LEDPainter.height));
    expect(ResistorPainter.bodyWidth, lessThan(ResistorPainter.width));
    expect(ResistorPainter.bodyHeight, lessThan(ResistorPainter.height));
    expect(PushButtonPainter.bodySize, lessThanOrEqualTo(PushButtonPainter.width));
    expect(CapacitorPainter.bodyDiameter, lessThan(CapacitorPainter.width));
    expect(PiezoBuzzerPainter.bodyDiameter, lessThan(PiezoBuzzerPainter.width));
    expect(PotentiometerPainter.bodyWidth, lessThan(PotentiometerPainter.width));
    expect(PotentiometerPainter.bodyHeight, lessThan(PotentiometerPainter.height));
    expect(ServoMotorPainter.bodyWidth, lessThan(ServoMotorPainter.width));
    expect(Ky037MicSensorPainter.pcbHeight, lessThan(Ky037MicSensorPainter.height));
  });
}
