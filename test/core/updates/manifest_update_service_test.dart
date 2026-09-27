import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:pinbench/core/updates/release_version.dart';
import 'package:pinbench/core/updates/update_service.dart';
import 'package:pinbench/core/updates/update_status.dart';

/// The Linux path end to end: fetch, parse, compare, decide.
///
/// The failure that matters most here is the one that fails *open* — a
/// malformed manifest, a 404 before the first release exists, an offline
/// laptop — because a check that reports "update available" on every error
/// would send users to a download page for a build they already have.
void main() {
  ManifestUpdateService serviceFor(String? current, MockClient client) =>
      ManifestUpdateService(currentVersion: current, client: client);

  MockClient respondingWith(String body, {int status = 200}) =>
      MockClient((_) async => http.Response(body, status));

  String manifest({required String version, String? linuxUrl}) => jsonEncode({
    'version': version,
    'notesUrl': 'https://example.test/releases/v$version',
    if (linuxUrl != null)
      'assets': {
        'linux': {'url': linuxUrl, 'sha256': 'abc', 'size': 1},
      },
  });

  test('reports an available update when the manifest is ahead', () async {
    final service = serviceFor(
      '0.3.0',
      respondingWith(manifest(version: '0.4.0', linuxUrl: 'https://example.test/app.AppImage')),
    );

    final status = await service.check(inBackground: true);

    expect(status, isA<UpdateAvailable>());
    final available = status as UpdateAvailable;
    expect(available.version, const ReleaseVersion(0, 4, 0));
    expect(available.downloadUrl, 'https://example.test/app.AppImage');
    // Linux never installs for itself — see UpdateConfig.linuxManifestUrl.
    expect(available.installable, isFalse);
  });

  test('reports up to date when the manifest matches', () async {
    final service = serviceFor('0.4.0', respondingWith(manifest(version: '0.4.0')));
    expect(await service.check(inBackground: true), isA<UpdateUpToDate>());
  });

  test('reports up to date when the running build is ahead of the manifest', () async {
    // A local build from main is normal for a contributor, and telling them
    // to "update" to an older release would be wrong.
    final service = serviceFor('0.5.0', respondingWith(manifest(version: '0.4.0')));
    expect(await service.check(inBackground: true), isA<UpdateUpToDate>());
  });

  test('fails closed on a 404, which is the state before the first release', () async {
    final service = serviceFor('0.1.0', respondingWith('Not Found', status: 404));
    expect(await service.check(inBackground: true), isA<UpdateFailed>());
  });

  test('fails closed on a body that is not the manifest', () async {
    final service = serviceFor('0.1.0', respondingWith('<html>a proxy login page</html>'));
    expect(await service.check(inBackground: true), isA<UpdateFailed>());
  });

  test('fails closed on valid JSON with no usable version', () async {
    final service = serviceFor('0.1.0', respondingWith(jsonEncode({'version': 'latest'})));
    expect(await service.check(inBackground: true), isA<UpdateFailed>());
  });

  test('fails closed when the network throws', () async {
    final service = serviceFor('0.1.0', MockClient((_) async => throw const _OfflineStub()));
    expect(await service.check(inBackground: true), isA<UpdateFailed>());
  });

  test('is unsupported when the running version cannot be read', () async {
    final service = serviceFor(null, respondingWith(manifest(version: '9.0.0')));
    expect(service.isSupported, isFalse);
    // And it refuses to compare rather than assuming everything is newer.
    expect(await service.check(inBackground: true), isA<UpdateFailed>());
  });
}

class _OfflineStub implements Exception {
  const _OfflineStub();
}
