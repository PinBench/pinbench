import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import 'package:forui/forui.dart';
import 'package:markdown/markdown.dart' as md;

import '../theme/app_colors.dart';
import '../theme/tokens.dart';

/// Renders a Markdown document in the app's own type and colours.
///
/// Covers what the app's own documents use — headings, paragraphs, bulleted
/// and numbered lists (nested too), quotes, rules, fenced code, and inline
/// bold, italic, strikethrough, code and links. Anything else falls back to
/// its text, so an unexpected construct reads as plain words rather than
/// vanishing.
///
/// Links do nothing unless [onTapLink] is given; the kit cannot open a URL,
/// and the app decides where one goes.
class const AppMarkdown({
  super.key,
  required final String data,
  final ValueChanged<String>? onTapLink,
}) extends StatefulWidget {
  @override
  State<AppMarkdown> createState() => _AppMarkdownState();
}

class _AppMarkdownState extends State<AppMarkdown> {
  late List<md.Node> _nodes = _parse(widget.data);

  /// Rebuilt with every build, so the previous build's are let go first.
  final _recognizers = <TapGestureRecognizer>[];

  /// The link under the pointer, by href and position among the links, so
  /// two links to the same place do not light up together.
  int? _hoveredLink;

  static List<md.Node> _parse(String data) => md.Document(
    extensionSet: md.ExtensionSet.gitHubFlavored,
    encodeHtml: false,
  ).parseLines(data.replaceAll('\r\n', '\n').split('\n'));

  @override
  void didUpdateWidget(AppMarkdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data) _nodes = _parse(widget.data);
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _hover(int? link) {
    if (!mounted || _hoveredLink == link) return;
    setState(() => _hoveredLink = link);
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    return _Builder(this, context).document(_nodes);
  }
}

/// One build's worth of rendering. Holds the styles and the running link
/// count, which numbers the links in document order for hover tracking.
class _Builder {
  new(this.state, BuildContext context)
    : colors = context.appColors,
      typography = context.theme.typography,
      text = context.appText;

  final _AppMarkdownState state;
  final AppColorScheme colors;
  final FTypography typography;
  final AppTypography text;
  var _links = 0;

  TextStyle get body => text.md.copyWith(color: colors.foreground, height: 1.6);

  TextStyle heading(int level) => switch (level) {
    1 => typography.display.xl2.copyWith(fontWeight: FontWeight.w700),
    2 => typography.display.xl.copyWith(fontWeight: FontWeight.w600),
    3 => typography.display.lg.copyWith(fontWeight: FontWeight.w600),
    _ => text.lg.copyWith(fontWeight: FontWeight.w600),
  }.copyWith(color: colors.foreground);

  static const _mono = ['Menlo', 'Consolas', 'DejaVu Sans Mono', 'monospace'];

