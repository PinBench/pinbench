import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/widgets.dart';

import 'package:pinbench_ui/strings.dart';
import 'package:pinbench_ui/theme/tokens.dart';
import 'package:pinbench_ui/ui/app_kbd.dart';
import 'package:pinbench_ui/theme/app_colors.dart';
import 'package:pinbench_ui/widgets/brand_logo.dart';
import 'package:pinbench_ui/widgets/brand_wash.dart';

/// Width of the cheat-sheet column, so every label/key pair aligns on the same
/// two edges rather than each row hugging its own text.
const _cheatSheetWidth = 320.0;

/// How large the mark is drawn when the pane has room for it.
const _markSize = 280.0;

/// What the editor area shows with no tab open: the mark as a watermark and
/// a few shortcuts under it, the way VS Code fills its empty editor group.
///
/// Every shortcut here is one `AppShortcuts` actually binds; a cheat sheet
/// that advertises keys which do nothing is worse than none.
class const EmptyEditorView({super.key}) extends StatelessWidget {
  /// `(label, key)` with `mod` meaning ⌘ on macOS and Ctrl elsewhere — the
  /// same both-platforms binding `AppShortcuts._bindMod` makes.
  static const _shortcuts = <(String, List<String>)>[
    (AppStrings.emptyEditorOpenFolder, ['mod', 'O']),
    (AppStrings.newUntitledFileShortcutLabel, ['mod', 'N']),
    (AppStrings.emptyEditorToggleExplorer, ['mod', 'B']),
    (AppStrings.emptyEditorRunSimulation, ['F5']),
    (AppStrings.emptyEditorOpenSettings, ['mod', ',']),
  ];

  static List<String> _keys(List<String> keys) {
    final isMac = defaultTargetPlatform == TargetPlatform.macOS;
    return [for (final key in keys) key == 'mod' ? (isMac ? '⌘' : 'Ctrl') : key];
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    // The welcome screen's ground, so the editor area looks the same whether
    // it is empty on arrival or emptied by closing every tab.
    return BrandWash(
      child: LayoutBuilder(
        builder: (context, constraints) {
          // The mark gives way first: in a short pane the shortcuts are the
          // useful half, and a mark squeezed above them helps no one.
          final markSize = (constraints.maxHeight - 360).clamp(0.0, _markSize);
          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (markSize >= 96) ...[
                    // Faint on purpose: a backdrop, not a logo. Faded as a
                    // whole rather than drawn in a pre-blended colour, so it
                    // sits on the gradient as evenly at the bottom as at
                    // the top.
                    Opacity(
                      opacity: 0.07,
                      child: BrandMark(
                        size: markSize,
                        color: colors.foreground,
                        holeColor: colors.surface,
                      ),
                    ),
                    Gap.vXxl,
                  ],
                  SizedBox(
                    width: _cheatSheetWidth,
                    child: DefaultTextStyle.merge(
                      style: TextStyle(color: colors.mutedForeground),
                      child: Column(
                        children: [
                          for (final (label, keys) in _shortcuts)
                            Padding(
                              padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                              child: AppShortcutHint(
                                label: label,
                                keys: _keys(keys),
                                spaceBetween: true,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
