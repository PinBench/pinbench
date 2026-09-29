import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart' as xterm;
import 'package:pinbench_ui/strings.dart';
import 'package:pinbench_ui/theme/tokens.dart';
import 'package:pinbench_ui/theme/app_colors.dart';
import 'package:pinbench_ui/theme/app_icons.dart';

import 'terminal_controller.dart';

class const TerminalView({super.key}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final terminalState = ref.watch(terminalControllerProvider);
    final colors = context.appColors;

    return ColoredBox(
      color: colors.surface,
      child: terminalState.pty == null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    AppIcons.terminal,
                    size: AppIconSize.hero,
                    color: colors.mutedForeground.withValues(alpha: 0.5),
                  ),
                  Gap.vXl,
                  const Text(AppStrings.terminalClosedMessage),
                  Gap.vMd,
                  const Text(AppStrings.terminalClosedHint),
                ],
              ),
            )
          : TerminalViewWrapper(
              terminal: terminalState.terminal,
              theme: terminalTheme(context, colors),
            ),
    );
  }

  xterm.TerminalTheme terminalTheme(BuildContext context, AppColorScheme colors) {
    const defaultTheme = xterm.TerminalThemes.defaultTheme;
    // Read brightness from the app's theme, not Material's — Material's isn't
    // guaranteed to follow it in this subtree, which has broken light/dark
    // here before.
    final isDark = context.appBrightness == Brightness.dark;

    return xterm.TerminalTheme(
      cursor: colors.primary,
      selection: colors.selection,
      foreground: colors.foreground,
      background: colors.surface,
      black: isDark ? const Color(0xFF1E1E1E) : const Color(0xFF000000),
      white: isDark ? const Color(0xFFFFFFFF) : const Color(0xFFE5E5E5),
      red: defaultTheme.red,
      green: defaultTheme.green,
      yellow: defaultTheme.yellow,
      blue: defaultTheme.blue,
      magenta: defaultTheme.magenta,
      cyan: defaultTheme.cyan,
      brightBlack: defaultTheme.brightBlack,
      brightRed: defaultTheme.brightRed,
      brightGreen: defaultTheme.brightGreen,
      brightYellow: defaultTheme.brightYellow,
      brightBlue: defaultTheme.brightBlue,
      brightMagenta: defaultTheme.brightMagenta,
      brightCyan: defaultTheme.brightCyan,
      brightWhite: defaultTheme.brightWhite,
      searchHitBackground: defaultTheme.searchHitBackground,
      searchHitBackgroundCurrent: defaultTheme.searchHitBackgroundCurrent,
      searchHitForeground: defaultTheme.searchHitForeground,
    );
  }
}

class const TerminalViewWrapper({
  super.key,
  required final xterm.Terminal terminal,
  required final xterm.TerminalTheme theme,
}) extends StatefulWidget {
  @override
  State<TerminalViewWrapper> createState() => _TerminalViewWrapperState();
}

class _TerminalViewWrapperState extends State<TerminalViewWrapper> {
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () {
      _focusNode.requestFocus();
    },
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: xterm.TerminalView(
        widget.terminal,
        theme: widget.theme,
        focusNode: _focusNode,
        autofocus: true,
        hardwareKeyboardOnly: true,
      ),
    ),
  );
}
