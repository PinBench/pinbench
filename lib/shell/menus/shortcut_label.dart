import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show SingleActivator;

/// Formats [activator] as a short label for display in the web menu bar.
///
/// The web menu bar is a fake in-app menu (`AppMenuBar`) that only
/// *displays* a shortcut hint — the real key handling lives in
/// `app_shortcuts.dart`. Native menus are real OS-drawn menus, so
/// `PlatformMenuItem.shortcut` renders its own platform-correct accelerator
/// and never needs this.
///
/// Uses Mac symbols (⌘⇧⌥⌃) on macOS and word form (Ctrl+Shift+Alt) elsewhere,
/// so the label is never wrong on Windows/Linux — previously the web menu
/// bar hand-typed Mac-only unicode literals (e.g. `'⌘O'`) regardless of the
/// platform the browser was actually running on.
String shortcutLabel(SingleActivator activator) {
  final isMac = defaultTargetPlatform == TargetPlatform.macOS;
  final parts = <String>[
    if (activator.control) (isMac ? '⌃' : 'Ctrl'),
    if (activator.alt) (isMac ? '⌥' : 'Alt'),
    if (activator.shift) (isMac ? '⇧' : 'Shift'),
    // `meta` is Cmd on macOS; treat it as the primary modifier (Ctrl) elsewhere.
    if (activator.meta) (isMac ? '⌘' : 'Ctrl'),
    _keyLabel(activator.trigger),
  ];
  return isMac ? parts.join() : parts.join('+');
}

String _keyLabel(LogicalKeyboardKey key) {
  final label = key.keyLabel;
  return label.length == 1 ? label.toUpperCase() : label;
}
