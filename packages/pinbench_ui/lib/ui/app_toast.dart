import 'package:flutter/widgets.dart';

import 'package:forui/forui.dart';

import 'app_button.dart';

/// Shows a toast.
///
/// Wraps [showFToast] for two reasons. It keeps the thirty-odd call sites from
/// each spelling out a `context:`/`variant:` pair, and it absorbs a small
/// mismatch: forui requires a `title`, while a handful of the app's toasts are
/// a single line of explanation with no headline. Those pass [message] alone
/// and it becomes the title, which is what a one-line toast should be anyway.
///
/// [isError] picks the destructive styling. Prefer it over composing the
/// variant at the call site, so "this failed" looks the same everywhere.
///
/// [action] adds a button at the toast's end; pressing it closes the toast,
/// then runs [ToastAction.onPressed]. A toast with a button stays up longer
/// unless [duration] says otherwise — reading it and deciding takes longer
/// than reading it.
void showAppToast(
  BuildContext context, {
  String? title,
  required String message,
  bool isError = false,
  ToastAction? action,
  Duration? duration,
}) {
  final variant = isError ? FToastVariant.destructive : FToastVariant.primary;
  showFToast(
    context: context,
    variant: variant,
    title: Text(title ?? message),
    description: title == null ? null : Text(message),
    duration: duration ?? (action == null ? _plainDuration : _actionDuration),
    suffixBuilder: action == null
        ? null
        : (context, entry) => AppButton(
            size: AppButtonSize.sm,
            onPressed: () {
              entry.dismiss();
              action.onPressed();
            },
            child: Text(action.label),
          ),
  );
}

/// forui's own default, kept for toasts without a button.
const _plainDuration = Duration(seconds: 5);
const _actionDuration = Duration(seconds: 12);

/// A toast's button: what it says, and what it does.
class const ToastAction({required final String label, required final VoidCallback onPressed});
