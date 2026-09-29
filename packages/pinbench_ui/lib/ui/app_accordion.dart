import 'package:flutter/widgets.dart';

import 'package:forui/forui.dart';

/// One collapsible section of an [AppAccordion].
class const AppAccordionSection({required final String title, required final Widget child});

/// A stack of collapsible sections, all openable at once.
///
/// Wraps the widget library so the rest of the app never names it. Sections
/// are plain data rather than widgets, because the one caller builds them from
/// a map of categories and had no use for the per-item styling the previous
/// library asked it to spell out.
class const AppAccordion({
  super.key,
  required final List<AppAccordionSection> sections,

  /// Whether sections start open. The parts palette wants everything visible
  /// on arrival; a section you have to hunt for is a section nobody finds.
  final bool initiallyExpanded = true,
}) extends StatelessWidget {
  /// Each item draws a rule under itself. The palette's sections are already
  /// separated by their headers and their grids, and the call site had
  /// explicitly suppressed this before, so it stays suppressed.
  ///
  /// Made transparent rather than zero-width: the divider asserts on a width
  /// of zero, so hiding it is the only way to not have one.
  static const _noDivider = FAccordionStyleDelta.delta(
    dividerStyle: FDividerStyleDelta.delta(color: Color(0x00000000)),
  );

  @override
  Widget build(BuildContext context) => FAccordion(
    // The default control puts no cap on how many sections can be open, which
    // is what the palette wants.
    children: [
      for (final section in sections)
        FAccordionItem(
          title: Text(section.title),
          initiallyExpanded: initiallyExpanded,
          style: _noDivider,
          child: section.child,
        ),
    ],
  );
}
