import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:plat/plat.dart';
import 'package:pinbench_ui/theme/tokens.dart';

import '../../providers/layout_provider.dart';
import 'activity_bar_button.dart';
import 'activity_target.dart';

class const ActivityBar({super.key}) extends ConsumerWidget {
  bool _isCanvasShowing(PlatSnapshot? node) {
    if (node == null) return false;
    if (node is LeafSnapshot && node.data == 'canvas_view') return true;
    if (node is TabGroupSnapshot) return _isCanvasShowing(node.activeTab?.child);
    if (node is SplitSnapshot) return node.children.any(_isCanvasShowing);
    if (node is SlotSnapshot) return _isCanvasShowing(node.child);
    return false;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(platControllerProvider);

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final canvasShowing = _isCanvasShowing(controller.root);

        // The rail is a `Row` child rather than a pane, so no splitter falls
        // between it and the island beside it — without this margin the two
        // touch, and that island stops looking like it floats.
        return Container(
          // margin: const EdgeInsets.only(right: AppChrome.paneGap),
          padding: const EdgeInsets.all(AppSpacing.md),
          // decoration: BoxDecoration(color: context.appColors.muted),
          child: Column(
            spacing: AppSpacing.md,
            children: [
              for (final tab in topTabs)
                if (canvasShowing ||
                    (tab != ActivityBarTab.parts && tab != ActivityBarTab.properties))
                  ActivityBarButton(tab: tab),
              const Spacer(),
              for (final tab in bottomTabs) ActivityBarButton(tab: tab),
              // Settings is a document, not a sidebar — it opens as a tab in the
              // center pane, the way an editor does. See [SettingsTabButton].
              const SettingsTabButton(),
            ],
          ),
        );
      },
    );
  }
}
