import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

import '../ui/app_icon_button.dart';
import '../strings.dart';
import '../theme/tokens.dart';
import '../ui/app_text_field.dart';
import '../theme/app_icons.dart';

class ScrubbableNumberField extends StatefulWidget {
  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final VoidCallback? onReset;
  final double? defaultValue;

  const ScrubbableNumberField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.onReset,
    this.defaultValue,
  });

  @override
  State<ScrubbableNumberField> createState() => _ScrubbableNumberFieldState();
}

class _ScrubbableNumberFieldState extends State<ScrubbableNumberField> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  var _currentValue = 0.0;
  var _isDragging = false;

  @override
  void initState() {
    super.initState();
    _currentValue = widget.value;
    _controller = TextEditingController(text: _formatValue(_currentValue));
    _focusNode = FocusNode();

    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        _controller.selection = TextSelection(baseOffset: 0, extentOffset: _controller.text.length);
      } else {
        // Apply value when focus is lost
        if (!_isDragging) {
          _handleSubmitted(_controller.text);
        }
      }
    });
  }

  @override
  void didUpdateWidget(covariant ScrubbableNumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && !_isDragging && !_focusNode.hasFocus) {
      _currentValue = widget.value;
      final newText = _formatValue(_currentValue);
      if (_controller.text != newText) {
        _controller.text = newText;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  String _formatValue(double val) => val.toStringAsFixed(1);

  void _handleDragStart(DragStartDetails details) {
    _isDragging = true;
    _currentValue = widget.value;
    _focusNode.unfocus();
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    setState(() {
      // Hold Shift for 10x faster scrubbing
      final isShiftPressed =
          HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.shiftLeft) ||
          HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.shiftRight);
      final multiplier = isShiftPressed ? 5.0 : 0.5;

      _currentValue += details.delta.dx * multiplier;
      _controller.text = _formatValue(_currentValue);
    });
    widget.onChanged(_currentValue);
  }

  void _handleDragEnd(DragEndDetails details) {
    _isDragging = false;
    widget.onChanged(_currentValue);
  }

  void _handleSubmitted(String val) {
    final numVal = double.tryParse(val);
    if (numVal != null) {
      widget.onChanged(numVal);
    } else {
      // Revert text to actual value if invalid input
      _controller.text = _formatValue(widget.value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final showResetButton =
        widget.defaultValue != null &&
        (widget.value - widget.defaultValue!).abs() > 0.01 &&
        widget.onReset != null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeLeftRight,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: _handleDragStart,
                onHorizontalDragUpdate: _handleDragUpdate,
                onHorizontalDragEnd: _handleDragEnd,
                onDoubleTap: showResetButton ? widget.onReset : null,
                // Shortened rather than wrapped: the field beside it is a
                // fixed width, so a label that wraps doubles the row's height
                // and breaks mid-word doing it.
                child: Text(widget.label, overflow: TextOverflow.ellipsis, softWrap: false),
              ),
            ),
          ),
          Gap.hMd,
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showResetButton) ...[
                AppIconButton(
                  icon: AppIcons.rotateLeft,
                  tooltip: AppStrings.resetToDefaultTooltip,
                  onPressed: widget.onReset,
                ),
                Gap.hMd,
              ],
              SizedBox(
                width: 70,
                // height: 30,
                child: AppTextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  textAlign: TextAlign.right,
                  onSubmitted: _handleSubmitted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
