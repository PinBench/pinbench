/// The sensor parts under the libraries people actually use: a sketch built
/// on Adafruit MPU6050, BH1750, RTClib and Adafruit AHTX0, plus two
/// `analogRead`s (`test/fixtures/sensors/`), runs on the emulated ATmega328P
/// against a circuit of placed `.pdl` parts, wired the way a user wires them.
///
/// `pinbench_parts`' own tests check each part's registers. This checks what
/// only the whole engine can: that the parts are on the bus *before* `setup()`
/// probes it (every library here gives up for good on a NACK), that their
/// wiring is traced through the netlist, and that each library's init
/// sequence ends in a reading.
library;

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/part_model.dart';
import 'package:pinbench_parts/models/port_model.dart';
import 'package:pinbench_parts/models/wire_model.dart';
import 'package:pinbench_parts/painting/dsl_component_painter.dart';
import 'package:pinbench_parts/part_registry.dart';
import 'package:pinbench_sim/core/simulation_engine.dart';
import 'package:pinbench_sim/core/simulation_output.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(PartRegistry.initializeAsync);

  test('each sensor reads through its Arduino library', () {
    final uno = ComponentInstance(
      key: const ValueKey('uno'),
      position: Offset.zero,
      part: PartModel(name: PartNames.arduinoUno, size: const Size(40, 40)),
    );
    final parts = <ComponentInstance>[];
    final wires = <WireModel>[];

    ComponentInstance place(String id, {Map<String, dynamic> properties = const {}}) {
      final definition = PartRegistry.getPart(id)!;
      final node = ComponentInstance(
        key: ValueKey(id),
        // Far apart, so no two parts' pins overlap and join by accident.
        position: Offset(600.0 * (parts.length + 1), 0),
        part: PartModel(
          name: definition.name,
          size: Size(definition.visual.width, definition.visual.height),
          definitionId: definition.id,
          logic: definition.logic,
          painterBuilder: ({isOutline = false, properties}) => DSLComponentPainter(
            definition: definition,
            isOutline: isOutline,
            properties: properties,
          ),
        ),
        properties: {...properties},
      );
      parts.add(node);
      return node;
    }

    void wire(ComponentInstance part, String pin, String boardPort) => wires.add(
      WireModel(
        id: '${part.key}.$pin-$boardPort',
        start: PortLocation(nodeKey: part.key, portId: pin),
        end: PortLocation(nodeKey: uno.key, portId: boardPort),
      ),
    );

    void onTheBus(ComponentInstance part) {
      wire(part, 'vcc', '5V');
      wire(part, 'gnd', 'GND_2');
      wire(part, 'sda', 'A4');
      wire(part, 'scl', 'A5');
    }

    final imu = place('mpu6050');
    onTheBus(imu);
    wire(imu, 'ad0', '5V'); // to 0x69, leaving 0x68 to the clock
    onTheBus(place('bh1750', properties: {'illuminance': 250}));
    onTheBus(place('ds1307', properties: {'startsAt': 'unset'}));
    onTheBus(place('aht20', properties: {'humidity': 60, 'temperature': 22.5}));

    final thermometer = place('tmp36', properties: {'temperature': 25});
    wire(thermometer, 'vs', '5V');
    wire(thermometer, 'vout', 'A0');
    wire(thermometer, 'gnd', 'GND_3');
    final soil = place('soil_moisture', properties: {'moisture': 40});
    wire(soil, 'vcc', '5V');
    wire(soil, 'aout', 'A1');
    wire(soil, 'gnd', 'GND_3');

    final lines = <String>[];
    final engine = SimulationEngine(
      output: _FakeOutput([uno, ...parts], wires),
      onSerialPrint: lines.add,
    )..prepareForFrameStepping(File('test/fixtures/sensors/sensors.hex').readAsStringSync());

    // Four simulated seconds is ample: the libraries' own delays add up to
    // well under one. Stop as soon as the sketch reports it is done.
    const cyclesPerFrame = 160000; // 10 ms at 16 MHz
    for (var frame = 0; frame < 400 && !lines.contains('DONE'); frame++) {
      engine.runFrame(cycles: cyclesPerFrame);
    }

    expect(
      lines,
      containsAllInOrder([
        'MPU=1',
        'AZ=9.8', // 1 g, in the m/s² the Adafruit event reports
        'BH=1',
        'LUX=250',
        'RTC=1',
        'RUN=0', // a fresh chip is halted...
        'NOW=2026-9-30 12:34:56',
        'RUN=1', // ...until adjust() sets it
        'AHT=1',
        'RH=60.0',
        'T=22.5',
        'A0=153', // TMP36: 0.75 V at 25 °C
        'A1=450', // soil: 2.2 V at 40 % moisture
        'DONE',
      ]),
    );
  });
}

class _FakeOutput(
  @override final List<ComponentInstance> simulationNodes,
  @override final List<WireModel> simulationWires,
) implements SimulationOutput {
  @override
  void applyNodeUpdates(Map<LocalKey, Map<String, dynamic>> updates) {}
}
