import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinbench_ui/strings.dart';
import 'package:pinbench_ui/theme/tokens.dart';
import 'package:pinbench_ui/theme/app_colors.dart';
import 'package:pinbench_ui/theme/app_icons.dart';
import 'package:pinbench_ui/theme/theme.dart';
import 'package:pinbench_ui/ui/app_button.dart';
import 'package:pinbench_ui/ui/app_spinner.dart';
import 'package:pinbench_ui/ui/app_toast.dart';

import '../../../features/workspace/providers/problems_provider.dart';

class const ProblemsView({super.key}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final problems = ref.watch(problemsProvider);

    if (problems.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              AppIcons.success,
              size: AppIconSize.hero,
              color: colors.mutedForeground.withValues(alpha: 0.5),
            ),
            Gap.vXl,
            const Text(AppStrings.noProblemsMessage),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      itemCount: problems.length,
      itemBuilder: (context, index) => _ProblemRow(problem: problems[index]),
    );
  }
}

class const _ProblemRow({required final Problem problem}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final (icon, color) = _iconFor(problem.severity, colors);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xxs),
            child: Icon(icon, size: AppIconSize.sm, color: color),
          ),
          Gap.hMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(problem.message),
                if (problem.detail != null && problem.detail!.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xxs),
                    child: Text(problem.detail!.trim()),
                  ),
                if (problem.action case final action?)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: _ProblemActionButton(action: action),
                  ),
              ],
            ),
          ),
          Gap.hMd,
          Text(_sourceLabel(problem.source)),
        ],
      ),
    );
  }

  (IconData, Color) _iconFor(ProblemSeverity severity, AppColorScheme colors) => switch (severity) {
    ProblemSeverity.error => (AppIcons.error, colors.destructive),
    ProblemSeverity.warning => (AppIcons.warning, AppPalette.orange),
    ProblemSeverity.info => (AppIcons.info, colors.primary),
  };

  String _sourceLabel(ProblemSource source) => switch (source) {
    ProblemSource.circuit => AppStrings.problemSourceCircuitLabel,
    ProblemSource.compiler => AppStrings.problemSourceCompilerLabel,
    ProblemSource.parser => AppStrings.problemSourceParserLabel,
    ProblemSource.simulation => AppStrings.problemSourceSimulationLabel,
  };
}

/// The button for a [Problem]'s [ProblemAction]: disabled with a spinner while
/// it runs — an install takes minutes, and a second press would start a second
/// download — then a toast saying how it went.
class const _ProblemActionButton({required final ProblemAction action}) extends StatefulWidget {
  @override
  State<_ProblemActionButton> createState() => _ProblemActionButtonState();
}

class _ProblemActionButtonState extends State<_ProblemActionButton> {
  var _running = false;

  Future<void> _run() async {
    setState(() => _running = true);
    try {
      await widget.action.run();
      if (!mounted) return;
      showAppToast(context, title: widget.action.doneTitle, message: widget.action.doneMessage);
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, title: widget.action.failedTitle, message: '$e', isError: true);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: AppButton(
      variant: AppButtonVariant.outline,
      size: AppButtonSize.sm,
      onPressed: _running ? null : _run,
      prefix: _running ? const AppSpinner(size: 14) : null,
      child: Text(_running ? widget.action.runningLabel : widget.action.label),
    ),
  );
}
