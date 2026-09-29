import 'package:flutter/widgets.dart';
import 'package:pinbench_cdl/pinbench_cdl.dart';

import '../models/component_instance.dart';
import '../models/part_model.dart';
import '../models/wire_model.dart';
import 'src/cdl_property_keys.dart';
import 'src/circuit_canvas_applier.dart';
import 'src/circuit_model_writer.dart';

export 'package:pinbench_cdl/pinbench_cdl.dart' show CdlPoint, CircuitData, PartData, WireData;

/// Converts between a `.cdl` document and placed parts on the canvas.
///
/// The format itself — text to [CircuitData] and back — is `pinbench_cdl`,
/// which is pure Dart so tools outside the app can use it. This facade is the
/// app's side of it: [parse] reads a document into this app's property
/// spelling, [applyToCanvas] resolves it into placed `ComponentInstance`s and
/// `WireModel`s, and [generate] serializes them back.
///
/// That round-trip is what keeps the code editor and the visual canvas in
/// sync, and it has to be *exact* — a template that regenerates even slightly
/// differently opens with its tab already marked unsaved.
abstract final class CircuitParser {
  /// [code] as [CircuitData], with property keys and colour values in the
  /// form the properties panel uses (`color: red` -> `Color: Red`).
  static CircuitData parse(String code) {
    final circuit = CdlParser.parse(code);
    return CircuitData(
      parts: [
        for (final part in circuit.parts)
          PartData(
            type: part.type,
            id: part.id,
            position: part.position,
            rotationAngle: part.rotationAngle,
            flipHorizontal: part.flipHorizontal,
            flipVertical: part.flipVertical,
            properties: part.properties == null ? null : _toInternal(part.properties!),
          ),
      ],
      wires: circuit.wires,
    );
  }

  static String generate(
    List<ComponentInstance> nodes,
    List<WireModel> wires, {
    Map<Key, String>? outNodeIdMap,
  }) => CdlWriter.write(CircuitModelWriter.toCircuitData(nodes, wires, outNodeIdMap: outNodeIdMap));

  static ({List<ComponentInstance> nodes, List<WireModel> wires}) applyToCanvas(
    CircuitData data,
    List<PartModel> components,
  ) => CircuitCanvasApplier.applyToCanvas(data, components);

  /// Maps each `.cdl` key back to the internal one (`color` -> `Color`) and
  /// restores a colour value's capitalization so it matches the property
  /// panel's dropdown options.
  static Map<String, String> _toInternal(Map<String, String> properties) => {
    for (final entry in properties.entries)
      CdlPropertyKeys.toInternal(
        entry.key,
      ): CdlPropertyKeys.toInternal(entry.key) == ComponentProps.color
          ? _capitalize(entry.value)
          : entry.value,
  };

  /// Upper-cases the first letter (`red` -> `Red`).
  static String _capitalize(String value) =>
      value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';
}
