import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:plat/plat.dart';
import 'package:pinbench_ui/ui/app_icon_button.dart';
import 'package:pinbench_ui/strings.dart';
import 'package:pinbench_ui/theme/tokens.dart';
import 'package:pinbench_ui/theme/app_icons.dart';
import 'package:pinbench_terminal/terminal_controller.dart';

import '../../../features/workspace/providers/debug_console_provider.dart';

class BottomPaneToolbar extends ConsumerWidget {
  final TabGroupSnapshot tabs;

  const BottomPaneToolbar({super.key, required this.tabs});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Find the currently selected tab
    final selectedTab = tabs.tabs.where((t) => t.selected).firstOrNull;
    final activeId = selectedTab?.id;

    if (activeId == null) {
      return const SizedBox.shrink();
    }

    final tools = <Widget>[];

    // Helper to create ghost icon buttons mimicking VS Code's toolbar
    Widget buildTool({
      required IconData icon,
      required String tooltip,
      required VoidCallback onPressed,
    }) => AppIconButton(icon: icon, tooltip: tooltip, onPressed: onPressed);

    switch (activeId) {
      case 'terminal':
        tools.addAll([
          buildTool(
            icon: AppIcons.add,
            tooltip: AppStrings.newTerminalTooltip,
            onPressed: () {
              ref.read(terminalControllerProvider.notifier).restartTerminal();
            },
          ),
          buildTool(
            icon: AppIcons.splitEditor,
            tooltip: AppStrings.splitTerminalTooltip,
            onPressed: () {},
          ),
          buildTool(
            icon: AppIcons.delete,
            tooltip: AppStrings.killTerminalTooltip,
            onPressed: () {
              ref.read(terminalControllerProvider.notifier).killTerminal();
            },
          ),
        ]);
      case 'debug_console':
        tools.addAll([
          buildTool(
            icon: AppIcons.copy,
            tooltip: AppStrings.copyConsoleTooltip,
            onPressed: () {
              final logs = ref.read(debugLogsProvider);
              unawaited(
                Clipboard.setData(ClipboardData(text: logs.map((l) => l.trimRight()).join('\r\n'))),
              );
            },
          ),
          buildTool(icon: AppIcons.filter, tooltip: AppStrings.filterTooltip, onPressed: () {}),
          buildTool(
            icon: AppIcons.blocked,
            tooltip: AppStrings.clearConsoleTooltip,
            onPressed: () {
              ref.read(debugLogsProvider.notifier).clear();
            },
          ),
        ]);
      case 'spice_logs':
        tools.addAll([
          buildTool(
            icon: AppIcons.copy,
            tooltip: AppStrings.copyLogsTooltip,
            onPressed: () {
              final logs = ref.read(spiceLogsProvider);
              unawaited(
                Clipboard.setData(ClipboardData(text: logs.map((l) => l.trimRight()).join('\r\n'))),
              );
            },
          ),
          buildTool(
            icon: AppIcons.blocked,
            tooltip: AppStrings.clearSpiceLogsTooltip,
            onPressed: () {
              ref.read(spiceLogsProvider.notifier).clear();
            },
          ),
        ]);
      case 'serial_monitor':
        tools.addAll([
          buildTool(
            icon: AppIcons.copy,
            tooltip: AppStrings.copyLogsTooltip,
            onPressed: () {
              final logs = ref.read(serialLogsProvider);
              unawaited(
                Clipboard.setData(ClipboardData(text: logs.map((l) => l.trimRight()).join('\r\n'))),
              );
            },
          ),
          buildTool(
            icon: AppIcons.blocked,
            tooltip: AppStrings.clearSerialMonitorTooltip,
            onPressed: () {
              ref.read(serialLogsProvider.notifier).clear();
            },
          ),
        ]);
    }

    if (tools.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Row(mainAxisSize: MainAxisSize.min, children: tools),
    );
  }
}
