import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench/features/canvas/widgets/components/circuit_preview.dart';
import 'package:pinbench/layout/views/center/welcome/welcome_templates_section.dart';

import '../../support/harness.dart';

/// Every tile in the Welcome screen's one long scroll view is built whether or
/// not it is on screen. That is cheap for a row of text and not at all cheap
/// for a rendered circuit: each thumbnail parses a bundled `.cdl` and lays out
/// a painter per component, which for the nine bundled templates measured
/// around 200ms of work before the screen could settle — most of it below the
/// fold, and some of it never looked at.
void main() {
  // One test, both phases. `PartRegistry.initializeAsync` clears a global
  // static before repopulating it, so a second container in the same file
  // races the first one's parts out from under it and every preview comes
  // back empty.
  testWidgets('draws thumbnails as their tiles come into view, not before', (tester) async {
    tester.view.physicalSize = const Size(900, 150);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: appTestApp(const SingleChildScrollView(child: WelcomeTemplatesSection())),
      ),
    );
    await tester.pumpAndSettle();

    int drawn() => tester.widgetList<CircuitPreview>(find.byType(CircuitPreview)).length;
    final tiles = tester.widgetList(find.byType(WelcomeTemplatesSection)).length;

    final before = drawn();
    expect(before, greaterThan(0), reason: 'the tiles on screen should show their circuits');

    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -400));
    await tester.pumpAndSettle();

    expect(
      drawn(),
      greaterThan(before),
      reason: 'scrolling further tiles into view should draw their circuits too',
    );
    expect(tiles, 1);
  });
}
