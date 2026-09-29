import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:plat/plat.dart';
import 'package:pinbench_ui/theme/app_colors.dart';

import '../../../features/workspace/providers/workspace_files_provider.dart';
import '../../providers/layout_provider.dart';

/// What the window is showing, in the middle of the title bar: the workspace,
/// and the document on screen inside it.
///
/// The same line every desktop editor puts there, and it answers the question
/// the title bar is actually asked — *which* project is this, when several
/// windows are open and they all look alike.
///
/// The workspace's own folder name is the name: a template opened from the
/// gallery is copied into a directory named after the template (see
/// `TemplateService.createTempWorkspaceFromTemplate`), so "blink" reads as
/// "blink" here without this having to know it came from a template.
///
/// It replaced a badge that said "Temporary workspace" beside a Save button.
/// The badge named a state rather than the thing on screen, and it appeared
/// only in that state, so the centre of the title bar was empty the rest of the
/// time. Saving lives in the File menu, which is where a menu-bar app's Save
/// belongs.
class const WorkspaceTitle({super.key}) extends ConsumerWidget {
  /// Between the two halves. An em dash with spaces, not a hyphen: file names
  /// contain hyphens and a separator has to be one.
  static const _separator = ' — ';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspacePath = ref.watch(workspaceFilesProvider.select((s) => s.workspacePath));
    if (workspacePath == null) return const SizedBox.shrink();

    final controller = ref.watch(platControllerProvider);

    // Listened to rather than read: which tab is on top is the controller's
    // state, and nothing else here changes when the user switches document.
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final document = _activeDocument(controller);
        return Text(
          document == null
              ? p.basename(workspacePath)
              : '${p.basename(workspacePath)}$_separator$document',
          style: context.appMutedText,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
        );
      },
    );
  }

  /// The title of the tab on top of the centre pane, or null when it holds
  /// none — the tab's own title rather than its file path, so a canvas and the
  /// editor for one `.cdl` read the same way here as they do on their tabs.
  static String? _activeDocument(PlatController controller) {
    final group = controller.snapshot('center_pane');
    return group is TabGroupSnapshot ? group.activeTab?.title : null;
  }
}
