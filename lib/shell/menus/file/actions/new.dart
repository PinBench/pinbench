import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:multiview_desktop/multiview_desktop.dart';
import 'package:pinbench_ui/widgets/text_input_dialog.dart';
import 'package:pinbench_ui/strings.dart';
import 'package:pinbench_ui/ui/app_page_route.dart';

import '../../../../features/workspace/providers/workspace_files_provider.dart';
import '../../../window.dart';
import '../../shared_menu_actions.dart';

Future<void> _openNewWindow() => openWindow(
  (context, windowId) => Window(windowId: windowId),
  options: WindowOptions(
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: true,
    shellOverrides: ViewShellOverrides(
      pageRouteBuilder: <T>(settings, builder) =>
          AppPageRoute<T>(settings: settings, builder: builder),
    ),
  ),
);

PlatformMenuItemGroup buildNewActions({required WidgetRef ref, required bool hasWorkspace}) =>
    PlatformMenuItemGroup(
      members: [
        PlatformMenuItem(
          label: AppStrings.newTextFileMenuLabel,
          shortcut: const SingleActivator(LogicalKeyboardKey.keyN, meta: true),
          // Needs a workspace to write the file into.
          onSelected: !hasWorkspace
              ? null
              : () async {
                  await ref.read(workspaceFilesProvider.notifier).createUntitledTextFile();
                },
        ),
        PlatformMenuItem(
          label: AppStrings.newSketchMenuLabel,
          onSelected: !hasWorkspace
              ? null
              : () => createNamedFile(
                  ref,
                  title: AppStrings.newSketchDialogTitle,
                  defaultName: 'sketch.ino',
                ),
        ),
        PlatformMenuItem(
          label: AppStrings.newCircuitMenuLabel,
          onSelected: !hasWorkspace
              ? null
              : () => createNamedFile(
                  ref,
                  title: AppStrings.newCircuitDialogTitle,
                  defaultName: 'circuit.cdl',
                ),
        ),
        PlatformMenuItem(
          label: AppStrings.newFileMenuLabel,
          shortcut: const SingleActivator(
            LogicalKeyboardKey.keyN,
            meta: true,
            control: true,
            alt: true,
          ),
          onSelected: !hasWorkspace
              ? null
              : () async {
                  final context = FocusManager.instance.primaryFocus?.context;
                  if (context == null) return;
                  final name = await showTextInputDialog(
                    context,
                    title: AppStrings.newFileDialogTitle,
                    placeholder: AppStrings.newFileNamePlaceholder,
                  );
                  if (name == null) return;
                  await ref.read(workspaceFilesProvider.notifier).createFile(name);
                },
        ),
        const PlatformMenuItem(
          label: AppStrings.newWindowMenuLabel,
          shortcut: SingleActivator(LogicalKeyboardKey.keyN, meta: true, shift: true),
          onSelected: _openNewWindow,
        ),
        const PlatformMenu(
          label: AppStrings.newWindowWithProfileMenuLabel,
          menus: [
            PlatformMenuItem(label: AppStrings.defaultProfileMenuLabel, onSelected: _openNewWindow),
          ],
        ),
      ],
    );
