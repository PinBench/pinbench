import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench_ui/ui/app_alert_dialog.dart';
import 'package:pinbench_ui/ui/app_button.dart';
import 'package:pinbench_ui/ui/app_dialog.dart';

import 'package:pinbench_ui/theme/testing.dart';

void main() {
  Widget host(void Function(BuildContext) onTap) => appTestApp(
    Builder(
      builder: (context) => Center(
        child: AppButton(onPressed: () => onTap(context), child: const Text('open')),
      ),
    ),
  );

  testWidgets('confirming answers true', (tester) async {
    late Future<bool> answer;
    await tester.pumpWidget(
      host(
        (context) => answer = showConfirmDialog(
          context,
          title: 'Delete folder?',
          message: 'This cannot be undone.',
          confirmLabel: 'Delete',
          isDestructive: true,
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(await answer, isTrue);
  });

  testWidgets('cancelling answers false', (tester) async {
    late Future<bool> answer;
    await tester.pumpWidget(
      host(
        (context) => answer = showConfirmDialog(
          context,
          title: 'Delete folder?',
          message: 'This cannot be undone.',
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await answer, isFalse);
  });

  // Why this dialog has no ✕: a question with one offers an answer that is
  // neither yes nor no, and the caller has to guess. Dismissing still works —
  // it just resolves to the answer that changes nothing.
  testWidgets('offers nothing but the two answers, and dismissing answers false', (tester) async {
    late Future<bool> answer;
    await tester.pumpWidget(
      host(
        (context) => answer = showConfirmDialog(
          context,
          title: 'Delete folder?',
          message: 'This cannot be undone.',
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: find.byType(AppDialog), matching: find.byType(AppButton)),
      findsNWidgets(2),
      reason: 'an alert must be answered, not dismissed by a third control',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(await answer, isFalse);
  });
}
