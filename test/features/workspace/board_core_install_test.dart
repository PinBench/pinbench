// The first Pico build on a machine without the arduino-pico core: told apart
// from an ordinary compile error, offered as a fix in the Problems pane, and
// installed only when asked — with the commands below, which these tests run
// against a fake arduino-cli so nothing is downloaded.
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench/app/simulation/workspace_simulation_diagnostics.dart';
import 'package:pinbench/features/workspace/providers/problems_provider.dart';
import 'package:pinbench/features/workspace/services/compiler_service.dart';
import 'package:pinbench/features/workspace/services/local_compile_service.dart';
import 'package:pinbench_parts/models/board_profile.dart';

void main() {
  const missingCore =
      "Error during build: Platform 'rp2040:rp2040' not found: platform not installed";
  const pico = BoardProfile.picoW;
  final url = pico.coreIndexUrl!;

  group('failureFor', () {
    test('a Pico build without the core is a MissingBoardCoreException for the Pico', () {
      final error = LocalCompileService.failureFor(ProcessResult(0, 1, '', missingCore), pico);
      expect(error, isA<MissingBoardCoreException>());
      expect((error as MissingBoardCoreException).board, same(pico));
      expect(
        error.message,
        contains('arduino-cli core install rp2040:rp2040 --additional-urls $url'),
      );
    });

    test('an ordinary compile error stays an ordinary one', () {
      final error = LocalCompileService.failureFor(
        ProcessResult(0, 1, '', "sketch.ino:3:1: error: expected ';'"),
        pico,
      );
      expect(error, isNot(isA<MissingBoardCoreException>()));
      expect(error.message, contains("expected ';'"));
    });

    test("the Uno's core ships with arduino-cli's own index, so there is nothing to offer", () {
      final error = LocalCompileService.failureFor(
        ProcessResult(0, 1, '', missingCore),
        BoardProfile.arduinoUno,
      );
      expect(error, isNot(isA<MissingBoardCoreException>()));
    });
  });

  group('installCore', () {
    test('refreshes the index, then installs, both from the core URL', () async {
      final calls = <List<String>>[];
      final output = <String>[];
      await LocalCompileService.installCore(
        pico,
        onOutput: output.add,
        run: (arguments, onOutput) async {
          calls.add(arguments);
          onOutput('ran ${arguments[1]}');
          return 0;
        },
      );
      expect(calls, [
        ['core', 'update-index', '--additional-urls', url],
        ['core', 'install', 'rp2040:rp2040', '--additional-urls', url],
      ]);
      expect(output, ['ran update-index', 'ran install']);
    });

    test('stops at a failed step and says which', () async {
      final calls = <List<String>>[];
      await expectLater(
        LocalCompileService.installCore(
          pico,
          run: (arguments, onOutput) async {
            calls.add(arguments);
            return 1;
          },
        ),
        throwsA(
          isA<CompilerException>().having((e) => e.message, 'message', contains('update-index')),
        ),
      );
      expect(calls, hasLength(1), reason: 'nothing is installed from an index that failed');
    });

    test('a board with no extra core has nothing to install', () async {
      await expectLater(
        LocalCompileService.installCore(
          BoardProfile.arduinoUno,
          run: (_, _) async => fail('nothing should run'),
        ),
        throwsA(isA<CompilerException>()),
      );
    });
  });

  group('the Problems pane', () {
    late ProviderContainer container;
    late WorkspaceSimulationDiagnostics diagnostics;

    setUp(() {
      container = ProviderContainer();
      diagnostics = container.read(Provider(WorkspaceSimulationDiagnostics.new));
    });
    tearDown(() => container.dispose());

    Problem problem() => container.read(problemsProvider).single;

    test('a missing core is offered as a fix', () {
      diagnostics.reportCompileError(
        MissingBoardCoreException('Compilation failed:\n$missingCore', board: pico),
      );
      expect(problem().message, 'The Raspberry Pi Pico W core is not installed');
      expect(problem().action?.label, 'Install the Raspberry Pi Pico W core');
    });

    test('an ordinary compile error has nothing to press', () {
      diagnostics.reportCompileError(CompilerException("error: expected ';'"));
      expect(problem().message, 'Sketch failed to compile');
      expect(problem().action, isNull);
    });

    test('a successful build clears it', () {
      diagnostics.reportCompileError(CompilerException('error: x'));
      diagnostics.reportCompileError(null);
      expect(container.read(problemsProvider), isEmpty);
    });
  });
}
