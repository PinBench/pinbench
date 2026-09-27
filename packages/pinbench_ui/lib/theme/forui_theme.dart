/// The app's theme, as the widget library wants it.
///
/// Everything the app draws resolves against this: `AppColorScheme` and
/// `AppTypography` in `app_colors.dart` read it, and every wrapper in
/// `shared/widgets` inherits it. Nothing outside `shared/theme` and
/// `shared/widgets` should construct or name it.
///
/// The base is forui's own Neutral scheme rather than a port of `AppPalette` —
/// the point of adopting the library was its look, so its greys, typography
/// and component shapes are left alone. Only [primary] is overridden, because
/// the teal is the product's identity and not something a library should
/// decide.
library;

import 'package:flutter/widgets.dart';

import 'package:forui/forui.dart';

import 'theme.dart' show primary;

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
final class AppColors {
  const AppColors({required this.accent, required this.accentForeground});

  /// Wash behind an active/selected control.
  final Color accent;

  /// Ink on [accent]. Checked against it for WCAG AA, as every pair in
  /// `AppPalette` is — see `theme.dart`.
  final Color accentForeground;

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
/// Not the brand [primary] (`#009696`) itself: white on it is 3.62:1, under
/// WCAG AA. These are the two values the UI actually paints, each tuned to
/// clear 4.5:1 against its own foreground.
const _lightPrimary = Color(0xFF007F7F);
const _lightPrimaryForeground = Color(0xFFFFFFFF);

const _lightAccent = Color(0xFFDCEDEC);
const _lightAccentForeground = Color(0xFF005F5F);

const _darkPrimary = Color(0xFF12A5A5);
const _darkPrimaryForeground = Color(0xFF08201F);

const _darkAccent = Color(0xFF1B2E2E);
const _darkAccentForeground = Color(0xFF7FD9D9);

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
FThemeData fTheme(Brightness brightness) => FThemeData(touch: false, colors: _colors(brightness));
