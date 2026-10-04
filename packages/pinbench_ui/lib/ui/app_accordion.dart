import 'package:flutter/widgets.dart';

import 'package:forui/forui.dart';

import '../theme/app_colors.dart';
import '../theme/tokens.dart';

/// One collapsible section of an [AppAccordion].
class const AppAccordionSection({required final String title, required final Widget child});

/// A stack of collapsible sections, all openable at once.
///
/// Wraps the widget library so the rest of the app never names it. Sections
/// are plain data rather than widgets, because the one caller builds them from
/// a map of categories and had no use for the per-item styling the previous
/// library asked it to spell out.
///
/// Built here from forui's parts rather than with its `FAccordion`, whose
/// header answers hover only by underlining the title and has no way to give
/// it a fill. Everything else is forui's: the title style, the chevron and its
/// half turn, the focus ring and the reveal timing.
class const AppAccordion({
  super.key,
  required final List<AppAccordionSection> sections,

  /// Whether sections start open. The parts palette wants everything visible
  /// on arrival; a section you have to hunt for is a section nobody finds.
  final bool initiallyExpanded = true,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final section in sections)
        _AccordionItem(
          key: ValueKey(section.title),
          section: section,
          initiallyExpanded: initiallyExpanded,
        ),
    ],
  );
}

class const _AccordionItem({
  super.key,
  required final AppAccordionSection section,
  required final bool initiallyExpanded,
}) extends StatefulWidget {
  @override
  State<_AccordionItem> createState() => _AccordionItemState();
}

class _AccordionItemState extends State<_AccordionItem> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
    value: widget.initiallyExpanded ? 1 : 0,
  );
  late final _reveal = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
  late final _iconTurns = Tween<double>(
    begin: 0,
    end: 0.5,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

  bool get _expanded =>
      _controller.status == AnimationStatus.forward ||
      _controller.status == AnimationStatus.completed;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final instant = MediaQuery.disableAnimationsOf(context);
    _controller.duration = instant ? Duration.zero : const Duration(milliseconds: 200);
  }

  @override
  void dispose() {
    _reveal.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    if (_expanded) {
      _controller.reverse();
    } else {
      _controller.forward();
    }
    // The header's expanded semantics read [_expanded], which just changed.
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final colors = context.appColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FTappable(
          semanticsExpanded: _expanded,
          onPress: _toggle,
          builder: (context, states, child) => Stack(
            clipBehavior: Clip.none,
            children: [
              // Reaching past the row, as the Welcome tiles' fill does, so
              // the title stays in line with the grid under it.
              if (states.contains(FTappableVariant.hovered))
                Positioned.fill(
                  left: -AppSpacing.sm,
                  right: -AppSpacing.sm,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: colors.muted, borderRadius: AppRadii.mdAll),
                  ),
                ),
              child!,
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                child: Center(
                  child: FFocusedOutline(
                    style: theme.style.focusedOutlineStyle,
                    focused: states.contains(FTappableVariant.focused),
                    child: RotationTransition(
                      turns: _iconTurns,
                      child: IconTheme(
                        data: IconThemeData(
                          color: theme.colors.mutedForeground,
                          size: theme.typography.display.md.fontSize,
                        ),
                        child: theme.icons.chevronDown(context),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
            child: Text(
              widget.section.title,
              textHeightBehavior: const TextHeightBehavior(
                applyHeightToFirstAscent: false,
                applyHeightToLastDescent: false,
              ),
              style: theme.typography.display.sm.copyWith(
                fontWeight: FontWeight.w500,
                color: theme.colors.foreground,
              ),
            ),
          ),
        ),
        SizeTransition(
          sizeFactor: _reveal,
          alignment: Alignment.topCenter,
          // Out of the focus order and the semantics tree once shut, so a
          // closed section's parts are not tabbed through or read out.
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) => ExcludeFocus(
              excluding: _controller.isDismissed,
              child: ExcludeSemantics(excluding: _controller.isDismissed, child: child),
            ),
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xl),
              child: widget.section.child,
            ),
          ),
        ),
      ],
    );
  }
}
