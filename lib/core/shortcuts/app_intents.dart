import 'package:flutter/widgets.dart';

/// Every keyboard-shortcut [Intent] in the app, in one place.
///
/// It was `features/canvas/managers/canvas_intents.dart`, which was never true:
/// the file has a section headed "App-chrome intents (handled globally in
/// AppShortcuts)" in it, and `SaveIntent` is what the code editor invokes when
/// you press Cmd-S with focus in a text buffer. Three layers declare handlers
/// for these — the canvas, the editor, and the global shortcut map in `shell/`
/// — so they belong under none of them.
///
/// They are marker classes with no behaviour. What a shortcut *does* is decided
/// by whichever `Actions` scope is nearest the focus, which is the point: the
/// canvas and the editor both answer to `UndoIntent`, differently.

class UndoIntent extends Intent {
  const UndoIntent();
}

class RedoIntent extends Intent {
  const RedoIntent();
}

class CopyIntent extends Intent {
  const CopyIntent();
}

class PasteIntent extends Intent {
  const PasteIntent();
}

class DuplicateIntent extends Intent {
  const DuplicateIntent();
}

class DeleteIntent extends Intent {
  const DeleteIntent();
}

class SaveIntent extends Intent {
  const SaveIntent();
}

class OpenIntent extends Intent {
  const OpenIntent();
}

class NewIntent extends Intent {
  const NewIntent();
}

class ToggleSimulationIntent extends Intent {
  const ToggleSimulationIntent();
}

class PauseSimulationIntent extends Intent {
  const PauseSimulationIntent();
}

class ZoomInIntent extends Intent {
  const ZoomInIntent();
}

class ZoomOutIntent extends Intent {
  const ZoomOutIntent();
}

class PanUpIntent extends Intent {
  const PanUpIntent();
}

class PanDownIntent extends Intent {
  const PanDownIntent();
}

class PanLeftIntent extends Intent {
  const PanLeftIntent();
}

class PanRightIntent extends Intent {
  const PanRightIntent();
}

class CancelWiringIntent extends Intent {
  const CancelWiringIntent();
}

class RotateRightIntent extends Intent {
  const RotateRightIntent();
}

class RotateLeftIntent extends Intent {
  const RotateLeftIntent();
}

class FlipHorizontalIntent extends Intent {
  const FlipHorizontalIntent();
}

class FlipVerticalIntent extends Intent {
  const FlipVerticalIntent();
}

class LayerUpIntent extends Intent {
  const LayerUpIntent();
}

class LayerDownIntent extends Intent {
  const LayerDownIntent();
}

class ToggleGridIntent extends Intent {
  const ToggleGridIntent();
}

class ResetViewIntent extends Intent {
  const ResetViewIntent();
}

// --- App-chrome intents (handled globally in AppShortcuts) ---------------

class ToggleLeftPaneIntent extends Intent {
  const ToggleLeftPaneIntent();
}

class ToggleBottomPaneIntent extends Intent {
  const ToggleBottomPaneIntent();
}

class ToggleRightPaneIntent extends Intent {
  const ToggleRightPaneIntent();
}

class ToggleThemeIntent extends Intent {
  const ToggleThemeIntent();
}

class ExportCircuitIntent extends Intent {
  const ExportCircuitIntent();
}

class ViewCodeIntent extends Intent {
  const ViewCodeIntent();
}

class CloseTabIntent extends Intent {
  const CloseTabIntent();
}

class GoHomeIntent extends Intent {
  const GoHomeIntent();
}

/// Opens app settings. ⌘, is the shortcut every editor on this platform uses
/// for it, and settings is a tab here, so it opens one.
class OpenSettingsIntent extends Intent {
  const OpenSettingsIntent();
}
