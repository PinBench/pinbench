// The only Material import left in this repo, and not by choice:
// `FTextFieldStyle.border` is typed as Material's `InputBorder`, so there is
// no other way to say "no border" to a forui field. `ui_library_boundary_test`
// records the exemption; it goes when forui migrates (duobaseio/forui#1159).
import 'package:flutter/material.dart' show InputBorder;
import 'package:flutter/widgets.dart';

import 'package:forui/forui.dart';

import '../theme/app_colors.dart';
import '../theme/tokens.dart';

/// A dropdown that picks one of [options].
///
/// Wraps the widget library so the rest of the app never names it. [options]
/// is label-to-value, which is what all of this app's selects actually are —
/// a list of labels and the value each one picks. Anything richer goes through
/// [AppSelect.rich].
///
/// [value] is what the select shows; [onChanged] fires when the user picks
/// something else. Deliberately controlled rather than holding its own state:
/// every select here is a view of something the app already owns, and one that
/// remembered its own answer would drift from it.
class AppSelect<T> extends StatelessWidget {
  const AppSelect({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.placeholder,
    this.openUpwards = false,
    this.maxHeight,
    this.bordered = true,
    this.menuWidth,
    this.height,
  }) : _itemBuilder = null,
       prefix = null;

  /// Label shown in the list, mapped to the value it selects.
  final Map<String, T> options;

  final T? value;
  final ValueChanged<T?> onChanged;
  final bool enabled;

  /// Shown when [value] is null.
  final String? placeholder;

  /// A select whose list items are widgets rather than plain labels — a colour
  /// swatch beside each name, say.
  ///
  /// [options] still maps label to value, because the closed select shows a
  /// label: the underlying widget renders the chosen entry as text and cannot
  /// reuse the item widget for it. [prefix] fills that gap, letting the caller
  /// put the current selection's own mark inside the closed control.
  const AppSelect.rich({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    required Widget Function(String label, T value) itemBuilder,
    this.enabled = true,
    this.placeholder,
    this.prefix,
    this.openUpwards = false,
    this.maxHeight,
    this.bordered = true,
    this.menuWidth,
    this.height,
  }) : _itemBuilder = itemBuilder;

  final Widget Function(String label, T value)? _itemBuilder;

  /// Shown inside the closed control, before the label.
  final Widget? prefix;

  /// Open the list above the control instead of below it, for selects near the
  /// bottom of the window where a downward list would be clipped.
  final bool openUpwards;

  /// Cap the list's height. Without one a long list runs the height of the
  /// window; this select has seventeen colours in it.
  final double? maxHeight;

  /// Draw the closed control's outline. Off for selects that sit inside
  /// something already bounded — a toolbar pill, a row of controls — where the
  /// box is a second frame around a frame.
  final bool bordered;

  /// Width of the open list. Defaults to the closed control's width, which is
  /// right when the control is wide enough to read its own contents; set it
  /// where the control is a narrow toolbar item and the list would inherit that
  /// narrowness, squeezing every item's label down to an ellipsis — or, for the
  /// selected item, whose row also carries a tick, down to nothing at all.
  final double? menuWidth;

  /// Height of the closed control, or null for the widget library's own — which
  /// is a form field's height, and too tall where a select is one item in a row
  /// of controls rather than a line of a form.
  ///
  /// The field is cropped to it rather than rebuilt shorter, which is what
  /// keeps the label centred — see [_cropped]. Anything at or above the text's
  /// own height (about 20px) works; below that it starts cutting into the text.
  final double? height;

  /// The chevron in the closed control, pointing the way the list will open.
  ///
  /// forui's default always points down. A select that opens upwards then says
  /// the opposite of what it does — and the ones that open upwards do so
  /// because they sit near the bottom of the window, where the mistake is most
  /// obvious. Otherwise identical to `FSelect.defaultIconBuilder`.
  static Widget _upwardIconBuilder(
    BuildContext context,
    FTextFieldStyle style,
    Set<FTextFieldVariant> variants,
  ) => Padding(
    padding: const EdgeInsetsDirectional.only(end: 8),
    child: IconTheme(
      data: style.iconStyle.resolve(variants),
      child: context.theme.icons.chevronUp(context),
    ),
  );

  FFieldIconBuilder<FTextFieldStyle> get _iconBuilder =>
      openUpwards ? _upwardIconBuilder : FSelect.defaultIconBuilder;

  Alignment get _fieldAnchor => openUpwards ? Alignment.topLeft : Alignment.bottomLeft;
  Alignment get _contentAnchor => openUpwards ? Alignment.bottomLeft : Alignment.topLeft;

  /// The open list's box.
  ///
  /// Must stay an *auto-width* constraint: the list floats in an overlay, so
  /// nothing above it bounds its width. A plain [FPortalConstraints] leaves
  /// that unbounded and every item lays out at infinite width, which tears
  /// down the frame. Auto-width ties the list to the closed control's width,
  /// which is also how the list is meant to look.
  /// Must stay *bounded* in width whichever branch is taken. A plain
  /// [FPortalConstraints] with no maxWidth leaves it unbounded, every item lays
  /// out at infinite width, and the frame tears down.
  FPortalConstraints get _contentConstraints {
    final height = maxHeight ?? 250;
    final width = menuWidth;
    return width == null
        ? FAutoWidthPortalConstraints(maxHeight: height)
        : FPortalConstraints(minWidth: width, maxWidth: width, maxHeight: height);
  }

