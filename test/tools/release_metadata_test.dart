@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench/core/updates/release_manifest.dart';
import 'package:pinbench/core/updates/release_version.dart';

import '../../tools/release_metadata.dart';

/// The two ends of the update mechanism, checked against each other.
///
/// The failure this exists for is silent in both directions: a malformed
/// appcast makes Sparkle report "no updates" with nothing in any log, and a
/// manifest the app cannot parse makes the Linux check fail closed forever.
/// Neither breaks a build, so nothing else would notice.
void main() {
  const asset = AssetInfo(
    fileName: 'app-0.4.0-macos.dmg',
    url: 'https://example.test/download/v0.4.0/app-0.4.0-macos.dmg',
    sha256: 'deadbeef',
    size: 12345,
    edSignature: 'c2lnbmF0dXJl',
  );

  group('appcast', () {
    final xml = buildAppcast(
      version: '0.4.0',
      buildNumber: 4000,
      notesUrl: 'https://example.test/tag/v0.4.0',
      publishedAt: DateTime.utc(2026, 8, 13, 12),
      asset: asset,
    );

    test('carries the build number as sparkle:version', () {
      // Sparkle compares this against CFBundleVersion. Putting the display
      // version here instead is the classic way to ship a feed that never
      // offers an update.
      expect(xml, contains('<sparkle:version>4000</sparkle:version>'));
      expect(xml, contains('<sparkle:shortVersionString>0.4.0</sparkle:shortVersionString>'));
    });

    test('dates the item in RFC 822, which is the only format Sparkle reads', () {
      expect(xml, contains('<pubDate>Thu, 13 Aug 2026 12:00:00 +0000</pubDate>'));
    });

    test('includes the signature when there is one', () {
      expect(xml, contains('sparkle:edSignature="c2lnbmF0dXJl"'));
    });

    test('omits the signature attribute entirely when there is none', () {
      // An empty `sparkle:edSignature=""` is worse than no attribute:
      // Sparkle treats it as a failed signature and rejects the item.
      const unsigned = AssetInfo(
        fileName: 'app.dmg',
        url: 'https://example.test/app.dmg',
        sha256: 'beef',
        size: 1,
      );
      final output = buildAppcast(
        version: '0.4.0',
        buildNumber: 4000,
        notesUrl: 'https://example.test/tag/v0.4.0',
        publishedAt: DateTime.utc(2026, 8, 13, 12),
        asset: unsigned,
      );
      expect(output, isNot(contains('edSignature')));
    });

    test('escapes a URL containing an ampersand', () {
      final output = buildAppcast(
        version: '0.4.0',
        buildNumber: 4000,
        notesUrl: 'https://example.test/notes?a=1&b=2',
        publishedAt: DateTime.utc(2026, 8, 13, 12),
        asset: asset,
      );
      expect(output, contains('a=1&amp;b=2'));
      expect(output, isNot(contains('a=1&b=2')));
    });
  });

  group('option parsing', () {
    test('splits repeated --asset and --ed-signature pairs', () {
      final options = ReleaseOptions.parse([
        '--version',
        '0.4.0',
        '--build-number',
        '4000',
        '--base-url',
        'https://example.test/v0.4.0/',
        '--notes-url',
        'https://example.test/tag',
        '--published-at',
        '2026-08-13T12:00:00Z',
        '--asset',
        'macos=dist/a.dmg',
        '--asset',
        'linux=dist/a.tar.gz',
        '--ed-signature',
        'macos=sig',
      ]);

      expect(options.assets, {'macos': 'dist/a.dmg', 'linux': 'dist/a.tar.gz'});
      expect(options.edSignatures, {'macos': 'sig'});
      // The trailing slash would otherwise produce `…/v0.4.0//a.dmg`.
      expect(options.baseUrl, 'https://example.test/v0.4.0');
    });

    test('treats an unset signing secret as no signature at all', () {
      // GitHub passes an absent secret through as an empty string, so the
      // flag arrives as `--ed-signature macos=` rather than not arriving.
      final options = ReleaseOptions.parse([
        '--version',
        '0.4.0',
        '--build-number',
        '4000',
        '--base-url',
        'https://example.test',
        '--notes-url',
        'https://example.test/tag',
        '--published-at',
        '2026-08-13T12:00:00Z',
        '--ed-signature',
        'macos=',
      ]);
      expect(options.edSignatures, isEmpty);
    });
  });

  test('the manifest it writes is the manifest the app reads', () async {
    // The round trip. `latest.json` has exactly one consumer in the app —
    // ManifestUpdateService — and the two are written in different files by
    // different halves of the release, so nothing but this pins them
    // together.
    final dir = await Directory.systemTemp.createTemp('release_metadata_test');
    addTearDown(() => dir.delete(recursive: true));

    final dmg = File('${dir.path}/app-0.4.0-macos.dmg')..writeAsStringSync('mac');
    final tarball = File('${dir.path}/app-0.4.0-linux-x64.tar.gz')..writeAsStringSync('linux');

    await generateReleaseMetadata([
      '--version',
      '0.4.0',
      '--build-number',
      '4000',
      '--base-url',
      'https://example.test/download/v0.4.0',
      '--notes-url',
      'https://example.test/tag/v0.4.0',
      '--published-at',
      '2026-08-13T12:00:00Z',
      '--out',
      '${dir.path}/out',
      '--asset',
      'macos=${dmg.path}',
      '--asset',
      'linux=${tarball.path}',
    ]);

    final json = jsonDecode(File('${dir.path}/out/latest.json').readAsStringSync());
    final manifest = ReleaseManifest.fromJson(json);

    expect(manifest, isNotNull);
    expect(manifest!.version, const ReleaseVersion(0, 4, 0));
    expect(manifest.notesUrl, 'https://example.test/tag/v0.4.0');
    expect(
      manifest.assets['linux']?.url,
      'https://example.test/download/v0.4.0/app-0.4.0-linux-x64.tar.gz',
    );
    expect(manifest.assets['linux']?.size, 5);

    // Linux has no appcast — it takes the manifest path instead.
    expect(File('${dir.path}/out/appcast-macos.xml').existsSync(), isTrue);
    expect(File('${dir.path}/out/appcast-linux.xml').existsSync(), isFalse);
  });
}
