import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinbench_ui/strings.dart';
import 'package:pinbench_ui/theme/text.dart';
import 'package:pinbench_ui/theme/tokens.dart';
import 'package:pinbench_ui/ui/app_toast.dart';
import 'package:pinbench_ui/ui/app_button.dart';
import 'package:pinbench_ui/ui/app_card.dart';
import 'package:pinbench_ui/ui/app_text_field.dart';
import 'package:pinbench_ui/theme/app_colors.dart';
import 'package:pinbench_ui/theme/app_icons.dart';

import '../../../../features/ai/providers/ai_config_provider.dart';
import '../../../../features/ai/services/assistant_launcher.dart';
import '../../../../core/chrome/chrome_commands.dart';
import '../../../../core/utils/logger.dart';

/// The assistant Welcome screen's headline: one box that turns a sentence into
/// a project.
///
/// Submitting creates a workspace, opens the assistant pane and sends the
/// prompt — see `AssistantLauncher`.
///
/// The box is always a box. Until a model is configured it carries a line
/// saying so and a way to Settings, and pressing Build it goes there instead of
/// failing — the form used to take the box's place here, which meant the first
/// thing the app ever showed a new user was a server URL field, and meant the
/// same form existed in three places, each with its own idea of the truth.
class WelcomePromptSection extends ConsumerStatefulWidget {
  /// Creates the prompt hero.
  const WelcomePromptSection({super.key});

  @override
  ConsumerState<WelcomePromptSection> createState() => _WelcomePromptSectionState();
}

class _WelcomePromptSectionState extends ConsumerState<WelcomePromptSection> {
  static const _log = AppLogger('app.ai.welcome');

  final _controller = TextEditingController();
  var _starting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _start([String? preset]) async {
    final prompt = (preset ?? _controller.text).trim();
    if (prompt.isEmpty || _starting) return;

    // Nothing to send the prompt to yet. Take the user to the one place that
    // fixes it rather than opening a project the assistant cannot act on.
    if (!ref.read(aiConfigControllerProvider).isConfigured) {
      _openSettings();
      return;
    }

    setState(() => _starting = true);
    // Clear before launching, not after: opening the project closes the
    // welcome screen, which disposes this controller partway through the call.
    // Coming back to Welcome later should not show an already-sent prompt.
    _controller.clear();
    try {
      await ref.read(assistantLauncherProvider).startFromPrompt(prompt);
    } catch (e, stack) {
      // Log unconditionally. By the time anything can fail here the welcome
      // screen is usually gone, so a toast alone would mean failures vanish
      // without trace — which is what a launcher bug looked like once already.
      _log.error('Starting from the welcome prompt failed', error: e, stackTrace: stack);
      if (!mounted) return;
      showAppToast(context, message: AppStrings.welcomePromptFailed(e), isError: true);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  void _openSettings() => ref.read(chromeCommandsProvider).openSettingsTab();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isConfigured = ref.watch(aiConfigControllerProvider).isConfigured;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                width: 50,
                height: 50,
                child: Icon(AppIcons.generate, size: AppIconSize.xxl, color: colors.primary),
              ),
              Gap.hLg,
              Expanded(
                child: Text(
                  AppStrings.welcomePromptHeading,
                  style: AppTextStyles.largePrimary(context),
                ),
              ),
            ],
          ),
          Gap.vMd,
          Text(AppStrings.welcomePromptSubtitle, style: AppTextStyles.smallMuted(context)),
          Gap.vMd,
          ..._composer(context),
          if (!isConfigured) ...[
            Gap.vMd,
            Row(
              children: [
                Icon(AppIcons.settings, size: AppIconSize.xs, color: colors.mutedForeground),
                Gap.hSm,
                Expanded(
                  child: Text(
                    AppStrings.aiNeedsSetupHint,
                    style: AppTextStyles.smallMuted(context),
                  ),
                ),
                AppButton(
                  variant: AppButtonVariant.outline,
                  size: AppButtonSize.sm,
                  onPressed: _openSettings,
                  child: const Text(AppStrings.aiOpenSettings),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _composer(BuildContext context) => [
    Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          // Enter submits, Shift+Enter breaks the line — the same contract as
          // the assistant panel's composer, so the two boxes behave alike.
          child: CallbackShortcuts(
            bindings: {const SingleActivator(LogicalKeyboardKey.enter): _start},
            child: AppTextField.multiline(
              controller: _controller,
              placeholder: AppStrings.welcomePromptPlaceholder,
            ),
          ),
        ),
        Gap.hMd,
        // Disabled while the box is empty. It previously stayed enabled and
        // silently did nothing, which is indistinguishable from a broken
        // button — especially since the placeholder reads like typed text.
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _controller,
          builder: (context, value, _) => AppButton(
            onPressed: _starting || value.text.trim().isEmpty ? null : _start,
            child: Text(
              _starting ? AppStrings.welcomePromptStarting : AppStrings.welcomePromptStart,
            ),
          ),
        ),
      ],
    ),
    Gap.vMd,
    // Examples double as documentation: they show the level of detail the
    // assistant works best with, which a placeholder alone cannot.
    Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      children: [
        for (final example in AppStrings.welcomePromptExamples)
          AppButton(
            variant: AppButtonVariant.outline,
            onPressed: (!_starting) ? () => unawaited(_start(example)) : null,
            size: AppButtonSize.sm,
            child: Text(example),
          ),
      ],
    ),
  ];
}
