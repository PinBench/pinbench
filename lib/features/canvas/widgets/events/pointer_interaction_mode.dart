/// The modes `PointerModeResolver.resolveForPointerDown` can resolve up
/// front, purely from the current hover/wiring state at the moment of a
/// pointer-down — no side effects needed to tell them apart.
///
/// [needsSelectionCheck] is the escape hatch for the remaining ambiguous
/// case: whether a click resolves to a bend-point drag, a node selection, or
/// a box selection depends on `SelectionManager.checkSelection()`'s side
/// effects (it mutates the selection), so those three can't be told apart
/// without running it. Duplicating that decision in a separate pure resolver
/// would just recreate the two-copies-of-the-same-logic problem this
/// refactor exists to remove elsewhere — see [PostSelectionMode] and
/// `_CanvasPointerEventState._handleAfterSelectionCheck`.
enum PointerInteractionMode {
  /// The canvas is read-only (a simulation is running): only push-button
  /// parts respond to a press.
  readOnlyTap,

  /// A wire is already being dragged from a start port; this click finishes
  /// or cancels it.
  continueWiring,

  /// Double-click on a hovered wire: toggles a bend point at that point.
  toggleBendPoint,

  /// Click on a free port: starts a new wire (or detaches+redrags an
  /// existing one).
  startWiring,

  /// Ambiguous until `SelectionManager.checkSelection()` runs — resolves to
  /// one of [PostSelectionMode]'s values.
  needsSelectionCheck,
}

/// The modes a [PointerInteractionMode.needsSelectionCheck] pointer-down
/// resolves to once `SelectionManager.checkSelection()` has run. Purely
/// documentation/labels for `_handleAfterSelectionCheck`'s branches — this
/// stage is inherently sequential (each branch's condition depends on
/// selection state the previous branch may have just changed), so it isn't
/// switched over the way [PointerInteractionMode] is.
enum PostSelectionMode {
  /// Click on an already-selected, hovered wire: starts dragging one of its
  /// bend points/segments.
  startBendPointDrag,

  /// Click on a node (including a push-button, which also toggles pressed).
  nodeSelect,

  /// Click on empty space with nothing selected: starts a box selection.
  boxSelect,
}
