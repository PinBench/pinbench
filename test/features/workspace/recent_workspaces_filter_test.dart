import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench/features/workspace/providers/recent_workspaces_provider.dart';

void main() {
  group('filterRecentWorkspaces', () {
    // Everything "exists" unless a test says otherwise.
    bool allExist(String _) => true;

    test('excludes workspaces under the app temp/cache dir (templates)', () {
      const appTemp = '/Users/me/Library/Caches/com.example.app';
      final result = filterRecentWorkspaces(
        ['$appTemp/fap_template_123/blink', '/Users/me/Projects/my_circuit'],
        systemTempDir: '/var/folders/xx',
        appTempDir: appTemp,
        exists: allExist,
      );
      expect(result, ['/Users/me/Projects/my_circuit']);
    });

    test('excludes workspaces under the system temp dir', () {
      final result = filterRecentWorkspaces(
        ['/var/folders/xx/T/fap_project_9/sketch', '/Users/me/Projects/keep'],
        systemTempDir: '/var/folders/xx',
        appTempDir: null,
        exists: allExist,
      );
      expect(result, ['/Users/me/Projects/keep']);
    });

    test('excludes non-existent and asset paths', () {
      final result = filterRecentWorkspaces(
        ['/gone/dir', '/app/assets/templates/blink', '/Users/me/Projects/keep'],
        systemTempDir: '/tmp',
        appTempDir: null,
        exists: (p) => p != '/gone/dir',
      );
      expect(result, ['/Users/me/Projects/keep']);
    });

    test('keeps a saved (permanent) workspace', () {
      final result = filterRecentWorkspaces(
        ['/Users/me/Documents/arduino/blink'],
        systemTempDir: '/var/folders/xx',
        appTempDir: '/Users/me/Library/Caches/app',
        exists: allExist,
      );
      expect(result, ['/Users/me/Documents/arduino/blink']);
    });
  });
}
