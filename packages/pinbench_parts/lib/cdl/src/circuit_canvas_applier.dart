import 'package:flutter/widgets.dart';
import 'package:pinbench_cdl/pinbench_cdl.dart';

import '../../models/component_instance.dart';
import '../../models/part_model.dart';
import '../../models/port_model.dart';
import '../../models/wire_model.dart';
import '../../parser_utils.dart';
import '../circuit_colors.dart';

/// Materializes parsed [CircuitData] into placed `ComponentInstance`s and
/// `WireModel`s on the canvas (data -> canvas). Extracted from
/// `CircuitParser`; carries the regression-sensitive node-key-derivation
/// logic verbatim — see the comment on [applyToCanvas] before changing it.
abstract final class CircuitCanvasApplier {
  static ({List<ComponentInstance> nodes, List<WireModel> wires}) applyToCanvas(
    CircuitData data,
    List<PartModel> catalog,
  ) {
    final outNodes = <ComponentInstance>[];
    final outWires = <WireModel>[];

    final idToKey = <String, Key>{};

    // `element` is one `id := Type { … }` block from the `.cdl`; `partModel`
    // is the catalog entry its type token resolves to. Two different things
    // that both used to be called some flavour of "component".
    for (final element in data.parts) {
      try {
        // `element.type` is the type token (`ArduinoUno` for "Arduino Uno");
        // resolve it back to a catalog part by comparing tokens.
        final partModel = catalog
            .firstWhere((p) => ParserUtils.typeToken(p.name) == element.type)
            .clone();
        // Derive the key DETERMINISTICALLY from the part id (which is unique
        // within a circuit) rather than minting a fresh UniqueKey() on every
        // parse. Node identity must survive a re-parse: the canvas<->code sync
        // re-parses the .cdl back onto the canvas whenever a property changes,
        // and during a simulation the LED's `isOn` toggles every blink — a new
        // key each time would orphan the live node from the simulation engine's
        // key-addressed frame updates, so the LED would stop lighting on re-run
        // even though the emulator keeps running.
        final key = ValueKey(element.id);
        idToKey[element.id] = key;

        outNodes.add(
          ComponentInstance(
            key: key,
            position: Offset(element.position.x, element.position.y),
            part: partModel,
            rotationAngle: element.rotationAngle,
            flipHorizontal: element.flipHorizontal,
            flipVertical: element.flipVertical,
            // A copy the canvas owns: it writes runtime flags (`isOn: true`)
            // into this map, which a `Map<String, String>` would reject.
            properties: element.properties == null
                ? null
                : Map<String, dynamic>.of(element.properties!),
          ),
        );
      } catch (_) {
        debugPrint('Warning: part type "${element.type}" not found in the catalog.');
      }
    }

    for (final wire in data.wires) {
      final startKey = idToKey[wire.fromId];
      final endKey = idToKey[wire.toId];
      if (startKey != null && endKey != null) {
        outWires.add(
          WireModel(
            id: UniqueKey().toString(),
            start: PortLocation(nodeKey: startKey, portId: wire.fromPort),
            end: PortLocation(nodeKey: endKey, portId: wire.toPort),
            color: CircuitColors.nameToColor(wire.color),
            bendPoints: [for (final p in wire.bendPoints) Offset(p.x, p.y)],
          ),
        );
      }
    }

    return (nodes: outNodes, wires: outWires);
  }
}
