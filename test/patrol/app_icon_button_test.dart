import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol_finders/patrol_finders.dart';

import 'package:pinbench_ui/ui/app_icon_button.dart';
import '../support/harness.dart';
import 'package:pinbench_ui/theme/app_icons.dart';

/// Widget-level Patrol tests.
///
/// Unlike the `integration_test/` suite (which needs a device + `patrol test`),
/// `patrolWidgetTest` runs under plain `flutter test` — fully headless. These
/// double as the proof that the patrol_finders + patrol_log wiring resolves and
/// runs in CI, and as a worked example of the `$` finder API on this codebase.
void main() {
  patrolWidgetTest(
    'AppIconButton renders its icon and fires onPressed when tapped',
    // printLogs routes through patrol_log, giving the readable step-by-step
    // output Patrol is known for.
    config: const PatrolTesterConfig(printLogs: true),
    ($) async {
      var taps = 0;

      await $.pumpWidgetAndSettle(
        appTestApp(
          Center(
            child: AppIconButton(icon: AppIcons.run, tooltip: 'Run', onPressed: () => taps++),
          ),
        ),
      );

      // `$(IconData)` resolves to find.byIcon under the hood.
      await $(AppIcons.run).waitUntilVisible();
      await $(AppIcons.run).tap();

      expect(taps, 1);
    },
  );

  patrolWidgetTest('AppIconButton without onPressed still renders its icon', ($) async {
    await $.pumpWidgetAndSettle(
      appTestApp(const Center(child: AppIconButton(icon: AppIcons.stop))),
    );

    expect($(AppIcons.stop).exists, isTrue);
    expect($(AppIcons.run).exists, isFalse);
  });
}
