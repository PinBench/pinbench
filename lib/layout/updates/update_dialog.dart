import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinbench_ui/strings.dart';
import 'package:pinbench_ui/ui/app_button.dart';
import 'package:pinbench_ui/ui/app_dialog.dart';

import '../../core/updates/update_providers.dart';
import 'update_panel.dart';

/// Opens the update dialog and starts a check straight away.
///
/// Backs "Check for Updates…" on both menus and the title-bar badge. The
/// check fires without waiting to be asked twice: the menu item is already
/// the request, and a dialog whose only content is a button saying "check"
/// makes the user press the same thing again.
Future<void> showUpdateDialog(BuildContext context, WidgetRef ref) {
  unawaited(ref.read(updateControllerProvider.notifier).checkNow());
  return showAppDialog<void>(
    context,
    builder: (context) => AppDialog(
      title: AppStrings.updatesDialogTitle,
      // The panel already renders the version, the status and the actions, so
      // the dialog is a frame around it plus a way out.
      child: const UpdatePanel(showAutomaticToggle: false),
      actions: [
        AppButton(
          variant: AppButtonVariant.outline,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(AppStrings.closeButtonLabel),
        ),
      ],
    ),
  );
}
