import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:pinbench_ui/strings.dart';
import 'package:pinbench/features/workspace/providers/workspace_loading_provider.dart';
import 'package:pinbench/layout/layout.dart';
import '../support/harness.dart';

/// Opening a template measures ~137ms in a profile build. A spinner that comes
/// and goes inside that window reads as a flicker rather than as progress — the
/// screen looks like it glitched, not like it worked — so the overlay waits
/// before saying anything, and most opens never show it at all.
void main() {
  Future<void> pumpLeaf(WidgetTester tester, ProviderContainer container) => tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: appTestApp(const WorkspaceLoadingScope(child: SizedBox.expand())),
    ),
  );

  // The spinner animates forever once mounted, so every wait here is an
  // explicit pump — `pumpAndSettle` would never return.
  Finder overlay() => find.text(AppStrings.loadingWorkspaceLabel);

  testWidgets('says nothing about a workspace that opens quickly', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await pumpLeaf(tester, container);

    container.read(workspaceLoadingProvider.notifier).begin();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(overlay(), findsNothing, reason: 'a short open should not flash a spinner');

    container.read(workspaceLoadingProvider.notifier).end();
    await tester.pump(const Duration(milliseconds: 500));

    expect(overlay(), findsNothing, reason: 'and never shows up late, either');
  });

  testWidgets('says so once the wait is long enough to look broken', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await pumpLeaf(tester, container);

    container.read(workspaceLoadingProvider.notifier).begin();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 200));

    expect(overlay(), findsOneWidget);

    container.read(workspaceLoadingProvider.notifier).end();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(overlay(), findsNothing, reason: 'and it goes away when the work is done');
  });
}
