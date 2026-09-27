import 'package:flutter/widgets.dart';

import 'package:pinbench_ui/ui/app_context_menu.dart';
import 'package:pinbench_ui/strings.dart';
import 'package:pinbench_ui/theme/app_colors.dart';
import 'package:pinbench_ui/theme/app_icons.dart';

import '../../controller/canvas_controller.dart';

/// Builds the right-click context menu items for a selected canvas node
/// (rotate/flip/layer/duplicate/delete) or a selected wire (layer/delete).
/// Extracted from `canvas.dart`, mirroring the `ExplorerContextMenu` pattern
/// used by the Explorer sidebar.
class CanvasContextMenu {
  static List<AppMenuEntry> buildItems(BuildContext context, CanvasController controller) {
    if (controller.contextMenuNode.value != null) return _nodeItems(context, controller);
    if (controller.selectedWireIds.isNotEmpty) return _wireItems(context, controller);
    return [];
  }

  /// A wire has no orientation or clipboard presence, so its menu is just
  /// paint order and delete. Layer up/down reorder the wire within the wires
  /// list — the same ⌘]/⌘[ the node menu uses, routed by what's selected.
  static List<AppMenuEntry> _wireItems(BuildContext context, CanvasController controller) => [
    AppContextMenuItem(
      onPressed: controller.layerUp,
      icon: AppIcons.bringForward,
      shortcut: '⌘]',
      text: AppStrings.bringForwardMenuLabel,
    ),
    AppContextMenuItem(
      onPressed: controller.layerDown,
      icon: AppIcons.sendBackward,
      shortcut: '⌘[',
      text: AppStrings.sendBackwardMenuLabel,
    ),
    const AppMenuSeparator(),
    AppContextMenuItem(
      onPressed: controller.remove,
      icon: AppIcons.delete,
      iconColor: context.appColors.destructive,
      textColor: context.appColors.destructive,
      shortcut: '⌫',
      text: AppStrings.delete,
    ),
  ];

  static List<AppMenuEntry> _nodeItems(BuildContext context, CanvasController controller) => [
    AppContextMenuItem(
      onPressed: controller.rotateLeft,
      icon: AppIcons.rotateLeft,
      shortcut: '⇧⌘R',
      text: AppStrings.rotateLeftMenuLabel,
    ),
    const AppMenuSeparator(),
    AppContextMenuItem(
      onPressed: controller.rotateRight,
      icon: AppIcons.rotateRight,
      shortcut: '⌘R',
      text: AppStrings.rotateRightMenuLabel,
    ),
    const AppMenuSeparator(),
    AppContextMenuItem(
      onPressed: controller.flipHorizontal,
      icon: AppIcons.flipHorizontal,
      shortcut: '⌘F',
      text: AppStrings.flipHorizontalMenuLabel,
    ),
    const AppMenuSeparator(),
    AppContextMenuItem(
      onPressed: controller.flipVertical,
      icon: AppIcons.flipVertical,
      shortcut: '⇧⌘F',
      text: AppStrings.flipVerticalMenuLabel,
    ),
    const AppMenuSeparator(),
    AppContextMenuItem(
      onPressed: controller.layerUp,
      icon: AppIcons.bringForward,
      shortcut: '⌘]',
      text: AppStrings.bringForwardMenuLabel,
    ),
    AppContextMenuItem(
      onPressed: controller.layerDown,
      icon: AppIcons.sendBackward,
      shortcut: '⌘[',
      text: AppStrings.sendBackwardMenuLabel,
    ),
    const AppMenuSeparator(),
    AppContextMenuItem(
      onPressed: () {
        controller.copy();
        controller.paste();
      },
      icon: AppIcons.copy,
      shortcut: '⌘D',
      text: AppStrings.duplicateMenuLabel,
    ),
    const AppMenuSeparator(),
    AppContextMenuItem(
      onPressed: controller.remove,
      icon: AppIcons.delete,
      iconColor: context.appColors.destructive,
      textColor: context.appColors.destructive,
      shortcut: '⌫',
      text: AppStrings.delete,
    ),
  ];
}
