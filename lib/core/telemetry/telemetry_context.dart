import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;

/// App version reported as an Analytics user property and an OpenTelemetry
/// resource attribute. Keep in sync with the `version:` in pubspec.yaml —
/// this can't just read it at runtime because pubspec fields aren't bundled
/// into the compiled app without an extra codegen step.
const appVersion = '0.0.1';

/// A coarse label for where the app is running (`web`, `macos`, `windows`,
/// …), attached to both Analytics events and OpenTelemetry spans so usage
/// can be sliced by platform.
String get runPlatform => kIsWeb ? 'web' : defaultTargetPlatform.name;
