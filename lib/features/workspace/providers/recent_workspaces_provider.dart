import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/platform/platform_capabilities.dart';
import '../../../core/utils/shared_preferences_provider.dart';

part 'recent_workspaces_provider.g.dart';

/// The app's temporary directory (`getTemporaryDirectory()`), resolved once at
/// startup and overridden in `app/bootstrap.dart`. On macOS this is
/// `~/Library/Caches/<id>/`, which differs from [Directory.systemTemp] —
/// template workspaces live here, so the recent list must exclude it to avoid
/// showing throwaway temp projects.
/// A plain [Provider], like every override placeholder here — see
/// `sharedPreferencesProvider`.
final appTempDirProvider = Provider<String?>((ref) => null);

/// Filters out workspaces that should never appear in "Recent": ones that no
/// longer exist, throwaway temporary workspaces (under the system temp dir or
/// the app's temp/cache dir — e.g. templates and blank projects), and anything
/// inside the bundled assets folder.
///
/// Pure (filesystem access is injected via [exists]) so it is unit-testable.
List<String> filterRecentWorkspaces(
  List<String> stored, {
  required String systemTempDir,
  required String? appTempDir,
  required bool Function(String path) exists,
}) => stored.where((path) {
  if (!exists(path)) return false;
  if (path.startsWith(systemTempDir)) return false;
  if (appTempDir != null && path.startsWith(appTempDir)) return false;
  if (path.contains('/assets/')) return false;
  return true;
}).toList();

@Riverpod(keepAlive: true)
class RecentWorkspaces extends _$RecentWorkspaces {
  static const _key = 'recentWorkspaces';
  static const _maxRecents = 10;

  @override
  List<String> build() {
    final prefs = ref.read(sharedPreferencesProvider);
    final stored = prefs.getStringList(_key) ?? [];
    // The web preview has no local filesystem, so there are no on-disk recent
    // workspaces to resolve; `dart:io` access would throw there.
    if (!PlatformCapabilities.supportsRecentWorkspaces) return const [];
    return filterRecentWorkspaces(
      stored,
      systemTempDir: Directory.systemTemp.path,
      appTempDir: ref.read(appTempDirProvider),
      exists: (path) => Directory(path).existsSync(),
    );
  }

  Future<void> addWorkspace(String path) async {
    final prefs = ref.read(sharedPreferencesProvider);
    final currentList = [...state];

    // Remove if it already exists to put it at the top
    currentList.remove(path);
    currentList.insert(0, path);

    // Keep only the most recent N
    if (currentList.length > _maxRecents) {
      currentList.removeLast();
    }

    state = currentList;
    await prefs.setStringList(_key, currentList);
  }

  Future<void> clearRecentWorkspaces() async {
    final prefs = ref.read(sharedPreferencesProvider);
    state = [];
    await prefs.remove(_key);
  }
}
