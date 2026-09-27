import 'package:pinbench_parts/part_registry.dart';
import 'package:pinbench_parts/cdl/circuit_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('breadboard template resolves the breadboard part and its wires', () {
    const cdl = '''
Circuit {
    breadboard := HalfBreadboard {
        position: (x: -210, y: -210);
    }
    uno := ArduinoUno {
        position: (x: -140, y: -130);
    }
    led1 := LED {
        position: (x: 20, y: -230);
        color: red;
    }
    Wire {
        from: uno.13;
        to: breadboard.sig_right_i_1;
        color: red;
    }
    Wire {
        from: uno.GND_1;
        to: breadboard.sig_right_f_0;
        color: black;
    }
}
''';

    final data = CircuitParser.parse(cdl);
    final result = CircuitParser.applyToCanvas(data, standardParts);

    final names = result.nodes.map((n) => n.part.name).toList();
    expect(
      names,
      contains('Half Breadboard'),
      reason: 'breadboard part should resolve against the component list',
    );
    expect(result.wires.length, 2, reason: 'both wires should resolve');
  });
}
