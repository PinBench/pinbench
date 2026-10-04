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

/// The Welcome screen's "Start" card: a new blank project, or a folder to
/// open.
class const WelcomeStartSection({super.key}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future<void> open(Future<String> Function(TemplateService) create) async {
      final tempPath = await create(ref.read(templateServiceProvider));
      await ref.read(workspaceFilesProvider.notifier).openWorkspace(tempPath, isTemporary: true);
      ref.read(appLayoutControllerProvider).closeWelcome();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WelcomeListTile(
          icon: AppIcons.blankProject,
          title: AppStrings.newBlankProjectTitle,
          subtitle: AppStrings.newBlankProjectSubtitle,
          onTap: () => open((templates) => templates.createBlankWorkspace()),
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
}
