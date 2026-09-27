import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_performance/firebase_performance.dart';

import '../../firebase_options.dart';
import '../utils/logger.dart';
import 'analytics_service.dart';
import 'crash_reporter.dart';
import 'telemetry_support.dart';

/// The Firebase-backed telemetry the app talks to: analytics events + crash
/// reporting. Both fall back to no-op instances where Firebase is unavailable.
class FirebaseTelemetry {
  const FirebaseTelemetry({required this.analytics, required this.crashReporter});

  final AnalyticsService analytics;
  final CrashReporter crashReporter;

  static const disabled = FirebaseTelemetry(
    analytics: AnalyticsService.disabled(),
    crashReporter: CrashReporter.disabled(),
  );
}

/// Initializes Firebase and wires up Crashlytics + Performance Monitoring for
/// the platforms that support them, returning the [FirebaseTelemetry] handles.
///
/// Everything here is best-effort: on an unsupported platform, or before
/// `flutterfire configure` has generated real options, this returns disabled
/// handles and the app runs exactly as before. Call **after** [initAppLogger] so
/// the existing Talker error handler is chained ahead of Crashlytics.
Future<FirebaseTelemetry> initFirebaseTelemetry() async {
  if (!TelemetrySupport.firebase) return FirebaseTelemetry.disabled;

  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (e) {
    // Missing/placeholder options (flutterfire not run) or unsupported host.
    talker.warning('Firebase telemetry disabled (init skipped): $e');
    return FirebaseTelemetry.disabled;
  }

  var crashReporter = const CrashReporter.disabled();
  if (TelemetrySupport.crashlytics) crashReporter = _wireCrashlytics();

  if (TelemetrySupport.performance) {
    unawaited(
      FirebasePerformance.instance
          .setPerformanceCollectionEnabled(!kDebugMode)
          .catchError((Object _) {}),
    );
  }

  var analytics = const AnalyticsService.disabled();
  if (TelemetrySupport.analytics) {
    final firebaseAnalytics = FirebaseAnalytics.instance;
    unawaited(firebaseAnalytics.setAnalyticsCollectionEnabled(true).catchError((Object _) {}));
    analytics = AnalyticsService(firebaseAnalytics);
  }

  return FirebaseTelemetry(analytics: analytics, crashReporter: crashReporter);
}

/// Routes uncaught Flutter-framework and async errors to Crashlytics while
/// preserving the existing Talker logging (chained, not replaced), and returns a
/// [CrashReporter] for custom keys + non-fatal errors.
CrashReporter _wireCrashlytics() {
  final crashlytics = FirebaseCrashlytics.instance;
  // Don't upload crashes from local debug runs.
  unawaited(crashlytics.setCrashlyticsCollectionEnabled(!kDebugMode).catchError((Object _) {}));

  final previousOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    previousOnError?.call(details); // keep Talker's handler
    unawaited(crashlytics.recordFlutterFatalError(details));
  };

  // Errors outside the Flutter callstack (e.g. unawaited futures).
  PlatformDispatcher.instance.onError = (error, stack) {
    unawaited(crashlytics.recordError(error, stack, fatal: true));
    return true;
  };

  return FirebaseCrashReporter(crashlytics);
}
