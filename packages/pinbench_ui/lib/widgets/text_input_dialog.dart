import 'package:flutter/widgets.dart';

import '../strings.dart';
import '../ui/app_button.dart';
import '../ui/app_dialog.dart';
import '../ui/app_text_field.dart';

/// Shows a small modal asking the user for a single line of text (e.g. a file
/// name). Returns the trimmed value, or null if cancelled / left empty.
Future<String?> showTextInputDialog(
  BuildContext context, {
  required String title,
  String? placeholder,
  String confirmLabel = AppStrings.confirmDialogDefaultLabel,
  String initialValue = '',
}) {
  final controller = TextEditingController(text: initialValue);
  return showAppDialog<String>(
    context,
    builder: (context) => AppDialog(
      title: title,
      child: AppTextField(
        controller: controller,
        placeholder: placeholder,
        autofocus: true,
        onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
      ),
      actions: [
        AppButton(
          variant: AppButtonVariant.outline,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(AppStrings.cancelButtonLabel),
        ),
        AppButton(
          onPressed: () => Navigator.of(context).pop(controller.text.trim()),
          child: Text(confirmLabel),
        ),
      ],
    ),
  ).then((value) => (value == null || value.isEmpty) ? null : value);
}
