import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show SingleActivator;
import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench/shell/menus/shortcut_label.dart';

/// Regression coverage for the web menu bar's shortcut labels: they used to
/// be hand-typed Mac-only unicode literals (e.g. `'⌘O'`) shown regardless of
/// the platform the browser was running on — wrong on Windows/Linux.
/// `shortcutLabel` now derives the label from the same `SingleActivator` the
/// action is defined with, adapting the modifier symbols per platform.
void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('uses Mac symbols on macOS', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    expect(
      shortcutLabel(const SingleActivator(LogicalKeyboardKey.keyS, meta: true, shift: true)),
      '⇧⌘S',
    );
    expect(shortcutLabel(const SingleActivator(LogicalKeyboardKey.keyO, meta: true)), '⌘O');
  });

  test('uses word form on Windows', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(
      shortcutLabel(const SingleActivator(LogicalKeyboardKey.keyS, meta: true, shift: true)),
      'Shift+Ctrl+S',
    );
    expect(shortcutLabel(const SingleActivator(LogicalKeyboardKey.keyO, meta: true)), 'Ctrl+O');
  });

  test('uses word form on Linux', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    expect(shortcutLabel(const SingleActivator(LogicalKeyboardKey.keyA, meta: true)), 'Ctrl+A');
  });
}
