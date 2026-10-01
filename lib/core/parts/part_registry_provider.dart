import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:pinbench_parts/part_registry.dart';
import 'package:pinbench_parts/models/part_model.dart';

part 'part_registry_provider.g.dart';

@Riverpod(keepAlive: true)
Future<List<PartModel>> partRegistry(Ref ref) async {
  await PartRegistry.initializeAsync();

  // One entry per part: a part with several configurations is listed once,
  // as its default one — see `PartRegistry.paletteParts`.
  final pdlParts = PartRegistry.paletteParts();

  return [...pdlParts, ...standardParts];
}
