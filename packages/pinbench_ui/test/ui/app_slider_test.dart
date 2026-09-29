import 'package:flutter/widgets.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench_ui/ui/app_slider.dart';

import 'package:pinbench_ui/theme/testing.dart';

/// The slider's whole job is a number that only exists once you drag it, and
/// the wrapper converts between the app's plain fraction and the span the
/// widget library models a slider as. A conversion that renders fine at rest
/// and lies under the thumb is what a build cannot catch.
void main() {
  Widget slider({
    double value = 0,
    ValueChanged<double>? onChanged,
    ValueChanged<double>? onChangeEnd,
  }) => appTestApp(
    Center(
      child: SizedBox(
        width: 200,
        child: AppSlider(value: value, onChanged: onChanged ?? (_) {}, onChangeEnd: onChangeEnd),
      ),
    ),
  );

  /// Drags the thumb right, in steps.
  ///
  /// The distance has to clear the gesture recogniser's slop or the drag is
  /// never recognised and nothing is reported at all.
  ///
  /// It has to be the thumb: the slider only follows a drag that starts on it,
  /// so a drag from the widget's centre moves nothing and silently reports
  /// the value it already had. Found by shape rather than by type so the test
  /// does not have to import the widget library the wrapper exists to hide.
  Future<void> dragThumb(WidgetTester tester) async {
    final thumb = find.byWidgetPredicate((w) => w.runtimeType.toString() == 'Thumb');
    expect(thumb, findsOneWidget, reason: 'the slider should have a thumb to drag');

    final gesture = await tester.startGesture(tester.getCenter(thumb));
    for (var step = 0; step < 6; step++) {
      await gesture.moveBy(const Offset(10, 0));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('renders at the value it is given', (tester) async {
    await tester.pumpWidget(slider(value: 0.5));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('reports a fraction while dragging', (tester) async {
    final reported = <double>[];
    await tester.pumpWidget(slider(onChanged: reported.add));
    await tester.pumpAndSettle();

    await dragThumb(tester);

    expect(reported, isNotEmpty);
    // A fraction, not pixels — the conversion the wrapper exists to do.
    expect(reported.every((v) => v >= 0 && v <= 1), isTrue);
    expect(reported.last, greaterThan(0));
  });

  // The caller records undo history and re-solves the circuit here, so this
  // firing per drag frame instead of once would bury the undo stack.
  testWidgets('reports the end of a drag once', (tester) async {
    final ends = <double>[];
    await tester.pumpWidget(slider(onChangeEnd: ends.add));
    await tester.pumpAndSettle();

    await dragThumb(tester);

    expect(ends, hasLength(1));
    expect(ends.single, inInclusiveRange(0, 1));
  });

  // A thumb that starts halfway must not report from zero: that would send a
  // servo or potentiometer snapping to the left the moment it was touched.
  testWidgets('drags on from where it started, not from zero', (tester) async {
    final reported = <double>[];
    await tester.pumpWidget(slider(value: 0.5, onChanged: reported.add));
    await tester.pumpAndSettle();

    await dragThumb(tester);

    expect(reported.first, greaterThan(0.4));
  });
}
