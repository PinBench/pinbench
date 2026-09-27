import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:multiview_desktop/multiview_desktop.dart';
import 'package:feedback/feedback.dart';
import 'package:pinbench_ui/theme/theme.dart';
import 'package:pinbench_ui/ui/app_icon_button.dart';
import 'package:pinbench_ui/strings.dart';
import 'package:pinbench_ui/theme/tokens.dart';
import 'package:pinbench_ui/ui/app_toast.dart';
import 'package:pinbench_ui/ui/app_text_field.dart';
import 'package:pinbench_ui/ui/app_tooltip.dart';
import 'package:pinbench_ui/theme/app_icons.dart';

import '../../../app/router.dart';
import '../../../shell/window.dart';
import '../../../core/remote_config/feature_flags_provider.dart';
import '../../../features/canvas/providers/canvas_controller_provider.dart';
import '../../../features/canvas/utils/canvas_exporter.dart';
import '../../../features/workspace/providers/workspace_files_provider.dart';
import '../../../core/services/feedback_service.dart';
import '../../../features/workspace/widgets/leave_temporary_project_dialog.dart';
import '../../updates/update_badge_button.dart';
import 'toggle_panes_buttons.dart';
import 'web_menu_bar.dart';
import 'workspace_title.dart';

class TitleBar extends ConsumerWidget {
  const TitleBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The native title bar is hidden (TitleBarStyle.hidden), so the OS draws its
    // window controls over our title bar: macOS traffic lights on the left,
    // Windows/Linux caption buttons on the right. Reserve empty space on the
    // matching side so our content never sits under them. The web has none —
    // and neither does a full-screen window, where the OS takes its controls
    // away and the space held open for them is a gap with nothing in it.
    final controls = ref.watch(windowIsFullScreenProvider)
        ? (left: 0.0, right: 0.0)
        : _windowControlsInsets;

    // Current effective brightness, so the toggle shows the target theme's icon
    // and flips to the opposite even when following the system.
    final themeMode = ref.watch(themeModeProvider);
    final platformDark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final isDark =
        themeMode == AppThemeMode.dark || (themeMode == AppThemeMode.system && platformDark);
    final showGlobalSearch = ref.watch(featureFlagsProvider).globalSearchEnabled;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onDoubleTap: () async {
        final mv = MultiViewDesktop.of(context);
        final isMaximized = await mv.isMaximized();
        if (isMaximized) {
          await mv.unmaximize();
        } else {
          await mv.maximize();
        }
      },
      child: Container(
        // A rule, not a gap: the title bar is a band of chrome, and the panes
        // below start at its edge rather than floating away from it.
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        child: _CentredTitleBar(
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Animated rather than added and removed: entering full screen is
              // itself a half-second zoom, and a reserve that vanished in one
              // frame made the row jump inside a window that was still moving.
              AnimatedContainer(
                duration: AppMotion.normal,
                curve: AppMotion.curve,
                width: controls.left,
              ),
              const _HomeButton(),
              const WebMenuBar(),
            ],
          ),
          // The centre of the *window*, which is the whole point of the layout
          // around this: what goes here names what the window is showing.
          middle: showGlobalSearch
              ? const AppTooltip(
                  message: AppStrings.searchComingSoonTooltip,
                  child: AppTextField(placeholder: AppStrings.globalSearchPlaceholder),
                )
              : const WorkspaceTitle(),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                spacing: AppSpacing.md,
                children: [
                  // First in the cluster, and absent entirely unless there is
                  // an update — see UpdateBadgeButton.
                  const UpdateBadgeButton(),
                  AppIconButton(
                    icon: isDark ? AppIcons.themeLight : AppIcons.themeDark,
                    tooltip: isDark
                        ? AppStrings.themeToggleTooltipLight
                        : AppStrings.themeToggleTooltipDark,
                    shortcutLabel: '⇧⌘L',
                    onPressed: () => ref
                        .read(themeModeProvider.notifier)
                        .setMode(isDark ? AppThemeMode.light : AppThemeMode.dark),
                  ),
                  if (!kIsWeb)
                    AppIconButton(
                      icon: AppIcons.feedback,
                      tooltip: AppStrings.sendFeedbackTooltip,
                      onPressed: () {
                        BetterFeedback.of(context).show((feedback) {
                          unawaited(FeedbackService.sendFeedback(feedback));
                        });
                      },
                    ),
                  AppIconButton(
                    icon: AppIcons.exportImage,
                    tooltip: AppStrings.exportCircuitTooltip,
                    shortcutLabel: '⌘E',
                    onPressed: () async {
                      final controller = ref.read(canvasControllerProvider.notifier);
                      final success = await CanvasExporter.exportToPng(controller);
                      if (context.mounted && success) {
                        showAppToast(
                          context,
                          title: AppStrings.exportSuccessTitle,
                          message: AppStrings.exportSuccessMessage,
                        );
                      } else if (context.mounted && !success) {
                        showAppToast(
                          context,
                          title: AppStrings.exportFailedTitle,
                          message: AppStrings.exportFailedMessage,
                          isError: true,
                        );
                      }
                    },
                  ),
                  const TogglePanesButtons(),
                ],
              ),
              AnimatedContainer(
                duration: AppMotion.normal,
                curve: AppMotion.curve,
                width: controls.right,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Empty space to leave for the OS window controls that overlap the (hidden)
  /// title bar. macOS reserves the left for its traffic lights; Windows/Linux
  /// reserve the right for the caption buttons; the web has no OS controls, and
  /// nor does a full-screen window — see the call site.
  ({double left, double right}) get _windowControlsInsets {
    if (kIsWeb) return (left: 0, right: 0);
    switch (defaultTargetPlatform) {
      case TargetPlatform.macOS:
        return (left: 70, right: 0);
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        return (left: 0, right: 138);
      case _:
        return (left: 0, right: 0);
    }
  }
}

