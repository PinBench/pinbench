import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinbench_ui/strings.dart';
import 'package:pinbench_ui/theme/tokens.dart';
import 'package:pinbench_ui/theme/app_colors.dart';
import 'package:pinbench_ui/theme/app_icons.dart';
import 'package:pinbench_ui/theme/theme.dart';

import '../../../features/workspace/providers/problems_provider.dart';

class ProblemsView extends ConsumerWidget {
  const ProblemsView({super.key});

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

class _ProblemRow extends StatelessWidget {
  const _ProblemRow({required this.problem});

  final Problem problem;

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
  };
}
