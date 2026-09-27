import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

import 'common/test_harness.dart';

/// The activity bar is context-aware: the Parts and Properties tabs only mount
/// once a circuit canvas is on screen. This test pins that behaviour and that
/// the tabs are interactive.
void main() {
  patrolTest('parts & properties tabs appear only once a canvas is open', config: patrolConfig, (
    $,
  ) async {
    await pumpApp($);

    // On the Welcome screen the canvas isn't showing, so the canvas-only
    // tabs are absent. The always-on tabs (Settings/Account) are present.
    await $(Icons.settings).waitUntilVisible();
    expect($(Icons.category).exists, isFalse, reason: 'Parts tab before canvas');
    expect($(Icons.tune).exists, isFalse, reason: 'Properties tab before canvas');

    // Open a circuit so the canvas mounts.
    await $('Blink').waitUntilVisible();
    await $('Blink').tap();
    await $(#playStopButton).waitUntilVisible();

    // Now the canvas-aware tabs are available...
    await $(Icons.category).waitUntilVisible();
    await $(Icons.tune).waitUntilVisible();

    // ...and they respond to taps (opening their side panels).
    await $(Icons.category).tap();
    await $(Icons.tune).tap();
    await $(Icons.folder).tap();
  });
}
