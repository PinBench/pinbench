import 'release_version.dart';

/// The `latest.json` the release workflow publishes alongside the binaries.
///
/// Deliberately smaller than the appcast: the only consumer is the Linux
/// notify-only check, which needs a version to compare and a page to send the
/// user to. Checksums and asset URLs live in the manifest too, but for the
/// download page and for anyone scripting an install — the app never fetches
/// a binary itself on Linux.
///
/// Shape:
/// ```json
/// {
///   "version": "0.3.0",
///   "publishedAt": "2026-08-13T00:00:00Z",
///   "notesUrl": "https://github.com/…/releases/tag/v0.3.0",
///   "assets": {
///     "linux": { "url": "…AppImage", "sha256": "…", "size": 91234567 }
///   }
/// }
/// ```
class const ReleaseManifest({
  required final ReleaseVersion version,

  /// The release notes page. Null is survivable — the update banner just
  /// links to the download page instead.
  required final String? notesUrl,
  final DateTime? publishedAt,

  /// Per-platform downloads, keyed `macos` / `windows` / `linux`.
  final Map<String, ReleaseAsset> assets = const {},
}) {
  /// Reads a decoded `latest.json`, or returns null if it is not one.
  ///
  /// Every field is checked rather than cast: this is parsing a document
  /// fetched over the network into a type, and the failure mode of a bad cast
  /// here is an exception on a background timer that nobody sees.
  static ReleaseManifest? fromJson(Object? json) {
    if (json is! Map) return null;
    final version = ReleaseVersion.tryParse(json['version'] as String?);
    if (version == null) return null;

    final assets = <String, ReleaseAsset>{};
    final rawAssets = json['assets'];
    if (rawAssets is Map) {
      for (final entry in rawAssets.entries) {
        final asset = ReleaseAsset.fromJson(entry.value);
        if (asset != null) assets['${entry.key}'] = asset;
      }
    }

    return ReleaseManifest(
      version: version,
      notesUrl: json['notesUrl'] as String?,
      publishedAt: DateTime.tryParse('${json['publishedAt']}'),
      assets: assets,
    );
  }
}

/// One downloadable file in a [ReleaseManifest].
class const ReleaseAsset({
  required final String url,

  /// Hex SHA-256, so a download can be verified by hand against what the
  /// download page prints. Not verified in-app: the app never downloads it.
  final String? sha256,
  final int? size,
}) {
  static ReleaseAsset? fromJson(Object? json) {
    if (json is! Map) return null;
    final url = json['url'];
    if (url is! String || url.isEmpty) return null;
    return ReleaseAsset(url: url, sha256: json['sha256'] as String?, size: json['size'] as int?);
  }
}
