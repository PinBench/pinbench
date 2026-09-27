import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench/features/canvas/widgets/events/pointer_interaction_mode.dart';
import 'package:pinbench/features/canvas/widgets/events/pointer_mode_resolver.dart';
import 'package:pinbench_parts/models/port_model.dart';

/// Unit tests for the pure [PointerModeResolver], extracted from
/// `pointer_event.dart`'s `onPointerDown` branching. No widget/controller
/// needed — this is exactly the testability win the extraction was for.
void main() {
  const port = PortLocation(nodeKey: ValueKey('n1'), portId: 'anode');

  PointerInteractionMode resolve({
    bool isReadOnly = false,
    bool isWiring = false,
    bool isDoubleClick = false,
    String? hoveredWireId,
    PortLocation? hoveredPort,
  }) => PointerModeResolver.resolveForPointerDown(
    isReadOnly: isReadOnly,
    isWiring: isWiring,
    isDoubleClick: isDoubleClick,
    hoveredWireId: hoveredWireId,
    hoveredPort: hoveredPort,
  );

  test('read-only wins over every other condition', () {
    expect(
      resolve(isReadOnly: true, isWiring: true, hoveredPort: port),
      PointerInteractionMode.readOnlyTap,
    );
  });

  test('an active wiring drag continues even if a port is hovered', () {
    expect(resolve(isWiring: true, hoveredPort: port), PointerInteractionMode.continueWiring);
  });

  test('double-clicking a hovered wire toggles a bend point', () {
    expect(
      resolve(isDoubleClick: true, hoveredWireId: 'wire-1'),
      PointerInteractionMode.toggleBendPoint,
    );
  });

  test('a single click on a hovered wire does not toggle a bend point', () {
    expect(resolve(hoveredWireId: 'wire-1'), isNot(PointerInteractionMode.toggleBendPoint));
  });

  test('a hovered free port starts wiring', () {
    expect(resolve(hoveredPort: port), PointerInteractionMode.startWiring);
  });

  test('a hovered port beats a merely-hovered wire (port takes priority)', () {
    expect(resolve(hoveredWireId: 'wire-1', hoveredPort: port), PointerInteractionMode.startWiring);
  });

  test('nothing hovered and not wiring/read-only needs a selection check', () {
    expect(resolve(), PointerInteractionMode.needsSelectionCheck);
  });
}
