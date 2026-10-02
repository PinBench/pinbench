import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:pinbench_ui/theme/app_colors.dart';
import 'package:pinbench_ui/theme/tokens.dart';

/// The name of the pin under the pointer, in a small chip just above it.
///
/// Every part's ports have names — `GP15`, `GND`, `VBUS`, an LED's `Anode`,
/// a breadboard's `Terminal Strip left A12` — and until this the canvas
/// showed none of them: hovering only ringed the hole, so finding GP15 on a
/// Pico meant counting pins. Shown while a wire is being drawn too, because
/// the pin under the pointer then is exactly the one about to be connected.
///
/// Laid out in screen space, over the canvas rather than inside it, so it
/// stays the same size at every zoom: drawn in canvas space it would be
/// unreadable zoomed out and a slab zoomed in. [viewer] is the canvas's
/// transform, and the chip follows it through pans and zooms without the
/// canvas rebuilding.
///
/// It takes no pointer events, so it never sits between the pointer and the
/// pin it names.
class const PortHoverLabel({
  super.key,
  required final String name,

  /// The pin's position in canvas coordinates.
  required final Offset canvasPosition,

  /// The canvas's pan-and-zoom transform.
  required final ValueListenable<Matrix4> viewer,
}) extends StatelessWidget {
  /// Clearance between the pin and the chip's bottom edge: clear of the hover
  /// ring the wire painter draws around the pin.
  static const gap = 12.0;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Matrix4>(
    valueListenable: viewer,
    builder: (context, transform, _) {
      final pin = MatrixUtils.transformPoint(transform, canvasPosition);
      return Positioned(
        left: pin.dx,
        top: pin.dy - gap,
        child: IgnorePointer(
          // Centred over the pin and sitting on top of it, whatever the
          // chip's width — no measuring needed.
          child: FractionalTranslation(
            translation: const Offset(-0.5, -1),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: context.appColors.surface,
                border: Border.all(color: context.appColors.border),
                borderRadius: AppRadii.smAll,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xxs,
                ),
                child: Text(
                  name,
                  maxLines: 1,
                  style: context.appText.xs.copyWith(color: context.appColors.foreground),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
