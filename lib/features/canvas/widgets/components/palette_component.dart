import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinbench_parts/models/part_model.dart';
import 'package:pinbench_ui/theme/text.dart';
import 'package:pinbench_ui/theme/tokens.dart';
import 'package:pinbench_ui/ui/app_card.dart';
import 'package:pinbench_ui/theme/app_colors.dart';

import '../../providers/canvas_controller_provider.dart';
import 'component_widget.dart';

class const PaletteComponent({super.key, required final PartModel part}) extends ConsumerWidget {
  /// The tile art, padded so the part's *body* lands in the middle of the tile
  /// rather than its bounding box.
  ///
  /// Those are not the same thing vertically. A part's bounds run out to
  /// wherever its leads meet the connection lattice, and for a through-hole
  /// part the leads all leave from one side: an LED's lens sits in the top
  /// three quarters of its box with two thin legs below, so centring the box
  /// leaves the lens visibly high while a resistor — body centred between its
  /// leads — sits square. Padding the short side moves the body to the middle
  /// without touching the geometry the canvas relies on.
  ///
  /// Horizontally there is deliberately no such correction. Every part's body
  /// is centred across its bounds by construction — its leads are placed
  /// symmetrically about it so they land on the lattice — so a sideways
  /// correction would always be zero, and the only thing a non-zero one could
  /// do is shove the art off centre. The [FittedBox] centres the box, and for
  /// x that is already the right answer.
  Widget _art() {
    final child = ComponentWidget(part: part);
    final body = part.getPainter()?.bodyRect(part.size);
    if (body == null) return child; // fills its bounds; already centred

    // Pad whichever end moves the padded box's centre onto the body's.
    final dy = 2 * body.center.dy - part.size.height;
    if (dy == 0) return child;

    return Padding(
      padding: EdgeInsets.only(top: dy < 0 ? -dy : 0, bottom: dy > 0 ? dy : 0),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => AppCard(
    padding: EdgeInsets.zero,
    child: Draggable<String>(
      data: part.name,
      // Anchor the top-left of the 100x100 ghost image exactly at the cursor
      dragAnchorStrategy: pointerDragAnchorStrategy,
      // The feedback subtree is only inflated when a drag starts, so read
      // the canvas zoom inside a Builder to get the scale AT DRAG TIME.
      // Reading it in build() instead captures a stale value: the palette
      // is built before the canvas runs its initial fit-to-content zoom,
      // and nothing rebuilds the tile when the zoom changes afterwards —
      // which made the ghost render huge until a sidebar resize forced a
      // rebuild.
      feedback: Builder(
        builder: (context) {
          final scale = ref.read(canvasControllerProvider.notifier).scale;
          return Transform.scale(
            scale: scale,
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: part.size.width,
              height: part.size.height,
              child: ComponentWidget(part: part),
            ),
          );
        },
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ClipRect(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: FittedBox(child: _art()),
              ),
            ),
          ),
          Container(
            height: 30,
            padding: const EdgeInsets.all(AppSpacing.md),
            color: context.appColors.primary,
            alignment: Alignment.center,
            child: Text(
              part.name,
              maxLines: 1,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.smallOnPrimary(context),
            ),
          ),
        ],
      ),
    ),
  );
}
