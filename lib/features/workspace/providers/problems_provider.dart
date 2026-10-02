import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'problems_provider.g.dart';

/// Severity of a [Problem], ordered most-severe first for sorting.
enum ProblemSeverity() {
  error,
  warning,
  info,
}

/// Which subsystem reported a [Problem]. Used to group/replace problems by
/// origin so, e.g., re-validating the circuit only swaps circuit problems.
enum ProblemSource() {
  circuit,
  compiler,
  parser,
}

/// A single diagnostic shown in the Problems pane.
class const Problem({
  required final ProblemSeverity severity,
  required final ProblemSource source,
  required final String message,

  /// Optional secondary line (e.g. compiler stderr, a file path).
  final String? detail,

  /// What the user can do about it from the pane, when the app can fix it
  /// rather than only explain it.
  final ProblemAction? action,
});

/// A one-button remedy offered beside a [Problem]: [label] on the button,
/// [runningLabel] while [run] works — it may take minutes; installing a
/// board's core downloads a toolchain — then a toast: [doneTitle] and
/// [doneMessage] when it succeeds, [failedTitle] and the error when it throws.
class const ProblemAction({
  required final String label,
  required final String runningLabel,
  required final Future<void> Function() run,
  required final String doneTitle,
  required final String doneMessage,
  required final String failedTitle,
});

/// Aggregates diagnostics from the circuit validator, the compiler and the CDL
/// parser. Problems are stored per [ProblemSource] so each subsystem can replace
/// only its own entries without clobbering the others.
// Kept alive because the things that drive it are: `canvasCodeSyncServiceProvider`, which is keep-alive.
// A `@Riverpod(keepAlive: true)` provider reading an autoDispose one pins it
// through a `KeepAliveLink` anyway, so this is what already happens at
// runtime — saying it out loud is what `only_use_keep_alive_inside_keep_alive`
// asks for, and it stops the lifetime depending on who happens to be watching.
@Riverpod(keepAlive: true)
class Problems extends _$Problems {
  final _bySource = <ProblemSource, List<Problem>>{};

  @override
  List<Problem> build() => const [];

  /// Replaces all problems for [source] with [problems] (pass an empty list to
  /// clear that source).
  void setForSource(ProblemSource source, List<Problem> problems) {
    if (problems.isEmpty) {
      _bySource.remove(source);
    } else {
      _bySource[source] = problems;
    }
    _recompute();
  }

  /// Clears problems reported by [source].
  void clearSource(ProblemSource source) => setForSource(source, const []);

  /// Clears every problem.
  void clearAll() {
    if (_bySource.isEmpty) return;
    _bySource.clear();
    state = const [];
  }

  void _recompute() {
    final all = _bySource.values.expand((e) => e).toList()
      ..sort((a, b) => a.severity.index.compareTo(b.severity.index));
    state = all;
  }
}

/// Number of error-severity problems — handy for badges/status.
@riverpod
int problemCount(Ref ref) => ref.watch(problemsProvider).length;
