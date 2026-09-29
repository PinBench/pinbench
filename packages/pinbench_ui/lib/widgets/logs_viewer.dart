import 'package:flutter/widgets.dart';

import '../strings.dart';
import '../theme/tokens.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../ui/app_selection_area.dart';

class const LogsViewer({
  super.key,
  required final String title,
  required final List<String> logs,
  required final VoidCallback onClear,
  final IconData? emptyIcon,
  final String? emptyMessage,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // The default shad `small`/`muted` text styles carry no color, so they'd
    // fall back to the ambient DefaultTextStyle and not track the theme. Set the
    // colour explicitly from the colorScheme so log text flips with light/dark.
    final scheme = context.appColors;
    return Column(
      children: [
        if (logs.isEmpty)
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    emptyIcon ?? AppIcons.fileText,
                    size: AppIconSize.hero,
                    color: scheme.mutedForeground.withValues(alpha: 0.5),
                  ),
                  Gap.vXl,
                  Text(
                    emptyMessage ?? AppStrings.defaultEmptyLogsMessage,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: MouseRegion(
              cursor: SystemMouseCursors.text,
              child: AppSelectionArea(
                child: ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  itemCount: logs.length,
                  itemBuilder: (context, index) {
                    final actualIndex = logs.length - 1 - index;
                    return Text(logs[actualIndex].trimRight());
                  },
                ),
              ),
            ),
          ),
      ],
    );
  }
}
