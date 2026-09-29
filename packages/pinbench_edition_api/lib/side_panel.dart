import 'package:flutter/widgets.dart';

/// A panel an `Edition` adds to the right-hand pane.
///
/// The app shows the pane — and its toggle button, menu entry and shortcut —
/// only when an edition supplies one. Everything the panel needs from the app
/// it reads through the host API in `host.dart`, never by importing the app.
@immutable
class const SidePanel({
  /// The pane's content.
  required final WidgetBuilder build,

  /// A section on the settings tab, if the panel has settings.
  final SettingsSection? settings,

  /// Shown at the top of the welcome screen, above Start and Templates.
  ///
  /// The pane itself stays closed on the welcome screen, so a panel that
  /// wants to be reachable from there says so here.
  final WidgetBuilder? welcome,
});

/// One group on the settings tab: a heading, a line saying what it is for,
/// and the controls.
@immutable
class const SettingsSection({
  required final IconData icon,
  required final String title,
  required final String description,
  required final WidgetBuilder build,
});
