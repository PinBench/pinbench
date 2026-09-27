import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinbench_ui/widgets/logs_viewer.dart';
import 'package:pinbench_ui/strings.dart';
import 'package:pinbench_ui/theme/app_icons.dart';

import '../../../features/workspace/providers/debug_console_provider.dart';

class DebugConsoleView extends ConsumerWidget {
  const DebugConsoleView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => LogsViewer(
    title: AppStrings.debugConsoleTitle,
    logs: ref.watch(debugLogsProvider),
    onClear: () => ref.read(debugLogsProvider.notifier).clear(),
    emptyIcon: AppIcons.problems,
    emptyMessage: AppStrings.noDebugLogsMessage,
  );
}
