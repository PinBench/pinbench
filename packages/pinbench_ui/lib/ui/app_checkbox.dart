import 'package:flutter/widgets.dart';

import 'package:forui/forui.dart';

/// A box to tick, with its label beside it; the label toggles it too.
///
/// Wraps the widget library so the rest of the app never names it. Controlled,
/// like `AppSwitch`: the value belongs to
/// whatever the box is a view of.
class const AppCheckbox({
  super.key,
  required final bool value,
  required final ValueChanged<bool> onChanged,
  required final String label,
  final bool enabled = true,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      FCheckbox(value: value, onChange: onChanged, enabled: enabled, label: Text(label));
}
