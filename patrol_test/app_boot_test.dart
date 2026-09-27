import 'package:patrol/patrol.dart';

import 'common/test_harness.dart';

/// Smoke test: the app boots into the Welcome screen and shows its core
/// entry points. If this fails, every other test in the suite will too, so
/// it's the canary for harness/provider wiring.
void main() {
  patrolTest('app boots to the Welcome screen', config: patrolConfig, ($) async {
    await pumpApp($);

    // Header + the three Welcome sections render.
    await $('PinBench').waitUntilVisible();
    await $('Start').waitUntilVisible();
    await $('Templates').waitUntilVisible();
    await $('Recent Workspaces').waitUntilVisible();

    // The two primary "Start" actions are present.
    await $('New Blank Project').waitUntilVisible();
    await $('Open Folder...').waitUntilVisible();
  });
}
