import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench_parts/painting/part_painter_registry.dart';
import 'package:pinbench_parts/painting/path_art.dart';
import 'package:pinbench_parts/part_registry.dart';

/// A `.pdl` part's `SIZE` and its painter's artwork are written in two places;
/// these keep them agreeing.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(PartRegistry.initializeAsync);

  test("every PAINTER a part names exists, and is drawn at the part's SIZE", () {
    final painted = PartRegistry.getAllParts().where((d) => d.visual.painter != null).toList();
    expect(painted, isNotEmpty);
    for (final definition in painted) {
      final builder = PartPainterRegistry.find(definition.visual.painter!);
      expect(builder, isNotNull, reason: '${definition.id} names "${definition.visual.painter}"');
      final painter = builder!();
      if (painter is! PathArtPainter) continue;
      // SIZE is authored in millimetres, so compare to a hundredth of a pixel.
      final reason = '${definition.id}: SIZE and the painter disagree, so the art is stretched';
      expect(painter.designSize.width, closeTo(definition.visual.width, 0.01), reason: reason);
      expect(painter.designSize.height, closeTo(definition.visual.height, 0.01), reason: reason);
    }
  });
}
