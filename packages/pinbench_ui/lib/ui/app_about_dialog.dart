import 'package:flutter/widgets.dart';

import '../strings.dart';
import 'app_button.dart';
import 'app_dialog.dart';

/// "About this app": the name, the running version, and a way out.
///
/// Replaces `showAboutDialog`, which left the SDK with the rest of Material in
/// Flutter 3.47. What is not carried over is its "View licenses" button: that
/// pushed `LicensePage`, a Material screen, and rebuilding one here would be a
/// second screen's worth of UI for a link nobody has asked for. The licences
/// are still registered with `LicenseRegistry` either way, so nothing was lost
/// but the button — say so out loud if it is ever wanted back.
Future<void> showAboutAppDialog(
  BuildContext context, {
  required String applicationName,

  /// The running build, when the caller knows it. Omitted rather than shown as
  /// "unknown" — a blank line reads better than a wrong one.
  String? version,
}) => showAppDialog<void>(
  context,
  builder: (context) => AppDialog(
    title: applicationName,
    message: version,
    actions: [
      AppButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text(AppStrings.closeButtonLabel),
      ),
    ],
  ),
);
