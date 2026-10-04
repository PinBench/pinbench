import 'package:flutter/widgets.dart';

import '../theme/app_colors.dart';

/// The faint brand-teal glow rising from the bottom of a pane, behind the
/// app's "nothing here yet" surfaces: the welcome screen and the empty editor.
///
/// A wash, not a spotlight. At a quarter opacity the brand teal turned the
/// whole lower half of the first screen green, which is the loudest thing a
/// tool can do before the user has done anything. One widget for both so the
/// two cannot drift apart.
class const BrandWash({super.key, required final Widget child}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          radius: 0.85,
          stops: const [0.0, 1.0],
          center: Alignment.bottomCenter,
          colors: [colors.primary.withValues(alpha: 0.05), colors.surface],
        ),
      ),
      child: child,
    );
  }
}
