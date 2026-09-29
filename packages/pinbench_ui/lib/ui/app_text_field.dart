import 'package:flutter/widgets.dart';

import 'package:forui/forui.dart';

/// A single-line text input.
///
/// Wraps the widget library so the rest of the app never names it. The
/// parameters are the app's: [placeholder] rather than a `hint` widget,
/// [onChanged]/[onSubmitted] rather than forui's `onChange`/`onSubmit`, and a
/// plain [controller] rather than the `FTextFieldControl` forui wraps one in.
///
/// There is deliberately no per-context decoration object. If a surface turns
/// out to need a different look, add a named variant here — the point is that
/// it is named once, not spelled out at the call site.
class AppTextField extends StatelessWidget {
  const new({
    super.key,
    this.controller,
    this.initialValue,
    this.placeholder,
    this.enabled = true,
    this.autofocus = false,
    this.obscureText = false,
    this.focusNode,
    this.textAlign = TextAlign.start,
    this.keyboardType,
    this.onChanged,
    this.onSubmitted,
  }) : minLines = null,
       maxLines = 1;

  /// A box that grows with what is typed into it — the two prompt composers.
  ///
  /// A named constructor rather than a separate widget because the underlying
  /// field is the same one; only the line count differs. Both composers bind
  /// Enter to submit themselves, so this deliberately has no [onSubmitted] —
  /// a multiline field's Enter belongs to the text.
  ///
  /// Sized in [minLines] rather than a pixel height — the same intent in the
  /// unit that survives a font change. Neither composer wants a drag handle,
  /// so there is no resize affordance.
  const new multiline({
    super.key,
    this.controller,
    this.initialValue,
    this.placeholder,
    this.enabled = true,
    this.autofocus = false,
    this.focusNode,
    this.textAlign = TextAlign.start,
    this.keyboardType,
    this.onChanged,
    this.minLines = 3,
    this.maxLines,
  }) : obscureText = false,
       onSubmitted = null;

  final TextEditingController? controller;

  /// Starting text when no [controller] is supplied.
  final String? initialValue;

  final String? placeholder;
  final bool enabled;
  final bool autofocus;

  /// Masks the text — for API keys and passwords.
  final bool obscureText;

  /// Supply one when the surface drives focus itself.
  final FocusNode? focusNode;
  final TextAlign textAlign;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// Lines the box shows before it starts scrolling. One for a plain field.
  final int? minLines;

  /// Lines it grows to. Null on a multiline field means it keeps growing.
  final int? maxLines;

  @override
  Widget build(BuildContext context) => FTextField(
    // forui manages the controller through a `control` rather than taking one
    // directly; `managed` hands it ours while keeping its own lifecycle, and
    // covers the initial-value case when there is no controller.
    control: FTextFieldControl.managed(
      controller: controller,
      initial: initialValue == null ? null : TextEditingValue(text: initialValue!),
      onChange: onChanged == null ? null : (value) => onChanged!(value.text),
    ),
    hint: placeholder,
    enabled: enabled,
    autofocus: autofocus,
    obscureText: obscureText,
    focusNode: focusNode,
    textAlign: textAlign,
    keyboardType: keyboardType,
    minLines: minLines,
    maxLines: maxLines,
    onSubmit: onSubmitted,
  );
}
