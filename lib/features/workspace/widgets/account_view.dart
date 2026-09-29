import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinbench_ui/widgets/sidebar_scaffold.dart';
import 'package:pinbench_ui/strings.dart';
import 'package:pinbench_ui/theme/text.dart';
import 'package:pinbench_ui/theme/tokens.dart';
import 'package:pinbench_ui/ui/app_empty_state.dart';
import 'package:pinbench_ui/ui/app_toast.dart';
import 'package:pinbench_ui/ui/app_button.dart';
import 'package:pinbench_ui/ui/app_card.dart';
import 'package:pinbench_ui/theme/app_colors.dart';
import 'package:pinbench_ui/theme/app_icons.dart';
import 'package:pinbench_cloud/auth/auth_user.dart';
import 'package:pinbench_cloud/auth/auth_service.dart';
import 'package:pinbench_ui/ui/app_spinner.dart';
import 'package:pinbench_ui/ui/app_avatar.dart';

import '../../../core/auth/auth_provider.dart';
import '../providers/workspace_files_provider.dart';
import 'share_project_dialog.dart';

class const AccountSidebarView({super.key}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final authService = ref.watch(authServiceProvider);

    return SidebarScaffold(
      title: 'Account',
      child: authState.when(
        loading: () => const Center(child: AppSpinner()),
        error: (err, _) => Center(child: Text(AppStrings.genericErrorMessage(err))),
        data: (user) {
          if (user != null) {
            return _SignedInView(
              user: user,
              onSignOut: () {
                unawaited(ref.read(authServiceProvider).signOut());
              },
            );
          }
          return _SignedOutView(authService: authService);
        },
      ),
    );
  }
}

class const _SignedInView({required final AuthUser user, required final VoidCallback onSignOut})
    extends ConsumerStatefulWidget {
  @override
  ConsumerState<_SignedInView> createState() => _SignedInViewState();
}

class _SignedInViewState extends ConsumerState<_SignedInView> {
  var _savingToCloud = false;

  Future<void> _saveToCloud() async {
    setState(() => _savingToCloud = true);
    try {
      final projectId = await ref.read(workspaceFilesProvider.notifier).saveWorkspaceToCloud();
      if (!mounted) return;
      if (projectId != null) {
        showAppToast(
          context,
          title: AppStrings.cloudSaveSuccessTitle,
          message: AppStrings.cloudSaveSuccessMessage,
        );
      } else {
        showAppToast(
          context,
          title: AppStrings.cloudSaveFailedTitle,
          message: AppStrings.cloudSaveFailedMessage,
          isError: true,
        );
      }
    } catch (e) {
      // Surface the failure instead of silently doing nothing — the most
      // common causes are the backend being unreachable (offline, or a
      // browser extension blocking it) or a permission error.
      if (mounted) {
        showAppToast(context, title: AppStrings.cloudSaveFailedTitle, message: '$e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _savingToCloud = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final workspaceState = ref.watch(workspaceFilesProvider);
    final cloudProjectId = workspaceState.cloudProjectId;
    final hasWorkspace = workspaceState.workspacePath != null;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        Column(
          children: [
            AppAvatar(
              radius: 36,
              image: widget.user.photoUrl == null ? null : NetworkImage(widget.user.photoUrl!),
              child: widget.user.photoUrl == null
                  ? Icon(AppIcons.user, size: AppIconSize.huge, color: colors.foreground)
                  : null,
            ),
            Gap.vLg,
            Text(widget.user.displayName ?? AppStrings.defaultUserNameFallback),
            Gap.vXs,
            Text(widget.user.email ?? ''),
            Gap.vXl,
            SizedBox(
              width: double.infinity,
              child: AppButton(
                variant: AppButtonVariant.outline,
                onPressed: widget.onSignOut,
                child: const Text(AppStrings.signOutButtonLabel),
              ),
            ),
          ],
        ),
        Gap.vXl,
        AppCard(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              Icon(AppIcons.cloudSynced, size: AppIconSize.lg, color: colors.primary),
              Gap.hMd,
              const Expanded(child: Text(AppStrings.cloudSyncHintMessage)),
            ],
          ),
        ),
        if (hasWorkspace) ...[
          Gap.vXl,
          if (cloudProjectId == null)
            SizedBox(
              width: double.infinity,
              child: AppButton(
                onPressed: _savingToCloud ? null : _saveToCloud,
                child: _savingToCloud
                    ? const SizedBox(width: 16, height: 16, child: AppSpinner(size: 20))
                    : const Text(AppStrings.saveToCloudButtonLabel),
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              child: AppButton(
                variant: AppButtonVariant.outline,
                onPressed: () {
                  unawaited(showShareProjectDialog(context, ref: ref, projectId: cloudProjectId));
                },
                child: const Text(AppStrings.shareProjectButtonLabel),
              ),
            ),
        ],
      ],
    );
  }
}

class const _SignedOutView({required final AuthService authService})
    extends ConsumerStatefulWidget {
  @override
  ConsumerState<_SignedOutView> createState() => _SignedOutViewState();
}

class _SignedOutViewState extends ConsumerState<_SignedOutView> {
  var _isSigningIn = false;
  String? _errorMessage;

  Future<void> _signIn() async {
    setState(() {
      _isSigningIn = true;
      _errorMessage = null;
    });
    try {
      await widget.authService.signInWithGoogle();
      // Success means the authStateProvider will rebuild this widget
      // automatically once the auth state stream emits the new user.
    } catch (e) {
      setState(() => _errorMessage = AppStrings.signInFailedMessage(e));
    } finally {
      if (mounted) setState(() => _isSigningIn = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.authService.enabled) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.xxl),
          child: Text(AppStrings.signInUnavailableMessage, textAlign: TextAlign.center),
        ),
      );
    }

    return AppEmptyState(
      icon: AppIcons.account,
      title: AppStrings.signInPromptMessage,
      children: [
        AppButton(
          onPressed: _isSigningIn ? null : _signIn,
          child: _isSigningIn
              ? const SizedBox(width: 20, height: 20, child: AppSpinner(size: 20))
              : const Row(
                  children: [
                    Icon(AppIcons.signIn, size: AppIconSize.md),
                    Gap.hSm,
                    Text(AppStrings.signInButtonLabel),
                  ],
                ),
        ),
        if (_errorMessage != null)
          Text(_errorMessage!, textAlign: TextAlign.center, style: AppTextStyles.error(context)),
        if (kIsWeb) const Text(AppStrings.signInPopupHintMessage, textAlign: TextAlign.center),
      ],
    );
  }
}
