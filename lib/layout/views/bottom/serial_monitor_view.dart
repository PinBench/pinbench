import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinbench_sim/models/simulation_state.dart';
import 'package:pinbench_ui/widgets/logs_viewer.dart';
import 'package:pinbench_ui/strings.dart';
import 'package:pinbench_ui/theme/tokens.dart';
import 'package:pinbench_ui/ui/app_button.dart';
import 'package:pinbench_ui/ui/app_text_field.dart';
import 'package:pinbench_ui/theme/app_icons.dart';

import '../../../features/simulation/providers/simulation_provider.dart';
import '../../../features/workspace/providers/debug_console_provider.dart';

class const SerialMonitorView({super.key}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<SerialMonitorView> createState() => _SerialMonitorViewState();
}

class _SerialMonitorViewState extends ConsumerState<SerialMonitorView> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text;
    if (text.isEmpty) return;
    ref.read(simulationProvider.notifier).sendSerialInput(text);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final isRunning = ref.watch(simulationProvider) == SimulationState.running;

    return Column(
      children: [
        Expanded(
          child: LogsViewer(
            title: AppStrings.serialMonitorTitle,
            logs: ref.watch(serialLogsProvider),
            onClear: () => ref.read(serialLogsProvider.notifier).clear(),
            emptyIcon: AppIcons.serialMonitor,
            emptyMessage: AppStrings.noSerialOutputMessage,
          ),
        ),
        _SerialInputBar(controller: _controller, enabled: isRunning, onSend: _send),
      ],
    );
  }
}

class const _SerialInputBar({
  required final TextEditingController controller,
  required final bool enabled,
  required final VoidCallback onSend,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.md),
    child: Row(
      children: [
        Expanded(
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.enter): () {
                if (enabled) onSend();
              },
            },
            child: AppTextField(
              controller: controller,
              enabled: enabled,
              placeholder: enabled
                  ? AppStrings.serialInputPlaceholderEnabled
                  : AppStrings.serialInputPlaceholderDisabled,
            ),
          ),
        ),
        Gap.hMd,
        AppButton(
          onPressed: enabled ? onSend : null,
          child: const Text(AppStrings.sendButtonLabel),
        ),
      ],
    ),
  );
}
