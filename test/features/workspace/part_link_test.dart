// `/part/<name>` links, as the website's part pages write them: which names
// resolve to which part, against the catalog the canvas itself uses.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:pinbench/features/workspace/services/part_link.dart';
import 'package:pinbench/features/workspace/services/template_service.dart';
import 'package:pinbench_parts/cdl/circuit_parser.dart';
import 'package:pinbench_parts/models/part_model.dart';
import 'package:pinbench_parts/part_registry.dart';

import '../../support/fake_project_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<PartModel> catalog;
  setUpAll(() async {
    await PartRegistry.initializeAsync();
    catalog = [...PartRegistry.paletteParts(), ...standardParts];
  });

  String? nameOf(String link) => partForLink(catalog, link)?.name;

  test('a built-in part by its .cdl type, in any case', () {
    expect(nameOf('ArduinoUno'), PartNames.arduinoUno);
    expect(nameOf('arduinouno'), PartNames.arduinoUno);
    expect(nameOf('RaspberryPiPicoW'), PartNames.picoW);
    expect(nameOf('led'), PartNames.led);
  });

  test('a .pdl part by its file id, its name or an alias', () {
    final byId = partForLink(catalog, 'mpu6050');
    expect(byId?.definitionId, 'mpu6050');
    expect(partForLink(catalog, 'MPU-6050')?.name, byId?.name);
    expect(partForLink(catalog, byId!.name)?.name, byId.name);
    expect(partForLink(catalog, 'battery_9v')?.definitionId, 'battery_9v');
  });

  test('a name is not mistaken for one it only contains', () {
    // "LED" is inside "RGB LED" and "OLED Display"; only the LED is called it.
    expect(nameOf('RGBLED'), isNot(PartNames.led));
    expect(nameOf('OLEDDisplay'), PartNames.oledDisplay);
  });

  test('every palette part can be linked to by its own name', () {
    for (final part in catalog) {
      expect(partForLink(catalog, part.name)?.name, part.name, reason: part.name);
    }
  });

  test('the workspace a link opens holds that part, and only it', () async {
    final tempDir = Directory.systemTemp.createTempSync('part_link_test_');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    PathProviderPlatform.instance = FakePathProvider(tempDir.path);

    final mpu = partForLink(catalog, 'mpu6050')!;
    final dir = await TemplateService().createWorkspaceWithPart(mpu);

    final circuit = CircuitParser.applyToCanvas(
      CircuitParser.parse(File(p.join(dir, 'circuit.cdl')).readAsStringSync()),
      catalog,
    );
    expect(circuit.nodes.map((n) => n.part.name), [mpu.name]);
    expect(circuit.wires, isEmpty);
    expect(File(p.join(dir, 'Untitled.ino')).existsSync(), isTrue);
  });

  test('no part, no match', () {
    expect(partForLink(catalog, 'flux-capacitor'), isNull);
    expect(partForLink(catalog, ''), isNull);
    expect(partForLink(catalog, '---'), isNull);
  });
}
