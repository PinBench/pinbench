import 'dart:convert';

import 'package:flutter/services.dart';

import 'package:path/path.dart' as p;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/part_model.dart';
import 'package:pinbench_parts/models/wire_model.dart';
import 'package:pinbench_parts/cdl/circuit_parser.dart';

import '../data/template_asset_loader.dart';
import '../data/workspace_fs.dart';
import '../../../core/parts/part_registry_provider.dart';
import 'compiler_service.dart';

part 'template_service.g.dart';

@riverpod
TemplateService templateService(Ref ref) => TemplateService();

@riverpod
Future<List<String>> availableTemplates(Ref ref) =>
    ref.watch(templateServiceProvider).getAvailableTemplates();

/// Parses [templateName]'s bundled `circuit.cdl` (if it has one) into
/// canvas nodes/wires, for rendering a static preview thumbnail — see
/// `CircuitPreview`. Returns `null` if the template has no `circuit.cdl` or
/// it fails to parse, so callers can fall back to a generic icon.
@riverpod
Future<({List<ComponentInstance> nodes, List<WireModel> wires})?> templateCircuitPreview(
  Ref ref,
  String templateName,
) async {
  final components = await ref.watch(partRegistryProvider.future);
  try {
    final bytes = await loadTemplateAsset('assets/templates/$templateName/circuit.cdl');
    final data = CircuitParser.parse(utf8.decode(bytes));
    return CircuitParser.applyToCanvas(data, components);
  } catch (_) {
    return null;
  }
}

class TemplateService {
  final _fs = WorkspaceFs();

  Future<List<String>> getAvailableTemplates() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final assets = manifest.listAssets();
    final templateDirs = assets
        .where((path) => path.startsWith('assets/templates/'))
        .map((path) {
          final parts = path.split('/');
          if (parts.length > 2) {
            return parts[2]; // e.g., "blink"
          }
          return null;
        })
        .whereType<String>()
        .toSet()
        .toList();

    return templateDirs;
  }

  Future<String> createTempWorkspaceFromTemplate(String templateName) async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final templateAssets = manifest.listAssets().where(
      (path) => path.startsWith('assets/templates/$templateName/'),
    );

    final base = await _fs.tempBasePath();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    // The workspace folder must EXACTLY match the .ino file name for Arduino to compile it!
    final workspaceDir = p.join(base, 'fap_template_$timestamp', templateName);
    await _fs.createDir(workspaceDir);

    for (final asset in templateAssets) {
      final relativePath = asset.replaceFirst('assets/templates/$templateName/', '');
      final bytes = await loadTemplateAsset(asset);
      await _fs.writeBytes(p.join(workspaceDir, relativePath), bytes);
      if (p.extension(relativePath) == '.ino') {
        final hash = utf8.decode(bytes).hashCode;
        CompilerService.pristineSourceHashes[workspaceDir] = hash;
        await _fs.writeString(
          p.join(workspaceDir, CompilerService.pristineHashFileName),
          hash.toString(),
        );
      }
    }

    return workspaceDir;
  }

  Future<String> createBlankWorkspace() => _createUntitledWorkspace(const []);

  /// A temporary workspace with [part] alone on the canvas and a blank sketch:
  /// what a `/part/<name>` link opens, so a part's page can hand you the part.
  Future<String> createWorkspaceWithPart(PartModel part) =>
      _createUntitledWorkspace([ComponentInstance(position: Offset.zero, part: part)]);

  Future<String> _createUntitledWorkspace(List<ComponentInstance> nodes) async {
    final base = await _fs.tempBasePath();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    const projectName = 'Untitled';
    // The workspace folder must EXACTLY match the .ino file name for Arduino
    // to compile it, so nest the "Untitled" dir under a unique temp dir —
    // same layout as createTempWorkspaceFromTemplate.
    final workspaceDir = p.join(base, 'fap_project_$timestamp', projectName);
    await _fs.createDir(workspaceDir);

    // Create a basic blank .ino file matching the directory name
    await _fs.writeString(
      p.join(workspaceDir, '$projectName.ino'),
      'void setup() {\n  // put your setup code here, to run once:\n}\n\n'
      'void loop() {\n  // put your main code here, to run repeatedly:\n}\n',
    );

    await _fs.writeString(
      p.join(workspaceDir, 'circuit.cdl'),
      CircuitParser.generate(nodes, const []),
    );

    return workspaceDir;
  }
}
