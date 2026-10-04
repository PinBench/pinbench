import 'package:flutter/foundation.dart';

/// Where a build looks for its successor, and where a human goes to buy one.
///
/// Every value is a public address rather than a secret, but they all move
/// with the release infrastructure (a repo rename, a custom domain), so they
/// are `--dart-define`-overridable the same way `SHARE_LINK_ORIGIN` and the
/// compile-service URL are. The defaults are what a plain `flutter build`
/// should produce.
abstract final class UpdateConfig {
  /// Root of the "newest release" asset URLs.
  ///
  /// GitHub serves `releases/latest/download/<name>` as a permanent redirect
  /// to whatever the newest non-prerelease tag published under that name,
  /// which is exactly the stable feed URL Sparkle wants — no extra hosting,
  /// and a shipped binary never has to be told about a tag that did not
  /// exist when it was built.
  // Build-time config, not a secret — it is the public address of the repo.
  // ignore: do_not_use_environment
  static const releasesBaseUrl = String.fromEnvironment(
    'UPDATE_RELEASES_BASE_URL',
    defaultValue: 'https://github.com/PinBench/pinbench/releases/latest/download',
  );

  /// The pay-what-you-want download page — the one place that explains the
  /// signed builds, takes the payment, and also tells you how to build the
  /// thing yourself for nothing.
  // Build-time config, not a secret — it is the public address of the site.
  // ignore: do_not_use_environment
  static const downloadPageUrl = String.fromEnvironment(
    'DOWNLOAD_PAGE_URL',
    defaultValue: 'https://pinbench.web.app/download',
  );

  /// The changelog on the web, which the Release Notes tab's "View online"
  /// opens: every release's notes, where the tab shows the running one's.
  // Build-time config, not a secret — it is the public address of the repo.
  // ignore: do_not_use_environment
  static const changelogUrl = String.fromEnvironment(
    'CHANGELOG_URL',
    defaultValue: 'https://github.com/PinBench/pinbench/blob/main/CHANGELOG.md',
  );

  /// Seconds between Sparkle's own background checks. A day is Sparkle's
  /// default and its documented sweet spot: often enough that a security fix
  /// lands within a day, rare enough that it is never the reason the app
  /// feels busy at launch.
  static const scheduledCheckInterval = 86400;

  /// The Sparkle/WinSparkle appcast for [platform], or null where there is no
  /// Sparkle to feed — Linux and the web, which take [linuxManifestUrl] and
  /// nothing respectively.
  ///
  /// Two separate feeds rather than one with per-platform items: an appcast
  /// entry carries a single enclosure, so a shared feed would offer a macOS
  /// `.dmg` to a Windows install.
  static String? appcastUrlFor(TargetPlatform platform) => switch (platform) {
    TargetPlatform.macOS => '$releasesBaseUrl/appcast-macos.xml',
    TargetPlatform.windows => '$releasesBaseUrl/appcast-windows.xml',
    _ => null,
  };

  /// The plain-JSON version manifest the Linux build polls.
  ///
  /// Linux has no Sparkle equivalent worth adopting — the platform's answer
  /// is the distro's package manager, and the app cannot replace its own
  /// files inside an AppImage or a `/opt` tarball without asking for
  /// privileges no circuit simulator should hold. So Linux reads a manifest
  /// and says "0.3.0 is out", and the download page does the rest.
  static String get linuxManifestUrl => '$releasesBaseUrl/latest.json';
}
