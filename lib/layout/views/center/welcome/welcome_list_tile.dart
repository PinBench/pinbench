import 'package:flutter/widgets.dart';

import 'package:pinbench_ui/theme/text.dart';
import 'package:pinbench_ui/theme/tokens.dart';
import 'package:pinbench_ui/ui/app_button.dart';
import 'package:pinbench_ui/theme/app_colors.dart';

/// A generic list-tile button used throughout the Welcome screen for
/// start actions, templates, and recent workspaces.
class const WelcomeListTile({
  super.key,
  required final IconData icon,
  required final String title,
  required final String subtitle,
  required final VoidCallback onTap,

  /// Overrides the default icon-in-a-box leading slot (e.g. a rendered
  /// circuit-preview thumbnail for templates). Same 50x50 footprint.
  final Widget? leading,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    // A tappable row rather than an `FButton`: this is 48px tall with a zero
    // inset and its own leading tile, so nearly everything a button contributes
    // would be overridden. `FTappable` gives the press and hover handling
    // without the padding and intrinsic sizing.
    return AppTappable(
      onPressed: onTap,
      // The fill reaches a little past the row rather than the row being
      // inset inside it: the thumbnail lines up with the icon in the card's
      // heading, and padding the row for the fill would push it out of line.
      builder: (context, child, {required hovered}) => Stack(
        clipBehavior: Clip.none,
        children: [
          if (hovered)
            Positioned.fill(
              left: -AppSpacing.sm,
              top: -AppSpacing.sm,
              right: -AppSpacing.sm,
              bottom: -AppSpacing.sm,
              child: DecoratedBox(
                decoration: BoxDecoration(color: colors.muted, borderRadius: AppRadii.lgAll),
              ),
            ),
          child,
        ],
      ),
      // A minimum rather than a fixed height: the thumbnail sets its own size,
      // and pinning the row to it left the two lines of text 2px short of
      // fitting once the type scale changed underneath them.
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppChrome.tileThumbSize),
        child: Row(
          children: [
            leading ??
                Container(
                  width: AppChrome.tileThumbSize,
                  height: AppChrome.tileThumbSize,
                  decoration: BoxDecoration(color: colors.accent, borderRadius: AppRadii.smAll),
                  child: Icon(icon, color: colors.accentForeground),
                ),
            Gap.hXl,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.largePrimary(context),
                  ),
                  Text(
                    subtitle,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.smallMuted(context),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
