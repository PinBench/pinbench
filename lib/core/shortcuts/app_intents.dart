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

class const UndoIntent() extends Intent;

class const RedoIntent() extends Intent;

class const CopyIntent() extends Intent;

class const PasteIntent() extends Intent;

class const DuplicateIntent() extends Intent;

class const DeleteIntent() extends Intent;

class const SaveIntent() extends Intent;

class const OpenIntent() extends Intent;

class const NewIntent() extends Intent;

class const ToggleSimulationIntent() extends Intent;

class const PauseSimulationIntent() extends Intent;

class const ZoomInIntent() extends Intent;

class const ZoomOutIntent() extends Intent;

class const PanUpIntent() extends Intent;

class const PanDownIntent() extends Intent;

class const PanLeftIntent() extends Intent;

class const PanRightIntent() extends Intent;

class const CancelWiringIntent() extends Intent;

class const RotateRightIntent() extends Intent;

class const RotateLeftIntent() extends Intent;

class const FlipHorizontalIntent() extends Intent;

class const FlipVerticalIntent() extends Intent;

class const LayerUpIntent() extends Intent;

class const LayerDownIntent() extends Intent;

class const ToggleGridIntent() extends Intent;

class const ResetViewIntent() extends Intent;

// --- App-chrome intents (handled globally in AppShortcuts) ---------------

class const ToggleLeftPaneIntent() extends Intent;

class const ToggleBottomPaneIntent() extends Intent;

class const ToggleRightPaneIntent() extends Intent;

class const ToggleThemeIntent() extends Intent;

class const ExportCircuitIntent() extends Intent;

class const ViewCodeIntent() extends Intent;

class const CloseTabIntent() extends Intent;

class const GoHomeIntent() extends Intent;

/// Opens app settings. ⌘, is the shortcut every editor on this platform uses
/// for it, and settings is a tab here, so it opens one.
class const OpenSettingsIntent() extends Intent;
