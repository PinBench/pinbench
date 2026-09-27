/// The app's design tokens: the raw scales every surface measures itself
/// against. Sibling to `AppTextStyles` — same rule,
/// the app's look is tuned from one place.
///
/// Values are not arbitrary. The scale was derived from what the app already
/// drew, so adopting a token is a rename, not a redesign; the few sizes that
/// sat off-scale (5, 10, 50) round to their nearest step.
///
/// Deliberately *not* covered here: the colors inside component painters
/// (LED lens, servo housing, breadboard shell). Those model real hardware, are
/// not themeable, and must not drift toward brand color.
library;

import 'package:flutter/widgets.dart';

/// The spacing ramp. Roughly 4-based, with [sm] kept at 6 because the IDE
/// chrome (tab strips, toolbars, tree rows) is denser than the 8pt grid the
/// content surfaces use.
///
/// These stay explicitly `double` — dropping the annotation would infer `int`
/// and break every call site that expects a dimension.
abstract final class AppSpacing {
  /// 2 — hairline separation inside a single control.
  static const double xxs = 2;

  /// 4 — tight padding; tree-row vertical inset.
  static const double xs = 4;

  /// 6 — dense chrome gaps: toolbar items, tab internals, pane gutter.
  static const double sm = 6;

  /// 8 — the default gap between related controls.
  static const double md = 8;

  /// 12 — separation between groups inside one panel.
  static const double lg = 12;

  /// 16 — separation between panel sections.
  static const double xl = 16;

  /// 24 — major section breaks on content surfaces (Welcome, dialogs).
  static const double xxl = 24;

  /// 32 — page-level padding on content surfaces.
  static const double xxxl = 32;

  /// 48 — hero spacing; only the Welcome surface should need this.
  static const double huge = 48;
}

/// Corner radii. [pane] sits well above the control radii so the surfaces that
/// do float — dialogs, popovers over the window — read as surfaces while
/// controls read as controls. The IDE's own panes are flush and square; see
/// `PaneSurface`.
abstract final class AppRadii {
  /// 2 — badges and other sub-control chrome.
  static const double xs = 2;

  /// 4 — the default control radius (buttons, inputs, chips).
  static const double sm = 4;

  /// 6 — cards and popovers.
  static const double md = 6;

  /// 8 — larger cards, template tiles.
  static const double lg = 8;

  /// 12 — dialogs and other surfaces that genuinely float over the window.
  static const double pane = 12;

  static const xsRadius = Radius.circular(xs);
  static const smRadius = Radius.circular(sm);
  static const mdRadius = Radius.circular(md);
  static const lgRadius = Radius.circular(lg);
  static const paneRadius = Radius.circular(pane);

  static const xsAll = BorderRadius.all(xsRadius);
  static const smAll = BorderRadius.all(smRadius);
  static const mdAll = BorderRadius.all(mdRadius);
  static const lgAll = BorderRadius.all(lgRadius);
  static const paneAll = BorderRadius.all(paneRadius);
}

/// How big an icon is drawn.
///
/// Derived the same way as [AppSpacing]: these are the sizes the app already
/// drew, so adopting one is a rename rather than a redesign. The single value
/// that moved is the Welcome header's 44, rounded up to [hero].
///
/// Reach for [sm] by default — it is what an icon sitting in a line of body
/// text or a menu row wants — and step off it only when the icon sits beside
/// text of a different size. Sizes above [xl] are not "a bigger icon": they
/// are icons acting as illustration, and there are few of them on purpose.
///
/// Not covered here: `AppIconButtonSize`, whose members pair an icon size from
/// this ramp with the box drawn around it, and `AppEmptyStateSize`, whose three
/// sizes say how much room a placeholder has to fill rather than how large an
/// icon is. Both are components choosing from this scale, not scales of their
/// own.
abstract final class AppIconSize {
  /// 14 — beside small or muted text: hints, meta rows, inline notes.
  static const double xs = 14;

  /// 16 — the default. Menu rows, list rows, tab icons, field prefixes.
  static const double sm = 16;

  /// 18 — leads a body-size label: a section heading, a tree row.
  static const double md = 18;

  /// 20 — a status glyph that should register without being read.
  static const double lg = 20;

  /// 24 — the largest size that still reads as a control rather than art.
  static const double xl = 24;

  /// 28 — heads a card whose title is set in a large style.
  static const double xxl = 28;

  /// 32 — the icon of an oversized (xlarge) icon button.
  static const double xxxl = 32;

  /// 36 — a glyph standing in for an image, like an absent avatar.
  static const double huge = 36;

  /// 48 — an icon carrying a whole area on its own: the Welcome header, or
  /// the glyph in an empty pane.
  static const double hero = 48;

  /// 64 — bigger than [hero], for a glyph that is the only thing on screen.
  static const double display = 64;
}

/// Ready-made insets for the paddings the app repeats most. Anything one-off
/// should still be written inline — this exists to collapse the duplicates,
/// not to force every rect through a named constant.
abstract final class AppInsets {
  /// Vertical inset of a compact list/tree row.
  static const row = EdgeInsets.symmetric(vertical: AppSpacing.xs);

  /// Padding inside a toolbar or tab strip.
  static const chrome = EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs);

  /// Padding inside a card or popover body.
  static const card = EdgeInsets.all(AppSpacing.md);

  /// Padding inside a panel body.
  static const panel = EdgeInsets.all(AppSpacing.xl);

  /// Page-level padding on content surfaces.
  static const page = EdgeInsets.all(AppSpacing.xxxl);

  /// A small badge's inner padding (shortcut chips, counts).
  static const badge = EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.xxs);

  /// Padding inside a dialog. Roomier than a panel — a modal has the screen's
  /// full attention and reads as cramped at panel spacing.
  static const dialog = EdgeInsets.all(AppSpacing.xxl);
}

