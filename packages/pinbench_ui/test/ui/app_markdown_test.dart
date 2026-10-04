import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench_ui/theme/testing.dart';
import 'package:pinbench_ui/ui/app_markdown.dart';

/// The release notes are a changelog section run through this, so it has to
/// carry everything a changelog uses: headings, nested lists, emphasis, code,
/// rules and links that go somewhere.
void main() {
  Future<void> pump(WidgetTester tester, String data, {ValueChanged<String>? onTapLink}) =>
      tester.pumpWidget(
        appTestApp(
          SingleChildScrollView(
            child: AppMarkdown(data: data, onTapLink: onTapLink),
          ),
        ),
      );

  Finder rich(String text) => find.textContaining(text, findRichText: true);

  testWidgets('headings, paragraphs and emphasis read as their words', (tester) async {
    await pump(tester, '### Added\n\nSome **bold**, some *italic* and `code`.');

    expect(find.text('Added'), findsOneWidget);
    expect(rich('Some bold, some italic and code.'), findsOneWidget);
  });

  testWidgets('list items each get a bullet, nested ones too', (tester) async {
    await pump(tester, '- **One.** First\n  continued\n- Two\n  - Nested');

    expect(find.text('•'), findsNWidgets(3));
    expect(rich('One. First continued'), findsOneWidget);
    expect(rich('Nested'), findsOneWidget);
  });

  testWidgets('numbered lists count from their start', (tester) async {
    await pump(tester, '3. Three\n4. Four');

    expect(find.text('3.'), findsOneWidget);
    expect(find.text('4.'), findsOneWidget);
  });

  testWidgets('entities come out as characters', (tester) async {
    await pump(tester, 'Fish & chips <3');
    expect(rich('Fish & chips <3'), findsOneWidget);
  });

  testWidgets('a link is handed to onTapLink', (tester) async {
    final tapped = <String>[];
    await pump(tester, 'See [the docs](https://example.com/docs).', onTapLink: tapped.add);

    await tester.tapOnText(find.textRange.ofSubstring('the docs'));
    expect(tapped, ['https://example.com/docs']);
  });

  testWidgets('a link lights up under the pointer', (tester) async {
    await pump(tester, '[here](https://example.com)', onTapLink: (_) {});

    TextSpan linkSpan() {
      final paragraph = tester.widget<RichText>(find.byType(RichText).first);
      TextSpan? found;
      paragraph.text.visitChildren((span) {
        if (span is TextSpan && span.recognizer != null) found = span;
        return found == null;
      });
      return found!;
    }

    expect(linkSpan().style?.decoration, isNot(TextDecoration.underline));

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    // Onto the word: the paragraph is as wide as the page, the link is not.
    await mouse.moveTo(tester.getRect(find.byType(RichText).first).centerLeft + const Offset(8, 0));
    await tester.pump();

    expect(linkSpan().style?.decoration, TextDecoration.underline);
  });

  testWidgets('a rule and a quote render without losing their text', (tester) async {
    await pump(tester, 'Above\n\n---\n\n> Quoted');

    expect(rich('Above'), findsOneWidget);
    expect(rich('Quoted'), findsOneWidget);
  });
}
