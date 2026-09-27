import 'package:flutter/material.dart';
import 'package:patrol/patrol.dart';

import 'common/test_harness.dart';

/// Exercises the two ways a user leaves the Welcome screen and lands on a
/// working canvas: creating a blank project, and opening a bundled template.
///
/// In both cases the tell-tale that the canvas is live is the simulation
/// "play" control, which only mounts once a circuit workspace is open.
void main() {
  patrolTest('creating a blank project opens the canvas', config: patrolConfig, ($) async {
    await pumpApp($);

    await $('New Blank Project').waitUntilVisible();
    await $('New Blank Project').tap();

    // Welcome is dismissed; the canvas + simulation controls take over.
    await $(#playStopButton).waitUntilVisible();
  });

  patrolTest('opening the Blink template loads a starter circuit', config: patrolConfig, ($) async {
    await pumpApp($);

    // Templates are derived from assets/templates/* — "blink" => "Blink".
    await $('Blink').waitUntilVisible();
    await $('Blink').tap();

    await $(#playStopButton).waitUntilVisible();
    // Sanity: the play (not stop) icon is what shows before we run anything.
    await $(Icons.play_arrow).waitUntilVisible();
  });
}
