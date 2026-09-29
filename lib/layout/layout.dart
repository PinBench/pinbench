import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:plat/plat.dart';
import 'package:pinbench_ui/strings.dart';
import 'package:pinbench_ui/widgets/pane_surface.dart';
import 'package:pinbench_ui/theme/tokens.dart';
import 'package:pinbench_ui/theme/app_colors.dart';
import 'package:pinbench_ui/ui/app_spinner.dart';

import 'components/editor_tab_item.dart';
import 'components/pane_sizing.dart';
import '../features/workspace/providers/workspace_loading_provider.dart';
import 'bars/activity/activity_bar.dart';
import 'components/chrome_tab.dart';
import 'leaf_registry.dart';
import 'providers/layout_provider.dart';
import 'bars/bottom/bottom_pane_toolbar.dart';
import 'bars/title/title_bar.dart';
import '../features/workspace/widgets/shared_project_banner.dart';

/// Wraps a `center_pane` leaf (welcome/canvas/editor content) with a spinner
/// overlay while a workspace or template is opening — but only once the wait
/// is long enough to be worth mentioning. Stacked over the leaf's
/// own content rather than the whole window, so sidebars, the bottom pane,
/// and the title/activity bars stay interactive and visible — only the
/// editor/canvas area actually being loaded into dims.
///
/// A `ConsumerWidget` of its own — not a boolean passed down from `Layout` —
/// because `PlatView`'s `leafBuilder` only re-invokes `_buildLeaf` when a
/// leaf's tab structure changes, not on every ancestor rebuild. A plain bool
/// baked in at the moment a leaf was first built would get "stuck" at
/// whatever [workspaceLoadingProvider] happened to read then. Watching the
/// provider directly here means this widget rebuilds on its own the instant
/// the provider changes, independent of whether `_buildLeaf` runs again.
class const WorkspaceLoadingScope({required final Widget child, super.key})
    extends ConsumerStatefulWidget {
  @override
  ConsumerState<WorkspaceLoadingScope> createState() => _WorkspaceLoadingScopeState();
}

class _WorkspaceLoadingScopeState extends ConsumerState<WorkspaceLoadingScope> {
  /// How long a workspace may take to open before it is worth saying so.
  ///
  /// Opening a template measures ~137ms in a profile build, and a spinner that
  /// comes and goes inside that reads as a flicker rather than as progress —
  /// the screen looks like it glitched, not like it worked. Past this, the wait
  /// is long enough that silence would look broken instead.
  static const _graceBeforeSaying = Duration(milliseconds: 200);

  Timer? _grace;
  var _showOverlay = false;

  @override
  void initState() {
    super.initState();
    // Already loading when this leaf mounts: `ref.listen` reports changes, and
    // the workspace may well have started opening before the pane it opens
    // into exists.
    _onLoadingChanged(loading: ref.read(workspaceLoadingProvider));
  }

  @override
  void dispose() {
    _grace?.cancel();
    super.dispose();
  }

  void _onLoadingChanged({required bool loading}) {
    _grace?.cancel();
    if (!loading) {
      if (_showOverlay) setState(() => _showOverlay = false);
      return;
    }
    _grace = Timer(_graceBeforeSaying, () {
      if (mounted) setState(() => _showOverlay = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(workspaceLoadingProvider, (_, loading) => _onLoadingChanged(loading: loading));

    return Stack(
      children: [
        Positioned.fill(child: widget.child),
        // Fades rather than appearing: by the time it is shown the wait is
        // long enough to be worth easing into.
        //
        // Switched rather than faded in place, so the spinner is *unmounted*
        // when it is not wanted. A `CircularProgressIndicator` left in the tree
        // at zero opacity keeps animating — a frame of work, forever, in every
        // center pane, for something nobody can see.
        Positioned.fill(
          child: IgnorePointer(
            ignoring: !_showOverlay,
            child: AnimatedSwitcher(
              duration: AppMotion.normal,
              switchInCurve: AppMotion.enter,
              child: _showOverlay ? const _WorkspaceLoadingOverlay() : const SizedBox.shrink(),
            ),
          ),
        ),
      ],
    );
  }
}

class const _WorkspaceLoadingOverlay() extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = context.appColors;
    return ColoredBox(
      color: scheme.background.withValues(alpha: 0.7),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 40, height: 40, child: AppSpinner(color: scheme.primary)),
            Gap.vXl,
            const Text(AppStrings.loadingWorkspaceLabel),
          ],
        ),
      ),
    );
  }
}

