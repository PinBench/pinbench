import 'package:flutter/painting.dart';

/// Text drawn *inside* a part's artwork — a sensor's readout, a printed value
/// — as opposed to app chrome.
///
/// Deliberately separate from `AppTextStyles`, for two reasons. Painters are
/// exempt from the theme tokens: a part is drawn as the real
/// object looks, not as the app's palette says, so a silkscreen label does not
/// follow light/dark mode. And keeping it here is what stops one hardcoded
/// style from dragging the whole theme graph — `app_colors`, `forui_theme`,
/// `theme.dart` — into every part painter that draws a word.
abstract final class PainterTextStyles {
  /// Small bold readout drawn directly on a part's canvas.
  static const readout = TextStyle(
    color: Color(0xFFFFFFFF),
    fontSize: 10,
    fontWeight: FontWeight.bold,
  );
}
