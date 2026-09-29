import 'dart:async';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';

/// Adds context to crash reports and records non-fatal errors.
///
/// Crashlytics only exists on macOS/mobile; on the web and unsupported
/// platforms this is a no-op (see [CrashReporter.disabled]). Obtain via
/// `crashReporterProvider`.
abstract interface class CrashReporter {
  /// A no-op instance used as the provider default and where Crashlytics is
  /// unavailable.
  const factory disabled() = _DisabledCrashReporter;

  /// Attaches a custom key/value to subsequent crash reports (e.g. the current
  /// simulation state or active file type), so a crash says *what the user was
  /// doing*.
  void setKey(String key, Object value);

  /// Adds a breadcrumb log line included in the next crash report.
  void log(String message);

  /// Records a caught (non-fatal by default) error so it's visible in
  /// Crashlytics even though it didn't crash the app.
  void recordError(Object error, StackTrace? stack, {bool fatal});
}

class const _DisabledCrashReporter() implements CrashReporter {
  @override
  void setKey(String key, Object value) {}

  @override
  void log(String message) {}

  @override
  void recordError(Object error, StackTrace? stack, {bool fatal = false}) {}
}

/// [CrashReporter] backed by [FirebaseCrashlytics]. All calls are fire-and-forget
/// and swallow errors so telemetry never breaks the app.
class FirebaseCrashReporter(final FirebaseCrashlytics _crashlytics) implements CrashReporter {
  @override
  void setKey(String key, Object value) =>
      unawaited(_crashlytics.setCustomKey(key, value).catchError((Object _) {}));

  @override
  void log(String message) => unawaited(_crashlytics.log(message).catchError((Object _) {}));

  @override
  void recordError(Object error, StackTrace? stack, {bool fatal = false}) =>
      unawaited(_crashlytics.recordError(error, stack, fatal: fatal).catchError((Object _) {}));
}
