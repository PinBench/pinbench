import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import 'package:pinbench/features/editor/edit_action_router.dart';
import 'package:pinbench/features/editor/widgets/custom_code_editor.dart';
import '../../support/harness.dart';

/// The Edit menu acts on whichever surface the user was last editing — and
/// keeps pointing there after focus moves to the menu itself, which is the
/// part that is easy to break.
void main() {
  late EditActionRouter router;
  late TextEditingController text;
  late FocusNode textFocus;
  late FocusNode canvasFocus;
  late FocusNode menuFocus;
  late CodeLineEditingController code;

  setUp(() {
    router = EditActionRouter()..startTracking();
    text = TextEditingController(text: 'hello');
    textFocus = FocusNode();
    canvasFocus = FocusNode(debugLabel: 'CanvasFocusNode');
    menuFocus = FocusNode(debugLabel: 'menu');
    code = CodeLineEditingController.fromText('void loop() {}');
  });

  tearDown(() {
    router.stopTracking();
    text.dispose();
    textFocus.dispose();
    canvasFocus.dispose();
    menuFocus.dispose();
    code.dispose();
  });

  // The code editor takes focus when it is built, so it is only in the tree for
  // the test that is about it.
  Future<void> pump(WidgetTester tester, {bool withCodeEditor = false}) => tester.pumpWidget(
    ProviderScope(
      child: appTestApp(
        Column(
          children: [
            EditableText(
              controller: text,
              focusNode: textFocus,
              style: const TextStyle(),
              cursorColor: const Color(0xFF000000),
              backgroundCursorColor: const Color(0xFF000000),
            ),
            Focus(focusNode: canvasFocus, child: const SizedBox(width: 10, height: 10)),
            Focus(focusNode: menuFocus, child: const SizedBox(width: 10, height: 10)),
            if (withCodeEditor)
              SizedBox(
                width: 300,
                height: 200,
                child: CustomCodeEditor(controller: code, filePath: 'sketch.ino'),
              ),
          ],
        ),
      ),
    ),
  );

  void selectAll() => router.route(
    textIntent: const SelectAllTextIntent(SelectionChangedCause.keyboard),
    codeAction: (controller) => controller.selectAll(),
    canvasFallback: () => canvasActions++,
  );

  testWidgets('falls back to the canvas before anything was focused', (tester) async {
    await pump(tester);
    canvasActions = 0;

    selectAll();

    expect(canvasActions, 1);
  });

  testWidgets('a text field gets the action, even after focus moves to the menu', (tester) async {
    await pump(tester);
    canvasActions = 0;
    textFocus.requestFocus();
    await tester.pump();
    menuFocus.requestFocus();
    await tester.pump();

    selectAll();
    await tester.pump();

    expect(text.selection, const TextSelection(baseOffset: 0, extentOffset: 5));
    expect(canvasActions, 0);
  });

  testWidgets('the canvas gets the action once it has focus', (tester) async {
    await pump(tester);
    canvasActions = 0;
    textFocus.requestFocus();
    await tester.pump();
    canvasFocus.requestFocus();
    await tester.pump();

    selectAll();

    expect(canvasActions, 1);
    expect(text.selection.isCollapsed, isTrue);
  });

  testWidgets("the code editor's controller gets the action", (tester) async {
    await pump(tester, withCodeEditor: true);
    canvasActions = 0;
    await tester.tap(find.byType(CustomCodeEditor));
    await tester.pump();
    menuFocus.requestFocus();
    await tester.pump();

    selectAll();

    expect(code.selection.isCollapsed, isFalse, reason: 'the whole sketch is selected');
    expect(canvasActions, 0);

    // The editor's cursor blinks on a timer; take it down before the test ends.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}

var canvasActions = 0;
