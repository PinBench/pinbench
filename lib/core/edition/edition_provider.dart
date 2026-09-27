import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinbench_edition_api/side_panel.dart';

/// The side panel this build's edition supplies, or null when it has none —
/// which is always the case in a build from source.
///
/// Decides whether the app has a right-hand pane at all: the layout, its
/// toggle button, menu entry and shortcut, the welcome screen and the settings
/// tab all read this. Overridden in `app/bootstrap.dart`.
final editionPanelProvider = Provider<SidePanel?>((ref) => null);
