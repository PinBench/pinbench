import 'canvas_commands.dart';
import 'canvas_context.dart';

/// Maximum number of undoable commands retained in memory.
///
/// Older entries are dropped when the limit is exceeded to prevent unbounded
/// memory growth during long editing sessions.
const _kMaxHistorySize = 100;

/// Undo/redo stack for [CanvasCommand]s. Executing a new command clears the redo
/// stack; the history is capped at [_kMaxHistorySize] entries.
class HistoryManager {
  final List<CanvasCommand> _undoStack = [];
  final List<CanvasCommand> _redoStack = [];

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  void execute(CanvasCommand command, CanvasContext controller) {
    command.execute(controller);
    _undoStack.add(command);
    _redoStack.clear();

    // Trim oldest entries when the cap is exceeded.
    if (_undoStack.length > _kMaxHistorySize) {
      _undoStack.removeRange(0, _undoStack.length - _kMaxHistorySize);
    }
  }

  void undo(CanvasContext controller) {
    if (!canUndo) return;
    final command = _undoStack.removeLast();
    command.undo(controller);
    _redoStack.add(command);
  }

  void redo(CanvasContext controller) {
    if (!canRedo) return;
    final command = _redoStack.removeLast();
    command.execute(controller);
    _undoStack.add(command);
  }
}
