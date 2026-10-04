import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pinbench/core/updates/release_notes.dart';
import 'package:pinbench/core/utils/shared_preferences_provider.dart';

/// The Release Notes tab shows the running build's section of the bundled
/// changelog, and opens on its own only on the first launch of a new version.
void main() {
  const changelog = '''
# Changelog

Preamble that belongs to no release.

## How entries are written

- Not a release either.

---

## [Unreleased]

### Added

- **Something new.**

### Internal

- A refactor nobody upgrading needs to hear about.

---

## [0.2.0] - 2026-09-09

### Fixed

- A bug.

---

## Before this file

History.
''';

  group('releaseNotesFor', () {
    test("picks the running version's section, with its date", () {
      final notes = releaseNotesFor(changelog, '0.2.0')!;
      expect(notes.title, '0.2.0');
      expect(notes.date, '2026-09-09');
      expect(notes.body, '### Fixed\n\n- A bug.');
    });

    test('takes a leading v on the version', () {
      expect(releaseNotesFor(changelog, 'v0.2.0')!.title, '0.2.0');
    });

    test('falls back to Unreleased for a version with no section of its own', () {
      final notes = releaseNotesFor(changelog, '0.3.0')!;
      expect(notes.title, 'Unreleased');
      expect(notes.date, isNull);
      expect(notes.body, contains('Something new'));
    });

    test('falls back to Unreleased before the version is known', () {
      expect(releaseNotesFor(changelog, null)!.title, 'Unreleased');
    });

    test('leaves out the Internal group and the rule after the section', () {
      final body = releaseNotesFor(changelog, null)!.body;
      expect(body, isNot(contains('Internal')));
      expect(body, isNot(contains('refactor')));
      expect(body, isNot(endsWith('---')));
    });

    test('ignores headings that are not releases', () {
      final body = releaseNotesFor(changelog, null)!.body;
      expect(body, isNot(contains('Preamble')));
      expect(body, isNot(contains('Not a release')));
      expect(body, isNot(contains('History')));
    });

    test('is null for a file with neither the version nor Unreleased', () {
      expect(releaseNotesFor('# Changelog\n\n## [0.1.0]\n\n- Old.\n', '0.2.0'), isNull);
    });

    // The file the app actually bundles, so a reshuffle of its headings that
    // leaves the tab empty fails here rather than in front of a user.
    // Asked for pubspec.yaml's version, which is what a build reports, so a
    // version bumped without its own section fails here too: the tab would
    // otherwise fall back to an empty [Unreleased].
    test("the repository's changelog has notes for this version", () {
      final version = RegExp(
        r'^version:\s*([0-9.]+)',
        multiLine: true,
      ).firstMatch(File('pubspec.yaml').readAsStringSync())![1]!;
      final notes = releaseNotesFor(File('CHANGELOG.md').readAsStringSync(), version)!;
      expect(notes.title, version, reason: 'CHANGELOG.md needs a "## [$version] - <date>" section');
      expect(notes.body, contains('### Added'));
      expect(notes.body, isNot(contains('### Internal')));
    });
  });

  group('opening on launch', () {
    Future<ProviderContainer> container(Map<String, Object> prefs) async {
      SharedPreferences.setMockInitialValues(prefs);
      final c = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(await SharedPreferences.getInstance()),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    Future<bool> launch(ProviderContainer c, String version) =>
        c.read(showReleaseNotesAfterUpdateProvider.notifier).shouldOpenOnLaunchOf(version);

    test('not on a first install', () async {
      final c = await container({});
      expect(await launch(c, '0.2.0'), isFalse);
    });

    test('on the first launch of a new version, and only that one', () async {
      final c = await container({});
      await launch(c, '0.1.0');

      expect(await launch(c, '0.2.0'), isTrue);
      expect(await launch(c, '0.2.0'), isFalse, reason: 'the second launch of it');
    });

    test('not when the box is cleared, though the version is still recorded', () async {
      final c = await container({});
      await launch(c, '0.1.0');
      await c.read(showReleaseNotesAfterUpdateProvider.notifier).set(enabled: false);

      expect(await launch(c, '0.2.0'), isFalse);

      // Ticked again later: the update it skipped is not replayed.
      await c.read(showReleaseNotesAfterUpdateProvider.notifier).set(enabled: true);
      expect(await launch(c, '0.2.0'), isFalse);
    });

    test('the box remembers being cleared', () async {
      final c = await container({'releaseNotes.showAfterUpdate': false});
      expect(c.read(showReleaseNotesAfterUpdateProvider), isFalse);
    });
  });
}
