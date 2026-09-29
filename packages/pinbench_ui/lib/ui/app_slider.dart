import 'package:flutter/widgets.dart';

import 'package:forui/forui.dart';

/// A track you drag to pick a fraction between 0 and 1.
///
/// Wraps the widget library so the rest of the app never names it. The one
/// caller is a component property — a potentiometer's turn, a servo's angle —
/// which is always a fraction, so this deliberately has no min/max: a range
/// nothing asks for is a range nothing has ever rendered.
///
/// forui models a slider as a *span* with a `min` and a `max` offset, since the
/// same widget does range selection. A single-thumb slider is that span pinned
/// at zero, which is why the value goes in and comes out as [FSliderValue.max].
class AppSlider extends StatelessWidget {
  const AppSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.onChangeEnd,
    this.enabled = true,
  });

  /// Where the thumb sits, 0 to 1.
  final double value;

  /// Fires continuously while dragging.
  final ValueChanged<double> onChanged;

  /// Fires once the drag ends.
  ///
  /// Separate from [onChanged] because the caller records undo history and
  /// re-solves the circuit here, and doing that per frame of a drag would
  /// bury the undo stack.
  final ValueChanged<double>? onChangeEnd;

  final bool enabled;

  @override
  Widget build(BuildContext context) => FSlider(
    enabled: enabled,
    control: FSliderControl.managedContinuous(
      initial: FSliderValue(max: value),
      onChange: (value) => onChanged(value.max),
    ),
    onEnd: onChangeEnd == null ? null : (value) => onChangeEnd!(value.max),
  );
}
