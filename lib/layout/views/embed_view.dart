import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinbench_ui/strings.dart';
import 'package:pinbench_ui/theme/tokens.dart';
import 'package:pinbench_ui/ui/app_button.dart';
import 'package:pinbench_ui/theme/app_colors.dart';

import '../../features/canvas/widgets/controls/simulation_controls.dart';
import '../../features/canvas/widgets/controls/zoom_controls.dart';
import '../../features/canvas/widgets/core/canvas_area.dart';
import '../../features/workspace/providers/workspace_files_provider.dart';
import '../../core/platform/open_external_url.dart';
import '../../features/workspace/services/share_link.dart';

/// The whole app, reduced to a circuit you can run — for `?embed=1`.
///
/// An embed lives in someone else's page, usually a few hundred pixels tall in
/// the middle of a tutorial. It is not a small IDE: everything that implies
/// authoring is gone, because none of it can be used here — the workspace is a
/// read-only copy of somebody else's project, so a palette, a file tree or a
/// toolbar would offer edits that go nowhere.
///
/// What survives is the part that makes the embed worth having: the circuit,
/// and a Run button so a reader can see the LED actually blink.
///
/// Also dropped: the minimap (meaningless at embed size) and the canvas
/// toolbar (component/wire tools).
class const EmbedView({super.key}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final state = ref.watch(workspaceFilesProvider);
    final projectId = state.viewingSharedProjectId ?? state.cloudProjectId;

    return ColoredBox(
      color: colors.background,
      child: Stack(
        children: [
          const CanvasArea(),
          const SimulationControls(),
          const ZoomControls(),
          if (projectId != null) _OpenInPlayground(projectId: projectId),
        ],
      ),
    );
  }
}

/// The attribution link, bottom-left.
///
/// Every embed is on someone else's page, so this is the only thing telling a
/// reader where the circuit came from — and the only route from a tutorial
/// back to the app. It opens in a new tab: navigating the host page away from
/// the article the embed is illustrating would be hostile.
///
/// Bottom-**left** because the other three corners are taken: run controls sit
/// top-left and the zoom cluster bottom-right, which this originally collided
/// with. It also carries its own backing, since canvas content scrolls beneath
/// it and bare text over the grid is unreadable.
class const _OpenInPlayground({required final String projectId}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final typography = context.appText;
    return Positioned(
      left: 8,
      bottom: 8,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.background.withValues(alpha: 0.72),
          borderRadius: AppRadii.smAll,
        ),
        // forui has no link variant, and a ghost button would add an inset
        // and a hover fill this does not want. The underline is the
        // affordance; hover answers by bringing the text up to full strength.
        child: AppTappable(
          // An embed only ever renders in a browser, but the route is
          // reachable in a desktop build and `openExternalUrl` opens the
          // system browser there, so there is nothing left to guard.
          onPressed: () => openExternalUrl(shareLinkFor(projectId)),
          // The whole style is set here, not on the text: the type scale's
          // styles carry a colour of their own, which would win over this one.
          builder: (context, child, {required hovered}) => DefaultTextStyle.merge(
            style: typography.sm.copyWith(
              color: hovered ? colors.foreground : colors.mutedForeground,
              decoration: TextDecoration.underline,
            ),
            child: child,
          ),
          child: const Padding(
            padding: AppInsets.badge,
            child: Text(AppStrings.embedOpenInAppLabel),
          ),
        ),
      ),
    );
  }
}
