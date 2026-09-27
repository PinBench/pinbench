import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

import '../../controller/canvas_controller.dart';
import '../../../../core/shortcuts/app_intents.dart';

/// Builds the canvas's keyboard shortcut and action maps for a given
/// controller. Extracted from `canvas.dart` — callers should build these
/// once per controller instance (see `_CanvasState._ensureActions`'s
/// identity check) rather than on every rebuild, since these maps are
/// otherwise reallocated on every canvas state change.
class CanvasShortcuts {
  static Map<LogicalKeySet, Intent> shortcuts() => <LogicalKeySet, Intent>{
    LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyZ): const UndoIntent(),
    LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.shift, LogicalKeyboardKey.keyZ):
        const RedoIntent(),
    LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyC): const CopyIntent(),
    LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyV): const PasteIntent(),
    LogicalKeySet(LogicalKeyboardKey.backspace): const DeleteIntent(),
    LogicalKeySet(LogicalKeyboardKey.delete): const DeleteIntent(),
    LogicalKeySet(LogicalKeyboardKey.equal): const ZoomInIntent(),
    LogicalKeySet(LogicalKeyboardKey.minus): const ZoomOutIntent(),
    LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.equal): const ZoomInIntent(),
    LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.shift, LogicalKeyboardKey.equal):
        const ZoomInIntent(),
    LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.minus): const ZoomOutIntent(),
    LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.numpadAdd): const ZoomInIntent(),
    LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.numpadSubtract):
        const ZoomOutIntent(),
    LogicalKeySet(LogicalKeyboardKey.arrowUp): const PanUpIntent(),
    LogicalKeySet(LogicalKeyboardKey.arrowDown): const PanDownIntent(),
    LogicalKeySet(LogicalKeyboardKey.arrowLeft): const PanLeftIntent(),
    LogicalKeySet(LogicalKeyboardKey.arrowRight): const PanRightIntent(),
    LogicalKeySet(LogicalKeyboardKey.escape): const CancelWiringIntent(),
    LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyR): const RotateRightIntent(),
    LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.shift, LogicalKeyboardKey.keyR):
        const RotateLeftIntent(),
    LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyF): const FlipHorizontalIntent(),
    LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.shift, LogicalKeyboardKey.keyF):
        const FlipVerticalIntent(),
    LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.bracketRight): const LayerUpIntent(),
    LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.bracketLeft): const LayerDownIntent(),
    LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyD): const DuplicateIntent(),
    LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.quote): const ToggleGridIntent(),
    LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.digit0): const ResetViewIntent(),
  };

  static Map<Type, Action<Intent>> actions(CanvasController controller) => <Type, Action<Intent>>{
    UndoIntent: CallbackAction<UndoIntent>(onInvoke: (intent) => controller.undo()),
    RedoIntent: CallbackAction<RedoIntent>(onInvoke: (intent) => controller.redo()),
    CopyIntent: CallbackAction<CopyIntent>(onInvoke: (intent) => controller.copy()),
    PasteIntent: CallbackAction<PasteIntent>(onInvoke: (intent) => controller.paste()),
    DuplicateIntent: CallbackAction<DuplicateIntent>(
      onInvoke: (intent) {
        controller.copy();
        controller.paste();
        return null;
      },
    ),
    DeleteIntent: CallbackAction<DeleteIntent>(onInvoke: (intent) => controller.remove()),
    ZoomInIntent: CallbackAction<ZoomInIntent>(onInvoke: (intent) => controller.zoomIn()),
    ZoomOutIntent: CallbackAction<ZoomOutIntent>(onInvoke: (intent) => controller.zoomOut()),
    PanUpIntent: CallbackAction<PanUpIntent>(onInvoke: (intent) => controller.panUp()),
    PanDownIntent: CallbackAction<PanDownIntent>(onInvoke: (intent) => controller.panDown()),
    PanLeftIntent: CallbackAction<PanLeftIntent>(onInvoke: (intent) => controller.panLeft()),
    PanRightIntent: CallbackAction<PanRightIntent>(onInvoke: (intent) => controller.panRight()),
    CancelWiringIntent: CallbackAction<CancelWiringIntent>(
      onInvoke: (intent) => controller.cancelWiring(),
    ),
    RotateRightIntent: CallbackAction<RotateRightIntent>(
      onInvoke: (intent) => controller.rotateRight(),
    ),
    RotateLeftIntent: CallbackAction<RotateLeftIntent>(
      onInvoke: (intent) => controller.rotateLeft(),
    ),
    FlipHorizontalIntent: CallbackAction<FlipHorizontalIntent>(
      onInvoke: (intent) => controller.flipHorizontal(),
    ),
    FlipVerticalIntent: CallbackAction<FlipVerticalIntent>(
      onInvoke: (intent) => controller.flipVertical(),
    ),
    LayerUpIntent: CallbackAction<LayerUpIntent>(onInvoke: (intent) => controller.layerUp()),
    LayerDownIntent: CallbackAction<LayerDownIntent>(onInvoke: (intent) => controller.layerDown()),
    ToggleGridIntent: CallbackAction<ToggleGridIntent>(
      onInvoke: (intent) => controller.toggleGrid(),
    ),
    ResetViewIntent: CallbackAction<ResetViewIntent>(
      onInvoke: (intent) => controller.fitToContent(controller.viewportSize),
    ),
  };
}
