import 'package:flutter/widgets.dart';

import 'package:forui/forui.dart';

/// An on/off toggle.
///
/// Wraps the widget library so the rest of the app never names it. Controlled,
/// like `AppSelect`: the value belongs to whatever the switch is a view of,
/// and one that remembered its own answer would drift from it.
class const AppSwitch({
  super.key,
  required final bool value,
  required final ValueChanged<bool> onChanged,
  final bool enabled = true,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => FSwitch(
    value: value,
    onChange: onChanged,
    enabled: enabled,
    // The underlying switch is built to sit beside a label and reserves a gap
    // for one even when there is none. This switch never has one — callers put
    // their own text in their own row — so the gap is 24px of nothing, which a
    // narrow sidebar cannot spare.
    style: const FSwitchStyleDelta.delta(
      trailingLabelStyle: FLabelStyleDelta.delta(
        childPadding: EdgeInsetsGeometryDelta.value(EdgeInsets.zero),
      ),
    ),
  );
}
