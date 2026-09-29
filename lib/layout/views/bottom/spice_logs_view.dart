import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinbench_ui/widgets/logs_viewer.dart';
import 'package:pinbench_ui/strings.dart';
import 'package:pinbench_ui/theme/app_icons.dart';

import '../../../features/workspace/providers/debug_console_provider.dart';

class const SpiceLogsView({super.key}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) => LogsViewer(
    title: AppStrings.spiceLogsTitle,
    logs: ref.watch(spiceLogsProvider),
    onClear: () => ref.read(spiceLogsProvider.notifier).clear(),
    emptyIcon: AppIcons.memory,
    emptyMessage: AppStrings.noSpiceLogsMessage,
  );
}
