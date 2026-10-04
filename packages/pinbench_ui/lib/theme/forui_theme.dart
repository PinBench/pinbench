/// The app's theme, as the widget library wants it.
///
/// Everything the app draws resolves against this: `AppColorScheme` and
/// `AppTypography` in `app_colors.dart` read it, and every wrapper in
/// `shared/widgets` inherits it. Nothing outside `shared/theme` and
/// `shared/widgets` should construct or name it.
///
/// The base is forui's own Neutral scheme rather than a port of `AppPalette` —
/// the point of adopting the library was its look, so its greys, type scale
/// and component shapes are left alone. Two things are the product's identity
/// and not something a library should decide, so they are overridden: the
/// teal ([primary]), and the typefaces, the brand kit's IBM Plex Sans and
/// Outfit (see [fTheme]) in place of forui's Inter.
library;

import 'package:flutter/widgets.dart';

import 'package:forui/forui.dart';

import 'theme.dart' show AppPalette, primary;

/// Tokens the app leans on that [FColors] has no slot for.
///
/// forui's scheme is a small one: there is no `accent`, `popover`, `ring`,
/// `input` or `selection`. Most of those have a natural home
/// (`popover` → `card`, hover states → [FColors.hover]), but the accent wash
/// behind anything active or selected — toolbar buttons, keyboard badges, the
/// current tab, the selected row in the explorer or the autocomplete list — is
/// a real colour the app cannot derive, so it is carried here instead of being
/// hard-coded at the call sites.
///
/// This used to ride in forui's documented extension slot, which types its
/// entries as Material's `ThemeExtension`. Flutter 3.47 moved that library out
/// of the SDK, and naming it here would have put the design library back in
/// the theme's import list to carry two colours. It is a plain value now,
/// looked up by brightness — which is all the extension slot ever did with it,
/// since both pairs are compile-time constants that never interpolate.
final class const AppColors({
  /// Wash behind an active/selected control.
  required final Color accent,

  /// Ink on [accent]. Checked against it for WCAG AA, as every pair in
  /// `AppPalette` is — see `theme.dart`.
  required final Color accentForeground,
}) {
  AppColors copyWith({Color? accent, Color? accentForeground}) => AppColors(
    accent: accent ?? this.accent,
    accentForeground: accentForeground ?? this.accentForeground,
  );
}

const _lightApp = AppColors(accent: _lightAccent, accentForeground: _lightAccentForeground);
const _darkApp = AppColors(accent: _darkAccent, accentForeground: _darkAccentForeground);

/// Reads the app's extra colours off a forui theme.
extension AppColorsX on FColors {
  AppColors get app => brightness == Brightness.dark ? _darkApp : _lightApp;
}

/// The interactive teal, per brightness.
///
/// Not the brand [primary] (PCB teal, `#00878F`) itself: white on it is
/// 4.32:1, under WCAG AA. These are the values the UI actually paints, each
/// derived from it and tuned to clear 4.5:1 against its own foreground. They
/// are read from `AppPalette`, where the measured ratios are recorded, so the
/// two cannot drift apart.
const _lightPrimary = AppPalette.lightPrimary;
const _lightPrimaryForeground = AppPalette.white;

const _lightAccent = AppPalette.lightAccent;
const _lightAccentForeground = AppPalette.lightAccentForeground;

const _darkPrimary = AppPalette.darkPrimary;
const _darkPrimaryForeground = AppPalette.darkPrimaryForeground;

const _darkAccent = AppPalette.darkAccent;
const _darkAccentForeground = AppPalette.darkAccentForeground;

FColors _colors(Brightness brightness) => brightness == Brightness.light
    ? FColors.neutralLight.copyWith(
        primary: _lightPrimary,
        primaryForeground: _lightPrimaryForeground,
      )
    : FColors.neutralDark.copyWith(
        primary: _darkPrimary,
        primaryForeground: _darkPrimaryForeground,
      );

/// The forui theme for [brightness].
///
/// `touch: false` because this is a desktop IDE — forui sizes its controls for
/// fingers by default, which would make every toolbar in the app taller.
FThemeData fTheme(Brightness brightness) {
  final colors = _colors(brightness);
  return FThemeData(
    touch: false,
    colors: colors,
    typography: FTypography(
      display: FTypeface.inherit(colors: colors, touch: false, fontFamily: _displayFont),
      body: FTypeface.inherit(colors: colors, touch: false, fontFamily: _bodyFont),
    ),
  );
}

/// The brand kit's type, bundled by this package (see its pubspec): IBM Plex
/// Sans for body and UI text, Outfit for display. forui's sizes, weights and
/// line heights are kept; only the faces change.
const _bodyFont = 'packages/pinbench_ui/IBMPlexSans';
const _displayFont = 'packages/pinbench_ui/Outfit';
