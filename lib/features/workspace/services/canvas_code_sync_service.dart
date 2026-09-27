import 'package:flutter/widgets.dart';

import 'package:re_editor/re_editor.dart';
import 'package:pinbench_parts/models/part_model.dart';
import 'package:pinbench_sim/services/circuit_validator.dart';
import 'package:pinbench_parts/cdl/circuit_parser.dart';

import 'editor_state_controller.dart';
import 'syncable_canvas.dart';

/// Keeps a `.cdl` file and the visual canvas in sync, both ways.
///
/// Editing the `.cdl` text re-parses it onto the canvas; editing the canvas
/// regenerates the text. A re-entrancy guard prevents the two directions from
/// looping. Parse failures are reported via [onParseError] and circuit
/// validation issues via [onCircuitError] (both surface in the Problems pane).
class CanvasCodeSyncService {
  final SyncableCanvas canvas;
  final EditorStateController editorStateController;
  final List<PartModel> components;

  /// Reports a circuit-validation error (or `''`/empty to clear). Fired when the
  /// canvas changes and the netlist is validated.
  final void Function(String)? onCircuitError;

  /// Reports a CDL parse error, or `null` when the latest parse succeeded.
  final void Function(String?)? onParseError;

  final Map<String, VoidCallback> _cdlListeners = {};
  String? activeCdlPath;

  var _isSyncing = false;
  var _pendingCodeToCanvas = false;
  var _pendingCanvasToCode = false;

  /// Path of a `.cdl` just opened whose saved-baseline should be re-adopted
  /// after the initial load round-trip. A hand-authored `.cdl` may use
  /// non-canonical component ids (e.g. `part1` vs the generator's
  /// `halfbreadboard1`); the load-time canvas->code echo rewrites the editor
  /// text to canonical form, which would otherwise flip the tab to "unsaved"
  /// for a circuit the user never edited. Cleared after the first re-baseline.
  String? _baselinePendingPath;

  /// Called when the canvas switches to a different `.cdl`, or to none.
  /// Published so the rest of the app can ask what is on screen without asking
  /// the sync machinery — see `activeCircuitFileProvider`.
  final void Function(String? filePath)? onActiveCircuitChanged;

  CanvasCodeSyncService({
    required this.canvas,
    required this.editorStateController,
    required this.components,
    this.onCircuitError,
    this.onParseError,
    this.onCircuitValidation,
    this.onActiveCircuitChanged,
  }) {
    // The canvas tells us when its circuit changed; regenerating the text is
    // this service's answer. Subscribed here rather than watched from the
    // provider so a canvas edit does not rebuild the service.
    canvas.changes.addListener(syncCanvasToCode);
  }

  /// Reports a circuit-validation error type for analytics.
  final void Function(String? errorType)? onCircuitValidation;

  void attachCdlListener(String path, CodeLineEditingController controller) {
    activeCdlPath = path;
    onActiveCircuitChanged?.call(path);
    // The upcoming initial parse triggers a canvas->code echo that may rewrite
    // the editor text to canonical form; re-baseline the saved snapshot to that
    // text so opening an unedited circuit doesn't show as "unsaved".
    _baselinePendingPath = path;
    void listener() {
      if (activeCdlPath == path) {
        _syncCodeToCanvas();
      }
    }

    _cdlListeners[path] = listener;
    controller.addListener(listener);
    // Trigger initial parse
    _syncCodeToCanvas();
  }

  void detachCdlListener(String path) {
    final listener = _cdlListeners.remove(path);
    if (listener != null) {
      final controller = editorStateController.openFileControllers[path];
      if (controller != null) {
        controller.removeListener(listener);
      }
    }
    if (activeCdlPath == path) {
      activeCdlPath = null;
      onActiveCircuitChanged?.call(null);
    }
    if (_baselinePendingPath == path) {
      _baselinePendingPath = null;
    }
  }

  CodeLineEditingController? get _activeCdlController {
    if (activeCdlPath != null &&
        editorStateController.openFileControllers.containsKey(activeCdlPath)) {
      return editorStateController.openFileControllers[activeCdlPath];
    }
    for (final entry in editorStateController.openFileControllers.entries) {
      if (entry.key.endsWith('.cdl')) return entry.value;
    }
    return null;
  }

  void dispose() {
    canvas.changes.removeListener(syncCanvasToCode);
    for (final entry in editorStateController.openFileControllers.entries) {
      if (entry.key.endsWith('.cdl')) {
        final listener = _cdlListeners[entry.key];
        if (listener != null) {
          entry.value.removeListener(listener);
        }
      }
    }
    _cdlListeners.clear();
  }

