import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench_parts/part_registry.dart';
import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench/features/canvas/widgets/painters/wire_painter.dart';
import 'package:pinbench_parts/models/part_model.dart';
import 'package:pinbench_parts/models/port_model.dart';
import 'package:pinbench_ui/theme/testing.dart';

/// A wire with one end in hand is still the wire you selected — it just can't
/// sit in the wire list while an end is off a port. So it has to keep looking
/// like itself: full strength, and a handle on every point, exactly as when a
/// bend point is being dragged. Anything less reads as "my wire disappeared and
/// I'm drawing a new one".
PartModel _model(String name) => standardParts.firstWhere((c) => c.name == name);

void main() {
  testWidgets('a wire in flight draws a handle on every point', (tester) async {
    final led = ComponentInstance(part: _model(PartNames.led), position: const Offset(100, 100));
    final anode = led.position + led.getPortOffset('anode')!;
    const bend = Offset(200, 140);
    const inHand = Offset(260, 180);

    await tester.pumpWidget(
      appTestApp(
        CustomPaint(
          size: const Size(400, 400),
          painter: WirePainter(
            wires: const [],
            nodes: [led],
            pendingStart: PortLocation(nodeKey: led.key, portId: 'anode'),
            pendingEndMouse: inHand,
            pendingBendPoints: const [bend],
            isMovingExistingWire: true,
          ),
        ),
      ),
    );

    // The pinned end, the bend it turns at, and the end following the pointer.
    // Each handle is a white fill plus a coloured border — two circles a piece,
    // the same pair `_drawHandles` draws for a selected wire's own handles.
    expect(
      find.byType(CustomPaint).first,
      paints
        ..circle(x: anode.dx, y: anode.dy, radius: 3.5)
        ..circle(x: anode.dx, y: anode.dy, radius: 3.5)
        ..circle(x: bend.dx, y: bend.dy, radius: 3.5)
        ..circle(x: bend.dx, y: bend.dy, radius: 3.5)
        ..circle(x: inHand.dx, y: inHand.dy, radius: 3.5)
        ..circle(x: inHand.dx, y: inHand.dy, radius: 3.5),
    );
  });
}
