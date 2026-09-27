import 'package:flutter/foundation.dart' show immutable;

/// A released version, as `major.minor.patch` with an optional pre-release
/// tag — the subset of semver the release tags actually use.
///
/// This exists because the Linux path has to answer "is the manifest newer
/// than me?" in Dart. macOS and Windows never reach it: Sparkle and
/// WinSparkle do their own comparison natively against `CFBundleVersion` /
/// the Windows file version, and disagreeing with them would be worse than
/// not having an opinion.
@immutable
class ReleaseVersion implements Comparable<ReleaseVersion> {
  const ReleaseVersion(this.major, this.minor, this.patch, {this.preRelease});

  /// Parses `1.2.3`, `v1.2.3`, `1.2.3-beta.1`, or `1.2.3+7`.
  ///
  /// Returns null rather than throwing: the two inputs are a downloaded
  /// manifest and a value read out of the app bundle, and neither is worth
  /// crashing an update check over. A null on either side is treated as
  /// "cannot tell", which reads as "no update" — a version check that fails
  /// open would nag every launch.
  ///
  /// The build metadata after `+` is dropped, per semver: it is Flutter's
  /// build number, which is a monotonic counter for the OS rather than a
  /// thing users compare.
  static ReleaseVersion? tryParse(String? input) {
    if (input == null) return null;
    var text = input.trim();
    if (text.startsWith('v') || text.startsWith('V')) text = text.substring(1);
    final plus = text.indexOf('+');
    if (plus != -1) text = text.substring(0, plus);

    String? preRelease;
    final dash = text.indexOf('-');
    if (dash != -1) {
      preRelease = text.substring(dash + 1);
      text = text.substring(0, dash);
      if (preRelease.isEmpty) return null;
    }

    final parts = text.split('.');
    if (parts.isEmpty || parts.length > 3) return null;
    final numbers = <int>[];
    for (final part in parts) {
      final value = int.tryParse(part);
      if (value == null || value < 0) return null;
      numbers.add(value);
    }
    return ReleaseVersion(
      numbers[0],
      numbers.length > 1 ? numbers[1] : 0,
      numbers.length > 2 ? numbers[2] : 0,
      preRelease: preRelease,
    );
  }

  final int major;
  final int minor;
  final int patch;

  /// The bit after `-`, or null for a normal release. Compared as a whole
  /// string rather than by semver's dot-separated identifier rules — the tags
  /// this project cuts are `-beta.1`-shaped, where the two agree, and the
  /// full rule is a lot of code to make `-alpha.10` sort after `-alpha.9` in
  /// a comparison that only ever gates a "there is a newer build" banner.
  final String? preRelease;

  @override
  int compareTo(ReleaseVersion other) {
    for (final (mine, theirs) in [
      (major, other.major),
      (minor, other.minor),
      (patch, other.patch),
    ]) {
      final byNumber = mine.compareTo(theirs);
      if (byNumber != 0) return byNumber;
    }

    // A pre-release precedes the release it leads to: 1.2.0-beta.1 < 1.2.0.
    return switch ((preRelease, other.preRelease)) {
      (null, null) => 0,
      (null, _) => 1,
      (_, null) => -1,
      (final a?, final b?) => a.compareTo(b).sign,
    };
  }

  bool operator >(ReleaseVersion other) => compareTo(other) > 0;

  bool operator <(ReleaseVersion other) => compareTo(other) < 0;

  bool operator >=(ReleaseVersion other) => compareTo(other) >= 0;

  bool operator <=(ReleaseVersion other) => compareTo(other) <= 0;

  @override
  bool operator ==(Object other) =>
      other is ReleaseVersion &&
      other.major == major &&
      other.minor == minor &&
      other.patch == patch &&
      other.preRelease == preRelease;

  @override
  int get hashCode => Object.hash(major, minor, patch, preRelease);

  @override
  String toString() => '$major.$minor.$patch${preRelease == null ? '' : '-$preRelease'}';
}
