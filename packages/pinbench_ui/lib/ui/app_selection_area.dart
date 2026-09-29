import 'package:flutter/widgets.dart';

/// Makes the text inside [child] selectable with the mouse.
///
/// Replaces `SelectionArea` and `SelectableText`, both of which left the SDK
/// with the rest of Material in Flutter 3.47. The framework kept the widget
/// that does the actual work — [SelectableRegion] — and moved only the
/// convenience wrapper that picks per-platform *touch handles* for it.
///
/// This app never wanted those: the draggable dots either side of a selection
/// are a touch affordance, and every surface that selects text here — the log
/// panes, the consoles, the side panel — is a desktop pane driven by a
/// mouse. So it passes [emptyTextSelectionControls] and the selection looks
/// the way it already did.
class const AppSelectionArea({super.key, required final Widget child}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      SelectableRegion(selectionControls: emptyTextSelectionControls, child: child);
}

/// A run of selectable text.
///
/// The [AppSelectionArea] equivalent of the old `SelectableText`: same
/// arguments as a plain [Text], and you can drag across it.
class const AppSelectableText(
  final String data, {
  super.key,
  final TextStyle? style,
  final TextAlign? textAlign,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => AppSelectionArea(
    child: Text(data, style: style, textAlign: textAlign),
  );
}
