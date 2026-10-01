import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:re_highlight/re_highlight.dart';

import 'package:pinbench/features/editor/syntax/cdl_syntax.dart';
import 'package:pinbench/features/editor/syntax/pdl_syntax.dart';

String _html(String code, String language) {
  final highlight = Highlight()
    ..registerLanguage('cdl', langCdl)
    ..registerLanguage('pdl', langPdl);
  return highlight.highlight(code: code, language: language).toHtml();
}

void main() {
  group('CDL', () {
    test('marks the structure: keywords, types, attributes, values, comments', () {
      final html = _html('// blink\nCircuit {\n  led := LED { color: red, x: 12.5 }\n}', 'cdl');

      expect(html, contains('<span class="hljs-comment">// blink</span>'));
      expect(html, contains('<span class="hljs-keyword">Circuit</span>'));
      expect(html, contains('<span class="hljs-type">LED</span>'));
      expect(html, contains('<span class="hljs-attr">color</span>'));
      expect(html, contains('<span class="hljs-built_in">red</span>'));
      expect(html, contains('<span class="hljs-number">12.5</span>'));
    });

    // The type list is written by hand, so it drifts from the parts: the OLED
    // display shipped in a template while its type stayed plain text. Every
    // type the bundled templates use must be highlighted as one.
    test('highlights every part type the bundled templates use', () {
      final types = <String>{};
      for (final file in Directory('assets/templates').listSync(recursive: true)) {
        if (file is! File || !file.path.endsWith('.cdl')) continue;
        for (final m in RegExp(
          r':=\s*([A-Z][A-Za-z0-9]*)\s*\{',
        ).allMatches(file.readAsStringSync())) {
          types.add(m.group(1)!);
        }
      }
      expect(types, isNotEmpty, reason: 'found no templates to check');

      for (final type in types) {
        expect(
          _html('x := $type {}', 'cdl'),
          contains('<span class="hljs-type">$type</span>'),
          reason: '$type is used in a template but not highlighted as a type',
        );
      }
    });
  });

  group('PDL', () {
    test('marks directives, shapes and strings', () {
      final html = _html(
        'PART "Transistor"\nCONFIGURATION type "NPN"\nVISUALS\n  RECT 0px 0px 10px 4px',
        'pdl',
      );

      expect(html, contains('<span class="hljs-keyword">PART</span>'));
      expect(html, contains('<span class="hljs-string">&quot;Transistor&quot;</span>'));
      expect(html, contains('<span class="hljs-keyword">CONFIGURATION</span>'));
      expect(html, contains('<span class="hljs-keyword">VISUALS</span>'));
      expect(html, contains('<span class="hljs-type">RECT</span>'));
    });
  });
}
