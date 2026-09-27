import 'package:flutter/material.dart';
import 'package:patrol/patrol.dart';

import 'common/test_harness.dart';

/// End-to-end of the headline feature: starting and stopping a simulation.
///
/// Tapping play compiles the sketch (a brief spinner) and then runs it, at
/// which point the control flips to a stop icon. Tapping again returns to the
/// idle play state.
///
/// NOTE: this drives the real AVR/SPICE pipeline, so it must run on a device
/// where the simulation toolchain is available (i.e. via `patrol test`, not a
/// pure widget test). The compile step is why the stop-icon wait is generous.
void main() {
  patrolTest('play starts the simulation and stop returns it to idle', config: patrolConfig, (
    $,
  ) async {
    await pumpApp($);

    // Load a known-good starter circuit.
    await $('Blink').waitUntilVisible();
    await $('Blink').tap();

    final playStop = $(#playStopButton);
    await playStop.waitUntilVisible();
    await $(Icons.play_arrow).waitUntilVisible();

    // Start: kicks off compile -> run. The play icon goes away immediately.
    await playStop.tap();

    // Running state surfaces a stop icon once compilation finishes.
    await $(Icons.stop).waitUntilVisible(timeout: const Duration(seconds: 60));

    // Stop: back to the idle play state.
    await $(#playStopButton).tap();
    await $(Icons.play_arrow).waitUntilVisible(timeout: const Duration(seconds: 15));
  });
}
