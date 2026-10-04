import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:plat/plat.dart';
import 'package:pinbench_ui/theme/tokens.dart';
import 'package:pinbench_ui/theme/app_colors.dart';

import '../../features/workspace/providers/problems_provider.dart';
import '../controllers/app_layout_controller.dart';
import '../providers/layout_provider.dart';

/// One tab in a tab strip.
///
/// A browser-style tab: the active one is filled with the pane color it opens
/// onto and flares outward at the bottom, so it reads as continuous with the
/// view below it. The flare is why the strip needs the hover-aware separators
/// in `Layout` — a straight rule butted against a curve reads as a fault.
class const ChromeTab({super.key, required final PlatTabDetails tab, final Widget? child})
    extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isActive = tab.states.contains(WidgetState.selected);
    final isHovered = tab.states.contains(WidgetState.hovered);
    final isDragged = tab.states.contains(WidgetState.dragged);

    final isFirst = tab.index == 0;
    final isLast = tab.index >= tab.group.tabs.length - 1;
    final isNextActive = !isLast && tab.group.tabs[tab.index + 1].selected;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      if (isHovered && hoveredTabNotifier.value != tab.index) {
        hoveredTabNotifier.value = tab.index;
      } else if (!isHovered && hoveredTabNotifier.value == tab.index) {
        hoveredTabNotifier.value = -1;
      }
    });

    return ReorderableDragStartListener(
      index: tab.index,
      child: GestureDetector(
        onTap: () {
          ref.read(appLayoutControllerProvider).focusTab(tab.snapshot.id);
        },
        child: CustomPaint(
          painter: ChromeTabPainter(
            isActive: isActive,
            isHovered: isHovered,
            isDragged: isDragged,
            isFirst: isFirst,
            isLast: isLast,
            isNextActive: isNextActive,
            activeBackgroundColor: context.appColors.surface,
            hoverBackgroundColor: context.appColors.accent,
            borderColor: context.appColors.chromeBorder,
          ),
          child: _Tab(tab: tab, isActive: isActive, child: child),
        ),
      ),
    );
  }
}

class const _Tab({
  required final PlatTabDetails tab,
  required final bool isActive,
  final Widget? child,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = isActive ? context.appColors.primary : context.appColors.foreground;

    // Surface a VS Code-style count badge on the Problems tab so issues are
    // visible without opening the pane.
    final problemCount = tab.snapshot.id == 'problems' ? ref.watch(problemCountProvider) : 0;

    return Container(
      padding: const EdgeInsets.only(
        left: AppSpacing.md,
        right: AppSpacing.md,
        bottom: AppSpacing.xs,
      ),
      child: Center(
        child:
            child ??
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(tab.snapshot.title, style: TextStyle(color: color)),
                if (problemCount > 0) ...[Gap.hSm, _CountBadge(count: problemCount)],
              ],
            ),
      ),
    );
  }
}

class const _CountBadge({required final int count}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 1),
    decoration: BoxDecoration(color: context.appColors.destructive, borderRadius: AppRadii.lgAll),
    child: Text('$count'),
  );
}

class ChromeTabPainter({
  required final bool isActive,
  required final bool isHovered,
  required final bool isDragged,
  required final bool isFirst,
  required final bool isLast,
  required final bool isNextActive,
  required final Color activeBackgroundColor,
  required final Color hoverBackgroundColor,

  /// The line drawn around the active tab. It is the *same* line the pane
  /// below draws around itself — together they outline one shape, which is
  /// what makes a tab look attached to its own content.
  required final Color borderColor,
}) extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const radius = AppChrome.tabRadius;
    const margin = 6.0;
    const bottomMargin = margin;

    final paint = Paint();
    final path = Path();

    if (isActive) {
      paint.color = activeBackgroundColor;

      // Built as an *open* path — up one side, across the top, down the other
      // — because the bottom edge is the one that must not exist: it is where
      // the tab meets the view, and a line there would sever the two. Closing
      // a copy of it gives the fill its bottom.
      if (isFirst) {
        // First tab: no outward flare — its left edge starts flush with the
        // view's left edge below it.
        path.moveTo(0, size.height);
      } else {
        // Flare out to the left so the tab blends into the strip/previous tab.
        path.moveTo(-radius, size.height);
        path.arcToPoint(
          Offset(0, size.height - radius),
          radius: const Radius.circular(radius),
          clockwise: false,
        );
      }
      path.lineTo(0, radius);
      path.arcToPoint(const Offset(radius, 0), radius: const Radius.circular(radius));
      path.lineTo(size.width - radius, 0);
      path.arcToPoint(Offset(size.width, radius), radius: const Radius.circular(radius));
      path.lineTo(size.width, size.height - radius);
      path.arcToPoint(
        Offset(size.width + radius, size.height),
        radius: const Radius.circular(radius),
        clockwise: false,
      );

      canvas
        ..drawPath(
          Path.from(path)
            ..lineTo(isFirst ? 0 : -radius, size.height)
            ..close(),
          paint,
        )
        ..drawPath(
          path,
          Paint()
            ..color = borderColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = AppChrome.hairline,
        );
      return;
    } else if (isHovered) {
      paint.color = hoverBackgroundColor;
      path.addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(0, 0, size.width, size.height - bottomMargin),
          const Radius.circular(radius),
        ),
      );
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(ChromeTabPainter o) =>
      !identical(this, o) &&
      (o.activeBackgroundColor != activeBackgroundColor ||
          o.hoverBackgroundColor != hoverBackgroundColor ||
          o.borderColor != borderColor ||
          o.isActive != isActive ||
          o.isHovered != isHovered ||
          o.isFirst != isFirst ||
          o.isLast != isLast ||
          o.isNextActive != isNextActive);
}
