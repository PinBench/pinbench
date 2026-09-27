/// The app's test harness now lives with the theme it mounts.
///
/// Re-exported rather than moved outright so the ~20 tests that pump through
/// `appTestApp` keep one short relative import, and so this file stays the
/// obvious place to add app-specific harness bits that have no business in a
/// UI-kit package.
library;

export 'package:pinbench_ui/theme/testing.dart' show appTestApp;
