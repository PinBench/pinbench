import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinbench_parts/models/board_profile.dart';
import 'package:pinbench_ui/strings.dart';

import '../../core/platform/platform_capabilities.dart';

import '../../core/telemetry/telemetry_providers.dart';
import '../../features/simulation/ports/simulation_diagnostics.dart';
import '../../features/workspace/providers/debug_console_provider.dart';
import '../../features/workspace/providers/problems_provider.dart';
import '../../features/workspace/services/compiler_service.dart';
import '../../features/workspace/services/local_compile_service.dart';

/// Binds the simulation's [SimulationDiagnostics] port to the panes that show
/// a run's output: the three log channels and the Problems list.
///
/// The compiler-output parsing below came with it. Picking the line a user
/// should read out of a wall of gcc stderr, and bucketing that failure for
/// analytics, are both about *presenting* a failure — the simulation only
/// knows the build did not produce bytes.
class const WorkspaceSimulationDiagnostics(final Ref _ref) implements SimulationDiagnostics {
  @override
  void serial(String text) => _ref.read(serialLogsProvider.notifier).addLog(text);

  @override
  void spice(String text) => _ref.read(spiceLogsProvider.notifier).addLog(text);

  @override
  void debug(String text) => _ref.read(debugLogsProvider.notifier).addLog(text);

  @override
  void clearRunLogs() {
    _ref.read(spiceLogsProvider.notifier).clear();
    _ref.read(debugLogsProvider.notifier).clear();
    _ref.read(serialLogsProvider.notifier).clear();
  }

  @override
  void reportCompileError(Object? error) {
    final problems = _ref.read(problemsProvider.notifier);
    if (error == null) {
      problems.clearSource(ProblemSource.compiler);
      return;
    }

    final detail = _firstMeaningfulLine('$error');
    // Breadcrumb (not a crash) so a later report shows the failed compile.
    _ref.read(crashReporterProvider).log('compile error: $detail');
    problems.setForSource(ProblemSource.compiler, [
      if (error is MissingBoardCoreException && PlatformCapabilities.supportsLocalCompile)
        Problem(
          severity: ProblemSeverity.error,
          source: ProblemSource.compiler,
          message: AppStrings.missingBoardCoreProblem(error.board.partName),
          detail: detail,
          action: _installCore(error.board),
        )
      else
        Problem(
          severity: ProblemSeverity.error,
          source: ProblemSource.compiler,
          message: 'Sketch failed to compile',
          detail: detail,
        ),
    ]);
  }

  /// Installs [board]'s core when the user asks, its progress in the Debug
  /// Console, then clears the problem: the next run builds.
  ProblemAction _installCore(BoardProfile board) => ProblemAction(
    label: AppStrings.installBoardCoreLabel(board.partName),
    runningLabel: AppStrings.installingBoardCoreLabel,
    doneTitle: AppStrings.boardCoreInstalledTitle,
    doneMessage: AppStrings.boardCoreInstalledMessage,
    failedTitle: AppStrings.boardCoreInstallFailedTitle,
    run: () async {
      debug('[Setup] Installing the ${board.partName} core with arduino-cli…');
      await LocalCompileService.installCore(board, onOutput: (line) => debug('[Setup] $line'));
      debug('[Setup] Installed. Run the sketch again.');
      _ref.read(problemsProvider.notifier).clearSource(ProblemSource.compiler);
    },
  );

  @override
  int get problemCount => _ref.read(problemCountProvider);

  @override
  String? get compileErrorType {
    final compilerProblems = _ref
        .read(problemsProvider)
        .where((p) => p.source == ProblemSource.compiler)
        .map((p) => p.detail)
        .join('\n');
    return compilerProblems.isEmpty ? null : _categorizeError(compilerProblems);
  }
}

/// Picks the first compiler output line that looks like an actual error, so the
/// Problems entry shows the cause rather than the "Compilation failed:" banner.
String _firstMeaningfulLine(String raw) {
  final lines = raw.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty);
  for (final line in lines) {
    final lower = line.toLowerCase();
    if (lower.contains('error:') || lower.contains('error ')) return line;
  }
  return lines.isNotEmpty ? lines.first : raw;
}

/// Categorizes a compiler error message into a general type for analytics.
String _categorizeError(String message) {
  final lower = message.toLowerCase();
  if (lower.contains('syntax error') || lower.contains('expected')) return 'syntax_error';
  if (lower.contains('not declared') || lower.contains('was not declared')) {
    return 'undeclared_identifier';
  }
  if (lower.contains('no such file') || lower.contains('fatal error')) return 'missing_header';
  if (lower.contains('undefined reference') || lower.contains('linker')) return 'linker_error';
  if (lower.contains('board') || lower.contains('fqbn')) return 'board_config';
  if (lower.contains('redefinition') || lower.contains('conflicting')) return 'redefinition';
  if (lower.contains('out of memory') || lower.contains('overflow')) return 'resource_exhausted';
  return 'other';
}
