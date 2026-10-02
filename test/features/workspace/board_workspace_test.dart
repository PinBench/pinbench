// "New … Project" for a board: the workspace opens with that board on the
// canvas and a sketch to build for it.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:pinbench/features/workspace/services/template_service.dart';
import 'package:pinbench_parts/cdl/circuit_parser.dart';
import 'package:pinbench_parts/models/board_profile.dart';
import 'package:pinbench_parts/models/part_model.dart';
import 'package:pinbench_parts/part_registry.dart';

import '../../support/fake_project_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(PartRegistry.initializeAsync);

  late Directory tempDir;
  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('board_workspace_test_');
    PathProviderPlatform.instance = FakePathProvider(tempDir.path);
  });
  tearDown(() => tempDir.deleteSync(recursive: true));

  Future<({List<String> parts, String sketch})> open(BoardProfile board) async {
    final dir = await TemplateService().createBoardWorkspace(board);
    final circuit = CircuitParser.applyToCanvas(
      CircuitParser.parse(File(p.join(dir, 'circuit.cdl')).readAsStringSync()),
      standardParts,
    );
    return (
      parts: [for (final node in circuit.nodes) node.part.name],
      sketch: File(p.join(dir, 'Untitled.ino')).readAsStringSync(),
    );
  }

  test('a Pico W project opens with the Pico on the canvas and its pins explained', () async {
    final (:parts, :sketch) = await open(BoardProfile.picoW);
    expect(parts, [PartNames.picoW]);
    expect(sketch, startsWith('// Raspberry Pi Pico W: a pin is its GPIO number'));
    expect(sketch, contains('drives GP15'));
    expect(sketch, contains('void setup()'));
  });

  test('an Uno project opens with the Uno and the blank sketch it always had', () async {
    final (:parts, :sketch) = await open(BoardProfile.arduinoUno);
    expect(parts, [PartNames.arduinoUno]);
    expect(sketch, startsWith('void setup() {'));
  });

  test('every board can be started on', () async {
    for (final board in BoardProfile.all) {
      expect((await open(board)).parts, [board.partName], reason: board.partName);
    }
  });

  test('a blank project is still an empty canvas', () async {
    final dir = await TemplateService().createBlankWorkspace();
    final circuit = CircuitParser.parse(File(p.join(dir, 'circuit.cdl')).readAsStringSync());
    expect(CircuitParser.applyToCanvas(circuit, standardParts).nodes, isEmpty);
  });
}
