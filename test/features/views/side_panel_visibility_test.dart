import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pinbench_edition_api/side_panel.dart';

import 'package:pinbench/core/edition/edition_provider.dart';
import 'package:pinbench/layout/controllers/app_layout_controller.dart';

/// The side panel follows the welcome screen: hidden while it is up (welcome
/// carries the panel's own entry), shown with an open project.
///
/// The rule is split across the initial layout, `closeWelcome` and
/// `resetToWelcome`, and the failure mode is invisible — a pane that quietly
/// stops coming back, which is exactly what happened before `resetToWelcome`
/// was fixed.
void main() {
  ProviderContainer container({bool withPanel = true}) {
    final c = ProviderContainer(
      overrides: [
        if (withPanel)
          editionPanelProvider.overrideWithValue(SidePanel(build: (_) => const SizedBox())),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  AppLayoutController layoutOf(ProviderContainer c) => c.read(appLayoutControllerProvider);

  test('starts hidden, because the app opens on the welcome screen', () {
    expect(layoutOf(container()).isPaneHidden('right_pane'), isTrue);
  });

  test('appears when a project opens', () {
    final layout = layoutOf(container())..closeWelcome();

    expect(layout.isPaneHidden('right_pane'), isFalse);
  });

  test('goes away again on the way back to welcome', () {
    final layout = layoutOf(container())
      ..closeWelcome()
      ..resetToWelcome();

    expect(layout.isPaneHidden('right_pane'), isTrue);
  });

  // The regression that motivated the test: opening a project after returning
  // home used to leave the pane hidden for the rest of the session.
  test('comes back after a round trip through welcome', () {
    final layout = layoutOf(container())
      ..closeWelcome()
      ..resetToWelcome()
      ..closeWelcome();

    expect(layout.isPaneHidden('right_pane'), isFalse);
  });

  group('a build without a side panel', () {
    test('has no right-hand pane at all', () {
      final layout = layoutOf(container(withPanel: false));

      expect(layout.hasSidePanel, isFalse);
      expect(layout.isPaneHidden('right_pane'), isTrue);
    });

    test('leaves the welcome screen without trying to reveal one', () {
      final layout = layoutOf(container(withPanel: false))
        ..closeWelcome()
        ..resetToWelcome()
        ..closeWelcome();

      expect(layout.isPaneHidden('left_slot'), isFalse);
      expect(layout.isPaneHidden('right_pane'), isTrue);
    });

    test('ignores the toggle shortcut rather than failing', () {
      final layout = layoutOf(container(withPanel: false))..togglePane('right_pane');

      expect(layout.isPaneHidden('right_pane'), isTrue);
    });
  });

  test('the explorer follows the same lifecycle', () {
    final layout = layoutOf(container());

    expect(layout.isPaneHidden('left_slot'), isTrue);
    layout.closeWelcome();
    expect(layout.isPaneHidden('left_slot'), isFalse);
  });
}
