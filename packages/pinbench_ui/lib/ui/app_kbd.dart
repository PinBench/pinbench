import 'package:flutter/widgets.dart';

import 'package:forui/forui.dart';

import '../theme/forui_theme.dart';
import '../theme/tokens.dart';

/// How prominent a key cap should be.
enum AppKbdVariant() {
  /// Small, filled with the accent wash. For key hints riding inside another
  /// control's chrome — most often an icon button's tooltip.
  dense,

  /// Full-size cap on the muted surface with a border. For key hints that are
  /// content in their own right, e.g. the empty-editor cheat sheet.
  normal,
}

/// Minimum width of a normal cap's label, so the cap reads as square-ish for
/// one-character keys. Sized to leave a 24px cap once the horizontal padding
/// is added back on.
const _capFloorWidth = 24 - 2 * AppSpacing.sm;

/// A single keyboard key rendered as a cap: `⌘`, `⇧`, `P`.
///
/// Before this existed the app drew key caps three different ways — two
/// paddings, two fills, and one pair whose text sat at 1.85:1 on its own
/// background. Route every new key hint through here.
class const AppKbd(
  final String label, {
  super.key,
  final AppKbdVariant variant = AppKbdVariant.normal,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final dense = variant == AppKbdVariant.dense;

    return Container(
      padding: dense
          ? AppInsets.badge
          : const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: dense ? colors.app.accent : colors.muted,
        borderRadius: dense ? AppRadii.xsAll : AppRadii.smAll,
        border: dense ? null : Border.all(color: colors.border),
      ),
      // A single narrow glyph ("P") would make a lopsided cap, so the normal
      // variant reserves a floor width and centers the label inside it.
      //
      // That floor lives on the *text*, not on the Container: giving a
      // Container an `alignment` makes it expand to fill whatever constraints
      // it is handed, and a tooltip overlay hands it the full screen height —
      // which stretched the cap, and the whole popup with it.
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: dense ? 0 : _capFloorWidth),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: dense ? 10 : null,
            fontWeight: dense ? FontWeight.w600 : null,
            color: dense ? colors.app.accentForeground : colors.foreground,
          ),
        ),
      ),
    );
  }
}

/// A label paired with the keys that trigger it — `Open File   ⌘ P`.
///
/// [spaceBetween] pushes the caps to the trailing edge, which is what a
/// fixed-width cheat-sheet column wants; the default hugs the label.
class const AppShortcutHint({
  super.key,
  required final String label,
  required final List<String> keys,
  final AppKbdVariant variant = AppKbdVariant.normal,
  final bool spaceBetween = false,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: spaceBetween ? MainAxisSize.max : MainAxisSize.min,
    mainAxisAlignment: spaceBetween ? MainAxisAlignment.spaceBetween : MainAxisAlignment.start,
    children: [
      // The label gives way, not the keys: a long one ellipsizes rather than
      // pushing the caps out of a fixed-width column.
      Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
      Gap.hMd,
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final key in keys)
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.xs),
              child: AppKbd(key, variant: variant),
            ),
        ],
      ),
    ],
  );
}
