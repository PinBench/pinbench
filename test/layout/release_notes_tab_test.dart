import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plat/plat.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pinbench/core/chrome/chrome_commands.dart';
import 'package:pinbench/core/updates/release_notes.dart';
import 'package:pinbench/core/updates/update_providers.dart';
import 'package:pinbench/core/utils/shared_preferences_provider.dart';
import 'package:pinbench/layout/controllers/app_layout_controller.dart';
import 'package:pinbench/layout/views/center/release_notes_tab_view.dart';

import '../support/harness.dart';

/// Help ▸ Release Notes opens one tab, named for the version, beside whatever
/// else is open; the tab shows that version's notes and the box that decides
/// whether it opens after the next update.
void main() {
  group('the tab', () {
    ProviderContainer container() {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      return c;
    }

    test('opens in the center pane, named for the version, and focused', () {
      final c = container();
      c.read(appLayoutControllerProvider).openReleaseNotesTab(version: '0.2.0');

      final tab = c.read(appLayoutControllerProvider).platController.snapshot(AppTabs.releaseNotes);
      expect(tab, isA<LeafSnapshot>());
      expect((tab! as LeafSnapshot).title, 'Release Notes: 0.2.0');

      final group =
          c.read(appLayoutControllerProvider).platController.snapshot('center_pane')!
              as TabGroupSnapshot;
      expect(group.activeTab?.firstLeaf?.id, AppTabs.releaseNotes);
      expect(
        group.tabs.map((t) => t.firstLeaf?.id),
        contains(AppTabs.welcome),
        reason: 'beside the welcome screen, not in place of it',
      );
    });

    test('opening it again focuses the one already open', () {
      final c = container();
      final layout = c.read(appLayoutControllerProvider)
        ..openReleaseNotesTab(version: '0.2.0')
        ..openSettingsTab()
        ..openReleaseNotesTab(version: '0.2.0');

      final group =
          c.read(appLayoutControllerProvider).platController.snapshot('center_pane')!
              as TabGroupSnapshot;
      expect(group.tabs.where((t) => t.firstLeaf?.id == AppTabs.releaseNotes), hasLength(1));
      expect(group.activeTab?.firstLeaf?.id, AppTabs.releaseNotes);
      expect(layout.isSettingsTabSelected(), isFalse);
    });
  });

  group('the page', () {
    Future<void> pump(WidgetTester tester, {ReleaseNotes? notes}) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            appVersionProvider.overrideWith((ref) async => '0.2.0'),
            releaseNotesProvider.overrideWith((ref) async => notes),
          ],
          child: appTestApp(const ReleaseNotesTabView()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows the version, its date and its notes', (tester) async {
      await pump(
        tester,
        notes: const ReleaseNotes(
          title: '0.2.0',
          date: '2026-09-09',
          body: '### Added\n\n- **Something new.**',
        ),
      );

      expect(find.text('PinBench 0.2.0'), findsOneWidget);
      expect(find.text('Release date: 2026-09-09'), findsOneWidget);
      expect(find.text('Added'), findsOneWidget);
      expect(find.textContaining('Something new.', findRichText: true), findsOneWidget);
    });

    testWidgets('says so when there are no notes to show', (tester) async {
      await pump(tester);
      expect(find.text('The release notes for this build could not be read.'), findsOneWidget);
    });

    testWidgets('the box turns opening after an update off and on', (tester) async {
      await pump(
        tester,
        notes: const ReleaseNotes(title: '0.2.0', body: '- A change.'),
      );
      final container = ProviderScope.containerOf(tester.element(find.byType(ReleaseNotesTabView)));
      expect(container.read(showReleaseNotesAfterUpdateProvider), isTrue);

      await tester.tap(find.text('Show release notes after an update'));
      await tester.pumpAndSettle();
      expect(container.read(showReleaseNotesAfterUpdateProvider), isFalse);

      await tester.tap(find.text('Show release notes after an update'));
      await tester.pumpAndSettle();
      expect(container.read(showReleaseNotesAfterUpdateProvider), isTrue);
    });
  });
}
