import 'package:flutter/widgets.dart';

import '../strings.dart';
import 'app_button.dart';
import 'app_dialog.dart';

/// Asks the user to confirm something, and returns whether they did.
///
/// There is deliberately no close ✕. A question with one offers a third answer
/// that means neither yes nor no, and the caller then has to guess what the
/// user meant. Escape and a tap outside still dismiss — both resolve to
/// `false`, the answer that changes nothing.
///
/// (forui's dialog draws no close button at all, so this comes free — the
/// guard in `app_alert_dialog_test.dart` is what keeps it that way.)
///
/// Use this for anything the user cannot undo. For a dialog that *collects*
/// something rather than confirming it, use `showTextInputDialog`.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = AppStrings.confirmButtonLabel,
  String cancelLabel = AppStrings.cancelButtonLabel,

  /// Paints the confirm button in the destructive colour. Set it whenever the
  /// action removes something — it is the last signal before the thing is gone.
  bool isDestructive = false,
}) async {
  final confirmed = await showAppDialog<bool>(
    context,
    builder: (context) => AppDialog(
      title: title,
      message: message,
      actions: [
        AppButton(
          variant: AppButtonVariant.outline,
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(cancelLabel),
        ),
        AppButton(
          variant: isDestructive ? AppButtonVariant.destructive : AppButtonVariant.primary,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  // Dismissed rather than answered — take the reading that changes nothing.
  return confirmed ?? false;
}
