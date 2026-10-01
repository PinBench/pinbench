import 'package:pinbench_parts/models/board_profile.dart';
import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/part_model.dart';
import 'package:pinbench_parts/part_registry.dart';
import 'package:pinbench_sim/core/simulation_runner.dart';
import 'package:pinbench_sim/core/sketch_compiler.dart';
import 'package:pinbench_sim/core/sim_io.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/simulation_bindings.dart';

/// The engine's compile port.
///
/// `SimulationRunner` used to call `CompilerService` statically, which meant
/// the emulator knew about `arduino-cli`, remote build services and
/// precompiled template hex — none of which is its business.
///
/// Worth real tests because the runner had *none*: the blink and servo suites
/// drive `SimulationEngine` directly and never go through it, so this boundary
/// was unverified before and after the change.
///
/// Every case here stops before the emulator starts — the compiler either
/// throws or the run is rejected — so nothing spawns an isolate.
void main() {
  ({SimulationRunner runner, List<String?> problems}) build(
    SketchCompiler compiler, {
    List<ComponentInstance> nodes = const [],
  }) {
    final problems = <String?>[];
    final runner = SimulationRunner(
      // An empty circuit, or a board alone: nothing here gets as far as
      // building a netlist.
      circuit: FakeSimulationCanvas()..simulationNodes = nodes,
      compiler: compiler,
      tone: const _SilentTone(),
      microphone: const _NoMicrophone(),
      onCompileError: problems.add,
    );
    addTearDown(runner.stop);
    return (runner: runner, problems: problems);
  }

  test('the whole workspace directory reaches the compiler, not just the buffer', () async {
    // Multi-file sketches and libraries only build if the directory travels;
    // passing the editor buffer alone silently drops them.
    String? seenPath;
    String? seenCode;
    final harness = build(({workspacePath, required code, required board}) async {
      seenPath = workspacePath;
      seenCode = code;
      throw const FormatException('stop here');
    });

    final started = await harness.runner.start(
      'void setup(){}',
      workspacePath: '/tmp/sketch',
      onStop: () {},
    );

    expect(seenPath, '/tmp/sketch');
    expect(seenCode, 'void setup(){}');
    expect(started, isFalse);
  });

  group('the sketch is built for the board on the canvas', () {
    Future<BoardProfile?> boardFor(List<ComponentInstance> nodes) async {
      BoardProfile? seen;
      final harness = build(({workspacePath, required code, required board}) async {
        seen = board;
        throw const FormatException('stop here');
      }, nodes: nodes);
      await harness.runner.start('void setup(){}', onStop: () {});
      return seen;
    }

    ComponentInstance placed(String name) => ComponentInstance(
      position: Offset.zero,
      part: standardParts.firstWhere((p) => p.name == name),
    );

    test('a Pico W', () async {
      final board = await boardFor([placed(PartNames.picoW)]);
      expect(board, BoardProfile.picoW);
      expect(board?.fqbn, 'rp2040:rp2040:rpipico');
    });

    test('an Uno', () async {
      expect(await boardFor([placed(PartNames.arduinoUno)]), BoardProfile.arduinoUno);
    });

    test('an Uno when there is no board, as always', () async {
      expect(await boardFor(const []), BoardProfile.arduinoUno);
    });
  });

  test('with no workspace, the code buffer is compiled on its own', () async {
    String? seenPath = 'unset';
    final harness = build(({workspacePath, required code, required board}) async {
      seenPath = workspacePath;
      throw const FormatException('stop here');
    });

    await harness.runner.start('void loop(){}', onStop: () {});
    expect(seenPath, isNull);
  });

  test('a compile failure refuses to start and surfaces the message verbatim', () async {
    final harness = build(({workspacePath, required code, required board}) async {
      throw const FormatException('sketch.ino:4: expected ;');
    });

    final started = await harness.runner.start('oops', onStop: () {});

    expect(started, isFalse, reason: 'a failed build must not start the emulator');
    expect(
      harness.problems.whereType<String>().join(),
      contains('expected ;'),
      reason: 'this string is what the user reads in the Problems pane',
    );
  });
}

/// No speaker and no microphone — these tests never reach the emulator, and a
/// unit test should not open a host device to find that out.
class const _SilentTone() implements ToneOutput {
  @override
  Future<void> init() async {}
  @override
  void playTone(double frequency) {}
  @override
  void stopTone() {}
  @override
  void dispose() {}
}

class const _NoMicrophone() implements MicrophoneDevice {
  @override
  double get analogVoltage => 0;
  @override
  bool get isDigitalHigh => false;
  @override
  Future<void> init() async {}
  @override
  Future<void> dispose() async {}
}
