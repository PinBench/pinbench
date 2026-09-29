import 'package:flutter/widgets.dart';

import 'package:forui/forui.dart';

import '../theme/tokens.dart';

/// A raised block of content: a floating toolbar, a settings group, a panel.
///
/// Wraps the widget library's card so the rest of the app never names it. Both
/// libraries call this a "card"; the app calls the colour underneath it
/// `surface`, because what matters is that it sits above the ground.
///
/// forui's card, like its dialog, is a surface and a set of text styles rather
/// than a title/subtitle/child widget — the header arrangement is the caller's.
/// Composing it once here is what keeps every card in the app the same shape.
///
/// Sibling to `AppSurface`, which is the flatter, in-flow version — this one is
/// for things that float.
class const AppCard({
  super.key,
  required final Widget child,

  /// Optional heading above [child].
  final String? title,

  /// Optional line of explanation under [title].
  final String? message,

  /// Defaults to the card inset from the token scale.
  final EdgeInsetsGeometry? padding,

  /// Clip [child] to the card's rounded corners. For content that paints to
  /// the edges, like the minimap.
  final bool clipContent = false,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => FCard(
    clipBehavior: clipContent ? Clip.antiAlias : Clip.none,
    builder: (context, style, _) => Padding(
      padding: padding ?? AppInsets.card,
      child: title == null && message == null
          ? child
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) Text(title!, style: style.titleTextStyle),
                if (message != null) ...[
                  if (title != null) Gap.vXs,
                  Text(message!, style: style.subtitleTextStyle),
                ],
                Gap.vLg,
                child,
              ],
            ),
    ),
    child: child,
  );
}
