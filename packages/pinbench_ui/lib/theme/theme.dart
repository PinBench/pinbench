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
enum AppThemeMode() {
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

/// The brand kit v1 palette (solder mask, copper and silkscreen), exactly as
/// the brand guide lists it — `handbook/brand/README.md`.
///
/// These are identity colours, not UI tokens: the logo, the app icon and
/// marketing use them verbatim. The UI paints the per-brightness values in
/// [AppPalette], which are derived from them and tuned for WCAG AA. Nothing
/// here moves with light/dark.
abstract final class BrandPalette {
  /// PCB teal — carries the brand. White on it is 4.32:1 and board ink
  /// 3.05:1, so neither is body text on it: white is safe from 24 px up only.
  static const pcbTeal = Color(0xFF00878F);

  /// Board ink — dark UI, drilled holes, the dark icon.
  static const boardInk = Color(0xFF06363A);

  /// Solder gold — the pads, and the brand's only accent. 1.86:1 on white, so
  /// never text on a light ground.
  static const solderGold = Color(0xFFE0B95C);

  /// Trace cyan — connections, links on dark. 7.72:1 on [boardInk].
  static const traceCyan = Color(0xFF6FD6DB);

  /// Flux cream — light ground, print stock.
  static const fluxCream = Color(0xFFF3F1EA);

  /// Graphite — body text on light. 14.37:1 on [fluxCream].
  static const graphite = Color(0xFF142322);
}

/// The brand teal — [BrandPalette.pcbTeal]. This is the identity color — it
/// appears in the logo and in marketing — but it is deliberately *not* used as
/// an interactive fill: white text on it lands at 4.32:1, short of WCAG AA.
/// The per-brightness [AppPalette.lightPrimary] and [AppPalette.darkPrimary]
/// values below are the ones the UI actually paints, each derived from it and
/// tuned to clear 4.5:1 against its own foreground.
const primary = BrandPalette.pcbTeal;

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

  /// Interactive teal fill: PCB teal with its channels scaled to 92%, so the
  /// hue is the brand's exactly. 4.98:1 with white, and as text 4.98:1 on
  /// card, 4.63:1 on the gutter and 4.57:1 on forui's muted `#F5F5F5`.
  static const lightPrimary = Color(0xFF007C84);

  /// Hover/active wash: 13% PCB teal over white. Its foreground is board ink,
  /// at 11.09:1 (13.15:1 on card) — up from 1.85:1 before this scale.
  static const lightAccent = Color(0xFFDEEFF0);
  static const lightAccentForeground = BrandPalette.boardInk;

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

  /// PCB teal mixed halfway to trace cyan, so it carries on a dark ground:
  /// as text 6.85:1 on the gutter and 6.40:1 on card (7.44:1 / 6.74:1 /
  /// 5.69:1 on forui's `#0A0A0A` background, `#171717` card and `#262626`
  /// muted), and 4.94:1 against [darkPrimaryForeground] as a fill.
  static const darkPrimary = Color(0xFF38AEB5);

  /// Board ink on the bright teal fill — white would only reach 2.66:1.
  static const darkPrimaryForeground = BrandPalette.boardInk;

  /// Board ink as the active wash, with trace cyan on it at 7.72:1.
  static const darkAccent = BrandPalette.boardInk;
  static const darkAccentForeground = BrandPalette.traceCyan;

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
