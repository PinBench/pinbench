import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinbench_sim/models/simulation_state.dart';
import 'package:pinbench_ui/strings.dart';
import 'package:pinbench_ui/ui/app_icon_button.dart';
import 'package:pinbench_ui/theme/app_icons.dart';
import 'package:pinbench_ui/theme/theme.dart';

import '../../../simulation/providers/simulation_provider.dart';

class SimulationControls extends ConsumerWidget {
  const SimulationControls({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final simulationState = ref.watch(simulationProvider);
    final isCompiling = simulationState == SimulationState.compiling;
    final isSimulating = simulationState != SimulationState.stopped;
    final isPaused = simulationState == SimulationState.paused;

    final playStopColor = isCompiling
        ? AppPalette.orange
        : isSimulating
        ? AppPalette.red
        : AppPalette.green;
    final pauseResumeColor = isPaused ? AppPalette.green : AppPalette.orange;

    return Positioned(
      top: 8,
      left: 8,
      child: Row(
        spacing: 8,
        children: [
          AppIconButton(
            ghost: false,
            color: AppPalette.white,
            isLoading: isCompiling,
            size: AppIconButtonSize.xlarge,
            backgroundColor: playStopColor,
            hoverBackgroundColor: playStopColor,
            icon: isSimulating ? AppIcons.stop : AppIcons.run,
            onPressed: () => ref.read(simulationProvider.notifier).toggle(),
            tooltip: isSimulating
                ? AppStrings.stopSimulationMenuLabelWeb
                : AppStrings.runSimulationMenuLabelWeb,
            shortcutLabel: 'F5',
          ),
          if (isSimulating && simulationState != SimulationState.compiling)
            AppIconButton(
              ghost: false,
              color: AppPalette.white,
              size: AppIconButtonSize.xlarge,
              backgroundColor: pauseResumeColor,
              hoverBackgroundColor: pauseResumeColor,
              icon: isPaused ? AppIcons.run : AppIcons.pause,
              onPressed: () => ref.read(simulationProvider.notifier).togglePause(),
              tooltip: isPaused
                  ? AppStrings.resumeSimulationMenuLabelWeb
                  : AppStrings.pauseSimulationMenuLabelWeb,
              shortcutLabel: 'F8',
            ),
        ],
      ),
    );
  }
}
