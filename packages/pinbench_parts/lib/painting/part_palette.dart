import 'package:flutter/painting.dart';

/// The fixed colours a component is *made of*.
///
/// Grey plastic, white silkscreen, tinned legs, a red LED lens. These are
/// properties of the part, not of the app's theme: a red LED is red in dark
/// mode too, and the breadboard is the same beige whichever way the user has
/// their editor set. Nothing here moves with brightness, and nothing here
/// should — the theme's colours live in `package:pinbench_ui`, and this package
/// deliberately does not depend on it.
///
/// The values are Material's palette, carried over verbatim when Flutter 3.47
/// moved that library out of the SDK. Copied rather than re-chosen on purpose:
/// every one of these is a pixel already on screen in a saved circuit, and the
/// painters were tuned against these exact greys. Only add to this list; do
/// not retune it.
abstract final class PartPalette {
  static const transparent = Color(0x00000000);
  static const black = Color(0xFF000000);
  static const white = Color(0xFFFFFFFF);
  static const white70 = Color(0xB3FFFFFF);

  static const grey200 = Color(0xFFEEEEEE);
  static const grey300 = Color(0xFFE0E0E0);
  static const grey400 = Color(0xFFBDBDBD);
  static const grey500 = Color(0xFF9E9E9E);
  static const grey600 = Color(0xFF757575);
  static const grey700 = Color(0xFF616161);
  static const grey800 = Color(0xFF424242);
  static const grey900 = Color(0xFF212121);

  /// Material's unshaded `grey` was the 500 step, and the painters that used
  /// it meant that one.
  static const grey = grey500;

  static const red = Color(0xFFF44336);
  static const redAccent = Color(0xFFFF5252);
  static const pink = Color(0xFFE91E63);
  static const purple = Color(0xFF9C27B0);
  static const blue = Color(0xFF2196F3);
  static const blue300 = Color(0xFF64B5F6);
  static const blueAccent = Color(0xFF448AFF);
  static const cyan = Color(0xFF00BCD4);
  static const green = Color(0xFF4CAF50);
  static const yellow = Color(0xFFFFEB3B);
  static const orange = Color(0xFFFF9800);
}
