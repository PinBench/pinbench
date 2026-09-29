import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:pinbench_pdl/pinbench_pdl.dart' show parseResistance;

import 'painting/part_palette.dart';

class ResistorCalculator {
  static const Color black = PartPalette.black;
  static const brown = Color(0xFF8D6E63);
  static const Color red = PartPalette.red;
  static const Color orange = PartPalette.orange;
  static const Color yellow = PartPalette.yellow;
  static const Color green = PartPalette.green;
  static const Color blue = PartPalette.blue;
  static const Color violet = PartPalette.purple;
  static const Color gray = PartPalette.grey;
  static const Color white = PartPalette.white;
  static const gold = Color(0xFFFFD700);
  static const silver = Color(0xFFC0C0C0);

  static Color getColorForDigit(int digit) {
    switch (digit) {
      case 0:
        return black;
      case 1:
        return brown;
      case 2:
        return red;
      case 3:
        return orange;
      case 4:
        return yellow;
      case 5:
        return green;
      case 6:
        return blue;
      case 7:
        return violet;
      case 8:
        return gray;
      case 9:
        return white;
      default:
        return black;
    }
  }

  static Color? getColorForMultiplier(int exponent) {
    if (exponent >= 0 && exponent <= 9) {
      return getColorForDigit(exponent);
    }
    if (exponent == -1) return gold;
    if (exponent == -2) return silver;
    return null;
  }

  static Color? getColorForTolerance(double tolerance) {
    if (tolerance == 1.0) return brown;
    if (tolerance == 2.0) return red;
    if (tolerance == 0.5) return green;
    if (tolerance == 0.25) return blue;
    if (tolerance == 0.1) return violet;
    if (tolerance == 5.0) return gold;
    if (tolerance == 10.0) return silver;
    return null;
  }

  /// Ohms from `220`, `4k7`, `1M`, `10 kΩ`. The format's reading of a
  /// resistance — see `parseResistance` in `pinbench_pdl`.
  static double? parseResistanceValue(String input) => parseResistance(input);

  static int determineBandCount(double resistance, int defaultBands) {
    if (defaultBands >= 5) return 5;

    // Check if it has more than 2 significant digits
    final log10 = math.log(resistance) / math.ln10;
    final floorLog = log10.floor();

    // For 2 significant digits
    final adjust2 = floorLog - 1;
    final sigVal2 = resistance / math.pow(10, adjust2);

    // If it cannot be cleanly represented with 2 significant digits, use 5 bands
    if ((sigVal2 - sigVal2.roundToDouble()).abs() > 0.001) {
      return 5;
    }

    return 4;
  }

  static List<Color> getBandColors(double resistance, {int bandCount = 4, double tolerance = 5.0}) {
    if (resistance <= 0) return [black, black, black, gold];

    final actualBandCount = determineBandCount(resistance, bandCount);
    final sigDigitsCount = actualBandCount == 5 ? 3 : 2;

    final log10 = math.log(resistance) / math.ln10;
    final floorLog = log10.floor();
    final adjust = floorLog - (sigDigitsCount - 1);

    var mulExponent = adjust;
    final sigVal = resistance / math.pow(10, adjust);
    var sigDigits = sigVal.round();

    // Handle edge case where rounding pushes to next power of 10 (e.g. 9.99k -> 10k)
    if (sigDigits >= math.pow(10, sigDigitsCount)) {
      sigDigits = sigDigits ~/ 10;
      mulExponent++;
    }

    final bands = <Color>[];
    final digitsStr = sigDigits.toString().padLeft(sigDigitsCount, '0');

    for (var i = 0; i < sigDigitsCount; i++) {
      bands.add(getColorForDigit(int.parse(digitsStr[i])));
    }

    bands.add(getColorForMultiplier(mulExponent) ?? black);

    final tolColor = getColorForTolerance(tolerance);
    if (tolColor != null) {
      bands.add(tolColor);
    }

    return bands;
  }
}