/// Fixed dimensions of the IDE chrome. These are structural, not stylistic —
/// changing one moves the layout, so they live apart from the spacing ramp.
abstract final class AppChrome {
  /// Thickness of the hairlines that separate the IDE's regions: pane borders,
  /// splitters, the rule under the title bar. One line, one weight — the panes
  /// are flush, so these lines are the only thing giving the layout structure.
  static const double hairline = 1;

  /// The window gutter: how far a floating pane sits from the window edge and
  /// from its neighbours. Spent in two places only — the layout's own padding,
  /// and half of it on each side of a splitter. A pane never insets itself.
  static const double paneGap = AppSpacing.sm;

  /// Height of a tab strip, and of one tab in it.
  static const double tabHeight = 35;

  /// The curve a tab's corners are cut with, and the same curve the tab strip's
  /// outline turns in at each end. One value on purpose: where the active tab
  /// sits at the edge of the strip the two lines have to be the same arc, or
  /// the join reads as a kink.
  static const double tabRadius = 10;

  /// Width of the active-tab indicator drawn along a tab's top edge.
  static const double tabIndicator = 2;

  /// Width of the active-item indicator in the activity bar.
  static const double indicatorWidth = 2;

  /// Height of that indicator.
  static const double indicatorHeight = 20;

  /// Side of the square logo/avatar in the activity bar.
  static const double logoSize = 40;

  /// Side of the leading thumbnail in a Welcome list tile.
  static const double tileThumbSize = 48;

  /// Height of one row in a menu, and of the menu bar's own buttons.
  ///
  /// Matches the row height the widget library gives a context-menu item, so
  /// the menus that drop from the bar and the ones that appear under the
  /// pointer are the same menu. Material's own default was a 48px touch target
  /// and read as a phone list.
  static const double menuRowHeight = 28;
}

/// What lifts a floating surface off the page.
///
/// One entry, and it should stay that way. The IDE is flat by design — panes
/// are separated by [AppChrome.hairline], not by shadow — so a shadow here
/// means "this is temporarily above everything", which is true of exactly one
/// class of thing: a panel that opens over the content and closes again.
///
/// It exists because Material's `elevation:` went with the rest of Material in
/// Flutter 3.47, and the two surfaces that used it were passing a raw number
/// each. A number in two files is a value nobody owns.
abstract final class AppElevation {
  /// A popup panel over the editor: the autocomplete list, and anything else
  /// that behaves like it. Tuned to read as lifted without casting a halo on
  /// a dark background, which a wider, darker shadow does.
  static const popover = [
    BoxShadow(color: Color(0x1F000000), blurRadius: 12, offset: Offset(0, 4)),
  ];
}

/// Animation timings. Anything the user drives directly ([instant], [fast])
/// must stay under ~150ms or the UI feels laggy; [slow] is for entrances the
/// user did not initiate.
abstract final class AppMotion {
  /// 50ms — near-imperceptible; state echoes that must not lag the pointer.
  static const instant = Duration(milliseconds: 50);

  /// 100ms — hover and press feedback.
  static const fast = Duration(milliseconds: 100);

  /// 150ms — the default transition.
  static const normal = Duration(milliseconds: 150);

  /// 250ms — panel and pane transitions.
  static const slow = Duration(milliseconds: 250);

  /// 400ms — deliberate, attention-drawing entrances.
  static const deliberate = Duration(milliseconds: 400);

  /// 250ms — how long an open menu waits after the pointer leaves it before
  /// closing itself. Long enough to cross the gap between a menu and the thing
  /// it belongs to, short enough that a menu you walked away from goes away.
  static const menuDismissDelay = Duration(milliseconds: 250);

  /// Default easing for size and position changes.
  static const curve = Curves.easeOutCubic;

  /// Easing for things entering the screen.
  static const enter = Curves.easeOut;
}

/// Fixed-size gaps, as widgets. Shorter and harder to typo than a bare
/// `SizedBox(height: 8)`, and they make the scale visible at the call site.
abstract final class Gap {
  static const Widget hXxs = SizedBox(width: AppSpacing.xxs);
  static const Widget hXs = SizedBox(width: AppSpacing.xs);
  static const Widget hSm = SizedBox(width: AppSpacing.sm);
  static const Widget hMd = SizedBox(width: AppSpacing.md);
  static const Widget hLg = SizedBox(width: AppSpacing.lg);
  static const Widget hXl = SizedBox(width: AppSpacing.xl);
  static const Widget hXxl = SizedBox(width: AppSpacing.xxl);
  static const Widget hXxxl = SizedBox(width: AppSpacing.xxxl);

  static const Widget vXxs = SizedBox(height: AppSpacing.xxs);
  static const Widget vXs = SizedBox(height: AppSpacing.xs);
  static const Widget vSm = SizedBox(height: AppSpacing.sm);
  static const Widget vMd = SizedBox(height: AppSpacing.md);
  static const Widget vLg = SizedBox(height: AppSpacing.lg);
  static const Widget vXl = SizedBox(height: AppSpacing.xl);
  static const Widget vXxl = SizedBox(height: AppSpacing.xxl);
  static const Widget vXxxl = SizedBox(height: AppSpacing.xxxl);
  static const Widget vHuge = SizedBox(height: AppSpacing.huge);
}
