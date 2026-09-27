import 'package:flutter/widgets.dart';

import 'package:forui/forui.dart';

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
void showAppToast(
  BuildContext context, {
  String? title,
  required String message,
  bool isError = false,
}) {
  final variant = isError ? FToastVariant.destructive : FToastVariant.primary;
  showFToast(
    context: context,
    variant: variant,
    title: Text(title ?? message),
    description: title == null ? null : Text(message),
  );
}
