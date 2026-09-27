import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench/core/shortcuts/app_intents.dart';
import 'package:pinbench/shell/shortcuts/app_shortcuts.dart';

import '../support/harness.dart';
import 'package:pinbench_ui/ui/app_text_field.dart';

/// The app-wide shortcuts, covered from two directions.
///
/// The keymap tests intercept each intent above the real handlers, so they
/// check the binding — which chord produces which intent — without running the
/// action behind it.
///
/// The focus tests cover the thing that actually broke in the past: a key event
/// travels *up* from the focused node, so `Shortcuts` only sees one while focus
/// is inside its subtree. Focus coming to rest above the app killed every
/// shortcut until the user clicked back into the editor. Those tests assert
/// where focus lands, which is precisely the precondition the keymap tests then
/// assume.
void main() {
  /// Records an intent instead of letting the app act on it.
  ///
  /// Sits below the app's own `Actions`, so a lookup from the focused node
  /// finds this first.
  MapEntry<Type, Action<Intent>> spy<T extends Intent>(List<Intent> log) => MapEntry(
    T,
    CallbackAction<T>(
      onInvoke: (intent) {
        log.add(intent);
        return null;
      },
    ),
  );

  Widget shortcutsUnderTest(List<Intent> log, {Widget? sibling, Widget? child, FocusNode? above}) {
    final app = AppShortcuts(
      child: Actions(
        actions: Map.fromEntries([
          spy<SaveIntent>(log),
          spy<OpenIntent>(log),
          spy<NewIntent>(log),
          spy<ExportCircuitIntent>(log),
          spy<CloseTabIntent>(log),
          spy<ToggleLeftPaneIntent>(log),
          spy<ToggleBottomPaneIntent>(log),
          spy<ToggleRightPaneIntent>(log),
          spy<ToggleThemeIntent>(log),
          spy<GoHomeIntent>(log),
          spy<ViewCodeIntent>(log),
          spy<ToggleSimulationIntent>(log),
          spy<PauseSimulationIntent>(log),
        ]),
        child: child ?? const Focus(autofocus: true, child: SizedBox()),
      ),
    );

    final wrapped = above == null ? app : Focus(focusNode: above, child: app);

    return ProviderScope(
      child: appTestApp(sibling == null ? wrapped : Stack(children: [wrapped, sibling])),
    );
  }

  Future<void> press(
    WidgetTester tester,
    LogicalKeyboardKey key, {
    List<LogicalKeyboardKey> withKeys = const [],
  }) async {
    for (final modifier in withKeys) {
      await tester.sendKeyDownEvent(modifier);
    }
    await tester.sendKeyDownEvent(key);
    await tester.sendKeyUpEvent(key);
    for (final modifier in withKeys.reversed) {
      await tester.sendKeyUpEvent(modifier);
    }
    await tester.pump();
  }

  /// Whether a keystroke would still reach the app's `Shortcuts`.
  ///
  /// A key event only travels up through widgets above the focused node, so
  /// this asks the one question that matters: is focus still somewhere inside
  /// `AppShortcuts`?
  bool shortcutsAreReachable() =>
      FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<AppShortcuts>() !=
      null;

  group('keymap', () {
    /// Every chord, against both modifiers: the app is expected to answer to
    /// ⌘ and Ctrl alike, and a Windows user losing Save is the sort of thing
    /// nobody on a Mac notices.
    final bindings = <String, (LogicalKeyboardKey, List<LogicalKeyboardKey>, Type)>{
      'save': (LogicalKeyboardKey.keyS, [], SaveIntent),
      'open': (LogicalKeyboardKey.keyO, [], OpenIntent),
      'new file': (LogicalKeyboardKey.keyN, [], NewIntent),
      'export': (LogicalKeyboardKey.keyE, [], ExportCircuitIntent),
      'close tab': (LogicalKeyboardKey.keyW, [], CloseTabIntent),
      'left pane': (LogicalKeyboardKey.keyB, [], ToggleLeftPaneIntent),
      'bottom pane': (LogicalKeyboardKey.keyJ, [], ToggleBottomPaneIntent),
      'view code': (LogicalKeyboardKey.backslash, [], ViewCodeIntent),
      'right pane': (LogicalKeyboardKey.keyB, [LogicalKeyboardKey.altLeft], ToggleRightPaneIntent),
      'theme': (LogicalKeyboardKey.keyL, [LogicalKeyboardKey.shiftLeft], ToggleThemeIntent),
      'home': (LogicalKeyboardKey.keyH, [LogicalKeyboardKey.shiftLeft], GoHomeIntent),
    };

    for (final MapEntry(key: name, value: (key, extras, intent)) in bindings.entries) {
      for (final modifier in [LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.controlLeft]) {
        final label = modifier == LogicalKeyboardKey.metaLeft ? 'meta' : 'control';
        testWidgets('$name is bound to $label', (tester) async {
          final fired = <Intent>[];
          await tester.pumpWidget(shortcutsUnderTest(fired));
          await tester.pump();

          await press(tester, key, withKeys: [modifier, ...extras]);

          expect(fired.map((i) => i.runtimeType), [intent]);
        });
      }
    }

    testWidgets('the simulation keys need no modifier', (tester) async {
      final fired = <Intent>[];
      await tester.pumpWidget(shortcutsUnderTest(fired));
      await tester.pump();

      await press(tester, LogicalKeyboardKey.f5);
      await press(tester, LogicalKeyboardKey.f8);

      expect(fired.map((i) => i.runtimeType), [ToggleSimulationIntent, PauseSimulationIntent]);
    });

    testWidgets('alt distinguishes the right pane from the left', (tester) async {
      final fired = <Intent>[];
      await tester.pumpWidget(shortcutsUnderTest(fired));
      await tester.pump();

      // Both hang off B, so a chord that ignored the modifier would toggle the
      // wrong pane rather than fail outright.
      await press(tester, LogicalKeyboardKey.keyB, withKeys: [LogicalKeyboardKey.metaLeft]);
      await press(
        tester,
        LogicalKeyboardKey.keyB,
        withKeys: [LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.altLeft],
      );

      expect(fired.map((i) => i.runtimeType), [ToggleLeftPaneIntent, ToggleRightPaneIntent]);
    });

    testWidgets('an unmodified letter is left alone for typing', (tester) async {
      final fired = <Intent>[];
      await tester.pumpWidget(shortcutsUnderTest(fired));
      await tester.pump();

      await press(tester, LogicalKeyboardKey.keyS);

      expect(fired, isEmpty);
    });
  });

  group('focus', () {
    testWidgets('starts inside the shortcut scope', (tester) async {
      await tester.pumpWidget(shortcutsUnderTest([]));
      await tester.pump();

      expect(shortcutsAreReachable(), isTrue);
    });

    testWidgets('survives a child giving focus up', (tester) async {
      final fired = <Intent>[];
      await tester.pumpWidget(shortcutsUnderTest(fired));
      await tester.pump();

      // What a toolbar button or a tab strip does: takes focus on a click and
      // hands it straight back. Focus used to land above the app here, and
      // every shortcut went dead until the user clicked into the editor.
      FocusManager.instance.primaryFocus!.unfocus();
      await tester.pump();

      expect(shortcutsAreReachable(), isTrue);
    });

    testWidgets('is pulled back down when it comes to rest above the app', (tester) async {
      final outside = FocusNode(debugLabel: 'above the app');
      addTearDown(outside.dispose);

      final fired = <Intent>[];
      await tester.pumpWidget(shortcutsUnderTest(fired, above: outside));
      await tester.pump();

      // Nothing in the app holds focus now, so no shortcut would ever fire
      // again. Being an ancestor is what makes it safe to take back.
      outside.requestFocus();
      await tester.pump();

      expect(shortcutsAreReachable(), isTrue);

      await press(tester, LogicalKeyboardKey.keyS, withKeys: [LogicalKeyboardKey.metaLeft]);
      expect(fired.map((i) => i.runtimeType), [SaveIntent]);
    });

    testWidgets('is not stolen from a text field', (tester) async {
      final field = FocusNode(debugLabel: 'text field');
      addTearDown(field.dispose);
      await tester.pumpWidget(
        shortcutsUnderTest(
          [],
          child: Column(children: [AppTextField(focusNode: field)]),
        ),
      );
      await tester.pump();

      field.requestFocus();
      await tester.pump();
      await tester.pump();

      expect(FocusManager.instance.primaryFocus, field);
    });

    testWidgets('is not stolen from a dialog or menu outside the app', (tester) async {
      final overlay = FocusScopeNode(debugLabel: 'overlay');
      addTearDown(overlay.dispose);
      final inOverlay = FocusNode(debugLabel: 'in overlay');
      addTearDown(inOverlay.dispose);

      await tester.pumpWidget(
        shortcutsUnderTest(
          [],
          // A route the app does not contain: its node is neither an ancestor
          // of the shortcut scope nor inside it, so reclaiming focus here would
          // dismiss the very thing the user just opened.
          sibling: FocusScope(
            node: overlay,
            child: Focus(focusNode: inOverlay, child: const SizedBox()),
          ),
        ),
      );
      await tester.pump();

      inOverlay.requestFocus();
      await tester.pump();
      await tester.pump();

      expect(FocusManager.instance.primaryFocus, inOverlay);
    });
  });
}
