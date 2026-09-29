import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinbench_ui/strings.dart';
import 'package:pinbench_ui/theme/tokens.dart';
import 'package:pinbench_ui/ui/app_toast.dart';
import 'package:pinbench_ui/ui/app_button.dart';
import 'package:pinbench_ui/theme/app_colors.dart';
import 'package:pinbench_ui/theme/app_icons.dart';

import '../../../core/auth/auth_provider.dart';
import '../providers/workspace_files_provider.dart';

/// Shown when the open workspace is a read-only copy of somebody else's shared
/// project — see `WorkspaceState.viewingSharedProjectId`.
///
/// Without this the shared-view state is invisible: a visitor gets a workspace
/// that silently never syncs, which reads as a bug rather than a design. The
/// banner names whose circuit it is, says plainly that edits go nowhere, and
/// offers the one action that makes them permanent.
///
/// Renders nothing at all when the workspace is local or linked, so it can sit
/// unconditionally in the layout.
class const SharedProjectBanner({super.key}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<SharedProjectBanner> createState() => _SharedProjectBannerState();
}

class _SharedProjectBannerState extends ConsumerState<SharedProjectBanner> {
  var _saving = false;

  Future<void> _saveCopy() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      // saveWorkspaceToCloud creates a project owned by the current user,
      // pushes the local files, and links the workspace to it — which clears
      // the shared-view state, so this banner disappears on success.
      final newId = await ref.read(workspaceFilesProvider.notifier).saveWorkspaceToCloud();
      if (!mounted) return;

      if (newId == null) {
        showAppToast(
          context,
          title: AppStrings.sharedProjectCopyFailedTitle,
          message: AppStrings.sharedProjectCopyFailedMessage,
          isError: true,
        );
        return;
      }
      showAppToast(
        context,
        title: AppStrings.sharedProjectCopiedTitle,
        message: AppStrings.sharedProjectCopiedMessage,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(workspaceFilesProvider);
    if (!state.isViewingShared) return const SizedBox.shrink();
    final signedIn = ref.watch(authServiceProvider).currentUser != null;
    final name = state.viewingSharedProjectName;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      decoration: BoxDecoration(
        color: context.appColors.muted,
        border: Border.all(color: context.appColors.border),
        borderRadius: AppRadii.mdAll,
      ),
      child: Row(
        children: [
          Icon(AppIcons.preview, size: AppIconSize.sm, color: context.appColors.mutedForeground),
          Gap.hLg,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name == null
                      ? AppStrings.sharedProjectBannerTitle
                      : '${AppStrings.sharedProjectBannerTitle} · $name',
                  style: context.appText.sm,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  AppStrings.sharedProjectBannerBody,
                  style: context.appMutedText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Gap.hLg,
          // Signing in is a whole flow of its own, so an anonymous visitor is
          // told what is missing rather than being dropped into it mid-edit.
          if (!signedIn)
            Text(AppStrings.sharedProjectSignInToCopy, style: context.appMutedText)
          else
            AppButton(
              onPressed: (!_saving) ? _saveCopy : null,
              child: Text(
                _saving
                    ? '${AppStrings.sharedProjectSaveCopyLabel}…'
                    : AppStrings.sharedProjectSaveCopyLabel,
              ),
            ),
        ],
      ),
    );
  }
}
