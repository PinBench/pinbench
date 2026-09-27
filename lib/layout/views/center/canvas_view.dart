import 'package:flutter/widgets.dart';

import '../../../features/canvas/widgets/core/canvas_area.dart';
import '../../../features/canvas/widgets/controls/simulation_controls.dart';
import '../../../features/canvas/widgets/controls/toolbar.dart';
import '../../../features/canvas/widgets/controls/zoom_controls.dart';
import '../../../features/canvas/widgets/controls/minimap_view.dart';

class CanvasView extends StatelessWidget {
  const CanvasView({super.key});

  @override
  Widget build(BuildContext context) => const Stack(
    children: [CanvasArea(), SimulationControls(), CanvasToolbar(), ZoomControls(), MinimapView()],
  );
}
