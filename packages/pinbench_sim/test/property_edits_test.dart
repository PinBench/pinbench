import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/part_model.dart';
import 'package:pinbench_parts/part_registry.dart';
import 'package:pinbench_sim/core/simulation_runner.dart';

/// Which of a part's properties a mid-run edit forwards to the engine: what
/// the user sets, never what the simulation wrote back onto the canvas — that
/// would echo round to the engine as an edit every frame.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(PartRegistry.initializeAsync);

  ComponentInstance pdl(String id, Map<String, dynamic> properties) => ComponentInstance(
    position: Offset.zero,
    part: PartModel(name: id, size: const Size(40, 40), definitionId: id),
    properties: properties,
  );

  test('a .pdl part forwards its declared PROPERTIES, not its STATE', () {
    final ldr = pdl('ldr', {'illumination': 80, 'darkResistance': 1e6, 'level': 0.8});
    expect(SimulationRunner.userProperties(ldr), {'illumination': 80, 'darkResistance': 1e6});

    final rgb = pdl('rgb_led', {'red': 0.5, ComponentProps.hasError: false});
    expect(SimulationRunner.userProperties(rgb), isEmpty, reason: 'all of it is the logic’s');

    final sw = pdl('slide_switch_spdt', {'position': 'B'});
    expect(SimulationRunner.userProperties(sw), {'position': 'B'});
  });

  test('a built-in part forwards everything but its runtime flags', () {
    final led = ComponentInstance(
      position: Offset.zero,
      part: standardParts.firstWhere((p) => p.name == PartNames.led),
      properties: {
        ComponentProps.color: 'Green',
        ComponentProps.isOn: true,
        ComponentProps.brightness: 0.4,
      },
    );
    expect(SimulationRunner.userProperties(led), {ComponentProps.color: 'Green'});

    final remote = ComponentInstance(
      position: Offset.zero,
      part: standardParts.firstWhere((p) => p.name == PartNames.irRemote),
      properties: {ComponentProps.pressedRegion: '5'},
    );
    expect(SimulationRunner.userProperties(remote), isEmpty, reason: 'a press is an event');
  });
}
