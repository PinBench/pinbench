import 'package:flutter/widgets.dart';

import 'package:forui/forui.dart';

import '../theme/app_colors.dart';

/// An indeterminate "working on it" spinner.
///
/// forui's [FCircularProgress] with the two things the call sites actually
/// ask it for — a size and a colour — bound to its icon style, so a spinner
/// reads the same wherever it appears without every site writing the delta.
///
/// It spins a loader glyph rather than sweeping an arc, which is why there is
/// no `strokeWidth` here: the stroke belongs to the glyph, and a width the
/// widget could not honour is worse than one it never offered.
class const AppSpinner({
  super.key,

  /// The diameter of the spinner.
  final double size = 36,

  /// Defaults to the theme's primary. forui's own default is the muted
  /// foreground, which is too quiet for something the user is waiting on.
  final Color? color,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: SizedBox.square(
      dimension: size,
      // The glyph must be laid out at exactly [size], whatever the parent
      // offers — otherwise the spinner wobbles instead of spinning.
      //
      // [FCircularProgress] turns the glyph about the centre of its box. At
      // its natural size the glyph draws centred in that box, so the two
      // centres agree and it turns in place. Squeeze the box below the
      // glyph's size and the paragraph is laid out against the smaller width
      // while the glyph keeps drawing at its font size: the ink lands low and
      // to the right, and the rotation swings it around that offset. A 32px
      // spinner in a 24px slot puts the ink 3.5px off in each axis — a 5px
      // orbit, which is exactly the wobble this widget shipped with.
      child: OverflowBox(
        minWidth: size,
        maxWidth: size,
        minHeight: size,
        maxHeight: size,
        child: FCircularProgress(
          style: FCircularProgressStyleDelta.delta(
            iconStyle: IconThemeDataDelta.delta(
              color: color ?? context.appColors.primary,
              size: size,
            ),
          ),
        ),
      ),
    ),
  );
}
