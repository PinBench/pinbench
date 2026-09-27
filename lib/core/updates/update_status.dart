import 'release_version.dart';

/// Where an update check has got to.
///
/// One type for both back ends even though they reach the states very
/// differently — Sparkle drives them from native callbacks, Linux from an
/// HTTP round trip — because the UI has no business knowing which it is
/// talking to. The only visible difference is [UpdateAvailable.installable],
/// which decides whether the banner says "Restart to update" or "Download".
sealed class UpdateStatus {
  const UpdateStatus();
}

/// Nothing has been checked yet, or the last check has been dismissed.
class UpdateIdle extends UpdateStatus {
  const UpdateIdle();
}

/// A check is in flight.
class UpdateChecking extends UpdateStatus {
  const UpdateChecking();
}

/// The running build is the newest one. [checkedAt] is what lets Settings say
/// "checked 3 minutes ago" rather than leaving a manual check looking inert
/// when the answer is the same as last time.
class UpdateUpToDate extends UpdateStatus {
  const UpdateUpToDate(this.checkedAt);

  final DateTime checkedAt;
}

/// There is a newer release.
class UpdateAvailable extends UpdateStatus {
  const UpdateAvailable({
    required this.version,
    required this.installable,
    this.notesUrl,
    this.downloadUrl,
  });

  /// Null when the platform found an update but described its version in a
  /// way [ReleaseVersion] could not read. Sparkle still installs it correctly
  /// — only the label is lost, so the UI says "a new version" rather than
  /// inventing a number.
  final ReleaseVersion? version;

  /// Whether the platform's updater can install this itself.
  ///
  /// True under Sparkle/WinSparkle, which download and swap the app in place.
  /// False on Linux, where the only honest offer is a link — see
  /// `UpdateConfig.linuxManifestUrl` for why the app does not try to replace
  /// its own files there.
  final bool installable;

  final String? notesUrl;

  /// Where a non-[installable] update sends the user. Null falls back to the
  /// download page.
  final String? downloadUrl;
}

/// The check could not complete — offline, a 500, a malformed feed.
///
/// Surfaced but never modal: a failed update check is not an event the user
/// asked for unless they pressed the button, and `UpdateController` only
/// shows this when they did.
class UpdateFailed extends UpdateStatus {
  const UpdateFailed(this.message);

  final String message;
}
