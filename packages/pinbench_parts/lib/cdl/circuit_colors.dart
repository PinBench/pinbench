import 'package:flutter/widgets.dart';

import '../painting/part_palette.dart';

/// Maps `.cdl` wire color names (`COLOR red`) to/from Flutter [Color]s.
/// Shared by `CircuitModelWriter` (color -> name) and `CircuitCanvasApplier`
/// (name -> color) so the color table has one source of truth.
abstract final class CircuitColors {
  static const _colorMap = {
    'red': PartPalette.red,
    'black': PartPalette.black,
    'blue': PartPalette.blue,
    'green': PartPalette.green,
    'yellow': PartPalette.yellow,
    'orange': PartPalette.orange,
    'purple': PartPalette.purple,
    'white': PartPalette.white,
    'grey': PartPalette.grey,
  };

  /// Every wire colour name the format accepts, in file order. Used to tell the
  /// AI assistant which names it may write.
  static Iterable<String> get names => _colorMap.keys;

  static String colorToName(Color color) => _colorMap.entries
      .firstWhere((e) => e.value == color, orElse: () => const MapEntry('green', PartPalette.green))
      .key;

  static Color nameToColor(String name) => _colorMap[name] ?? PartPalette.green;
}
