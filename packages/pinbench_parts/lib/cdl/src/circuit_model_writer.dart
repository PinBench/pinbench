import 'package:flutter/widgets.dart';
import 'package:pinbench_cdl/pinbench_cdl.dart';

import '../../models/component_instance.dart';
import '../../models/part_model.dart';
import '../../models/wire_model.dart';
import '../../parser_utils.dart';
import '../../part_registry.dart';
import '../circuit_colors.dart';
import 'cdl_property_keys.dart';

/// Turns the canvas model into [CircuitData] as a `.cdl` spells it (canvas ->
/// data); `CdlWriter` then writes it out.
///
/// Everything here is this app's convention, not the format's: which id a
/// node gets, which properties are transient and never saved, how a property
/// key and a colour are spelled in the file.
abstract final class CircuitModelWriter {
  static CircuitData toCircuitData(
    List<ComponentInstance> nodes,
    List<WireModel> wires, {
    Map<Key, String>? outNodeIdMap,
  }) {
    final idMap = _assignIds(nodes);
    if (outNodeIdMap != null) outNodeIdMap.addAll(idMap);

    return CircuitData(
      parts: [for (final node in nodes) _part(node, idMap[node.key]!)],
      wires: [
        for (final wire in wires)
          if (idMap[wire.start.nodeKey] case final fromId?)
            if (idMap[wire.end.nodeKey] case final toId?)
              WireData(
                fromId: fromId,
                fromPort: wire.start.portId,
                toId: toId,
                toPort: wire.end.portId,
                color: CircuitColors.colorToName(wire.color),
                bendPoints: [for (final p in wire.bendPoints) CdlPoint(p.dx, p.dy)],
              ),
      ],
    );
  }

  static PartData _part(ComponentInstance node, String id) {
    // Simulation-written runtime flags (isOn, brightness, ...) share the
    // `properties` map with user-editable ones but must never be persisted:
    // they're transient per-frame state, and writing them here would flip a
    // just-simulated `.cdl` to "unsaved" even though nothing the user controls
    // changed. The internal property keys/values are capitalized (`Color: Red`,
    // used verbatim as the properties-panel label and dropdown option); the
    // `.cdl` presents them lowercase (`color: red`) for a cleaner, consistent
    // look, and `CircuitParser.parse` maps them back. Unknown keys pass through.
    //
    // A `.pdl` part's declared `STATE` is the same kind of value — what a run
    // measured, recreated every run — so it is skipped too. Saving a PIR's
    // `holdUntilMs` or a sensor's register settings would dirty the file the
    // same way, and hand the next run a stale value to start from.
    final definitionId = node.part.definitionId;
    final declaredState = definitionId == null
        ? const <String>{}
        : PartRegistry.getPart(definitionId)?.state.keys.toSet() ?? const <String>{};
    final properties = <String, String>{
      for (final entry in node.properties.entries)
        if (!ComponentProps.runtimeFlags.contains(entry.key) && !declaredState.contains(entry.key))
          CdlPropertyKeys.toCdl(entry.key): entry.key == ComponentProps.color
              ? entry.value.toString().toLowerCase()
              : _unitless(entry.value.toString()),
    };

    return PartData(
      id: id,
      type: ParserUtils.typeToken(node.part.name),
      position: CdlPoint(node.position.dx, node.position.dy),
      rotationAngle: node.rotationAngle,
      flipHorizontal: node.flipHorizontal,
      flipVertical: node.flipVertical,
      properties: properties,
    );
  }

  /// Assigns each node a `.cdl` id. Ids the node already carries (from a prior
  /// parse or a hand-written `.cdl`) are reused so identity — and the editor's
  /// "saved" state — survive the round-trip; only nodes without a meaningful id
  /// (freshly dropped ones, whose key is an auto-generated `node_…`) get a fresh
  /// type-based id like `led1`, `r2`, `button3`.
  static Map<Key, String> _assignIds(List<ComponentInstance> nodes) {
    final idMap = <Key, String>{};
    final used = <String>{};

    for (final node in nodes) {
      final reusable = _reusableId(node.key);
      if (reusable != null && used.add(reusable)) {
        idMap[node.key] = reusable;
      }
    }

    final counts = <String, int>{};
    for (final node in nodes) {
      if (idMap.containsKey(node.key)) continue;
      final prefix = _prefixFor(node.part.name);
      var n = counts[prefix] ?? 0;
      String id;
      do {
        n++;
        id = (prefix == 'uno' && n == 1) ? 'uno' : '$prefix$n';
      } while (!used.add(id));
      counts[prefix] = n;
      idMap[node.key] = id;
    }

    return idMap;
  }

  static final _cleanId = RegExp(r'^[A-Za-z_]\w*$');
  static final _autoNodeId = RegExp(r'^node_\d+_\d+$');

  /// The node's own id if it is a clean identifier worth preserving (e.g.
  /// `led_red`, `part1`, `uno`), or null for auto-generated drop keys.
  static String? _reusableId(Key key) {
    if (key is ValueKey && key.value is String) {
      final value = key.value as String;
      if (_cleanId.hasMatch(value) && !_autoNodeId.hasMatch(value)) return value;
    }
    return null;
  }

  static String _prefixFor(String componentName) => switch (componentName) {
    PartNames.arduinoUno => 'uno',
    PartNames.resistor => 'r',
    PartNames.led => 'led',
    PartNames.pushButton => 'button',
    PartNames.piezoBuzzer => 'buzzer',
    PartNames.breadboardHalf || PartNames.breadboardFull => 'breadboard',
    PartNames.ky037MicSensor => 'mic',
    PartNames.potentiometer => 'pot',
    _ => _sanitize(componentName),
  };

  static String _sanitize(String name) {
    final cleaned = name.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
    return cleaned.isEmpty ? 'part' : cleaned;
  }

  /// A property value with its unit dropped, so the file carries the number
  /// and not the way it happens to be displayed (`220 Ω` -> `220`,
  /// `1 kΩ` -> `1k`).
  ///
  /// The unit is presentation: the panel may show whatever the user typed, and
  /// `parseResistance` reads either form, so nothing downstream needs it
  /// written down.
  static String _unitless(String value) => value
      .replaceAll(RegExp('ohms?', caseSensitive: false), '')
      .replaceAll(RegExp('[ΩωΩ]'), '')
      .replaceAll(' ', '');
}
