import 'package:flutter/widgets.dart';

import 'package:forui/forui.dart';

import '../theme/tokens.dart';
import 'app_kbd.dart';

/// Which edge of the target a tooltip sits against.
///
/// Call sites used to pass a pair of alignments, which spelled out the same
/// idea twice and was easy to get backwards. A side is what the caller means,
/// and it keeps the widget library out of their imports.
enum AppTooltipSide() {
  /// Above the target — the default, and right for anything in a toolbar.
  top,

  /// To the target's right, for controls pinned to the window's left edge
  /// where a tooltip above would sit over the title bar.
  right,
}

/// A hover label on [child].
///
/// Wraps the widget library so the rest of the app never names it. Lives here
/// rather than inside `AppIconButton` because tooltips hang off plain widgets
/// too — the global search field, for one.
///
/// [shortcutLabel] renders its key caps beside the message, so a tooltip and
/// the keystroke that does the same thing stay one thing to write.
class const AppTooltip({
  super.key,
  required final String message,
  required final Widget child,

  /// A keystroke to show beside [message], as key caps.
  final String? shortcutLabel,
  final AppTooltipSide side = AppTooltipSide.top,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => FTooltip(
    childAnchor: switch (side) {
      AppTooltipSide.top => Alignment.topCenter,
      AppTooltipSide.right => Alignment.centerRight,
    },
    tipAnchor: switch (side) {
      AppTooltipSide.top => Alignment.bottomCenter,
      AppTooltipSide.right => Alignment.centerLeft,
    },
    tipBuilder: (context, controller) => shortcutLabel == null
        ? Text(message)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message),
              Gap.hMd,
              AppKbd(shortcutLabel!, variant: AppKbdVariant.dense),
            ],
          ),
    child: child,
  );
}
