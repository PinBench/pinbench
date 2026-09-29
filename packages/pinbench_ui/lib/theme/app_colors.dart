import 'package:flutter/widgets.dart';

import 'package:forui/forui.dart';

import 'forui_theme.dart';
import 'theme.dart';

/// The app's colour vocabulary, named in the app's own terms.
///
/// Widgets outside `shared/theme` and `shared/widgets` read colours from here
/// rather than from the widget library's own scheme. The two are close today —
/// this mostly forwards to forui — but the point is that "close" is a fact
/// about the current library and not a promise. A library swap should mean
/// editing this file, not every file that wanted a colour.
///
/// Deliberately smaller than any library's scheme: it carries the tokens the
/// app actually paints with. Add one when a surface needs it, not in advance.
class const AppColorScheme._(final FColors _colors) {
  /// The recessed ground the floating panes sit on.
  Color get background => _colors.background;

  /// Default ink.
  Color get foreground => _colors.foreground;

  /// A raised surface — panes, cards, dialogs.
  Color get surface => _colors.card;

  /// Hairline borders and rules.
  Color get border => _colors.border;

  /// The interactive teal, and ink that sits on it.
  Color get primary => _colors.primary;
  Color get primaryForeground => _colors.primaryForeground;

  /// A quieter fill for secondary controls.
  Color get secondary => _colors.secondary;
  Color get secondaryForeground => _colors.secondaryForeground;

  /// A recessed surface. Not ink — see [mutedForeground] for that.
  Color get muted => _colors.muted;

  /// Secondary text.
  Color get mutedForeground => _colors.mutedForeground;

  /// The wash behind an active or selected control, and ink on it.
  Color get accent => _colors.app.accent;
  Color get accentForeground => _colors.app.accentForeground;

  /// Anything that removes or fails.
  Color get destructive => _colors.destructive;
  Color get destructiveForeground => _colors.destructiveForeground;

  /// The wash behind selected text — the terminal's, specifically.
  ///
  /// Spelled out here rather than forwarded: forui's scheme has no selection
  /// slot, and these are the values the app's own theme had already chosen.
  Color get selection =>
      _colors.brightness == Brightness.dark ? AppPalette.white50 : AppPalette.black50;

  /// The hover state of [color], worked out by the theme rather than by the
  /// call site guessing an opacity.
  Color hover(Color color) => _colors.hover(color);
}

/// Type scale, in the app's terms. Same reasoning as [AppColorScheme].
class const AppTypography._(final FTypography _typography) {
  TextStyle get xs => _typography.body.xs;
  TextStyle get sm => _typography.body.sm;
  TextStyle get md => _typography.body.md;
  TextStyle get lg => _typography.body.lg;

  /// The one page-title size the app uses, on the welcome screen.
  ///
  /// Spelled out rather than taken from the library's scale: forui's 36px step
  /// carries a 2.5 line height, meant for headings with air around them, and
  /// using it here would tear the welcome screen's title apart. These are the
  /// numbers the app already looked like.
  TextStyle get h1 => _typography.display.xl3.copyWith(
    fontSize: 36,
    height: 40 / 36,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.4,
  );

  /// Secondary text: small, in [AppColorScheme.mutedForeground]. Named because
  /// the app reaches for this pairing constantly and each call site guessing
  /// its own size/colour combination is how the two drift apart.
  TextStyle mutedOn(AppColorScheme colors) =>
      _typography.body.sm.copyWith(color: colors.mutedForeground);
}

extension AppThemeContext on BuildContext {
  /// The app's colours. Prefer this over any widget library's scheme.
  AppColorScheme get appColors => AppColorScheme._(theme.colors);

  /// The app's type scale.
  AppTypography get appText => AppTypography._(theme.typography);

  /// Secondary text in the current theme.
  TextStyle get appMutedText => appText.mutedOn(appColors);

  /// Whether the app is currently light or dark.
  ///
  /// Read this rather than `Theme.of(context).brightness` — the Material
  /// brightness is not the one the app resolves `themeMode` against, and
  /// reading it has broken light/dark toggling here before.
  Brightness get appBrightness => theme.colors.brightness;
}
