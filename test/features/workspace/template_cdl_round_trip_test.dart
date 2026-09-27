import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench_parts/cdl/circuit_parser.dart';
import 'package:pinbench_parts/part_registry.dart';

/// Every `.cdl` this app ships must survive a round-trip unchanged.
///
/// The format's own grammar is tested in `packages/pinbench_cdl`. This is the other
/// half, and it belongs here rather than there: it is about the files in
/// `assets/templates/`, which the package neither ships nor knows about.
void main() {
  group('template .cdl files', () {
    // Regression guard for "opening a template shows the circuit.cdl tab as
    // unsaved": the element form a template ships in must regenerate
    // byte-for-byte after a parse -> canvas -> generate round-trip, or the
    // editor's saved snapshot won't match and the tab flips dirty on open.
    final templateFiles = Directory(
      'assets/templates',
    ).listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('circuit.cdl'));

    for (final file in templateFiles) {
      test('round-trips unchanged: ${file.path}', () {
        final text = file.readAsStringSync();
        final applied = CircuitParser.applyToCanvas(CircuitParser.parse(text), standardParts);
        final regenerated = CircuitParser.generate(applied.nodes, applied.wires);
        expect(regenerated, text);
      });
    }
  });
}
