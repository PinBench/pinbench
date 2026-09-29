import 'package:flutter/widgets.dart';

import 'package:pinbench_ui/strings.dart';
import 'package:pinbench_ui/theme/tokens.dart';
import 'package:pinbench_ui/ui/app_empty_state.dart';
import 'package:pinbench_ui/ui/app_kbd.dart';
import 'package:pinbench_ui/theme/app_colors.dart';
import 'package:pinbench_ui/theme/app_icons.dart';

/// Width of the cheat-sheet column, so every label/key pair aligns on the same
/// two edges rather than each row hugging its own text.
const _cheatSheetWidth = 320.0;

const _shortcuts = <(String, List<String>)>[
  (AppStrings.openChatShortcutLabel, ['^', '⌘', 'I']),
  (AppStrings.showAllCommandsShortcutLabel, ['⇧', '⌘', 'P']),
  (AppStrings.openRecentMenuLabel, ['^', 'R']),
  (AppStrings.openFileOrFolderShortcutLabel, ['⌘', 'O']),
  (AppStrings.newUntitledFileShortcutLabel, ['⌘', 'N']),
];

class const EmptyEditorView({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: context.appColors.background,
    child: AppEmptyState(
      icon: AppIcons.emptyEditor,
      size: AppEmptyStateSize.hero,
      title: AppStrings.noFileOpenHeading,
      message: AppStrings.noFileOpenSubtext,
      children: [
        SizedBox(
          width: _cheatSheetWidth,
          child: Column(
            children: [
              for (final (label, keys) in _shortcuts)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                  child: AppShortcutHint(label: label, keys: keys, spaceBetween: true),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}
