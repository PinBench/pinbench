import 'package:flutter/widgets.dart';

import 'package:forui/forui.dart';

import '../theme/forui_theme.dart';
import '../theme/tokens.dart';
import 'app_tooltip.dart';
import 'app_spinner.dart';
export 'app_tooltip.dart' show AppTooltipSide;

/// The four sizes an icon button comes in: a box, and the icon drawn in it.
///
/// The icon half comes from [AppIconSize] — a button is one more place an icon
/// is drawn, and it should be drawn at the same sizes as everywhere else. The
/// box half is this enum's own business: it is a hit target, sized so the icon
/// has air around it rather than to any icon ramp.
enum AppIconButtonSize(final double size, final double iconSize) {
  small(20, AppIconSize.sm),
  medium(28, AppIconSize.lg),
  large(32, AppIconSize.xl),
  xlarge(40, AppIconSize.xxxl),
}

/// A square, icon-only button.
///
/// Built on [FTappable] rather than [FButton] because almost everything
/// [FButton] brings — padding, intrinsic sizing, its own fill per variant — is
/// something this overrides anyway with a fixed box and an explicit colour.
class const AppIconButton({
  super.key,
  final Color? color,
  required final IconData icon,
  final String? tooltip,
  final VoidCallback? onPressed,

  /// What a screen reader announces for the button.
  ///
  /// Defaults to [tooltip], since an icon-only button's tooltip is already the
  /// name of the action. Pass this when there is no tooltip, or when the
  /// spoken name should differ from the visible one.
  final String? semanticLabel,
  final String? shortcutLabel,
  final AppTooltipSide tooltipSide = AppTooltipSide.top,
  final Color? backgroundColor,
  final Color? hoverBackgroundColor,
  final bool ghost = true,
  final bool isActive = false,
  final bool isEnabled = true,
  final bool isLoading = false,
  final AppIconButtonSize size = AppIconButtonSize.medium,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final enabled = isEnabled && onPressed != null;

    // An active control keeps the accent wash whether or not the pointer is
    // over it — that is what marks it as the current one.
    final resting = isActive ? colors.app.accent : backgroundColor;
    final hovered = isActive
        ? colors.app.accent
        : (hoverBackgroundColor ??
              colors.hover(backgroundColor ?? (ghost ? colors.background : colors.primary)));

    final button = FTappable(
      onPress: enabled ? onPressed : null,
      // Nothing else in an icon-only button carries a name, so without this a
      // screen reader announces bare "button".
      semanticsLabel: semanticLabel ?? tooltip,
      builder: (context, states, child) => Container(
        width: size.size,
        height: size.size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: states.contains(FTappableVariant.hovered)
              ? hovered
              : (resting ?? (ghost ? null : colors.primary)),
          borderRadius: AppRadii.smAll,
        ),
        child: Opacity(opacity: enabled ? 1 : 0.5, child: child),
      ),
      child: isLoading
          // Drawn at the icon's own size, in the icon's own place: the
          // spinner stands in for the icon, so anything that shrinks its box
          // below the glyph only moves the glyph off the point it spins
          // about. It used to sit in an `AppSpacing.md` padding, and the
          // wobble that produced is why [AppSpinner] now pins its own size.
          ? AppSpinner(size: size.iconSize, color: color)
          : Icon(
              icon,
              size: size.iconSize,
              color: color ?? (ghost ? colors.foreground : colors.primaryForeground),
            ),
    );

    if (tooltip == null) return button;

    return AppTooltip(
      message: tooltip!,
      shortcutLabel: shortcutLabel,
      side: tooltipSide,
      child: button,
    );
  }
}
