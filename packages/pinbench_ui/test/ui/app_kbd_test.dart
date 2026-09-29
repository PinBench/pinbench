import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench_ui/theme/testing.dart';
import 'package:pinbench_ui/ui/app_kbd.dart';

/// Stands in for a tooltip overlay: tall, and loose rather than tight.
Widget _inTallLooseBox(List<Widget> children) => appTestApp(
  Align(
    alignment: Alignment.topLeft,
    child: SizedBox(
      height: 600,
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    ),
  ),
);

void main() {
  group('AppKbd', () {
    // Regression: the cap used to set `alignment` on its Container, which
    // makes a Container expand to fill whatever constraints it is handed.
    // Inside a tooltip the overlay hands it the full screen height, so the
    // cap grew to 600px and stretched the whole popup with it.
    testWidgets('stays text-sized inside a tall, loose parent', (tester) async {
      await tester.pumpWidget(
        _inTallLooseBox(const [
          Text('Undo'),
          AppKbd('⌘Z', variant: AppKbdVariant.dense),
          AppKbd('P'),
        ]),
      );
      await tester.pumpAndSettle();

      for (final cap in tester.widgetList<AppKbd>(find.byType(AppKbd))) {
        expect(
          tester.getSize(find.byWidget(cap)).height,
          lessThan(40),
          reason: 'cap "${cap.label}" stretched to fill its parent',
        );
      }
    });

    testWidgets('gives one-character caps a consistent floor width', (tester) async {
      await tester.pumpWidget(_inTallLooseBox(const [AppKbd('P'), AppKbd('⇧')]));
      await tester.pumpAndSettle();

      final caps = tester.widgetList<AppKbd>(find.byType(AppKbd)).toList();
      final narrow = tester.getSize(find.byWidget(caps[0]));
      final wide = tester.getSize(find.byWidget(caps[1]));

      expect(narrow.width, greaterThanOrEqualTo(24));
      expect(narrow.width, equals(wide.width));
    });
  });
}
