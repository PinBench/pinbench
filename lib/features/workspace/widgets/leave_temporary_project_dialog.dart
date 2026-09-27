import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinbench_ui/strings.dart';
import 'package:pinbench_ui/theme/app_colors.dart';
import 'package:pinbench_ui/ui/app_button.dart';
import 'package:pinbench_ui/ui/app_dialog.dart';
import 'package:pinbench_ui/ui/app_toast.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/platform/platform_capabilities.dart';
import '../providers/workspace_files_provider.dart';

/// What the user chose to do with a temporary project they are leaving.
enum _LeaveChoice { saveToComputer, saveToCloud, discard }

/// The dialog's stacked buttons.
///
/// Every one is full width. Left to size themselves they came out three
/// different widths, right-aligned — a staircase rather than a stack, with no
/// edge for the eye to follow down the list.
///
/// Whichever save is available leads and takes the filled style; on the web
/// there is no local filesystem, so the cloud is the primary rather than a
/// secondary sitting under an option that isn't there.
List<Widget> _leaveActions(
  BuildContext context, {
  required bool canSaveToCloud,
  required bool canSaveToComputer,
}) {
  final colors = context.appColors;

  void pop(_LeaveChoice choice) => Navigator.of(context).pop(choice);

  return [
    if (canSaveToComputer)
      AppButton(
        onPressed: () => pop(_LeaveChoice.saveToComputer),
        child: const Text(AppStrings.leaveTemporarySaveToComputer),
      ),
    if (canSaveToCloud)
      // Filled only when it is the sole way to save, outline when it sits
      // under "Save to Computer" — two filled buttons read as two primaries.
      AppButton(
        variant: canSaveToComputer ? AppButtonVariant.outline : AppButtonVariant.primary,
        onPressed: () => pop(_LeaveChoice.saveToCloud),
        child: const Text(AppStrings.leaveTemporarySaveToCloud),
      ),
    // Ghost, so it does not compete with the saves, but in the destructive
    // colour: this is the one button here that loses the work, and nothing
    // else on screen says so.
    AppButton(
      variant: AppButtonVariant.ghost,
      onPressed: () => pop(_LeaveChoice.discard),
      child: Text(AppStrings.leaveTemporaryDiscard, style: TextStyle(color: colors.destructive)),
    ),
    // Every other button here leaves. Staying was reachable only by pressing
    // Escape, which is not visible anywhere — and when there is nowhere to
    // save, that made a red "Discard" the only thing on offer. Popping null
    // lands in the same branch a dismissal does.
    AppButton(
      variant: AppButtonVariant.ghost,
      onPressed: () => Navigator.of(context).pop(),
      child: const Text(AppStrings.leaveTemporaryKeepEditing),
    ),
  ];
}

/// Asks what to do with a temporary project before leaving it, and carries the
/// answer out.
///
/// Templates and assistant-built projects live in a throwaway folder under the
/// system temp directory. Leaving one loses it with no warning and no undo,
/// which is the worst moment to be quiet — the user has just spent time on it.
///
/// Returns whether to go ahead and leave. False means stay put: either the
/// user cancelled, or a save they asked for did not happen (they dismissed the
/// folder picker, or the upload failed), and leaving anyway would throw the
/// work away behind their back.
Future<bool> confirmLeavingTemporaryProject(BuildContext context, WidgetRef ref) async {
  final state = ref.read(workspaceFilesProvider);
  // A saved project is already somewhere the user can find it again.
  if (state.workspacePath == null || !state.isTemporary) return true;

  final auth = ref.read(authServiceProvider);
  final canSaveToCloud = auth.enabled && auth.currentUser != null;
  final canSaveToComputer = PlatformCapabilities.supportsLocalFilesystem;

  final choice = await showAppDialog<_LeaveChoice>(
    context,
    // No close ✕ anywhere in an FDialog, which is what this wants: the ✕ would
    // be a fourth answer meaning none of the three. Escape and a tap outside
    // still dismiss, and both fall through to `null` below, keeping the
    // project.
    builder: (context) => AppDialog(
      title: AppStrings.leaveTemporaryTitle,
      message: canSaveToCloud || canSaveToComputer
          ? AppStrings.leaveTemporaryMessage
          : AppStrings.leaveTemporaryNowhereToSave,
      // Stacked, not in a row: three actions with labels this long overflow a
      // dialog's width, and shortening them to fit ("Cloud", "Computer") loses
      // the thing the user is actually choosing between.
      //
      // Ordered safest first. A stack of buttons is read top-down, so the one
      // that keeps the work leads and the one that throws it away is last —
      // the reverse of how this used to be, which put Discard under the
      // pointer and the primary action furthest from it.
      actionsAxis: Axis.vertical,
      actions: _leaveActions(
        context,
        canSaveToCloud: canSaveToCloud,
        canSaveToComputer: canSaveToComputer,
      ),
    ),
  );

  final files = ref.read(workspaceFilesProvider.notifier);
  switch (choice) {
    // Dismissed with Escape or a tap outside: treat it as "not now" rather
    // than as discarding, since the safe reading of an ambiguous answer is the
    // one that keeps the work.
    case null:
      return false;
    case _LeaveChoice.discard:
      return true;
    case _LeaveChoice.saveToComputer:
      // False when the folder picker was dismissed — nothing was written, so
      // leaving now would still lose it.
      return files.saveWorkspaceToLocation();
    case _LeaveChoice.saveToCloud:
      final projectId = await files.saveWorkspaceToCloud();
      if (!context.mounted) return projectId != null;
      showAppToast(
        context,
        title: projectId == null
            ? AppStrings.cloudSaveFailedTitle
            : AppStrings.cloudSaveSuccessTitle,
        message: projectId == null
            ? AppStrings.cloudSaveFailedMessage
            : AppStrings.cloudSaveSuccessMessage,
        isError: projectId == null,
      );
      return projectId != null;
  }
}