class const Layout({super.key}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(platControllerProvider);

    // The window gutter, painted once and inset once. A floating pane needs
    // ground to float on: without this the islands run into the window edge
    // and only their inner sides read as floating, which looks like a
    // rounding bug rather than a layout.
    //
    // `PaneSurface` insets nothing itself, so the gap around a pane is decided
    // in exactly two places — this padding at the window edge, and the splitter
    // thickness between two panes.
    return ColoredBox(
      color: context.appColors.background,
      child: Column(
        children: [
          // Outside the gutter: the title bar is the window's own chrome, and
          // the OS draws its controls over it at fixed coordinates.
          const TitleBar(),
          // Full-width, directly under the title bar, so "these edits are not
          // being saved anywhere" cannot be missed. Renders nothing unless the
          // workspace is a read-only view of somebody else's shared project.
          const SharedProjectBanner(),
          Expanded(
            child: Row(
              children: [
                const ActivityBar(),
                Expanded(
                  child: PaneFit(
                    controller: controller,
                    child: Stack(
                      children: [
                        // Empty editor screen sits behind PlatView;
                        // visible when the center tab group has no tabs.
                        // const EmptyEditorView(),
                        // Always render PlatView so sidebars/bottom pane stay alive.
                        PlatTheme(
                          data: PlatTheme.of(context).copyWith(
                            // The splitter *is* the gutter between two islands:
                            // its thickness is the whole gap, and it is also the
                            // handle. It paints nothing at rest — each pane
                            // already draws its own edge, so a filled splitter
                            // is a second line beside that one — and takes the
                            // accent only under the pointer, which is the only
                            // moment it is a control rather than a gap.
                            divider: PlatDividerTheme(
                              thickness: AppSpacing.xs,
                              borderRadius: AppRadii.xsAll,
                              color: WidgetStateProperty.fromMap({
                                WidgetState.pressed: context.appColors.primary,
                                WidgetState.hovered: context.appColors.primary,
                                WidgetState.focused: context.appColors.primary,
                                WidgetState.any: const Color(0x00000000),
                              }),
                            ),
                            // The strip has no fill of its own: what shows
                            // between the tabs is the window ground behind it.
                            // An unselected tab paints nothing, so it *is* that
                            // ground — one surface, not a grey band with darker
                            // shapes cut into it — and only the selected tab
                            // paints, which is what makes it the selected one.
                            //
                            // No fill, and the outline drawn by [_TabStripOutline]
                            // rather than a `Border` — a `Border` cannot curve the
                            // ends of three sides, which is the whole shape here.
                            //
                            // A theme decoration paints *behind* the tabs, which
                            // is what the shape depends on: the bottom rule runs
                            // the full width and the active tab covers its own
                            // segment of it, or the tab is fenced off from the
                            // view it opens onto.
                            tabBar: PlatTheme.of(context).tabBar.copyWith(
                              size: AppChrome.tabHeight,
                              // The strip's own 4px inset has to go, and at the
                              // theme rather than per-bar. It is what kept the
                              // first tab from sitting flush with the island's
                              // left edge, so the tab's border ran 4px inside the
                              // pane's border below it — two parallel lines where
                              // there should be one.
                              padding: EdgeInsets.zero,
                              decoration: _TabStripOutline(color: context.appColors.border),
                            ),
                          ),
                          child: PlatView(
                            controller: controller,
                            tabBar: (context, tabs) {
                              if (tabs.id == 'bottom_pane') {
                                return PlatTabBar(
                                  padding: EdgeInsets.zero,
                                  trailing: BottomPaneToolbar(tabs: tabs),
                                  separatorBuilder: (context, index) =>
                                      _buildSeparator(tabs: tabs, index: index),
                                  placeholderBuilder: (context, tab) =>
                                      _buildTabDropPreview(context: context),
                                  tabBuilder: (context, tab) => ChromeTab(tab: tab),
                                );
                              }
                              return PlatTabBar(
                                padding: EdgeInsets.zero,
                                separatorBuilder: (context, index) =>
                                    _buildSeparator(tabs: tabs, index: index),
                                placeholderBuilder: (context, tab) =>
                                    _buildTabDropPreview(context: context),
                                tabBuilder: (context, tab) => EditorTab(tab: tab),
                              );
                            },
                            leafBuilder: (context, leaf) => _buildLeaf(
                              context,
                              leaf.id,
                              leaf.data,
                              firstTabActive: _activeLeafIsFirstTab(controller.root, leaf.id),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The mark between two tabs: a short rule, which gives way to a plain gap
  /// beside the active or hovered tab. Those are drawn with a curved flare, and
  /// a straight rule butted against a curve reads as a rendering fault.
  Widget _buildSeparator({required TabGroupSnapshot tabs, required int index}) {
    final leftTab = tabs.tabs[index];
    final rightTab = index + 1 < tabs.tabs.length ? tabs.tabs[index + 1] : null;

    return ValueListenableBuilder<int?>(
      valueListenable: hoveredTabNotifier,
      builder: (context, hoveredTabIndex, _) {
        final isSelected = leftTab.selected || (rightTab?.selected ?? false);
        final isHovered = index == hoveredTabIndex || (index + 1) == hoveredTabIndex;

        final separator = Center(
          child: Container(
            width: AppChrome.tabIndicator,
            height: AppChrome.indicatorHeight,
            color: context.appColors.foreground.withValues(alpha: 0.1),
            margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
          ),
        );
        return isSelected || isHovered ? Gap.hSm : separator;
      },
    );
  }

  Widget _buildTabDropPreview({required BuildContext context}) => Center(
    child: Container(
      width: AppChrome.tabIndicator,
      height: AppChrome.indicatorHeight,
      color: context.appColors.primary,
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
    ),
  );

  /// Whether the active (rendered) leaf is the *first* tab of its tab group.
  /// The pane squares its top-left corner in that case — see
  /// [PaneSurface.squareTopLeft]. Single-leaf regions return false.
  bool _activeLeafIsFirstTab(PlatSnapshot? node, String leafId) {
    switch (node) {
      case final TabGroupSnapshot g:
        final active = g.activeTab;
        final activeLeafId = (active?.focusedLeaf ?? active?.firstLeaf)?.id;
        if (activeLeafId == leafId) return g.activeIndex == 0;
        for (final tab in g.tabs) {
          if (_activeLeafIsFirstTab(tab.child, leafId)) return true;
        }
        return false;
      case final SplitSnapshot s:
        for (final c in s.children) {
          if (_activeLeafIsFirstTab(c, leafId)) return true;
        }
        return false;
      case final SlotSnapshot s:
        return _activeLeafIsFirstTab(s.child, leafId);
      case _:
        return false;
    }
  }

  Widget _buildLeaf(BuildContext context, String id, Object? data, {bool firstTabActive = false}) {
    final child = LeafRegistry.buildChild(id, data);
    var content = LeafRegistry.isCenterPaneLeaf(id) ? WorkspaceLoadingScope(child: child) : child;
    // A side pane's contents stop shrinking at the pane's own minimum and are
    // clipped past it, rather than being squeezed to nothing while it closes.
    final pane = paneForLeaf(id);
    if (pane != null) content = PaneContentFloor(pane: pane, child: content);
    // Every pane fills its rect. A tabbed pane's strip already marks the top
    // edge, so only the untabbed regions (sidebars, the side panel) draw the
    // hairline that separates them from whatever sits above.
    final tabbed = LeafRegistry.isTabbed(id);
    return PaneSurface(
      connectedTop: tabbed,
      squareTopLeft: tabbed && firstTabActive,
      child: content,
    );
  }
}

/// The rule along the bottom of the tab strip, which closes the top of the
/// pane below it.
///
/// That is the whole outline. The strip draws no sides and no top: the tabs are
/// the top of the island and they sit on the window ground, so the only lines
/// up here belong to the tabs themselves. Sides in the strip were tried and
/// removed — they run parallel to the active tab's own border a few pixels
/// away, which reads as a doubled line, and where they turn in at the top they
/// disappear behind the tab. The island still reads as one shape because the
/// pane below carries its sides up to meet this rule.
///
/// A `Decoration` rather than a `CustomPaint` around the bar: `PlatTabBar`'s
/// builder is typed to return a `PlatTabBar`, and a theme decoration is painted
/// behind the tabs — which this rule depends on, since the active tab has to
/// cover its own segment of it or it is fenced off from the view it opens onto.
class const _TabStripOutline({required final Color color}) extends Decoration {
  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) => _TabStripOutlinePainter(color);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is _TabStripOutline && other.color == color);

  @override
  int get hashCode => color.hashCode;
}

class _TabStripOutlinePainter(final Color color) extends BoxPainter {
  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size;
    if (size == null) return;

    // Inset by half the stroke: a hairline drawn *on* the edge is half outside
    // the strip, where it is clipped and reads as a half-weight line.
    const inset = AppChrome.hairline / 2;
    final rect = (offset & size).deflate(inset);

    // Stopping short of the pane's turned corners at each end: the rule is the
    // straight run between them, and drawing it edge to edge would leave a
    // hairline tail poking out past each curve. Where the first tab is active
    // and squares the left corner, the tab's own fill covers this gap.
    canvas.drawLine(
      Offset(rect.left + AppRadii.pane, rect.bottom),
      Offset(rect.right - AppRadii.pane, rect.bottom),
      Paint()
        ..color = color
        ..strokeWidth = AppChrome.hairline,
    );
  }
}