  /// What a borderless select gives up, in every state.
  ///
  /// Both overrides apply to all of the field's variants rather than to the
  /// base alone: it carries a separate style for hovered, focused, disabled and
  /// error, and one left untouched brings the default back the moment the
  /// pointer arrives.
  ///
  /// The outline goes because this sits inside something already bounded — see
  /// [bordered] — and the fill goes with it. The fill is opaque and covers
  /// whatever is behind the control, including the wash [_HoverWash] paints
  /// there; forui declares a hovered variant for the field but never applies
  /// it, so there is no fill of its own to light up in its place.
  FSelectStyleDelta get _style => bordered
      ? const FSelectStyleDelta.context()
      : FSelectStyleDelta.delta(
          fieldStyles: FVariantsDelta.delta([
            FVariantOperation.all(
              FTextFieldStyleDelta.delta(
                border: FVariantsValueDelta.delta([
                  FVariantValueDeltaOperation.all(InputBorder.none),
                ]),
                color: FVariantsValueDelta.delta([
                  FVariantValueDeltaOperation.all(const Color(0x00000000)),
                ]),
              ),
            ),
          ]),
        );

  /// A borderless select answers the pointer with a wash of its own.
  ///
  /// A field shows the pointer it is a control by way of its outline, so one
  /// with [bordered] off has nothing to show: it sits in a toolbar beside icon
  /// buttons that all light up, and stays flat. This is the wash and the corner
  /// they use, so the row reacts as one set of controls.
  Widget _hoverable(Widget child) => bordered ? child : _HoverWash(child: child);

  /// The control as presented: cropped to [height] if one was asked for, and
  /// lit under the pointer if it has no border to do that for it.
  Widget _wrapped(Widget child) => _hoverable(_cropped(child));

  /// Gives the control [height] by cropping it, rather than by rebuilding it
  /// shorter.
  ///
  /// Shortening the field itself is the obvious way and it goes wrong twice
  /// over. The size variant carries a `minHeight` (36 for the medium field
  /// these all are) that an outer box cannot talk it below, so the field has to
  /// be given a tight height — and the padding under its text, which is the
  /// only thing centring the label, has to go with it, leaving the label
  /// against the top of the control with all the slack beneath it.
  /// `textAlignVertical` does not put it back: the label is laid out at the top
  /// of the content box either way.
  ///
  /// So the field keeps its own height and its own padding, and this shows a
  /// shorter window onto the middle of it. What is cropped is the even padding
  /// above and below the text, which is exactly the part that was making the
  /// control taller than it needed to be, and the label stays centred because
  /// the field never stopped centring it.
  Widget _cropped(Widget child) => height == null
      ? child
      : SizedBox(
          height: height,
          child: ClipRect(
            child: OverflowBox(maxHeight: double.infinity, child: child),
          ),
        );

  /// A borderless select answers the pointer with a wash of its own.
  ///
  /// The field's own hover state is carried by its outline, so a select with
  /// [bordered] off has nothing to show — it sits in a toolbar beside icon
  /// buttons that all light up under the pointer, and stays flat. This is the
  /// same wash they use, so a row of controls reacts as one thing.
  @override
  Widget build(BuildContext context) {
    final builder = _itemBuilder;
    if (builder != null) {
      return _wrapped(
        FSelect<T>.rich(
          style: _style,
          suffixBuilder: _iconBuilder,
          enabled: enabled,
          hint: placeholder,
          fieldAnchor: _fieldAnchor,
          contentAnchor: _contentAnchor,
          contentConstraints: _contentConstraints,
          control: FSelectControl<T>.lifted(value: value, onChange: onChanged),
          format: (value) => options.entries
              .firstWhere((e) => e.value == value, orElse: () => options.entries.first)
              .key,
          prefixBuilder: prefix == null ? null : (context, style, variants) => prefix!,
          children: [
            for (final entry in options.entries)
              FSelectItem<T>(value: entry.value, title: builder(entry.key, entry.value)),
          ],
        ),
      );
    }
    return _wrapped(_plain(context));
  }

  Widget _plain(BuildContext context) => FSelect<T>(
    style: _style,
    suffixBuilder: _iconBuilder,
    items: options,
    enabled: enabled,
    hint: placeholder,
    fieldAnchor: _fieldAnchor,
    contentAnchor: _contentAnchor,
    contentConstraints: _contentConstraints,
    // `lifted` rather than `managed`: the value lives in the app's state, and
    // the select is only reflecting it. A managed control would keep a second
    // copy that could disagree.
    control: FSelectControl<T>.lifted(value: value, onChange: onChanged),
  );
}

/// Paints the app's hover wash behind its child while the pointer is over it.
///
/// A `MouseRegion` rather than an `FTappable`: the child is already the thing
/// that handles the press, and wrapping a control in a second gesture layer
/// would take the taps it needs. This only watches.
class _HoverWash extends StatefulWidget {
  const _HoverWash({required this.child});

  final Widget child;

  @override
  State<_HoverWash> createState() => _HoverWashState();
}

class _HoverWashState extends State<_HoverWash> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: DecoratedBox(
      // The accent wash rather than `hover(background)`, which is what an
      // icon button uses: the same few percent of grey that reads clearly
      // under a 32px square is barely there under a control four times as
      // wide, and this control has no border of its own to help it. The
      // accent is the app's own "the pointer is on this" colour and it is
      // tinted, so it separates from the card underneath at any size.
      decoration: BoxDecoration(
        color: _hovered ? context.appColors.accent : null,
        borderRadius: AppRadii.smAll,
      ),
      child: widget.child,
    ),
  );
}
