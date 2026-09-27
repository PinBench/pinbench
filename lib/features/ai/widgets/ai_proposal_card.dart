import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinbench_ai/models/file_proposal.dart';
import 'package:pinbench_ui/strings.dart';
import 'package:pinbench_ui/theme/text.dart';
import 'package:pinbench_ui/theme/tokens.dart';
import 'package:pinbench_ui/ui/app_toast.dart';
import 'package:pinbench_ui/ui/app_button.dart';
import 'package:pinbench_ui/theme/app_colors.dart';
import 'package:pinbench_ui/theme/app_icons.dart';
import 'package:pinbench_ui/ui/app_selection_area.dart';

import '../providers/ai_chat_provider.dart';

/// One file the assistant is offering, with its code and an Apply button.
///
/// Collapsed by default: the code is there to be checked before applying, and
/// an expanded sketch would push the conversation off screen. The card is the
/// only route from a model reply into the workspace.
class AiProposalCard extends ConsumerStatefulWidget {
  /// Creates a card for [proposal].
  const AiProposalCard({super.key, required this.proposal});

  /// The file being offered.
  final FileProposal proposal;

  @override
  ConsumerState<AiProposalCard> createState() => _AiProposalCardState();
}

class _AiProposalCardState extends ConsumerState<AiProposalCard> {
  var _expanded = false;
  var _applying = false;
  var _applied = false;

  Future<void> _apply() async {
    setState(() => _applying = true);
    try {
      final path = await ref.read(aiChatProvider.notifier).apply(widget.proposal);
      if (!mounted) return;
      setState(() => _applied = true);
      showAppToast(context, message: AppStrings.aiAppliedToast(path));
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, message: AppStrings.aiApplyFailed(e), isError: true);
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final proposal = widget.proposal;
    final title = switch (proposal.kind) {
      ProposalKind.circuit => AppStrings.aiProposalCircuitTitle,
      ProposalKind.sketch => AppStrings.aiProposalSketchTitle,
    };

    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.md),
      decoration: BoxDecoration(
        color: context.appColors.background,
        border: Border.all(color: context.appColors.border),
        borderRadius: AppRadii.smAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTappable(
            onPressed: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.sm,
                AppSpacing.sm,
              ),
              child: Row(
                children: [
                  Icon(
                    _expanded ? AppIcons.expanded : AppIcons.collapsed,
                    size: AppIconSize.xs,
                    color: context.appColors.mutedForeground,
                  ),
                  Gap.hXs,
                  Icon(
                    proposal.kind == ProposalKind.circuit ? AppIcons.board : AppIcons.fileCode,
                    size: AppIconSize.xs,
                  ),
                  Gap.hSm,
                  Text(title, style: AppTextStyles.label),
                  Gap.hSm,
                  Expanded(
                    child: Text(
                      proposal.label,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.smallMuted(context),
                    ),
                  ),
                  AppButton(
                    variant: AppButtonVariant.ghost,
                    onPressed: () =>
                        unawaited(Clipboard.setData(ClipboardData(text: proposal.content))),
                    size: AppButtonSize.sm,
                    child: const Text(AppStrings.aiCopy),
                  ),
                  AppButton(
                    onPressed: (!_applying) ? _apply : null,
                    size: AppButtonSize.sm,
                    child: Text(_applied ? AppStrings.aiApplied : AppStrings.aiApply),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: context.appColors.border)),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: AppSelectableText(
                  proposal.content.trimRight(),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5, height: 1.4),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
