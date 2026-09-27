import 'package:flutter/widgets.dart';

import 'app_colors.dart';

/// Named, reusable text styles for plain [Text] widgets.
///
/// Sibling to [AppTypography], which carries the bare size scale. These are
/// the recurring *combinations* — a size and a colour that always travel
/// together — named once so they cannot drift apart at the call site.
class AppTextStyles {
  AppTextStyles._();

  /// Inline error text (form/API error messages).
  static TextStyle error(BuildContext context) => TextStyle(color: context.appColors.destructive);

  /// Bold property/section label.
  static const label = TextStyle(fontWeight: FontWeight.bold);

  /// Default paragraph text.
  static TextStyle style1(BuildContext context) => context.appText.md;

  static TextStyle largePrimary(BuildContext context) =>
      context.appText.lg.copyWith(color: context.appColors.primary);

  static TextStyle smallOnPrimary(BuildContext context) =>
      context.appText.sm.copyWith(color: context.appColors.primaryForeground);

  static TextStyle h1LargePrimary(BuildContext context) =>
      context.appText.h1.copyWith(color: context.appColors.primary);

  /// Secondary text reads `mutedForeground`, never `muted` — the latter is the
  /// muted *surface* and would be near-invisible as ink.
  static TextStyle largeMuted(BuildContext context) =>
      context.appText.lg.copyWith(color: context.appColors.mutedForeground);

  static TextStyle smallMuted(BuildContext context) => context.appMutedText;

  /// Default body text for compact list/tree rows.
  static TextStyle body(BuildContext context) =>
      TextStyle(fontSize: 13, color: context.appColors.foreground);

  /// Serial plotter legend/axis label, colored per data series.
  static TextStyle plotterLabel(Color? color) =>
      TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 11);

  /// Keyboard-shortcut badge shown inside icon-button tooltips.
  static TextStyle shortcutBadge(BuildContext context) => TextStyle(
    fontSize: 10,
    color: context.appColors.accentForeground,
    fontWeight: FontWeight.w600,
  );
}
