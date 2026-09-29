import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinbench_ui/ui/app_icon_button.dart';
import 'package:pinbench_ui/strings.dart';
import 'package:pinbench_ui/ui/app_card.dart';
import 'package:pinbench_ui/theme/app_icons.dart';

import '../../providers/canvas_controller_provider.dart';
import 'canvas_tool_group_divider.dart';
import 'wire_color_select.dart';

class const CanvasToolbar({super.key}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(canvasControllerProvider.notifier);
    // Watch the STATE too (not just the notifier): selection changes reassign
    // state (see forceUpdate), and without this the enabled/disabled flags
    // below were computed once and never refreshed — leaving Delete greyed
    // out with a component selected.
    //
    // Narrowed to the two flags actually read. Dragging a part rewrites the
    // canvas state on every pointer move and this toolbar has no interest in
    // where the part went — only in whether anything is selected at all.
    //
    // The wire half is read off the selection manager rather than the state,
    // which is why it rides along in the same selector: selecting a wire does
    // not change any field of the state, it just reassigns it (`forceUpdate`),
    // so this recomputes and the record compares unequal. Watching only
    // `selectedNodes` would leave Delete greyed out with a wire selected.
    final (hasNodeSelection, hasWireSelection) = ref.watch(
      canvasControllerProvider.select(
        (state) => (
          state.selectedNodes.isNotEmpty,
          controller.selectionManager.selectedWireIds.isNotEmpty,
        ),
      ),
    );

    return Positioned(
      left: 8,
      bottom: 8,
      child: Align(
        alignment: AlignmentGeometry.bottomStart,
        child: AppCard(
          child: Builder(
            builder: (context) {
              final hasSelection = hasNodeSelection || hasWireSelection;
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppIconButton(
                      icon: AppIcons.copy,
                      tooltip: AppStrings.copy,
                      shortcutLabel: '⌘C',
                      isEnabled: hasNodeSelection,
                      onPressed: controller.copy,
                    ),
                    AppIconButton(
                      icon: AppIcons.paste,
                      tooltip: AppStrings.paste,
                      shortcutLabel: '⌘V',
                      onPressed: controller.paste,
                    ),
                    AppIconButton(
                      icon: AppIcons.delete,
                      tooltip: AppStrings.delete,
                      shortcutLabel: '⌫',
                      isEnabled: hasSelection,
                      onPressed: controller.remove,
                    ),
                    const CanvasToolGroupDivider(),
                    AppIconButton(
                      icon: AppIcons.undo,
                      tooltip: AppStrings.undo,
                      shortcutLabel: '⌘Z',
                      onPressed: controller.undo,
                    ),
                    AppIconButton(
                      icon: AppIcons.redo,
                      tooltip: AppStrings.redo,
                      shortcutLabel: '⇧⌘Z',
                      onPressed: controller.redo,
                    ),
                    const CanvasToolGroupDivider(),
                    const WireColorSelect(),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
