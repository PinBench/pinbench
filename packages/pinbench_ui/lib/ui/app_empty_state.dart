import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';
import '../theme/app_colors.dart';

/// How much room an empty state has to fill.
enum AppEmptyStateSize {
  /// Inside a sidebar or a narrow panel.
  compact(40, AppSpacing.lg),

  /// Inside a normal pane — the default.
  normal(56, AppSpacing.xl),

  /// A whole editor area or the workspace backdrop.
  hero(96, AppSpacing.xxl);

  const AppEmptyStateSize(this.iconSize, this.gap);

  final double iconSize;

  /// Space between the icon and the title.
  final double gap;
}

/// The "nothing here yet" placeholder: an icon, a heading, an optional line of
/// explanation, and optional content beneath.
///
/// This replaced five hand-rolled variants whose icons were sized 48, 56, 64
/// and 120 and which disagreed about whether the glyph was `muted`,
/// `mutedForeground` or `foreground`. The icon is intentionally drawn in
/// `mutedForeground` at reduced opacity: it should establish the shape of the
/// empty area without competing with the text that tells you what to do.
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.icon,
    this.title,
    this.message,
    this.size = AppEmptyStateSize.normal,
    this.iconColor,
    this.children = const [],
  });

  final IconData icon;

  /// Omit when the state needs only a single explanatory line — pass that as
  /// [message] so it renders as secondary text rather than as a heading.
  final String? title;
  final String? message;
  final AppEmptyStateSize size;

  /// Overrides the muted glyph — pass `colorScheme.primary` only when the
  /// empty state is an invitation rather than a report of absence.
  final Color? iconColor;

  /// Extra content below the message, e.g. an action button or a key cheat
  /// sheet. Laid out in a column, [AppSpacing.xl] apart.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: AppInsets.panel,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: size.iconSize,
            color: iconColor ?? context.appColors.mutedForeground.withValues(alpha: 0.6),
          ),
          SizedBox(height: size.gap),
          if (title != null) Text(title!, textAlign: TextAlign.center, style: context.appText.lg),
          if (message != null) ...[
            if (title != null) const SizedBox(height: AppSpacing.md),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: context.appMutedText.copyWith(color: context.appColors.mutedForeground),
            ),
          ],
          for (final child in children) ...[const SizedBox(height: AppSpacing.xl), child],
        ],
      ),
    ),
  );
}
