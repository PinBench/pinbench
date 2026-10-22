import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;

import 'package:package_info_plus/package_info_plus.dart';

/// The running build's version, reported as an Analytics user property and an
/// OpenTelemetry resource attribute.
///
/// Read from the build itself rather than kept as a constant: release builds
/// stamp it with `--build-name`, and a constant here went stale at `0.0.1`
/// while the app moved on. `unknown` where the platform cannot say (a plain
/// `flutter test`).
Future<String> readAppVersion() async {
  try {
    return (await PackageInfo.fromPlatform()).version;
  } catch (_) {
    return 'unknown';
  }
}

/// A coarse label for where the app is running (`web`, `macos`, `windows`,
/// …), attached to both Analytics events and OpenTelemetry spans so usage
/// can be sliced by platform.
String get runPlatform => kIsWeb ? 'web' : defaultTargetPlatform.name;
