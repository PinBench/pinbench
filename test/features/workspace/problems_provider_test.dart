import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench/features/workspace/providers/problems_provider.dart';

Problem _p(ProblemSeverity s, ProblemSource src, String m) =>
    Problem(severity: s, source: src, message: m);

void main() {
  group('Problems', () {
    late ProviderContainer container;
    setUp(() => container = ProviderContainer());
    tearDown(() => container.dispose());

    test('aggregates problems from multiple sources', () {
      final notifier = container.read(problemsProvider.notifier);
      notifier.setForSource(ProblemSource.circuit, [
        _p(ProblemSeverity.error, ProblemSource.circuit, 'short circuit'),
      ]);
      notifier.setForSource(ProblemSource.compiler, [
        _p(ProblemSeverity.error, ProblemSource.compiler, 'build failed'),
      ]);
      expect(container.read(problemsProvider).length, 2);
    });

    test("replacing a source swaps only that source's problems", () {
      final notifier = container.read(problemsProvider.notifier);
      notifier.setForSource(ProblemSource.circuit, [
        _p(ProblemSeverity.error, ProblemSource.circuit, 'a'),
      ]);
      notifier.setForSource(ProblemSource.compiler, [
        _p(ProblemSeverity.error, ProblemSource.compiler, 'b'),
      ]);
      notifier.setForSource(ProblemSource.circuit, [
        _p(ProblemSeverity.warning, ProblemSource.circuit, 'c'),
      ]);
      final all = container.read(problemsProvider);
      expect(all.length, 2);
      expect(all.where((p) => p.source == ProblemSource.circuit).single.message, 'c');
    });

    test('sorts errors before warnings before info', () {
      final notifier = container.read(problemsProvider.notifier);
      notifier.setForSource(ProblemSource.circuit, [
        _p(ProblemSeverity.info, ProblemSource.circuit, 'i'),
        _p(ProblemSeverity.error, ProblemSource.circuit, 'e'),
        _p(ProblemSeverity.warning, ProblemSource.circuit, 'w'),
      ]);
      final severities = container.read(problemsProvider).map((p) => p.severity).toList();
      expect(severities, [ProblemSeverity.error, ProblemSeverity.warning, ProblemSeverity.info]);
    });

    test('clearSource and clearAll empty the list', () {
      final notifier = container.read(problemsProvider.notifier);
      notifier.setForSource(ProblemSource.circuit, [
        _p(ProblemSeverity.error, ProblemSource.circuit, 'a'),
      ]);
      notifier.setForSource(ProblemSource.parser, [
        _p(ProblemSeverity.error, ProblemSource.parser, 'b'),
      ]);
      notifier.clearSource(ProblemSource.circuit);
      expect(container.read(problemsProvider).length, 1);
      notifier.clearAll();
      expect(container.read(problemsProvider), isEmpty);
    });
  });
}
