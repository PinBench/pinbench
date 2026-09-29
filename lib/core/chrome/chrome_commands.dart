import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The three pane slots a feature may ask to be shown or hidden.
///
/// Named for where they sit rather than what is in them, because what is in
/// them is the chrome's business: the left slot holds the explorer today and
/// the activity bar decides that, not the feature asking for it.
enum AppPane { left, bottom, right }

/// The ids the chrome addresses its tabs by.
///
/// This is shared vocabulary, not an implementation detail, and it was
/// duplicated before it lived here: features built `'canvas_$path'` by hand to
/// focus or close a schematic, `AppLayoutController` built the same string to
/// open one, and `editor_tab_item` sliced the prefix back off to find out which
/// file a tab belonged to. Three copies of one convention, none of them
/// naming it.
abstract final class AppTabs {
  /// The welcome screen. One tab, always this id.
  static const welcome = 'welcome';

  /// The serial monitor, in the bottom pane.
  static const serialMonitor = 'serial_monitor';

  /// App settings. A document in the center pane rather than a sidebar, so it
  /// gets the width a form needs and can be left open beside the work.
  static const settings = 'settings';

  /// A file open in the code editor. The path *is* the id.
  static String editor(String filePath) => filePath;

  /// A `.cdl` file open as a schematic. Distinct from [editor] because both
  /// views of the same file can be open at once.
  static String canvas(String filePath) => '$_canvasPrefix$filePath';

  /// The file a canvas tab is showing, or null if [tabId] is not a canvas tab.
  static String? canvasFileOf(String tabId) =>
      tabId.startsWith(_canvasPrefix) ? tabId.substring(_canvasPrefix.length) : null;

  static const _canvasPrefix = 'canvas_';
}

/// What a feature may ask the chrome to do.
///
/// Eight commands, which is the whole of it — measured across every feature that
/// was reaching for `AppLayoutController` directly: open a document, close one,
/// focus one, show a pane, go back to the welcome screen. Not "drive the
/// layout": a feature that knows a file should now be on screen says so, and
/// where a tab goes stays the chrome's decision.
///
/// Declared in `core/` because four features need it — canvas, workspace,
/// editor and ai — so it cannot live in any of them, and a feature may not
/// import the chrome that implements it. See `lib/app/chrome_bindings.dart`.
abstract interface class ChromeCommands {
  /// Opens [filePath] in the code editor, or focuses it if already open.
  void openEditorTab(String filePath);

  /// Opens [filePath] as a schematic, or focuses it if already open.
  void openCanvasTab(String filePath);

  /// Opens app settings as a center-pane tab, or focuses it if already open.
  ///
  /// A command rather than a feature reaching for the settings widget itself:
  /// a side panel sends the user here to set itself up, and where settings
  /// live is the chrome's business, not the panel's.
  void openSettingsTab();

  /// Closes one tab. Takes an id rather than a path because the editor's own
  /// tab strip passes ids straight back from what the chrome handed it — see
  /// [AppTabs] for how to build one.
  void closeTab(String tabId);

  /// Brings an already-open tab to the front.
  void focusTab(String tabId);

  /// Shows or hides a pane slot.
  void setPaneVisible(AppPane pane, {required bool visible});

  /// Leaves the welcome screen: closes its tab and reveals the chrome that
  /// belongs with an open project.
  ///
  /// One command rather than the three it expands to, because the rule about
  /// what the welcome screen hides — the side panel, which has an entry of its
  /// own there — is expressed in exactly two places on the chrome side
  /// and would be re-derived, slightly differently, by every caller otherwise.
  void closeWelcome();

  /// Returns to the welcome screen, closing what the workspace opened.
  void resetToWelcome();
}

/// The live chrome binding. Has no default: a build that shows files to a user
/// must say where they appear.
///
/// Overridden in `buildGlobalScope`. A test that renders a feature without ever
/// opening anything can use the fake in
/// `test/support/chrome_commands.dart`.
final chromeCommandsProvider = Provider<ChromeCommands>(
  (ref) => throw UnimplementedError(
    'chromeCommandsProvider has no binding. Override it with the adapter in '
    'lib/app/chrome_bindings.dart, or with a fake from test/support/chrome_commands.dart.',
  ),
);
