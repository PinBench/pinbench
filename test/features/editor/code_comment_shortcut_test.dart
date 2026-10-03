import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import 'package:pinbench/features/editor/widgets/custom_code_editor.dart';

import '../../support/harness.dart';

/// ⌘/ toggles a line comment in every kind of file the editor opens, and ⇧⌘/
/// a block comment only where the language has one.
///
/// Run as macOS: re_editor installs no shortcuts at all on Android, the test
/// default, and reads the platform once per isolate.
void main() {
  final macOS = TargetPlatformVariant.only(TargetPlatform.macOS);
  late CodeLineEditingController code;

  tearDown(() => code.dispose());

  Future<void> pump(WidgetTester tester, String filePath, String text) async {
    code = CodeLineEditingController.fromText(text);
    await tester.pumpWidget(
      ProviderScope(
        child: appTestApp(
          SizedBox(
            width: 400,
            height: 200,
            child: CustomCodeEditor(controller: code, filePath: filePath),
          ),
        ),
      ),
    );
    // The editor focuses itself when built; no tap, whose double-tap timer
    // would outlive the test.
    await tester.pump();
  }

  Future<void> pressCommandSlash(WidgetTester tester, {bool shift = false}) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.slash);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
  }

  for (final file in ['sketch.ino', 'main.cpp', 'board.h', 'circuit.cdl', 'part.pdl']) {
    testWidgets('⌘/ toggles a line comment in $file', (tester) async {
      await pump(tester, file, '  led: 13');
      code.selection = const CodeLineSelection.collapsed(index: 0, offset: 4);

      await pressCommandSlash(tester);
      expect(code.text, '  // led: 13');

      await pressCommandSlash(tester);
      expect(code.text, '  led: 13');
    }, variant: macOS);
  }

  testWidgets('⌘/ comments every selected line', (tester) async {
    await pump(tester, 'sketch.ino', 'a();\nb();');
    code.selectAll();

    await pressCommandSlash(tester);
    expect(code.text, '// a();\n// b();');
  }, variant: macOS);

  testWidgets('⇧⌘/ block-comments C++', (tester) async {
    await pump(tester, 'sketch.ino', 'a();');
    code.selectAll();

    await pressCommandSlash(tester, shift: true);
    expect(code.text, allOf(startsWith('/*'), endsWith('*/')));
  }, variant: macOS);

  testWidgets('⇧⌘/ leaves CDL alone, whose parser only strips `//`', (tester) async {
    await pump(tester, 'circuit.cdl', 'led: 13');
    code.selectAll();

    await pressCommandSlash(tester, shift: true);
    expect(code.text, 'led: 13');
  }, variant: macOS);
}
