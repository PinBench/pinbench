import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinbench_ui/strings.dart';
import 'package:pinbench_ui/theme/tokens.dart';
import 'package:pinbench_ui/ui/app_toast.dart';
import 'package:pinbench_ui/theme/app_icons.dart';

import 'welcome_list_tile.dart';
import '../../../../features/workspace/providers/workspace_files_provider.dart';
import '../../../../features/workspace/services/template_service.dart';
import '../../../controllers/app_layout_controller.dart';

/// The Welcome screen's "Start" card: new blank project / open folder.
class WelcomeStartSection extends ConsumerWidget {
  const WelcomeStartSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      WelcomeListTile(
        icon: AppIcons.blankProject,
        title: AppStrings.newBlankProjectTitle,
        subtitle: AppStrings.newBlankProjectSubtitle,
        onTap: () async {
          final tempPath = await ref.read(templateServiceProvider).createBlankWorkspace();
          await ref
              .read(workspaceFilesProvider.notifier)
              .openWorkspace(tempPath, isTemporary: true);
          ref.read(appLayoutControllerProvider).closeWelcome();
        },
      ),
      Gap.vMd,
      WelcomeListTile(
        icon: AppIcons.folderOpen,
        title: AppStrings.openFolderMenuLabel,
        subtitle: AppStrings.openFolderTileSubtitle,
        onTap: () async {
          if (kIsWeb) {
            showAppToast(
              context,
              title: AppStrings.webPreviewUnavailableTitle,
              message: AppStrings.webPreviewFolderUnavailableMessageAlt,
            );
            return;
          }
          final directoryPath = await getDirectoryPath();
          if (directoryPath != null) {
            await ref.read(workspaceFilesProvider.notifier).openWorkspace(directoryPath);
            ref.read(appLayoutControllerProvider).closeWelcome();
          }
        },
      ),
    ],
  );
}
