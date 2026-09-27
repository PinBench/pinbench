import 'package:flutter/widgets.dart';

import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/c.dart';
import 'package:re_highlight/languages/cpp.dart';
import 'package:re_highlight/styles/vs.dart';
import 'package:re_highlight/styles/vs2015.dart';
import 'package:pinbench_ui/theme/app_colors.dart';

import '../../../core/shortcuts/app_intents.dart';
import '../syntax/cdl_syntax.dart';
import '../syntax/pdl_syntax.dart';
import 'autocomplete_view.dart';

class CustomCodeEditor extends StatelessWidget {
  final CodeLineEditingController controller;
  final String filePath;

  const CustomCodeEditor({super.key, required this.controller, required this.filePath});

  @override
  Widget build(BuildContext context) {
    // Drive everything off the app's own brightness, not Material `Theme.of`.
    // `context.appBrightness` is provided app-wide (incl. multiview_desktop
    // windows) and switches reliably, whereas the Material brightness under it
    // isn't guaranteed to track — which left the editor's syntax colors and
    // text stuck on the light "vs" style.
    final scheme = context.appColors;
    final isDark = context.appBrightness == Brightness.dark;

    final isCdl = filePath.endsWith('.cdl');
    final isPdl = filePath.endsWith('.pdl');
    final langMode = isCdl ? langCdl : (isPdl ? langPdl : langCpp);

    return CodeAutocomplete(
      viewBuilder: (context, notifier, onSelected) =>
          AutocompleteOptionsView(notifier: notifier, onSelected: onSelected),
      promptsBuilder: DefaultCodeAutocompletePromptsBuilder(language: langMode),
      child: CodeEditor(
        controller: controller,
        shortcutOverrideActions: {
          CodeShortcutSaveIntent: CallbackAction<CodeShortcutSaveIntent>(
            onInvoke: (intent) {
              Actions.invoke(context, const SaveIntent());
              return null;
            },
          ),
        },
        style: CodeEditorStyle(
          fontSize: 14,
          // Editor chrome follows the app theme so code text, background, cursor
          // and selection all flip with light/dark instead of using re_editor's
          // fixed defaults.
          backgroundColor: scheme.surface,
          textColor: scheme.foreground,
          cursorColor: scheme.primary,
          selectionColor: scheme.primary.withValues(alpha: 0.25),
          cursorLineColor: scheme.foreground.withValues(alpha: 0.05),
          chunkIndicatorColor: scheme.mutedForeground,
          codeTheme: CodeHighlightTheme(
            languages: {
              'h': CodeHighlightThemeMode(mode: langC),
              'c': CodeHighlightThemeMode(mode: langC),
              'cpp': CodeHighlightThemeMode(mode: langCpp),
              'ino': CodeHighlightThemeMode(mode: langCpp),
              'hpp': CodeHighlightThemeMode(mode: langCpp),
              'cdl': CodeHighlightThemeMode(mode: langCdl),
              'pdl': CodeHighlightThemeMode(mode: langPdl),
            },
            theme: isDark ? vs2015Theme : vsTheme,
          ),
        ),
        indicatorBuilder: (context, editingController, chunkController, notifier) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DefaultCodeLineNumber(controller: editingController, notifier: notifier),
            DefaultCodeChunkIndicator(width: 20, controller: chunkController, notifier: notifier),
          ],
        ),
      ),
    );
  }
}
