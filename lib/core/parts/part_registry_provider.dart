import 'package:flutter/widgets.dart';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:pinbench_parts/part_registry.dart';
import 'package:pinbench_parts/painting/dsl_component_painter.dart';
import 'package:pinbench_parts/models/part_model.dart';

part 'part_registry_provider.g.dart';

@Riverpod(keepAlive: true)
Future<List<PartModel>> partRegistry(Ref ref) async {
  await PartRegistry.initializeAsync();

  final pdlParts = PartRegistry.getAllParts()
      .map(
        (def) => PartModel(
          name: def.name,
          size: Size(def.visual.width, def.visual.height),
          definitionId: def.id,
          aliases: def.aliases,
          // Without this every data-driven part landed in `other`, however
          // carefully its .pdl declared a CATEGORY.
          category: PartCategory.fromName(def.category),
          logic: def.logic,
          painterBuilder: ({isOutline = false, properties}) =>
              DSLComponentPainter(definition: def, isOutline: isOutline, properties: properties),
        ),
      )
      .toList();

  return [...pdlParts, ...standardParts];
}
