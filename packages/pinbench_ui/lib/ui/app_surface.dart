import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';
import '../theme/app_colors.dart';
import '../theme/theme.dart';

/// The role a surface plays, which fixes its fill and radius.
enum AppSurfaceVariant {
  /// Raised content block on the pane background. Card fill, hairline border.
  card,

  /// A recessed strip — banners, callouts, inactive rows. Muted fill.
  inset,

  /// Fill drawn from the accent wash, for a highlighted/selected block.
  accent,

  /// No fill at all; border only. For grouping without adding weight.
  outline,
}

/// A bordered, rounded block of content.
///
/// The app had eighteen hand-written `BoxDecoration`s that were mostly this
/// same shape with radii drifting across 2, 4, 6 and 8. Use this for anything
/// card-shaped; `PaneSurface` remains separate because a pane is structural
/// chrome — flat, square and edge-to-edge — rather than content.
class AppSurface extends StatelessWidget {
  const AppSurface({
    super.key,
    required this.child,
    this.variant = AppSurfaceVariant.card,
    this.padding = AppInsets.card,
    this.margin,
    this.radius = AppRadii.mdAll,
    this.bordered = true,
    this.onTap,
  });

  final Widget child;
  final AppSurfaceVariant variant;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final BorderRadius radius;

  /// Set false to drop the hairline border while keeping the fill.
  final bool bordered;

  /// When set, the surface becomes clickable and gains a hover fill.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.appColors;

    final fill = switch (variant) {
      AppSurfaceVariant.card => colorScheme.surface,
      AppSurfaceVariant.inset => colorScheme.muted,
      AppSurfaceVariant.accent => colorScheme.accent,
      AppSurfaceVariant.outline => AppPalette.transparent,
    };

    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: radius,
        border: bordered ? Border.all(color: colorScheme.border) : null,
      ),
      child: child,
    );

    final surface = onTap == null
        ? content
        : MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(onTap: onTap, child: content),
          );

    return margin == null ? surface : Padding(padding: margin!, child: surface);
  }
}
