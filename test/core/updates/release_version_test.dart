import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench/core/updates/release_version.dart';

/// The Linux update check is a version comparison and nothing else, so this
/// is the whole correctness surface of that path: get it wrong in the
/// permissive direction and every launch nags about an update that is already
/// installed; wrong the other way and a release is never announced at all.
void main() {
  group('tryParse', () {
    test('reads a plain release', () {
      final version = ReleaseVersion.tryParse('1.2.3');
      expect(version, const ReleaseVersion(1, 2, 3));
    });

    test('tolerates the v the git tags carry', () {
      expect(ReleaseVersion.tryParse('v0.4.0'), const ReleaseVersion(0, 4, 0));
    });

    test('drops the build metadata pubspec versions carry', () {
      // `version: 0.0.1+1` reaches the app as `0.0.1`, but a manifest written
      // by hand might not have had the `+1` stripped.
      expect(ReleaseVersion.tryParse('0.0.1+42'), const ReleaseVersion(0, 0, 1));
    });

    test('fills in omitted components', () {
      expect(ReleaseVersion.tryParse('2'), const ReleaseVersion(2, 0, 0));
      expect(ReleaseVersion.tryParse('2.1'), const ReleaseVersion(2, 1, 0));
    });

    test('keeps the pre-release tag', () {
      expect(
        ReleaseVersion.tryParse('1.0.0-beta.2'),
        const ReleaseVersion(1, 0, 0, preRelease: 'beta.2'),
      );
    });

    test('returns null rather than throwing on anything else', () {
      for (final input in [null, '', 'latest', '1.2.3.4', '1.x.0', '-1.0.0', '1.0.0-']) {
        expect(ReleaseVersion.tryParse(input), isNull, reason: 'parsed $input');
      }
    });
  });

  group('ordering', () {
    test('compares component by component, most significant first', () {
      expect(ReleaseVersion.tryParse('1.0.0')! > ReleaseVersion.tryParse('0.99.99')!, isTrue);
      expect(ReleaseVersion.tryParse('0.4.0')! > ReleaseVersion.tryParse('0.3.99')!, isTrue);
      expect(ReleaseVersion.tryParse('0.3.10')! > ReleaseVersion.tryParse('0.3.9')!, isTrue);
    });

    test('does not compare 0.3.10 as a decimal', () {
      // The bug this guards: string or double comparison puts 0.3.9 above
      // 0.3.10, so the tenth patch of a series never announces itself.
      expect(ReleaseVersion.tryParse('0.3.9')! < ReleaseVersion.tryParse('0.3.10')!, isTrue);
    });

    test('a pre-release precedes the release it leads to', () {
      expect(ReleaseVersion.tryParse('1.0.0-beta.1')! < ReleaseVersion.tryParse('1.0.0')!, isTrue);
      expect(
        ReleaseVersion.tryParse('1.0.0-beta.1')! < ReleaseVersion.tryParse('1.0.0-beta.2')!,
        isTrue,
      );
    });

    test('equal versions are neither newer nor older', () {
      final a = ReleaseVersion.tryParse('1.2.3')!;
      final b = ReleaseVersion.tryParse('v1.2.3')!;
      expect(a <= b, isTrue);
      expect(a >= b, isTrue);
      expect(a > b, isFalse);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });
}
