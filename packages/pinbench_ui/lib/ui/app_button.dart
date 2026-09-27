import 'package:flutter/widgets.dart';

import 'package:forui/forui.dart';

/// How much weight a button carries.
enum AppButtonVariant {
  /// The one action a surface most wants you to take. At most one per view.
  primary,

  /// A filled but quieter alternative.
  secondary,

  /// Bordered. The usual choice for a secondary action beside a [primary] one.
  outline,

  /// No fill or border until hovered — for actions that should not compete.
  ghost,

  /// Removes something, or is otherwise not undoable.
  destructive,
}

enum AppButtonSize { xs, sm, md, lg }

/// A labelled button.
///
/// Wraps the widget library so the rest of the app never names it. Swapping
/// libraries should mean rewriting this file, not the twenty call sites
/// behind it.
///
/// The API is the app's, not the library's: [onPressed] rather than forui's
/// `onPress`, and [expands] rather than a `mainAxisSize` whose default flipped
/// between the two libraries and silently changed how buttons sized themselves.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.child,
    this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.size = AppButtonSize.md,
    this.prefix,
    this.expands = false,
    this.selected = false,
  });

  final Widget child;

  /// Null disables the button.
  final VoidCallback? onPressed;

  final AppButtonVariant variant;
  final AppButtonSize size;

  /// Icon shown before the label.
  final Widget? prefix;

  /// Fill the available width instead of hugging the label.
  final bool expands;

  /// Marks this as the current choice among several — a selected preset, an
  /// active mode. Styling is the theme's business, not the call site's.
  final bool selected;

  @override
  Widget build(BuildContext context) => FButton(
    onPress: onPressed,
    selected: selected,
    prefix: prefix,
    mainAxisSize: expands ? MainAxisSize.max : MainAxisSize.min,
    variant: switch (variant) {
      AppButtonVariant.primary => FButtonVariant.primary,
      AppButtonVariant.secondary => FButtonVariant.secondary,
      AppButtonVariant.outline => FButtonVariant.outline,
      AppButtonVariant.ghost => FButtonVariant.ghost,
      AppButtonVariant.destructive => FButtonVariant.destructive,
    },
    size: switch (size) {
      AppButtonSize.xs => FButtonSizeVariant.xs,
      AppButtonSize.sm => FButtonSizeVariant.sm,
      AppButtonSize.md => FButtonSizeVariant.md,
      AppButtonSize.lg => FButtonSizeVariant.lg,
    },
    child: child,
  );
}

/// Makes [child] respond to a press without drawing anything of its own.
///
/// For rows and links that need hover and tap handling but supply their own
/// box — an [AppButton] would bring an inset, a fill and intrinsic sizing that
/// those surfaces immediately override.
class AppTappable extends StatelessWidget {
  const AppTappable({super.key, required this.child, this.onPressed});

  final Widget child;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => FTappable(onPress: onPressed, child: child);
}
