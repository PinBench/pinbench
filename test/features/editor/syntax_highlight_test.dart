import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/arduino.dart';
import 'package:re_highlight/re_highlight.dart';

import 'package:pinbench/features/editor/syntax/cdl_syntax.dart';
import 'package:pinbench/features/editor/syntax/pdl_syntax.dart';
import 'package:pinbench/features/editor/widgets/custom_code_editor.dart';

import '../../support/harness.dart';

/// A sketch opened in the editor is coloured as Arduino code: keywords,
/// Arduino's constants and its built-in functions, not just strings and
/// numbers.
void main() {
  const sketch = '''
void setup() { pinMode(13, OUTPUT); }

void loop() {
  Serial.println("Hello World");
  digitalWrite(13, HIGH);
  delay(500);
}
''';

  test('a sketch is highlighted with the Arduino grammar', () {
    expect(editorLanguageFor('sketch.ino'), same(langArduino));
    expect(editorLanguageFor('/work/My.Project/SKETCH.INO'), same(langArduino));
    expect(editorLanguageFor('circuit.cdl'), same(langCdl));
    expect(editorLanguageFor('part.pdl'), same(langPdl));
  });

  test("the Arduino grammar marks a sketch's keywords and names", () {
    final html = (Highlight()..registerLanguage('arduino', editorLanguageFor('sketch.ino')))
        .highlight(code: sketch, language: 'arduino')
        .toHtml();

    for (final word in ['void', 'OUTPUT', 'HIGH', 'pinMode', 'digitalWrite', 'delay']) {
      expect(html, contains('>$word</span>'), reason: '`$word` should be coloured');
    }
  });

  // Given more than one grammar, re_editor guesses between them from the text,
  // and a sketch was taken for CDL or PDL — whose grammars colour only
  // strings, numbers and comments.
  testWidgets("the editor is given only the open file's grammar", (tester) async {
    final code = CodeLineEditingController.fromText(sketch);
    addTearDown(code.dispose);
    await tester.pumpWidget(
      ProviderScope(
        child: appTestApp(
          SizedBox(
            width: 400,
            height: 200,
            child: CustomCodeEditor(controller: code, filePath: 'sketch.ino'),
          ),
        ),
      ),
    );

    final languages = tester
        .widget<CodeEditor>(find.byType(CodeEditor))
        .style!
        .codeTheme!
        .languages;
    expect(languages.values.map((l) => l.mode), [same(langArduino)]);

    // And highlighted the way re_editor does it, through the editor's own key:
    // a key the highlighter cannot look up colours nothing at all.
    final highlight = Highlight();
    languages.forEach((key, theme) => highlight.registerLanguage(key, theme.mode));
    final html = highlight.highlight(code: sketch, language: languages.keys.single).toHtml();
    expect(html, contains('>void</span>'));
    expect(html, contains('>HIGH</span>'));

    // Let the editor's deferred highlight pass run out before the test ends.
    await tester.pump(const Duration(seconds: 1));
  });
}
