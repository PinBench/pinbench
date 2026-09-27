import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../ui/app_select.dart';
import '../theme/tokens.dart';
import '../theme/theme.dart';

const colorWheel = [
  AppPalette.red,
  AppPalette.pink,
  AppPalette.purple,
  AppPalette.indigo,
  AppPalette.blue,
  AppPalette.cyan,
  AppPalette.teal,
  AppPalette.green,
  AppPalette.lime,
  AppPalette.yellow,
  AppPalette.amber,
  AppPalette.orange,
];

const colorsList = [
  ...colorWheel,
  AppPalette.brown,
  AppPalette.grey,
  AppPalette.black,
  AppPalette.white,
];

class ColorSelect extends StatelessWidget {
  static final Map<String, Color?> colorsMap = {
    'Auto': null,
    'Red': colorsList[0],
    'Pink': colorsList[1],
    'Purple': colorsList[2],
    'Indigo': colorsList[3],
    'Blue': colorsList[4],
    'Cyan': colorsList[5],
    'Teal': colorsList[6],
    'Green': colorsList[7],
    'Lime': colorsList[8],
    'Yellow': colorsList[9],
    'Amber': colorsList[10],
    'Orange': colorsList[11],
    'Brown': colorsList[12],
    'Grey': colorsList[13],
    'Black': colorsList[14],
    'White': colorsList[15],
  };

  /// Room for a swatch, the longest colour name, and the tick the selected row
  /// carries — checked on screen, at the app's own font. Widget tests render
  /// with a fallback font whose glyphs are far wider, so a width that looks
  /// tight under test can be comfortable in the app; `app_select_test.dart`
  /// asserts the list is wider than its control rather than measuring glyphs.
  static const _menuWidth = 120.0;

  /// The closed control's height. Shorter than a form field's, because this is
  /// not one: it sits in a toolbar and in the properties panel's rows, beside
  /// controls of this height.
  static const _controlHeight = 28.0;

  final String value;
  final ValueChanged<String?> onChanged;
  final bool openUpwards;
  final bool excludeAuto;
  final double? maxHeight;
  final Map<String, Color?>? customColorsMap;

  /// Width of the open list, or null to take the closed control's width — which
  /// is too narrow wherever this sits in a toolbar. Defaults to [_menuWidth].
  final double? menuWidth;

  const ColorSelect({
    super.key,
    required this.value,
    required this.onChanged,
    this.customColorsMap,
    this.openUpwards = false,
    this.excludeAuto = false,
    this.maxHeight = 250.0,
    this.menuWidth = _menuWidth,
  });

  @override
  Widget build(BuildContext context) {
    final colorsMap = customColorsMap ?? ColorSelect.colorsMap;
    final entries = colorsMap.entries.where((e) => !excludeAuto || e.key != 'Auto').toList();
    final selectedValue = entries.any((e) => e.key == value) ? value : entries.first.key;

    return AppSelect<String>.rich(
      value: selectedValue,
      onChanged: onChanged,
      openUpwards: openUpwards,
      maxHeight: maxHeight,
      // This sits in the canvas toolbar, which is a bordered pill already — a
      // box around the swatch draws a second frame inside the first.
      bordered: false,
      height: _controlHeight,
      // Wide enough for the longest colour name plus its swatch and the tick
      // the selected row carries. Left to the closed control's width, the list
      // inherits how narrow a toolbar item is: names came out as "Pur…", and
      // the selected one — squeezed by the tick as well — vanished entirely,
      // which is why the current colour showed as a swatch and no word.
      menuWidth: menuWidth,
      options: {for (final entry in entries) entry.key: entry.key},
      // The closed control renders the chosen entry as text, so the swatch for
      // it rides along as a prefix rather than coming from the item widget.
      prefix: Padding(
        padding: const EdgeInsets.only(right: AppSpacing.md),
        child: _buildColorCircle(selectedValue, colorsMap[selectedValue]),
      ),
      // The ellipsis stays as a backstop for a custom map with a longer name
      // in it, but at [_menuWidth] none of the built-in names reach it.
      itemBuilder: (label, _) => Row(
        mainAxisSize: MainAxisSize.min,
        spacing: AppSpacing.md,
        children: [
          _buildColorCircle(label, colorsMap[label]),
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis, softWrap: false)),
        ],
      ),
    );
  }

  Widget _buildColorCircle(String colorName, Color? color) {
    if (colorName == 'Auto') {
      return Container(
        width: 16,
        height: 16,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: SweepGradient(colors: colorWheel, transform: GradientRotation(-math.pi / 2)),
        ),
      );
    }
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(color: AppPalette.black12, width: 0.5),
      ),
    );
  }
}