  Widget document(List<md.Node> nodes) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: blocks(nodes));

  /// Block-level children, spaced. Runs of inline nodes — a tight list item's
  /// text has no paragraph around it — are gathered into one paragraph.
  List<Widget> blocks(List<md.Node> nodes) {
    final out = <Widget>[];
    final inline = <md.Node>[];

    void flush() {
      if (inline.isEmpty) return;
      out.add(paragraph(List.of(inline), body));
      inline.clear();
    }

    for (final node in nodes) {
      if (node is md.Element && _blockTags.contains(node.tag)) {
        flush();
        out.add(block(node));
      } else {
        inline.add(node);
      }
    }
    flush();

    return [
      for (final (i, widget) in out.indexed) ...[if (i > 0) Gap.vMd, widget],
    ];
  }

  static const _blockTags = {
    'h1', 'h2', 'h3', 'h4', 'h5', 'h6', //
    'p', 'ul', 'ol', 'li', 'blockquote', 'hr', 'pre', 'table',
  };

  Widget block(md.Element element) {
    final children = element.children ?? const <md.Node>[];
    switch (element.tag) {
      case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
        final level = int.parse(element.tag.substring(1));
        return Padding(
          padding: EdgeInsets.only(top: level <= 2 ? AppSpacing.lg : AppSpacing.md),
          child: paragraph(children, heading(level)),
        );
      case 'p':
        return paragraph(children, body);
      case 'ul' || 'ol':
        return list(element);
      case 'blockquote':
        return DecoratedBox(
          decoration: BoxDecoration(
            color: colors.muted,
            border: Border(left: BorderSide(color: colors.border, width: 4)),
          ),
          child: Padding(padding: const EdgeInsets.all(AppSpacing.lg), child: document(children)),
        );
      case 'hr':
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: SizedBox(height: 1, child: ColoredBox(color: colors.border)),
        );
      case 'pre':
        return DecoratedBox(
          decoration: BoxDecoration(color: colors.muted, borderRadius: AppRadii.mdAll),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Text(
              element.textContent.trimRight(),
              style: body.copyWith(fontFamilyFallback: _mono, height: 1.4),
            ),
          ),
        );
      default:
        // `li` outside a list, a table: their words, not nothing.
        return paragraph(children, body);
    }
  }

  Widget list(md.Element element) {
    final ordered = element.tag == 'ol';
    final start = int.tryParse(element.attributes['start'] ?? '') ?? 1;
    final items = (element.children ?? const <md.Node>[]).whereType<md.Element>().toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.sm,
      children: [
        for (final (i, item) in items.indexed)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: AppSpacing.xxl,
                child: Text(
                  ordered ? '${start + i}.' : '•',
                  textAlign: TextAlign.center,
                  style: body,
                ),
              ),
              Expanded(child: document(item.children ?? const [])),
            ],
          ),
      ],
    );
  }

  Widget paragraph(List<md.Node> nodes, TextStyle style) =>
      Text.rich(TextSpan(style: style, children: spans(nodes, style)));

  List<InlineSpan> spans(List<md.Node> nodes, TextStyle style) => [
    for (final node in nodes) ...span(node, style),
  ];

  List<InlineSpan> span(md.Node node, TextStyle style) {
    // A single line break inside a paragraph is where the source wrapped,
    // not a break in the text — a changelog wraps every entry.
    if (node is md.Text) return [TextSpan(text: _unescape(node.text).replaceAll('\n', ' '))];
    if (node is! md.Element) return [TextSpan(text: node.textContent)];

    final children = node.children ?? const <md.Node>[];
    switch (node.tag) {
      case 'strong':
        final bold = style.copyWith(fontWeight: FontWeight.w700);
        return [TextSpan(style: bold, children: spans(children, bold))];
      case 'em':
        final italic = style.copyWith(fontStyle: FontStyle.italic);
        return [TextSpan(style: italic, children: spans(children, italic))];
      case 'del':
        final struck = style.copyWith(decoration: TextDecoration.lineThrough);
        return [TextSpan(style: struck, children: spans(children, struck))];
      case 'code':
        return [
          TextSpan(
            text: node.textContent,
            style: style.copyWith(
              fontFamilyFallback: _mono,
              fontSize: (style.fontSize ?? 14) * 0.9,
              backgroundColor: colors.muted,
            ),
          ),
        ];
      case 'br':
        return [const TextSpan(text: '\n')];
      case 'a':
        return [link(node, style)];
      case 'img':
        return [TextSpan(text: node.attributes['alt'] ?? '')];
      default:
        return spans(children, style);
    }
  }

  /// A link: the primary colour, brighter and underlined under the pointer.
  /// Drawn as plain text in that style; emphasis inside a link is dropped.
  InlineSpan link(md.Element node, TextStyle style) {
    final href = node.attributes['href'];
    final index = _links++;
    final onTap = state.widget.onTapLink;
    final hovered = state._hoveredLink == index;
    final linkStyle = style.copyWith(
      color: hovered ? colors.hover(colors.primary) : colors.primary,
      decoration: hovered ? TextDecoration.underline : null,
      decorationColor: colors.primary,
    );

    TapGestureRecognizer? recognizer;
    if (href != null && onTap != null) {
      recognizer = TapGestureRecognizer()..onTap = () => onTap(href);
      state._recognizers.add(recognizer);
    }

    return TextSpan(
      style: linkStyle,
      recognizer: recognizer,
      mouseCursor: recognizer == null ? MouseCursor.defer : SystemMouseCursors.click,
      onEnter: recognizer == null ? null : (_) => state._hover(index),
      onExit: recognizer == null ? null : (_) => state._hover(null),
      // Its words, on the span itself: hits land on the innermost span under
      // the pointer, so a tap or hover handler on a parent of the text spans
      // is never reached.
      text: _unescape(node.textContent).replaceAll('\n', ' '),
    );
  }

  /// The parser leaves HTML entities in text when not encoding; the few a
  /// changelog uses are put back as characters.
  static String _unescape(String text) => text
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'");
}
