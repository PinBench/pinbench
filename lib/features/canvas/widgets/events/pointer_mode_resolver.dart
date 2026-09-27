import 'package:pinbench_parts/models/port_model.dart';

import 'pointer_interaction_mode.dart';

/// Resolves a pointer-down into one of the four modes that don't depend on
/// `SelectionManager.checkSelection()`'s side effects, given a snapshot of
/// the canvas/wiring state at the moment of the click. Pure — no controller
/// reference, no mutation — so it's directly unit-testable. See
/// `PointerInteractionMode`'s doc comment for why the remaining three modes
/// aren't resolved here.
abstract final class PointerModeResolver {
  static PointerInteractionMode resolveForPointerDown({
    required bool isReadOnly,
    required bool isWiring,
    required bool isDoubleClick,
    required String? hoveredWireId,
    required PortLocation? hoveredPort,
  }) {
    if (isReadOnly) return PointerInteractionMode.readOnlyTap;
    if (isWiring) return PointerInteractionMode.continueWiring;
    if (isDoubleClick && hoveredWireId != null) return PointerInteractionMode.toggleBendPoint;
    if (hoveredPort != null) return PointerInteractionMode.startWiring;
    return PointerInteractionMode.needsSelectionCheck;
  }
}