/// The three parts of the title bar, with the middle one centred on the bar
/// itself.
///
/// A `Row` cannot do this. Its middle child is centred in whatever the other
/// two leave over, so the title sits in the middle of the *remaining* space —
/// and since the two sides are never the same width, that is visibly off
/// centre, drifting further as either side grows.
///
/// So the middle is positioned against the bar's own width, and kept clear of
/// the sides by being allowed only the space left once the *wider* of the two
/// is accounted for on both sides. That is what keeps it centred and out from
/// under them at the same time: reserving each side's own width would centre it
/// in the gap again. It ellipsizes into whatever is left, and disappears
/// entirely when there is nothing.
/// It is also as tall as its tallest part and no taller, which is what the
/// `Row` gave for free and is why this is a render object rather than a
/// `CustomMultiChildLayout`: that one settles its own size *before* laying its
/// children out, so it can only be as big as its constraints allow — and the
/// title bar sits in a `Column`, which offers it infinite height.
class _CentredTitleBar extends MultiChildRenderObjectWidget {
  _CentredTitleBar({required Widget leading, required Widget middle, required Widget trailing})
    : super(children: [leading, middle, trailing]);

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderCentredTitleBar();
}

class _TitleBarParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderCentredTitleBar extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _TitleBarParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _TitleBarParentData> {
  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _TitleBarParentData) child.parentData = _TitleBarParentData();
  }

  @override
  void performLayout() {
    final leading = firstChild!;
    final middle = childAfter(leading)!;
    final trailing = childAfter(middle)!;

    // The sides first, at whatever they come to: what the middle may have
    // depends on them, and neither of them depends on the middle.
    final sides = BoxConstraints.loose(Size(constraints.maxWidth, constraints.maxHeight));
    leading.layout(sides, parentUsesSize: true);
    trailing.layout(sides, parentUsesSize: true);

    final widest = math.max(leading.size.width, trailing.size.width);
    middle.layout(
      BoxConstraints.loose(
        Size(math.max(0, constraints.maxWidth - 2 * widest), constraints.maxHeight),
      ),
      parentUsesSize: true,
    );

    size = constraints.constrain(
      Size(
        constraints.maxWidth,
        math.max(leading.size.height, math.max(middle.size.height, trailing.size.height)),
      ),
    );

    void place(RenderBox child, double x) => (child.parentData! as _TitleBarParentData).offset =
        Offset(x, (size.height - child.size.height) / 2);

    place(leading, 0);
    place(trailing, size.width - trailing.size.width);
    place(middle, (size.width - middle.size.width) / 2);
  }

  @override
  double computeMaxIntrinsicHeight(double width) => [
    for (var child = firstChild; child != null; child = childAfter(child))
      child.getMaxIntrinsicHeight(width),
  ].reduce(math.max);

  @override
  double computeMinIntrinsicHeight(double width) => computeMaxIntrinsicHeight(width);

  @override
  void paint(PaintingContext context, Offset offset) => defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

/// "Back to Welcome" button shown in the title bar while a workspace is open.
///
/// Closes the workspace directly, then navigates to `/` — on the web this
/// also keeps the browser URL and history in sync. The direct close is
/// needed because workspaces opened without a route change (blank project,
/// "Open Folder") never leave `/`, so `HomeRoute().go()` alone would be a
/// same-location no-op and `_HomeView`'s route-entry `closeFolder()` would
/// never fire.
class _HomeButton extends ConsumerWidget {
  const _HomeButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasWorkspace = ref.watch(workspaceFilesProvider.select((s) => s.workspacePath != null));
    if (!hasWorkspace) return const SizedBox.shrink();
    return AppIconButton(
      icon: AppIcons.home,
      tooltip: AppStrings.backToWelcomeTooltip,
      shortcutLabel: '⇧⌘H',
      onPressed: () async {
        // A temporary project is discarded by leaving, so ask first.
        if (!await confirmLeavingTemporaryProject(context, ref)) return;
        if (!context.mounted) return;
        ref.read(workspaceFilesProvider.notifier).closeFolder();
        const HomeRoute().go(context);
      },
    );
  }
}
