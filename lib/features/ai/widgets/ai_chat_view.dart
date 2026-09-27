import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinbench_ai/models/chat_message.dart';
import 'package:pinbench_ui/strings.dart';
import 'package:pinbench_ui/theme/text.dart';
import 'package:pinbench_ui/ui/app_icon_button.dart';
import 'package:pinbench_ui/ui/app_empty_state.dart';
import 'package:pinbench_ui/theme/tokens.dart';
import 'package:pinbench_ui/ui/app_button.dart';
import 'package:pinbench_ui/ui/app_card.dart';
import 'package:pinbench_ui/ui/app_text_field.dart';
import 'package:pinbench_ui/theme/app_colors.dart';
import 'package:pinbench_ui/theme/app_icons.dart';
import 'package:pinbench_ui/ui/app_selection_area.dart';

import '../../../core/chrome/chrome_commands.dart';
import '../providers/ai_chat_provider.dart';
import '../providers/ai_config_provider.dart';
import 'ai_proposal_card.dart';

/// The assistant panel: a transcript and a composer.
///
/// No settings form. This pane is narrow, and a form, a conversation and a
/// composer do not fit in it together — the old panel resolved that by letting
/// the form *replace* the transcript, so opening settings hid the conversation
/// and a second copy of the same fields drifted from the one in Settings. The
/// gear now opens the Settings tab, which is where the fields live.
class AiChatView extends ConsumerStatefulWidget {
  /// Creates the panel.
  const AiChatView({super.key});

  @override
  ConsumerState<AiChatView> createState() => _AiChatViewState();
}

class _AiChatViewState extends ConsumerState<AiChatView> {
  final _composer = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send() {
    final text = _composer.text.trim();
    if (text.isEmpty) return;
    _composer.clear();
    unawaited(ref.read(aiChatProvider.notifier).send(text));
    _scrollToBottom();
  }

  /// Keeps the newest turn visible as tokens arrive. Posted to the next frame
  /// because the message that triggered it has not been laid out yet, so the
  /// scroll extent is still the old one.
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(aiChatProvider);
    final isStreaming = messages.any((message) => message.isStreaming);
    final isConfigured = ref.watch(aiConfigControllerProvider).isConfigured;

    // Follow the stream as it grows, not just on send.
    ref.listen(aiChatProvider, (_, _) => _scrollToBottom());

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(hasMessages: messages.isNotEmpty),
          Expanded(
            child: !isConfigured
                ? const _NotConfiguredState()
                : messages.isEmpty
                ? const _EmptyState()
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                    itemCount: messages.length,
                    itemBuilder: (context, index) => _MessageTile(message: messages[index]),
                  ),
          ),
          Gap.vMd,
          _Composer(
            controller: _composer,
            isStreaming: isStreaming,
            onSend: _send,
            onStop: () => unawaited(ref.read(aiChatProvider.notifier).stop()),
          ),
          Gap.vXs,
          Text(
            AppStrings.aiDisclaimer,
            textAlign: TextAlign.center,
            style: AppTextStyles.smallMuted(context),
          ),
        ],
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.hasMessages});

  final bool hasMessages;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Row(
    children: [
      Expanded(
        child: Text(AppStrings.buildWithAgentHeading, style: AppTextStyles.largePrimary(context)),
      ),
      if (hasMessages)
        AppIconButton(
          icon: AppIcons.clear,
          size: AppIconButtonSize.small,
          tooltip: AppStrings.aiClearTooltip,
          onPressed: () => unawaited(ref.read(aiChatProvider.notifier).clear()),
        ),
      AppIconButton(
        icon: AppIcons.settings,
        size: AppIconButtonSize.small,
        tooltip: AppStrings.aiSettingsTooltip,
        onPressed: () => ref.read(chromeCommandsProvider).openSettingsTab(),
      ),
    ],
  );
}

/// What the pane shows before there is a model: what is missing, why a local
/// one is worth having, and the one button that leads to the fields.
class _NotConfiguredState extends ConsumerWidget {
  const _NotConfiguredState();

  @override
  Widget build(BuildContext context, WidgetRef ref) => SingleChildScrollView(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
    child: AppCard(
      title: AppStrings.aiNotConfiguredTitle,
      message: AppStrings.aiNotConfiguredBody,
      child: Align(
        alignment: Alignment.centerLeft,
        child: AppButton(
          onPressed: () => ref.read(chromeCommandsProvider).openSettingsTab(),
          child: const Text(AppStrings.aiOpenSettings),
        ),
      ),
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) =>
      const AppEmptyState(icon: AppIcons.assistant, message: AppStrings.aiEmptyStateBody);
}

class _MessageTile extends StatelessWidget {
  const _MessageTile({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isUser = message.role == ChatRole.user;
    final prose = message.prose;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: isUser ? colors.accent : colors.surface,
        borderRadius: AppRadii.smAll,
        border: Border.all(color: message.error != null ? colors.destructive : colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (message.error case final error?)
            Text(error, style: AppTextStyles.error(context))
          else if (prose.isNotEmpty)
            AppSelectableText(prose, style: AppTextStyles.body(context))
          else if (message.isStreaming)
            Text(AppStrings.aiThinking, style: AppTextStyles.smallMuted(context)),
          for (final proposal in message.proposals) AiProposalCard(proposal: proposal),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.isStreaming,
    required this.onSend,
    required this.onStop,
  });

  final TextEditingController controller;
  final bool isStreaming;
  final VoidCallback onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Expanded(
        // Enter sends, Shift+Enter breaks the line — the convention every chat
        // UI uses, and worth the shortcut wiring because prompts here are
        // usually one line.
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.enter): () {
              if (!isStreaming) onSend();
            },
          },
          child: AppTextField.multiline(
            controller: controller,
            placeholder: AppStrings.aiComposerPlaceholder,
          ),
        ),
      ),
      Gap.hSm,
      if (isStreaming)
        AppIconButton(icon: AppIcons.stop, tooltip: AppStrings.aiStopTooltip, onPressed: onStop)
      else
        AppIconButton(icon: AppIcons.send, tooltip: AppStrings.aiSendTooltip, onPressed: onSend),
    ],
  );
}
