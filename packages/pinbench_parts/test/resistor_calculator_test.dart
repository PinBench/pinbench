import 'package:pinbench_parts/resistor_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ResistorCalculator.parseResistanceValue', () {
    test('parses a plain integer ohm value', () {
      expect(ResistorCalculator.parseResistanceValue('220'), 220.0);
    });

    test('ignores the ohm symbol and surrounding whitespace', () {
      expect(ResistorCalculator.parseResistanceValue('220 Ω'), 220.0);
      expect(ResistorCalculator.parseResistanceValue('  330  '), 330.0);
    });

    test('applies the kilo multiplier (K suffix)', () {
      expect(ResistorCalculator.parseResistanceValue('1K'), 1000.0);
      expect(ResistorCalculator.parseResistanceValue('4.7K'), 4700.0);
    });

    test('treats K as a decimal separator when no dot is present', () {
      // "4K7" => 4.7 * 1000 = 4700
      expect(ResistorCalculator.parseResistanceValue('4K7'), 4700.0);
    });

    test('applies the mega multiplier (M suffix)', () {
      expect(ResistorCalculator.parseResistanceValue('2M'), 2000000.0);
      expect(ResistorCalculator.parseResistanceValue('2.2M'), closeTo(2200000.0, 0.001));
    });

    test('treats R as a sub-ohm decimal marker (no multiplier)', () {
      expect(ResistorCalculator.parseResistanceValue('470R'), 470.0);
      expect(ResistorCalculator.parseResistanceValue('4R7'), closeTo(4.7, 0.001));
    });

    test('accepts a comma as a decimal separator', () {
      expect(ResistorCalculator.parseResistanceValue('4,7K'), 4700.0);
    });

    test('returns null for empty or non-numeric input', () {
      expect(ResistorCalculator.parseResistanceValue(''), isNull);
      expect(ResistorCalculator.parseResistanceValue('abc'), isNull);
    });
  });

  group('ResistorCalculator.getBandColors', () {
    test('returns the standard 4 bands for a 220 Ω resistor', () {
      // 220 Ω → red, red, brown (×10), plus tolerance band.
      final bands = ResistorCalculator.getBandColors(220);
      expect(bands.length, 4);
      expect(bands[0], ResistorCalculator.red);
      expect(bands[1], ResistorCalculator.red);
      expect(bands[2], ResistorCalculator.brown);
    });

    test('clamps a non-positive resistance to a safe default band set', () {
      final bands = ResistorCalculator.getBandColors(0);
      expect(bands, isNotEmpty);
    });
  });
}
