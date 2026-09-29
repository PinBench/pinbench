import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:forui/forui.dart';

import '../theme/tokens.dart';

/// How both menus lay their rows out — this one and the menu bar's, which is
/// the same panel dropped from a different place.
///
/// A menu panel has no padding of its own: the band of empty space above the
/// first row and below the last is the item group's `spacing`, which `FItem`
/// adds to the first row's top margin and the last row's bottom. Zeroed, so the
/// panel closes onto its rows — what is left above the first label is that
/// row's own content padding, the same as every other row, and the rhythm
/// between rows is untouched.
///
/// Shared rather than set twice, because the two are meant to be the same rows
/// and `app_menu_bar_test` asserts their heights match.
const appMenuItemGroupStyle = FItemGroupStyleDelta.delta(spacing: 0);

/// One line of a context menu.
///
/// Data rather than a widget: the underlying menu only accepts its own item
/// type, so the app describes what it wants and [AppContextMenu] builds it.
/// That is also what lets a menu be split into groups at its separators.
sealed class const AppMenuEntry();

/// A rule between two runs of items.
class const AppMenuSeparator() extends AppMenuEntry;

/// A menu line you can click.
class const AppContextMenuItem({
  required final String text,
  required final VoidCallback onPressed,
  final IconData? icon,
  final Color? iconColor,
  final Color? textColor,

  /// The keystroke that does the same thing, shown on the right.
  final String? shortcut,

  /// A greyed-out line that cannot be clicked — "Save" with nothing unsaved.
  final bool enabled = true,
}) extends AppMenuEntry;

/// Where a context menu is open, if it is.
///
/// Holds the screen point the menu was summoned at rather than a bare flag,
/// because a context menu's position is part of its state — it belongs where
/// you right-clicked, not where its trigger happens to be.
class AppContextMenuController extends ChangeNotifier {
  Offset? _at;

  /// The screen point the menu is anchored to, or null when it is closed.
  Offset? get position => _at;

  bool get isOpen => _at != null;

  /// Opens the menu with its top-left corner at [globalPosition].
  void showAt(Offset globalPosition) {
    _at = globalPosition;
    notifyListeners();
  }

  void hide() {
    if (_at == null) return;
    _at = null;
    notifyListeners();
  }
}

/// A right-click menu over [child].
///
/// Wraps the widget library so the rest of the app never names it, and papers
/// over the one thing forui's menu does not do: open at an arbitrary point.
/// Its menu anchors to a widget, so this puts a zero-sized widget where the
/// click was and anchors to that.
///
/// ## The child's position in the tree never changes
///
/// This matters more than it sounds. A menu that returns its child *bare*
/// when it has no items and wrapped when it has some moves everything beneath
/// it to a different depth as the item list changes — unmounting it. This
/// menu's items depend on the canvas selection, so that would be fatal
/// mid-gesture: grabbing a selected wire's endpoint clears the selection, the
/// menu empties, the pointer handler below is disposed on the spot, and the
/// wire springs back because no further move or up event ever arrives.
///
/// Here the child is always the first entry of the same [Stack], whether the
/// menu is open, closed, or empty. Keep it that way.
class const AppContextMenu({
  super.key,
  required final AppContextMenuController controller,

  /// The menu's contents, rebuilt by the caller as its state changes.
  required final List<AppMenuEntry> entries,
  required final Widget child,

  /// How long the menu waits after the pointer leaves both it and its trigger
  /// before closing itself.
  ///
  /// Right-clicking and then wandering off should not leave a menu stranded on
  /// screen, but closing the instant the pointer crosses the gap between the
  /// two would make the menu impossible to reach.
  final Duration dismissAfterLeaving = AppMotion.menuDismissDelay,
}) extends StatefulWidget {
  @override
  State<AppContextMenu> createState() => _AppContextMenuState();
}

class _AppContextMenuState extends State<AppContextMenu> {
  Timer? _dismiss;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(AppContextMenu old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    _dismiss?.cancel();
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() => setState(() {});

  void _scheduleDismiss() {
    _dismiss?.cancel();
    _dismiss = Timer(widget.dismissAfterLeaving, () {
      if (mounted) widget.controller.hide();
    });
  }

  void _cancelDismiss() {
    _dismiss?.cancel();
    _dismiss = null;
  }

  /// Splits the entries into one group per run between separators, which is
  /// how the underlying menu draws a rule: between groups, not between items.
  List<FItemGroupMixin> get _groups {
    final groups = <FItemGroupMixin>[];
    var run = <FItemMixin>[];

    void flush() {
      if (run.isEmpty) return;
      groups.add(FItemGroup(children: run));
      run = <FItemMixin>[];
    }

    for (final entry in widget.entries) {
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
    title: Text(item.text, style: item.textColor == null ? null : TextStyle(color: item.textColor)),
    prefix: item.icon == null ? null : Icon(item.icon, size: AppIconSize.sm, color: item.iconColor),
    suffix: item.shortcut == null ? null : Text(item.shortcut!),
    // The pointer sitting on an item is the clearest sign the menu is still
    // wanted. The menu floats in an overlay, so a MouseRegion around this
    // widget cannot see it — the items have to report for themselves.
    onHoverChange: (hovered) => hovered ? _cancelDismiss() : _scheduleDismiss(),
    onPress: () {
      widget.controller.hide();
      item.onPressed();
    },
  );

  @override
  Widget build(BuildContext context) {
    final position = widget.controller.position;
    final local = position == null ? Offset.zero : _toLocal(position);

    return MouseRegion(
      onEnter: (_) => _cancelDismiss(),
      onExit: (_) {
        if (widget.controller.isOpen) _scheduleDismiss();
      },
      child: Stack(
        children: [
          // Always first, always at this depth. See the class doc.
          widget.child,
          Positioned(
            left: local.dx,
            top: local.dy,
            child: FPopoverMenu(
              control: FPopoverControl.lifted(
                shown: widget.controller.isOpen,
                onChange: (shown) {
                  if (!shown) widget.controller.hide();
                },
              ),
              // The anchor is a zero-sized box at the click, so both corners
              // are the same point: the menu's top-left lands where you clicked.
              childAnchor: Alignment.topLeft,
              menuAnchor: Alignment.topLeft,
              spacing: FPortalSpacing.zero,
              style: const FPopoverMenuStyleDelta.delta(itemGroupStyle: appMenuItemGroupStyle),
              menu: _groups,
              child: const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }

  /// The click point in this widget's own coordinates, since the anchor is
  /// positioned inside its [Stack].
  Offset _toLocal(Offset global) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return Offset.zero;
    return box.globalToLocal(global);
  }
}
