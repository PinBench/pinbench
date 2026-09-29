// Generates the three files that turn a pile of release assets into a
// release: the two Sparkle appcasts the desktop app polls, and the plain
// JSON manifest the Linux build and the download page read.
//
// Run from the release workflow after every platform's artifact has been
// downloaded and hashed:
//
//   dart run tools/release_metadata.dart \
//     --version 0.4.0 \
//     --build-number 400 \
//     --base-url https://github.com/<owner>/<repo>/releases/download/v0.4.0 \
//     --notes-url https://github.com/<owner>/<repo>/releases/tag/v0.4.0 \
//     --published-at 2026-08-13T12:00:00Z \
//     --out dist \
//     --asset macos=dist/App-macos.dmg \
//     --asset windows=dist/App-windows-setup.exe \
//     --asset linux=dist/App-linux.tar.gz \
//     --ed-signature macos=<base64>
//
// Written in Dart rather than as a shell heredoc because it has to hash
// files, XML-escape strings and emit two different formats — and because a
// malformed appcast is not a build failure, it is an update mechanism that
// silently stops finding updates. `release_metadata_test.dart` covers it.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

Future<void> main(List<String> args) => generateReleaseMetadata(args);

/// The whole job, separated from `main` so the test can call it without its
/// own `main` colliding with this one.
Future<void> generateReleaseMetadata(List<String> args) async {
  final options = ReleaseOptions.parse(args);
  final assets = <String, AssetInfo>{};
  for (final entry in options.assets.entries) {
    final file = File(entry.value);
    if (!file.existsSync()) {
      stderr.writeln('release_metadata: no such asset ${entry.value}');
      exitCode = 1;
      return;
    }
    final bytes = await file.readAsBytes();
    assets[entry.key] = AssetInfo(
      fileName: file.uri.pathSegments.last,
      url: '${options.baseUrl}/${file.uri.pathSegments.last}',
      sha256: sha256.convert(bytes).toString(),
      size: bytes.length,
      edSignature: options.edSignatures[entry.key],
    );
  }

  final out = Directory(options.outDir)..createSync(recursive: true);
  Future<void> write(String name, String contents) =>
      File('${out.path}/$name').writeAsString(contents);

  for (final platform in ['macos', 'windows']) {
    final asset = assets[platform];
    // A platform that failed to build gets no appcast rather than an empty
    // one: replacing a good feed with a valid-but-empty document would tell
    // every installed copy that it is up to date.
    if (asset == null) continue;
    await write(
      'appcast-$platform.xml',
      buildAppcast(
        version: options.version,
        buildNumber: options.buildNumber,
        notesUrl: options.notesUrl,
        publishedAt: options.publishedAt,
        asset: asset,
      ),
    );
  }

  await write(
    'latest.json',
    '${const JsonEncoder.withIndent('  ').convert({
      'version': options.version,
      'publishedAt': options.publishedAt.toUtc().toIso8601String(),
      'notesUrl': options.notesUrl,
      'assets': {
        for (final entry in assets.entries) entry.key: {'url': entry.value.url, 'sha256': entry.value.sha256, 'size': entry.value.size},
      },
    })}\n',
  );

  // Two spaces between hash and name, and a trailing newline: that is the
  // format `shasum -c` reads, so the file is checkable and not just readable.
  final sums = [for (final asset in assets.values) '${asset.sha256}  ${asset.fileName}'];
  await write('SHA256SUMS.txt', '${sums.join('\n')}\n');

  stdout.writeln('release_metadata: wrote ${assets.length} platform(s) to ${out.path}');
}

/// One downloadable file, with everything the feeds need to say about it.
class const AssetInfo({
  required final String fileName,
  required final String url,
  required final String sha256,
  required final int size,

  /// Sparkle's EdDSA signature over the file, from `sign_update`. Null when
  /// no signing key was available — Sparkle then falls back to verifying the
  /// update's Developer ID against the running app's, which is weaker but is
  /// still a real check, and is better than refusing to publish.
  final String? edSignature,
});

/// A single-item Sparkle appcast.
///
/// One item, always the newest: Sparkle only ever installs the best item in
/// the feed, and keeping history in it means every old release stays
/// reachable by anyone who can edit the file. `sparkle:version` is the build
/// number (Sparkle compares this) and `sparkle:shortVersionString` is what it
/// shows a human.
String buildAppcast({
  required String version,
  required int buildNumber,
  required String notesUrl,
  required DateTime publishedAt,
  required AssetInfo asset,
}) {
  final signature = asset.edSignature;
  return '''
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>PinBench</title>
    <link>${_xml(notesUrl)}</link>
    <description>Signed desktop releases.</description>
    <language>en</language>
    <item>
      <title>Version ${_xml(version)}</title>
      <pubDate>${_rfc822(publishedAt)}</pubDate>
      <sparkle:version>$buildNumber</sparkle:version>
      <sparkle:shortVersionString>${_xml(version)}</sparkle:shortVersionString>
      <sparkle:releaseNotesLink>${_xml(notesUrl)}</sparkle:releaseNotesLink>
      <enclosure url="${_xml(asset.url)}"
                 length="${asset.size}"
                 type="application/octet-stream"${signature == null ? '' : '\n                 sparkle:edSignature="${_xml(signature)}"'} />
    </item>
  </channel>
</rss>
''';
}

/// Sparkle parses `pubDate` as RFC 822, and rejects the item outright if it
/// cannot — which presents as "no updates found" with nothing in any log.
String _rfc822(DateTime date) {
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final utc = date.toUtc();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${days[utc.weekday - 1]}, ${two(utc.day)} ${months[utc.month - 1]} ${utc.year} '
      '${two(utc.hour)}:${two(utc.minute)}:${two(utc.second)} +0000';
}

String _xml(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// The command line, parsed.
class const ReleaseOptions({
  required final String version,
  required final int buildNumber,
  required final String baseUrl,
  required final String notesUrl,
  required final DateTime publishedAt,
  required final String outDir,
  required final Map<String, String> assets,
  required final Map<String, String> edSignatures,
}) {
  factory parse(List<String> args) {
    final single = <String, String>{};
    final assets = <String, String>{};
    final signatures = <String, String>{};

    for (var i = 0; i < args.length; i += 2) {
      final name = args[i].replaceFirst(RegExp('^--'), '');
      final value = i + 1 < args.length ? args[i + 1] : '';
      switch (name) {
        case 'asset':
          final split = value.indexOf('=');
          assets[value.substring(0, split)] = value.substring(split + 1);
        case 'ed-signature':
          final split = value.indexOf('=');
          final signature = value.substring(split + 1);
          // An absent secret reaches us as an empty value, not an absent
          // flag — treat it as absent rather than emitting an empty
          // signature attribute, which Sparkle rejects the whole item over.
          if (signature.isNotEmpty) signatures[value.substring(0, split)] = signature;
        default:
          single[name] = value;
      }
    }

    final version = single['version']!;
    return ReleaseOptions(
      version: version,
      buildNumber: int.parse(single['build-number']!),
      baseUrl: single['base-url']!.replaceAll(RegExp(r'/+$'), ''),
      notesUrl: single['notes-url']!,
      publishedAt: DateTime.parse(single['published-at']!),
      outDir: single['out'] ?? 'dist',
      assets: assets,
      edSignatures: signatures,
    );
  }
}
