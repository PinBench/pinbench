import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/chrome/chrome_commands.dart';
import '../layout/controllers/app_layout_controller.dart';

/// Binds [ChromeCommands] to the layout that implements it.
///
/// The whole of what four features know about the chrome, in one file, at the
/// one layer allowed to know both sides. Before this, five files across
/// workspace, canvas, editor and ai read `appLayoutControllerProvider`
/// directly — which meant a feature naming the controller that happens to own
/// panes today, and an allowlist entry each.
class LayoutChromeCommands implements ChromeCommands {
  const LayoutChromeCommands(this._ref);

  final Ref _ref;

  /// Read per call rather than captured: the controller is keep-alive, but
  /// reading it at the point of use keeps this adapter free of lifecycle of
  /// its own.
  AppLayoutController get _layout => _ref.read(appLayoutControllerProvider);

  @override
  void openEditorTab(String filePath) => _layout.openEditorTab(filePath);

  @override
  void openCanvasTab(String filePath) => _layout.openCanvasTab(filePath);

  @override
  void openSettingsTab() => _layout.openSettingsTab();

  @override
  void closeTab(String tabId) => _layout.closeTab(tabId);

  @override
  void focusTab(String tabId) => _layout.focusTab(tabId);

  @override
  void closeWelcome() => _layout.closeWelcome();

  @override
  void resetToWelcome() => _layout.resetToWelcome();

  /// The one place a pane's slot id is spelled. Features name a position; the
  /// string the layout engine wants stays on this side of the boundary.
  @override
  void setPaneVisible(AppPane pane, {required bool visible}) =>
      _layout.setPaneVisible(_slotId(pane), visible: visible);

  static String _slotId(AppPane pane) => switch (pane) {
    AppPane.left => 'left_slot',
    AppPane.bottom => 'bottom_pane',
    AppPane.right => 'right_pane',
  };
}

/// Wires the chrome port to the layout. Spread into the root scope alongside
/// the simulation's bindings; see `bootstrap.dart`.
final chromeBindings = [chromeCommandsProvider.overrideWith(LayoutChromeCommands.new)];
