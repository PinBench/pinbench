import 'package:pinbench/core/chrome/chrome_commands.dart';

/// A chrome that records what it was asked to do and does none of it.
///
/// [chromeCommandsProvider] has no default binding on purpose — a build that
/// shows files to a user must say where they appear — so any test that renders
/// a feature capable of opening something has to supply one. Most only need it
/// to exist, which is what this is for.
///
/// A test that cares *what* was opened can read [calls]: each entry is the
/// method name and its argument, in order, so a sequence like "open the canvas,
/// then the editor, then re-focus the canvas" can be asserted as one list
/// rather than through five separate spies.
class FakeChromeCommands implements ChromeCommands {
  final calls = <String>[];

  @override
  void openEditorTab(String filePath) => calls.add('openEditorTab:$filePath');

  @override
  void openCanvasTab(String filePath) => calls.add('openCanvasTab:$filePath');

  @override
  void openSettingsTab() => calls.add('openSettingsTab');

  @override
  void closeTab(String tabId) => calls.add('closeTab:$tabId');

  @override
  void focusTab(String tabId) => calls.add('focusTab:$tabId');

  @override
  void setPaneVisible(AppPane pane, {required bool visible}) =>
      calls.add('setPaneVisible:${pane.name}:$visible');

  @override
  void closeWelcome() => calls.add('closeWelcome');

  @override
  void resetToWelcome() => calls.add('resetToWelcome');
}

/// The override to spread into a `ProviderScope`/`ProviderContainer`.
///
/// Untyped for the same reason as the simulation's fakes: Riverpod 3 does not
/// export `Override`, so the element type has to be inferred.
// ignore: prefer_function_declarations_over_variables, see above
final fakeChromeBindings = () => [chromeCommandsProvider.overrideWithValue(FakeChromeCommands())];
