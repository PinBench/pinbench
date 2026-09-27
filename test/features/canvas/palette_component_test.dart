import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:pinbench_parts/part_registry.dart';
import 'package:pinbench/features/canvas/providers/canvas_controller_provider.dart';
import 'package:pinbench/features/canvas/widgets/components/component_widget.dart';
import 'package:pinbench/features/canvas/widgets/components/palette_component.dart';
import 'package:pinbench_parts/models/part_model.dart';
import '../../support/harness.dart';

/// Regression test: the drag ghost's scale must be read when the drag STARTS,
/// not when the palette tile is built. On first launch the palette builds
/// before the canvas runs its initial fit-to-content zoom; a build-time read
/// captured that stale scale and rendered a huge ghost until a sidebar resize
/// happened to rebuild the tile.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('drag ghost uses the canvas zoom at drag time, not at tile build time', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(canvasControllerProvider.notifier);
    final model = standardParts.firstWhere((c) => c.name == PartNames.resistor);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: appTestApp(
          Center(
            child: SizedBox(width: 160, height: 240, child: PaletteComponent(part: model)),
          ),
        ),
      ),
    );

    // Zoom changes AFTER the tile was built — as the canvas's initial
    // fit-to-content does on app launch.
    controller.viewerController.value = Matrix4.diagonal3Values(0.5, 0.5, 0.5);

    final gesture = await tester.startGesture(tester.getCenter(find.byType(PaletteComponent)));
    await gesture.moveBy(const Offset(40, 40));
    await tester.pump();

    expect(
      find.byType(ComponentWidget),
      findsNWidgets(2),
      reason: 'tile + drag ghost should both be in the tree during the drag',
    );

    // The ghost is a ComponentWidget wrapped in our Transform.scale. With the
    // old build-time scale read no Transform anywhere carried the new zoom,
    // so asserting one exists pins the drag-time read. (Compare the x-axis
    // entry: Transform.scale leaves z at 1.0, so getMaxScaleOnAxis is
    // useless here.)
    final transformScales = find
        .byType(Transform)
        .evaluate()
        .map((e) => (e.widget as Transform).transform.entry(0, 0))
        .toList();
    expect(
      transformScales,
      contains(closeTo(0.5, 0.001)),
      reason: 'ghost must use the zoom in effect when the drag started',
    );

    await gesture.up();
    await tester.pump();
  });

  testWidgets('every tile centres the part on its body, not its bounds', (tester) async {
    // A through-hole part's leads all leave from one side, so its bounding box
    // is lopsided around the thing you actually see: an LED's lens sat visibly
    // high in its tile next to a resistor, whose body is centred between its
    // leads. Tiles centre the body instead.
    //
    // Swept across tile shapes, because the centring has to survive both
    // fitting regimes: a tile can be wide enough that the art is limited by
    // its height, or tall enough that it's limited by its width, and the
    // padding that does the centring changes which one applies.
    const tileSizes = [
      Size(129, 219), // the palette's own 0.6 aspect, three columns
      Size(100, 167),
      Size(253, 420),
      Size(129, 140), // squat: height-limited
      Size(300, 200), // wide
    ];

    for (final model in standardParts) {
      final body = model.getPainter()?.bodyRect(model.size);
      if (body == null) continue; // fills its bounds — nothing to correct

      for (final size in tileSizes) {
        await tester.pumpWidget(
          ProviderScope(
            child: appTestApp(
              Center(
                child: SizedBox(
                  width: size.width,
                  height: size.height,
                  child: PaletteComponent(part: model),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        final art = tester.getRect(
          find.descendant(of: find.byType(FittedBox), matching: find.byType(CustomPaint)).first,
        );
        final tile = tester.getRect(find.byType(FittedBox));

        // Where the body lands on screen, mapped through the tile's own scale.
        final scale = art.width / model.size.width;
        final bodyCentre = art.topLeft + body.center * scale;
        final where = '${model.name} in a ${size.width}x${size.height} tile';

        expect(bodyCentre.dy, closeTo(tile.center.dy, 0.5), reason: '$where: body y');

        // Sideways the tile centres the *art*, never the body, so this only
        // holds for a part whose body is centred within its own bounds — which
        // is most of them, since leads are placed symmetrically about the body
        // to land on the lattice. The servo is the exception: its pins have to
        // sit on the lattice and its box is an even number of pitches wide, so
        // the whole part is drawn half a cell off its box's centre line. A
        // tile that corrected for that would be shifting art sideways, which
        // is exactly what the check below forbids.
        if ((2 * body.center.dx - model.size.width).abs() < 0.001) {
          expect(bodyCentre.dx, closeTo(tile.center.dx, 0.5), reason: '$where: body x');
        }

        // Sideways, the art itself has to sit dead centre: equal air on both
        // sides. Nothing in the tile may ever pad one side only — that is what
        // an off-centre part looks like, and it is invisible to a body-centre
        // check when the body is centred within the art anyway.
        expect(
          art.left - tile.left,
          closeTo(tile.right - art.right, 0.5),
          reason:
              '$where: unequal air beside the part '
              '(${(art.left - tile.left).toStringAsFixed(1)} left vs '
              '${(tile.right - art.right).toStringAsFixed(1)} right)',
        );
      }
    }
  });
}
