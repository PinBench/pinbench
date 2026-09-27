import 'package:flutter/foundation.dart';

import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/wire_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The canvas, as the `.cdl` sync needs it.
///
/// `CanvasCodeSyncService` held a `CanvasController` directly, which was the
/// last place in this app where one feature reached into another's internals
/// rather than reading a provider. It never needed the controller: it needed
/// seven things, and this is those seven.
///
/// Two of them are deliberately narrower than what the controller exposes. The
/// sync only ever looks at the *first* selected node and the *first* selected
/// wire — to highlight the matching line of `.cdl` — so it asks for those
/// rather than for a selection it would then have to interpret. And
/// [applyValidatedProperties] bakes in `recordHistory: false`, because a value
/// the validator wrote is never something the user should be able to undo.
abstract interface class SyncableCanvas {
  /// True while a simulation is running.
  ///
  /// Load-bearing: the nodes carry transient runtime state during a run — an
  /// LED's `isOn`, brightness, voltages — and regenerating the `.cdl` from them
  /// would write that state into the user's source file. See
  /// `canvas_code_sync_read_only_test.dart`.
  bool get isReadOnly;

  List<ComponentInstance> get nodes;
  List<WireModel> get wires;

  /// The first selected node, or null if the selection is empty or is a wire.
  Key? get selectedNodeKey;

  /// The first selected wire, or null if the selection is empty or is a node.
  String? get selectedWireId;

  /// Replaces the placed circuit with what a `.cdl` parsed to.
  void replaceCircuit(List<ComponentInstance> nodes, List<WireModel> wires);

  /// Writes back a property the circuit validator computed — a shorted LED's
  /// state, say. Never recorded in undo history.
  void applyValidatedProperties(LocalKey nodeKey, Map<String, dynamic> properties);

  /// Fires when the placed circuit changes, so the text can be regenerated.
  ///
  /// A [Listenable] rather than something the sync provider watches, because
  /// rebuilding on every canvas edit would rebuild the service — and a second
  /// service on the same file would fight the first over the editor buffer.
  Listenable get changes;
}

/// The live canvas binding. Has no default: syncing a file to a canvas needs a
/// canvas. Overridden in `buildGlobalScope` — see `lib/app/canvas_sync_bindings.dart`.
final syncableCanvasProvider = Provider<SyncableCanvas>(
  (ref) => throw UnimplementedError(
    'syncableCanvasProvider has no binding. Override it with the adapter in '
    'lib/app/canvas_sync_bindings.dart, or with a fake from test/support/syncable_canvas.dart.',
  ),
);
