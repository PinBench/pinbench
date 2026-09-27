import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinbench_ui/strings.dart';

import '../../features/canvas/providers/canvas_controller_provider.dart';
import '../../features/editor/edit_action_router.dart';

/// The native macOS Edit menu. Undo/Redo and the clipboard actions route through
/// [router] to whichever surface the user last edited — a plain text field, the
/// re_editor code editor, or the canvas — so they work everywhere, mirroring the
/// web menu (`layout/bars/title/web_menu_bar.dart`).
PlatformMenu editMenu(WidgetRef ref, EditActionRouter router) {
  final canvas = ref.read(canvasControllerProvider.notifier);
  return PlatformMenu(
    label: AppStrings.editMenuLabel,
    menus: <PlatformMenuItem>[
      PlatformMenuItemGroup(
        members: [
          PlatformMenuItem(
            label: AppStrings.undo,
            shortcut: const SingleActivator(LogicalKeyboardKey.keyZ, meta: true),
            onSelected: () => router.route(
              textIntent: const UndoTextIntent(SelectionChangedCause.keyboard),
              codeAction: (c) => c.undo(),
              canvasFallback: canvas.undo,
            ),
          ),
          PlatformMenuItem(
            label: AppStrings.redo,
            shortcut: const SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true),
            onSelected: () => router.route(
              textIntent: const RedoTextIntent(SelectionChangedCause.keyboard),
              codeAction: (c) => c.redo(),
              canvasFallback: canvas.redo,
            ),
          ),
        ],
      ),
      PlatformMenuItemGroup(
        members: [
          PlatformMenuItem(
            label: AppStrings.cutMenuLabel,
            shortcut: const SingleActivator(LogicalKeyboardKey.keyX, meta: true),
            onSelected: () => router.route(
              textIntent: const CopySelectionTextIntent.cut(SelectionChangedCause.keyboard),
              codeAction: (c) => c.cut(),
              canvasFallback: () {
                canvas.copy();
                canvas.remove();
              },
            ),
          ),
          PlatformMenuItem(
            label: AppStrings.copy,
            shortcut: const SingleActivator(LogicalKeyboardKey.keyC, meta: true),
            onSelected: () => router.route(
              textIntent: CopySelectionTextIntent.copy,
              codeAction: (c) => c.copy(),
              canvasFallback: canvas.copy,
            ),
          ),
          PlatformMenuItem(
            label: AppStrings.paste,
            shortcut: const SingleActivator(LogicalKeyboardKey.keyV, meta: true),
            onSelected: () => router.route(
              textIntent: const PasteTextIntent(SelectionChangedCause.keyboard),
              codeAction: (c) => c.paste(),
              canvasFallback: canvas.paste,
            ),
          ),
          PlatformMenuItem(
            label: AppStrings.selectAllMenuLabel,
            shortcut: const SingleActivator(LogicalKeyboardKey.keyA, meta: true),
            onSelected: () => router.route(
              textIntent: const SelectAllTextIntent(SelectionChangedCause.keyboard),
              codeAction: (c) => c.selectAll(),
            ),
          ),
        ],
      ),
    ],
  );
}
