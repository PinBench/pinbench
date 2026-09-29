import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'package:forui/forui.dart';

import '../theme/app_colors.dart';
import '../theme/tokens.dart';
import 'app_context_menu.dart';

/// One top-level menu — "File", "Edit" — and what drops out of it.
class const AppMenu({
  required final String label,

  /// Shares its entry type with [AppContextMenu]: a menu line is a menu line
  /// whether it drops from a bar or appears under the pointer.
  required final List<AppMenuEntry> entries,
});

/// An operating-system-style menu bar, drawn in the app.
///
/// Built on the same forui popover [AppContextMenu] uses, and out of the same
/// `FItem` rows.
///
/// It used to be built on Flutter's `MenuBar` instead, for the conventions
/// that came with it. Two things ended that. Flutter 3.47 moved Material out
/// of the SDK, and `MenuBar`, `SubmenuButton` and `MenuItemButton` went with
/// it — the framework kept only `RawMenuAnchor`, which is the plumbing, not
/// the conventions. And the old file's own test carried the warning that
/// mattered: the bar's rows and the right-click menu's rows "are built on
/// different libraries, which is exactly why this can drift", and it had to
/// assert their heights matched to catch it. Built from the same rows, they
/// cannot drift, and most of the styling that existed to drag Material's
/// touch defaults onto the app's proportions is simply gone.
///
/// What is hand-rolled here is the behaviour a menu *bar* has and a lone
/// popover does not: only one menu open at a time, and sliding across the bar
/// with one open switches to the one under the pointer rather than needing a
/// second click.
class const AppMenuBar({super.key, required final List<AppMenu> menus}) extends StatefulWidget {
  /// Narrow menus look broken beside wide ones, so every menu starts at least
  /// this wide and grows to its longest row.
  static const double minMenuWidth = 200;

  @override
  State<AppMenuBar> createState() => _AppMenuBarState();
}

class _AppMenuBarState extends State<AppMenuBar> {
  /// Which menu is open, if any. One field, so two cannot be open at once.
  int? _open;

  void _toggle(int index) => setState(() => _open = _open == index ? null : index);

  /// Sliding along the bar with a menu already open follows the pointer. With
  /// none open it does nothing — hovering a closed menu bar must not make
  /// menus appear under the pointer as it crosses on its way somewhere else.
  void _hover(int index) {
    if (_open != null && _open != index) setState(() => _open = index);
  }

  void _close() {
    if (_open != null) setState(() => _open = null);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _close},
      child: Focus(
        canRequestFocus: false,
        child: DecoratedBox(
          // A rounded strip the menu names sit inside, and no outline: the fill
          // is enough to hold them together, and a line around them is a second
          // frame inside the title bar's own.
          decoration: BoxDecoration(color: colors.surface, borderRadius: AppRadii.mdAll),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xs),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (index, menu) in widget.menus.indexed)
                  _MenuButton(
                    menu: menu,
                    isOpen: _open == index,
                    onPressed: () => _toggle(index),
                    onHover: () => _hover(index),
                    onDismissed: _close,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One name in the bar, and the panel that drops from it.
class const _MenuButton({
  required final AppMenu menu,
  required final bool isOpen,
  required final VoidCallback onPressed,
  required final VoidCallback onHover,
  required final VoidCallback onDismissed,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return FPopoverMenu(
      control: FPopoverControl.lifted(
        shown: isOpen,
        onChange: (shown) {
          if (!shown) onDismissed();
        },
      ),
      // The panel hangs directly under the name it belongs to, left edges
      // aligned, which is where every desktop menu bar puts it.
      childAnchor: Alignment.bottomLeft,
      menuAnchor: Alignment.topLeft,
      // Rows laid out like the context menu's — see [appMenuItemGroupStyle],
      // which is what closes the panel onto its first and last row.
      style: const FPopoverMenuStyleDelta.delta(
        minWidth: AppMenuBar.minMenuWidth,
        itemGroupStyle: appMenuItemGroupStyle,
      ),
      autofocus: true,
      menu: _groups(),
      child: MouseRegion(
        onEnter: (_) => onHover(),
        child: FTappable(
          onPress: onPressed,
          builder: (context, states, child) => Container(
            height: AppChrome.menuRowHeight,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            decoration: BoxDecoration(
              // An open menu keeps its name filled, which is how you can tell
              // which one you opened.
              color: isOpen || states.contains(FTappableVariant.hovered) ? colors.muted : null,
              borderRadius: AppRadii.mdAll,
            ),
            child: child,
          ),
          child: Text(
            menu.label,
            style: context.appText.sm.copyWith(
              fontWeight: FontWeight.w500,
              color: colors.foreground,
            ),
          ),
        ),
      ),
    );
  }

  /// Splits the entries into one group per run between separators, which is
  /// how the underlying menu draws a rule: between groups, not between items.
  /// Same shape as [AppContextMenu]'s, because they are the same menu.
  List<FItemGroupMixin> _groups() {
    final groups = <FItemGroupMixin>[];
    var run = <FItemMixin>[];

    void flush() {
      if (run.isEmpty) return;
      groups.add(FItemGroup(children: run));
      run = <FItemMixin>[];
    }

    for (final entry in menu.entries) {
      switch (entry) {
        case AppMenuSeparator():
          flush();
        case AppContextMenuItem():
          run.add(_item(entry));
      }
    }
    flush();
    return groups;
  }

  FItem _item(AppContextMenuItem item) => FItem(
    enabled: item.enabled,
    title: Text(item.text),
    // The keystroke as text rather than an activator, which would re-register
    // a binding the app already owns. Held away from the label so the two read
    // as separate columns rather than one run-on line.
    suffix: item.shortcut == null ? null : Text(item.shortcut!),
    onPress: () {
      onDismissed();
      item.onPressed();
    },
  );
}
