import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinbench_entitlements/pinbench_entitlements.dart';
import 'package:pinbench_ui/strings.dart';
import 'package:pinbench_ui/theme/text.dart';
import 'package:pinbench_ui/ui/app_icon_button.dart';
import 'package:pinbench_ui/theme/tokens.dart';
import 'package:pinbench_ui/ui/app_button.dart';
import 'package:pinbench_ui/ui/app_text_field.dart';
import 'package:pinbench_ui/ui/app_select.dart';
import 'package:pinbench_ui/ui/app_dialog.dart';
import 'package:pinbench_ui/theme/app_colors.dart';
import 'package:pinbench_ui/theme/app_icons.dart';
import 'package:pinbench_cloud/project_model.dart';
import 'package:pinbench_ui/theme/theme.dart';
import 'package:pinbench_ui/ui/app_spinner.dart';
import 'package:pinbench_ui/ui/app_divider.dart';
import 'package:pinbench_ui/ui/app_avatar.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/entitlements/pro_provider.dart';
import '../../../core/cloud/project_providers.dart';
import '../services/share_link.dart';

/// Sharing, in the shape people already know from Google Docs: a link that
/// grants viewing, and named invitations that grant editing.
///
/// The split is not cosmetic — it falls out of what each mechanism can
/// actually promise:
///
/// - **A link** is held by whoever it is forwarded to, so it can only ever
///   confer the permission you are willing to give a stranger. Here that is
///   read-only, enforced by the security rules rather than by the UI.
/// - **An invitation** is bound to one verified email address, so it is safe
///   to attach write access to.
///
/// Invites are stored on the project keyed by email and claimed by the
/// recipient on first open — Firebase Auth gives clients no way to turn an
/// email into a uid. See `Project.pendingInvites`.
Future<void> showShareProjectDialog(
  BuildContext context, {
  required WidgetRef ref,
  required String projectId,
}) => showAppDialog<void>(context, builder: (context) => _ShareProjectDialog(projectId: projectId));

class const _ShareProjectDialog({required final String projectId}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<_ShareProjectDialog> createState() => _ShareProjectDialogState();
}

class _ShareProjectDialogState extends ConsumerState<_ShareProjectDialog> {
  final _emailController = TextEditingController();
  var _busy = false;
  String? _error;
  String? _notice;

  /// Mirrored out of the stream so the dialog *title* can name the project —
  /// the title is built outside the StreamBuilder that has the project.
  String? _projectName;

  /// Likewise for the action bar, which needs to know whether an embed snippet
  /// would actually work before offering one.
  var _sharedByLink = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  void _flash(String message) {
    setState(() {
      _notice = message;
      _error = null;
    });
  }