  void _syncCodeToCanvas() {
    if (_isSyncing || _pendingCodeToCanvas) return;
    _pendingCodeToCanvas = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pendingCodeToCanvas = false;
      if (_isSyncing) return;
      _isSyncing = true;
      try {
        final cdlController = _activeCdlController;
        if (cdlController == null) {
          return;
        }

        final data = CircuitParser.parse(cdlController.text);

        final result = CircuitParser.applyToCanvas(data, components);

        canvas.replaceCircuit(result.nodes, result.wires);
        onParseError?.call(null);
      } catch (e) {
        onParseError?.call('$e');
      } finally {
        _isSyncing = false;
      }
    });
  }

  void syncCanvasToCodeSync() {
    // Always clear the pending flag first so a skipped sync (below) doesn't
    // wedge future syncs — `syncCanvasToCode` bails while it's still set.
    _pendingCanvasToCode = false;

    // While the canvas is read-only (i.e. a simulation is running) its nodes
    // carry transient runtime state — LED `isOn`, brightness, voltages — merged
    // in each frame by `batchSimulationUpdate`. Regenerating the `.cdl` from
    // that would write runtime state into the source file and flip the tab to
    // "unsaved" even though the user never edited it. The pre-run save already
    // captured the real circuit before read-only was set, so there is nothing
    // to sync back here.
    if (canvas.isReadOnly) return;

    _isSyncing = true;
    try {
      final outNodeIdMap = <Key, String>{};
      final newText = CircuitParser.generate(
        canvas.nodes,
        canvas.wires,
        outNodeIdMap: outNodeIdMap,
      );

      // --- Validation Logic ---
      final validationResult = CircuitValidator.validate(nodes: canvas.nodes, wires: canvas.wires);
      final errorMessage = validationResult.errorMessage;

      // Report to analytics: categorize the validation error type.
      onCircuitValidation?.call(
        errorMessage == null
            ? null
            : errorMessage.contains('Short Circuit')
            ? 'short_circuit'
            : errorMessage.contains('backwards') || errorMessage.contains('reversed')
            ? 'led_reversed'
            : errorMessage.contains('short-circuited')
            ? 'led_shorted'
            : 'other',
      );

      for (final entry in validationResult.updatedProperties.entries) {
        canvas.applyValidatedProperties(entry.key, entry.value);
      }

      onCircuitError?.call(errorMessage ?? '');

      final cdlController = _activeCdlController;
      if (cdlController == null) return;

      if (cdlController.text != newText) {
        cdlController.text = newText;
      }

      // First sync after opening this `.cdl`: adopt the (now canonical) text as
      // its saved baseline so the load-time re-serialization isn't mistaken for
      // an unsaved user edit. A genuine later canvas edit changes the text away
      // from this baseline and still dirties the tab as expected.
      if (_baselinePendingPath != null && _baselinePendingPath == activeCdlPath) {
        editorStateController.markSaved(_baselinePendingPath!, cdlController.text);
        _baselinePendingPath = null;
      }

      var newSelection = const CodeLineSelection.zero();

      final selectedNodeKey = canvas.selectedNodeKey;
      final selectedWireId = canvas.selectedWireId;

      if (selectedNodeKey != null) {
        final id = outNodeIdMap[selectedNodeKey];
        if (id != null) {
          final lines = newText.split('\n');
          for (var i = 0; i < lines.length; i++) {
            if (lines[i].trimLeft().startsWith('$id := ')) {
              newSelection = CodeLineSelection(
                baseIndex: i,
                baseOffset: 0,
                extentIndex: i,
                extentOffset: lines[i].length,
              );
              break;
            }
          }
        }
      } else if (selectedWireId != null) {
        final wire = canvas.wires.where((w) => w.id == selectedWireId).firstOrNull;
        if (wire != null) {
          final fromId = outNodeIdMap[wire.start.nodeKey];
          final toId = outNodeIdMap[wire.end.nodeKey];
          if (fromId != null && toId != null) {
            final lines = newText.split('\n');
            // A wire is a `Wire { from: <fromId>.<port>; … }` block; highlight
            // its `from:` line, which uniquely identifies the connection.
            for (var i = 0; i < lines.length; i++) {
              if (lines[i].trimLeft().startsWith('from: $fromId.${wire.start.portId};')) {
                newSelection = CodeLineSelection(
                  baseIndex: i,
                  baseOffset: 0,
                  extentIndex: i,
                  extentOffset: lines[i].length,
                );
                break;
              }
            }
          }
        }
      }

      if (cdlController.selection != newSelection) {
        cdlController.selection = newSelection;
        cdlController.makeCursorCenterIfInvisible();
      }
    } finally {
      _isSyncing = false;
    }
  }

  void syncCanvasToCode() {
    if (_isSyncing || _pendingCanvasToCode) return;
    _pendingCanvasToCode = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_pendingCanvasToCode) return;
      if (_isSyncing) return;
      syncCanvasToCodeSync();
    });
  }
}
