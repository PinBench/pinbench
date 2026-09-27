import 'package:flutter/widgets.dart';

import '../theme/app_colors.dart';

/// A round portrait: an image if there is one, otherwise whatever [child]
/// stands in with — an initial, or a person icon.
///
/// Replaces `CircleAvatar`, which left the SDK with the rest of Material in
/// Flutter 3.47. Kept to the same three arguments the call sites were already
/// using, so the sites read the same; forui's `FAvatar` was the other
/// candidate and wants a style object to do what [backgroundColor] does here.
class AppAvatar extends StatelessWidget {
  const AppAvatar({super.key, this.radius = 20, this.backgroundColor, this.image, this.child});

  final double radius;

  /// Defaults to the muted surface — the same neutral a themed `CircleAvatar`
  /// resolved to, and a real fill rather than a hole in the layout while a
  /// network [image] is still loading.
  final Color? backgroundColor;

  final ImageProvider? image;

  /// Shown when there is no [image]. Centred, and clipped to the circle.
  final Widget? child;

  @override
  Widget build(BuildContext context) => Container(
    width: radius * 2,
    height: radius * 2,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: backgroundColor ?? context.appColors.muted,
      image: image == null ? null : DecorationImage(image: image!, fit: BoxFit.cover),
    ),
    child: child == null ? null : Center(child: child),
  );
}
