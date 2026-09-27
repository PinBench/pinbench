import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Light, dark, or follow the platform.
///
/// The app's own enum rather than Material's `ThemeMode`. It is the same three
/// cases, but taking it from the Material library would put that design
/// system in the import list of every file that reads the setting —
/// the title bar, the shortcut handler, the telemetry listener — which is the
/// opposite of what `ui_library_boundary_test` is for, and what Flutter 3.47
/// finished separating when it moved Material out of the SDK.
enum AppThemeMode {
  system,
  light,
  dark;

  /// Resolves against the platform's setting, which is the only thing
  /// [AppThemeMode.system] can mean.
  Brightness resolve(Brightness platform) => switch (this) {
    AppThemeMode.system => platform,
    AppThemeMode.light => Brightness.light,
    AppThemeMode.dark => Brightness.dark,
  };
}

/// The user's chosen theme mode.
///
/// Hand-written rather than `@Riverpod(keepAlive: true)`: it is the only
/// provider in this package, and generating it would mean a `build_runner`
/// step here that CI's per-package loop does not run. A plain
/// `NotifierProvider` is keep-alive already.
final themeModeProvider = NotifierProvider<ThemeModeNotifier, AppThemeMode>(ThemeModeNotifier.new);

class ThemeModeNotifier extends Notifier<AppThemeMode> {
  @override
  AppThemeMode build() => AppThemeMode.system;

  void setMode(AppThemeMode mode) => state = mode;

  void toggle() {
    if (state == AppThemeMode.light) {
      state = AppThemeMode.dark;
    } else if (state == AppThemeMode.dark) {
      state = AppThemeMode.light;
    } else {
      // If system, force toggle based on some default, or maybe just set to dark
      state = AppThemeMode.dark;
    }
  }
}

/// The brand teal. This is the identity color — it appears in the logo and in
/// marketing — but it is deliberately *not* used as an interactive fill:
/// white text on it lands at 3.6:1, short of WCAG AA. The per-brightness
/// [AppPalette.lightPrimary] and [AppPalette.darkPrimary] values below are the
/// ones the UI actually paints, each tuned to clear 4.5:1 against its own
/// foreground.
const primary = Color(0xFF009696);

/// The resolved color values for one brightness.
///
/// Every foreground/background pair here has been checked against WCAG AA
/// (4.5:1 for body text, 3:1 for large text and non-text boundaries). If you
/// change a value, re-check its partner — several of these pairs were below
/// AA before this scale was introduced, most severely the light-mode accent
/// pair at 1.85:1, which made active toolbar buttons and shortcut badges
/// almost unreadable.
///
/// Note the semantics, which an earlier version of this scale had inverted:
/// `muted` is a *surface* and `mutedForeground` is the secondary *text* on it.
/// Never use `muted` as a text color.
abstract final class AppPalette {
  // ---- Light -------------------------------------------------------------

  /// Window gutter — the recessed ground the floating panes sit on.
  static const lightBackground = Color(0xFFF5F7F7);

  /// Raised pane/card surface. Lighter than the gutter so the pane shadow and
  /// the pane color agree that the pane is *above* the ground.
  static const lightCard = Color(0xFFFFFFFF);
  static const lightForeground = Color(0xFF0E1717);

  /// Interactive teal fill. 4.84:1 with white.
  static const lightPrimary = Color(0xFF007F7F);

  /// Hover/active wash. Its foreground reaches 6.20:1 — up from 1.85:1.
  static const lightAccent = Color(0xFFDCEDEC);
  static const lightAccentForeground = Color(0xFF005F5F);

  static const lightSecondary = Color(0xFFE4EAEA);
  static const lightSecondaryForeground = Color(0xFF1B2B2B);

  /// A surface, not a text color.
  static const lightMuted = Color(0xFFECEFEF);

  /// Secondary text. 5.57:1 on card.
  static const lightMutedForeground = Color(0xFF5C6B6B);

  static const lightDestructive = Color(0xFFC62828);

  // ---- Dark --------------------------------------------------------------

  static const darkBackground = Color(0xFF121616);
  static const darkCard = Color(0xFF181D1D);
  static const darkForeground = Color(0xFFE8EDED);

  /// Brighter than the brand teal so it carries on a dark ground: 6.03:1 as
  /// text on the gutter, and 5.62:1 against [darkPrimaryForeground] as a fill.
  static const darkPrimary = Color(0xFF12A5A5);

  /// Dark text on the bright teal fill — white would only reach 3.02:1.
  static const darkPrimaryForeground = Color(0xFF08201F);

  static const darkAccent = Color(0xFF1B2E2E);
  static const darkAccentForeground = Color(0xFF7FD9D9);

  static const darkSecondary = Color(0xFF1F2727);
  static const darkSecondaryForeground = Color(0xFFDDE4E4);

  static const darkMuted = Color(0xFF1F2626);
  static const darkMutedForeground = Color(0xFF93A2A2);

  static const darkDestructive = Color(0xFFF87171);
  static const darkDestructiveForeground = Color(0xFF1A0A0A);

  // ---- Shared ------------------------------------------------------------

  static const transparent = Color(0x00000000);
  static const black = Color(0xFF000000);
  static const white = Color(0xFFFFFFFF);
  static const black12 = Color(0x1F000000);
  static const black50 = Color(0x80000000);
  static const white50 = Color(0x80FFFFFF);
  static const white70 = Color(0xB3FFFFFF);

  // ---- Raw hues ----------------------------------------------------------

  /// Fixed hues that are *not* theme colours: LED and wire colours a user
  /// picks by name, the fixed inks in the canvas painters, the severity dots
  /// in the problems list. They do not move with light/dark, because the thing
  /// they name — a red LED, a black jumper wire — does not either.
  ///
  /// The values are Material's palette primaries, carried over verbatim when
  /// Flutter 3.47 moved that library out of the SDK. Copied rather than
  /// re-derived on purpose: every one of these was already on screen and in a
  /// saved `.cdl` file, so a "nicer" red here would silently repaint every
  /// circuit anyone has saved. Only add to this list; do not retune it.
  static const red = Color(0xFFF44336);
  static const redAccent = Color(0xFFFF5252);
  static const pink = Color(0xFFE91E63);
  static const purple = Color(0xFF9C27B0);
  static const indigo = Color(0xFF3F51B5);
  static const blue = Color(0xFF2196F3);
  static const blueAccent = Color(0xFF448AFF);
  static const cyan = Color(0xFF00BCD4);
  static const teal = Color(0xFF009688);
  static const green = Color(0xFF4CAF50);
  static const lime = Color(0xFFCDDC39);
  static const yellow = Color(0xFFFFEB3B);
  static const amber = Color(0xFFFFC107);
  static const orange = Color(0xFFFF9800);
  static const deepOrange = Color(0xFFFF5722);
  static const brown = Color(0xFF795548);
  static const grey = Color(0xFF9E9E9E);
  static const grey400 = Color(0xFFBDBDBD);
  static const grey800 = Color(0xFF424242);
  static const grey900 = Color(0xFF212121);
}
