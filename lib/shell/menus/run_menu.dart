import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:pinbench_sim/models/simulation_state.dart';
import 'package:pinbench_ui/strings.dart';

import '../../features/simulation/providers/simulation_provider.dart';
import '../../features/workspace/models/workspace_state.dart';
import '../../features/workspace/providers/workspace_files_provider.dart';
import 'shared_menu_actions.dart';

/// The "Run" menu: start/stop/pause the simulation, choose which sketch and
/// circuit drive it, and optionally load a precompiled `.hex` (so no online or
/// local compile is needed).
PlatformMenu runMenu({
  required WidgetRef ref,
  required bool hasWorkspace,
  required SimulationState simState,
  required WorkspaceState workspace,
}) {
  final isSimulating = simState != SimulationState.stopped;
  final isPaused = simState == SimulationState.paused;
  final notifier = ref.read(workspaceFilesProvider.notifier);

  List<String> filesWithExt(String ext) => [
    for (final f in workspace.files)
      if (f.path.toLowerCase().endsWith(ext)) f.path,
  ]..sort();

  PlatformMenuItem fileChoice(String path, String? selected, void Function() onSelect) {
    final isSelected = path == selected;
    return PlatformMenuItem(
      label: '${isSelected ? '✓ ' : '   '}${p.basename(path)}',
      onSelected: onSelect,
    );
  }

  final inoFiles = filesWithExt('.ino');
  final cdlFiles = filesWithExt('.cdl');
  final hexLoaded = workspace.precompiledHexPath != null;

  return PlatformMenu(
    label: AppStrings.runMenuLabel,
    menus: <PlatformMenuItem>[
      PlatformMenuItemGroup(
        members: [
          // No accelerators here: F5/F8 are already registered globally in
          // app_shortcuts, and adding them again would double-fire the toggle.
          PlatformMenuItem(
            label: isSimulating
                ? AppStrings.stopSimulationMenuLabel
                : AppStrings.runSimulationMenuLabel,
            onSelected: !hasWorkspace ? null : () => ref.read(simulationProvider.notifier).toggle(),
          ),
          PlatformMenuItem(
            label: isPaused
                ? AppStrings.resumeSimulationMenuLabel
                : AppStrings.pauseSimulationMenuLabel,
            onSelected: !isSimulating
                ? null
                : () => ref.read(simulationProvider.notifier).togglePause(),
          ),
        ],
      ),
      PlatformMenuItemGroup(
        members: [
          PlatformMenu(
            label: AppStrings.mainSketchMenuLabel,
            menus: [
              PlatformMenuItem(
                label:
                    '${workspace.mainInoPath == null ? '✓ ' : '   '}${AppStrings.autoFirstSketchMenuLabel}',
                onSelected: () => notifier.setMainInoPath(null),
              ),
              for (final path in inoFiles)
                fileChoice(path, workspace.mainInoPath, () => notifier.setMainInoPath(path)),
            ],
          ),
          PlatformMenu(
            label: AppStrings.mainCircuitMenuLabel,
            menus: [
              PlatformMenuItem(
                label:
                    '${workspace.mainCdlPath == null ? '✓ ' : '   '}${AppStrings.autoActiveCircuitMenuLabel}',
                onSelected: () => notifier.setMainCdlPath(null),
              ),
              for (final path in cdlFiles)
                fileChoice(path, workspace.mainCdlPath, () => notifier.setMainCdlPath(path)),
            ],
          ),
        ],
      ),
      PlatformMenuItemGroup(
        members: [
          PlatformMenuItem(
            label: hexLoaded
                ? AppStrings.loadHexMenuLabelWithFile(p.basename(workspace.precompiledHexPath!))
                : AppStrings.loadHexMenuLabel,
            onSelected: !hasWorkspace ? null : () => loadPrecompiledHexFile(notifier),
          ),
          PlatformMenuItem(
            label: AppStrings.useCompilerMenuLabel,
            onSelected: !hexLoaded ? null : notifier.clearPrecompiledHex,
          ),
        ],
      ),
    ],
  );
}