  Future<void> _setVisibility(ProjectVisibility visibility) async {
    final repo = ref.read(projectRepositoryProvider);
    if (repo == null) return;
    setState(() => _busy = true);
    try {
      await repo.setVisibility(widget.projectId, visibility);
    } catch (e) {
      setState(() => _error = AppStrings.shareFailedErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Embeds are the paid half of sharing — see ProFeature.privateShareLinks.
  ///
  /// A link stays free deliberately: it is the growth loop, and gating it would
  /// cost more in reach than it could ever earn. Embedding is where the value
  /// is for the people most able to pay, and live embeds carry a real marginal
  /// cost — one open realtime subscription per reader of the page.
  ///
  /// > This is a UI gate, not enforcement. `?embed=1` is a URL anyone can type,
  /// > and nothing server-side rejects it. Real enforcement needs the embed
  /// > route to verify an entitlement against a backend that does not exist
  /// > yet. Treat this as the checkout prompt, not the lock.
  Future<void> _copyEmbed({bool live = false}) async {
    final access = ref.read(proFeatureProvider(ProFeature.privateShareLinks));
    if (access case ProDenied(:final reason)) {
      _showUpgrade(reason);
      return;
    }
    await Clipboard.setData(ClipboardData(text: embedSnippetFor(widget.projectId, live: live)));
    if (mounted) {
      _flash(live ? AppStrings.shareLiveEmbedCopiedMessage : AppStrings.shareEmbedCopiedMessage);
    }
  }

  /// Says *why*, not just no. A quota that resets, a tier that never included
  /// the feature, and a build with no subscription attached each need
  /// different words — the last one especially, since there is nothing there
  /// to upgrade.
  void _showUpgrade(ProDenialReason reason) {
    setState(() {
      _notice = null;
      _error = switch (reason) {
        ProDenialReason.notAvailableInThisBuild => AppStrings.shareEmbedUnavailableBody,
        _ => AppStrings.shareEmbedLockedBody,
      };
    });
  }

  Future<void> _copyLink() async {
    await Clipboard.setData(ClipboardData(text: shareLinkFor(widget.projectId)));
    if (mounted) _flash(AppStrings.shareLinkCopiedMessage);
  }

  Future<void> _invite() async {
    final repo = ref.read(projectRepositoryProvider);
    final email = _emailController.text.trim();
    if (repo == null) return;
    if (!isProbablyEmail(email)) {
      setState(() {
        _error = AppStrings.shareInvalidEmailMessage;
        _notice = null;
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Always editor: a viewer does not need an invitation, the link covers
      // them. Inviting someone by name is how you say "I trust this person to
      // change it".
      await repo.inviteByEmail(widget.projectId, email, ProjectRole.editor);
      _emailController.clear();
      if (mounted) _flash(AppStrings.shareInviteSentMessage);
    } catch (e) {
      setState(() => _error = AppStrings.shareFailedErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(projectRepositoryProvider);
    final myUid = ref.watch(authServiceProvider).currentUser?.uid;
    final embedLocked = !ref.watch(proFeatureProvider(ProFeature.privateShareLinks)).isAllowed;

    return AppDialog(
      title: "${AppStrings.shareDialogTitle} '${_projectName ?? ''}'".replaceAll(" ''", ''),
      child: SizedBox(
        width: 460,
        child: repo == null
            ? const SizedBox.shrink()
            : StreamBuilder<Project?>(
                stream: repo.watchProject(widget.projectId),
                builder: (context, snapshot) {
                  final project = snapshot.data;
                  if (project == null) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
                      child: Center(child: AppSpinner(size: 20)),
                    );
                  }
                  final isOwner = project.ownerId == myUid;
                  if (_sharedByLink != project.visibility.isSharedByLink) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        setState(() => _sharedByLink = project.visibility.isSharedByLink);
                      }
                    });
                  }
                  if (_projectName != project.name) {
                    // Title lives outside this builder; sync after the frame so
                    // we are not calling setState during a build.
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) setState(() => _projectName = project.name);
                    });
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Gap.vMd,
                      _inviteRow(isOwner: isOwner),
                      Gap.vLg,
                      Text(AppStrings.shareInviteSectionLabel, style: context.appText.sm),
                      Gap.vSm,
                      _people(project, isOwner: isOwner),
                      Gap.vXl,
                      const AppDivider.menu(),
                      Gap.vLg,
                      Text(AppStrings.shareLinkSectionLabel, style: context.appText.sm),
                      Gap.vSm,
                      _generalAccess(project, isOwner: isOwner),
                      if (_error != null) ...[
                        Gap.vMd,
                        Text(_error!, style: AppTextStyles.error(context)),
                      ] else if (_notice != null) ...[
                        Gap.vMd,
                        Text(_notice!, style: context.appMutedText),
                      ],
                    ],
                  );
                },
              ),
      ),
      // Copy link on the left, Done on the right — copying is the thing people
      // came to do, so it gets its own affordance rather than hiding inside the
      // general-access section.
      actions: [
        AppButton(
          variant: AppButtonVariant.outline,
          onPressed: _copyLink,
          prefix: const Icon(AppIcons.link, size: AppIconSize.sm),
          child: const Text(AppStrings.shareCopyLinkLabel),
        ),
        // Only meaningful once the link grants access: an <iframe> pointing at
        // a Restricted project renders an error for every reader of the page
        // it is pasted into.
        if (_sharedByLink) ...[
          Gap.hMd,
          AppButton(
            variant: AppButtonVariant.outline,
            onPressed: _copyEmbed,
            // Shown locked rather than hidden: someone who cannot see a feature
            // cannot decide they want it, and a padlock is a clearer answer
            // than a button that silently does nothing.
            prefix: Icon(embedLocked ? AppIcons.locked : AppIcons.code, size: AppIconSize.sm),
            child: const Text(AppStrings.shareCopyEmbedLabel),
          ),
          Gap.hMd,
          // The live variant is a separate snippet rather than a setting on the
          // project: two authors embedding the same circuit may want different
          // behaviour, and that is a property of their page, not of the
          // circuit.
          AppButton(
            variant: AppButtonVariant.outline,
            onPressed: () => _copyEmbed(live: true),
            prefix: Icon(
              embedLocked ? AppIcons.locked : AppIcons.privateLink,
              size: AppIconSize.sm,
            ),
            child: const Text(AppStrings.shareCopyLiveEmbedLabel),
          ),
        ],
        const Spacer(),
        AppButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(AppStrings.shareDoneButtonLabel),
        ),
      ],
    );
  }

  Widget _inviteRow({required bool isOwner}) => Row(
    children: [
      Expanded(
        child: AppTextField(
          controller: _emailController,
          enabled: isOwner && !_busy,
          placeholder: AppStrings.shareEmailPlaceholder,
          keyboardType: TextInputType.emailAddress,
          onSubmitted: (_) => isOwner ? _invite() : null,
        ),
      ),
      Gap.hMd,
      AppButton(
        onPressed: (isOwner && !_busy) ? _invite : null,
        child: const Text(AppStrings.shareInviteButtonLabel),
      ),
    ],
  );

  /// Owner, accepted collaborators, then still-pending invitations. Pending
  /// entries are shown rather than hidden so an owner can tell "I invited them
  /// and they have not opened it" apart from "I never invited them".
  /// Owner first, then accepted collaborators, then still-pending invitations.
  ///
  /// People are listed by email where the app knows it — see
  /// `Project.collaboratorEmails`, which is populated when an invitee claims
  /// their invite. It falls back to the raw uid for anyone added before that
  /// existed, and for the owner when they are not the signed-in user, because
  /// Firebase Auth will not let a client resolve someone else's uid.
  Widget _people(Project project, {required bool isOwner}) {
    final me = ref.watch(authServiceProvider).currentUser;

    String labelFor(String uid) {
      if (uid == me?.uid) return me?.email ?? me?.displayName ?? uid;
      return project.labelFor(uid);
    }

    final rows = <Widget>[
      _personRow(
        label: labelFor(project.ownerId),
        trailing: AppStrings.shareOwnerSuffix,
        isYou: project.ownerId == me?.uid,
      ),
      for (final entry in project.collaborators.entries)
        _personRow(
          label: labelFor(entry.key),
          trailing: entry.value.name,
          isYou: entry.key == me?.uid,
          onRemove: isOwner
              ? () => unawaited(
                  ref.read(projectRepositoryProvider)!.removeCollaborator(project.id, entry.key),
                )
              : null,
        ),
      // Shown rather than hidden, so an owner can tell "invited, has not opened
      // it yet" apart from "never invited".
      for (final entry in project.pendingInvites.entries)
        _personRow(
          label: entry.key,
          trailing: '${entry.value.name} · ${AppStrings.sharePendingSuffix}',
          isPending: true,
          onRemove: isOwner
              ? () => unawaited(
                  ref.read(projectRepositoryProvider)!.revokeInvite(project.id, entry.key),
                )
              : null,
        ),
    ];

    if (rows.length == 1) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          rows.first,
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xxs),
            child: Text(AppStrings.shareNobodyElseMessage, style: context.appMutedText),
          ),
        ],
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }

  Widget _personRow({
    required String label,
    required String trailing,
    bool isYou = false,
    bool isPending = false,
    VoidCallback? onRemove,
  }) {
    final colors = context.appColors;
    final initial = label.isEmpty ? '?' : label.characters.first.toUpperCase();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          // A monogram, not a photo: the app never learns another user's
          // avatar, and a plausible-looking blank circle reads as broken.
          AppAvatar(
            radius: 14,
            backgroundColor: isPending ? colors.muted : colors.primary.withValues(alpha: 0.15),
            child: Text(initial, style: context.appMutedText),
          ),
          Gap.hLg,
          Expanded(
            child: Text(
              isYou ? '$label ${AppStrings.shareYouSuffix}' : label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.appText.sm,
            ),
          ),
          Gap.hMd,
          Text(trailing, style: context.appMutedText),
          if (onRemove != null) ...[
            Gap.hXs,
            AppIconButton(
              icon: AppIcons.close,
              onPressed: onRemove,
              semanticLabel: AppStrings.shareRemoveCollaboratorLabel,
            ),
          ],
        ],
      ),
    );
  }

  Widget _generalAccess(Project project, {required bool isOwner}) {
    final colors = context.appColors;
    final shared = project.visibility.isSharedByLink;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.lg),
      decoration: BoxDecoration(
        // The shared state is highlighted, so "this is open to anyone" is
        // visible at a glance rather than only readable in the label.
        color: shared ? colors.muted : AppPalette.transparent,
        borderRadius: AppRadii.mdAll,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppAvatar(
            radius: 16,
            backgroundColor: shared ? colors.primary.withValues(alpha: 0.15) : colors.muted,
            child: Icon(
              shared ? AppIcons.publicLink : AppIcons.locked,
              size: AppIconSize.sm,
              color: colors.foreground,
            ),
          ),
          Gap.hLg,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppSelect<bool>(
                  enabled: isOwner && !_busy,
                  value: shared,
                  options: const {
                    AppStrings.shareLinkRestrictedTitle: false,
                    AppStrings.shareLinkAnyoneTitle: true,
                  },
                  onChanged: (value) {
                    if (value == null || value == shared) return;
                    unawaited(
                      _setVisibility(
                        value ? ProjectVisibility.unlisted : ProjectVisibility.private,
                      ),
                    );
                  },
                ),
                Gap.vXs,
                Text(
                  shared
                      ? AppStrings.shareAnyoneDescription
                      : AppStrings.shareRestrictedDescription,
                  style: context.appMutedText,
                ),
              ],
            ),
          ),
          if (shared) ...[
            Gap.hMd,
            // Static, not a dropdown: a link can only ever grant viewing here.
            // Whoever it is forwarded to holds it, so attaching write access to
            // one would mean handing edit rights to an unknown audience. To let
            // someone edit, invite them by email.
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(AppStrings.shareRoleViewerLabel, style: context.appMutedText),
            ),
          ],
        ],
      ),
    );
  }
}
