import 'package:flutter/services.dart';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../utils/logger.dart';
import '../utils/shared_preferences_provider.dart';
import 'update_providers.dart';

part 'release_notes.g.dart';

const _log = AppLogger('core.release_notes');

/// What changed in one release, as the Release Notes tab shows it.
class const ReleaseNotes({
  /// The changelog's name for the release: a version, or `Unreleased`.
  required final String title,

  /// The date on the release's heading, as written there, if it has one.
  final String? date,

  /// The release's entries, in Markdown, without the `Internal` group.
  required final String body,
});

/// The notes for [version] in a [Keep a Changelog][kac] [changelog]: the
/// section headed `## [version]`, or the `## [Unreleased]` one when there is
/// no section for it — which is where a build cut before its heading was
/// renamed finds its notes. Null when the file has neither.
///
/// The `### Internal` group is left out. The changelog keeps it for the people
/// working on the app; its own rules say someone deciding whether to upgrade
/// does not need it.
///
/// [kac]: https://keepachangelog.com/en/1.1.0/
ReleaseNotes? releaseNotesFor(String changelog, String? version) {
  final wanted = version?.replaceFirst(RegExp('^v'), '');
  final sections = <String, ({String? date, String body})>{};

  String? current;
  String? currentDate;
  final body = StringBuffer();
  void close() {
    if (current != null) sections[current] = (date: currentDate, body: body.toString());
    body.clear();
  }

  for (final line in changelog.replaceAll('\r\n', '\n').split('\n')) {
    if (line.startsWith('## ')) {
      close();
      final heading = _releaseHeading.firstMatch(line);
      current = heading?.group(1);
      currentDate = heading?.group(2);
    } else if (current != null) {
      body.writeln(line);
    }
  }
  close();

  final title = sections.containsKey(wanted) ? wanted! : 'Unreleased';
  final section = sections[title];
  if (section == null) return null;
  return ReleaseNotes(title: title, date: section.date, body: _withoutInternal(section.body));
}

/// `## [1.2.0] - 2026-09-09`, `## [Unreleased]`.
final _releaseHeading = RegExp(r'^## \[([^\]]+)\](?:\s+-\s+(\S+))?');

String _withoutInternal(String body) {
  final out = StringBuffer();
  var skipping = false;
  for (final line in body.split('\n')) {
    if (line.startsWith('### ')) skipping = line.trim().toLowerCase() == '### internal';
    if (!skipping) out.writeln(line);
  }
  // The rule that separates one release from the next belongs to neither.
  return out.toString().trim().replaceFirst(RegExp(r'\n*---$'), '').trim();
}

/// The bundled changelog's notes for the running build.
@Riverpod(keepAlive: true)
Future<ReleaseNotes?> releaseNotes(Ref ref) async {
  final version = await ref.watch(appVersionProvider.future);
  try {
    return releaseNotesFor(await rootBundle.loadString('CHANGELOG.md'), version);
  } catch (e) {
    _log.warning('could not read the bundled changelog: $e');
    return null;
  }
}

/// Whether the Release Notes tab opens by itself on the first launch of a new
/// version. The checkbox at the top of the tab, as in VS Code.
@Riverpod(keepAlive: true)
class ShowReleaseNotesAfterUpdate extends _$ShowReleaseNotesAfterUpdate {
  static const _prefsKey = 'releaseNotes.showAfterUpdate';

  @override
  bool build() => ref.read(sharedPreferencesProvider).getBool(_prefsKey) ?? true;

  Future<void> set({required bool enabled}) async {
    state = enabled;
    await ref.read(sharedPreferencesProvider).setBool(_prefsKey, enabled);
  }

  static const _lastLaunchedKey = 'releaseNotes.lastLaunchedVersion';

  /// Records [version] as the one last launched, and says whether the notes
  /// should open for it: only when a *different* version was launched before,
  /// so a first install opens on the welcome screen and nothing else, and only
  /// while this is on. Recorded either way, so turning it back on later does
  /// not replay an update long past.
  Future<bool> shouldOpenOnLaunchOf(String version) async {
    final prefs = ref.read(sharedPreferencesProvider);
    final previous = prefs.getString(_lastLaunchedKey);
    if (previous == version) return false;
    await prefs.setString(_lastLaunchedKey, version);
    return previous != null && state;
  }
}
