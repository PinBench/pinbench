import 'package:flutter/widgets.dart';

/// A panel an `Edition` adds to the right-hand pane.
///
/// The app shows the pane — and its toggle button, menu entry and shortcut —
/// only when an edition supplies one. Everything the panel needs from the app
/// it reads through the host API in `host.dart`, never by importing the app.
@immutable
class SidePanel {
  const SidePanel({required this.build, this.settings, this.welcome});

  /// The pane's content.
  final WidgetBuilder build;

  /// A section on the settings tab, if the panel has settings.
  final SettingsSection? settings;

  /// Shown at the top of the welcome screen, above Start and Templates.
  ///
  /// The pane itself stays closed on the welcome screen, so a panel that
  /// wants to be reachable from there says so here.
  final WidgetBuilder? welcome;
}

/// One group on the settings tab: a heading, a line saying what it is for,
/// and the controls.
@immutable
class SettingsSection {
  const SettingsSection({
    required this.icon,
    required this.title,
    required this.description,
    required this.build,
  });

  final IconData icon;
  final String title;
  final String description;
  final WidgetBuilder build;
}
