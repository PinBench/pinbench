import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_performance/firebase_performance.dart';

import 'package:pinbench_edition_api/telemetry.dart';

import '../utils/logger.dart';
import 'analytics_service.dart';
import 'crash_reporter.dart';
import 'telemetry_consent.dart';
import 'telemetry_support.dart';

/// The Firebase-backed telemetry the app talks to: analytics events + crash
/// reporting, and the [control] the consent UI switches collection with. All
/// fall back to no-op instances where there is no telemetry.
class FirebaseTelemetry {
  const FirebaseTelemetry({
    required this.analytics,
    required this.crashReporter,
    required this.control,
    required this.initialized,
  });

  final AnalyticsService analytics;
  final CrashReporter crashReporter;
  final TelemetryControl control;

  /// Whether `Firebase.initializeApp` ran, which Remote Config depends on.
  final bool initialized;

  static const disabled = FirebaseTelemetry(
    analytics: AnalyticsService.disabled(),
    crashReporter: CrashReporter.disabled(),
    control: NoTelemetry(),
    initialized: false,
  );
}

/// Initializes Firebase for [config] and wires up Crashlytics, Performance
/// Monitoring and Analytics on the platforms that support them.
///
/// No [config] — a build from source — means no telemetry: Firebase is never
/// initialised and every handle is a no-op. With one, collection starts only if
/// [granted]; [FirebaseTelemetry.control] turns it on or off later, when the
/// user answers or changes their mind.
///
/// Best-effort throughout: a failure here returns disabled handles and the app
/// runs exactly as before. Call **after** [initAppLogger] so the existing
/// Talker error handler is chained ahead of Crashlytics.
Future<FirebaseTelemetry> initFirebaseTelemetry({
  required TelemetryConfig? config,
  required bool granted,
}) async {
  if (config == null || !TelemetrySupport.firebase) return FirebaseTelemetry.disabled;

  try {
    await Firebase.initializeApp(options: config.firebase);
  } catch (e) {
    talker.warning('Firebase telemetry disabled (init skipped): $e');
    return FirebaseTelemetry.disabled;
  }

  var crashReporter = const CrashReporter.disabled();
  if (TelemetrySupport.crashlytics) crashReporter = _wireCrashlytics();

  var analytics = const AnalyticsService.disabled();
  if (TelemetrySupport.analytics) analytics = AnalyticsService(FirebaseAnalytics.instance);

  final control = _FirebaseTelemetryControl(config.privacyPolicyUrl, analytics)
    ..applyConsent(granted: granted);

  return FirebaseTelemetry(
    analytics: analytics,
    crashReporter: crashReporter,
    control: control,
    initialized: true,
  );
}

/// Switches every Firebase SDK's collection on or off together.
///
/// Crash reports and performance traces are never sent from a debug build,
/// whatever the answer — they would be noise from the developer's machine.
class _FirebaseTelemetryControl implements TelemetryControl {
  _FirebaseTelemetryControl(this.privacyPolicyUrl, this._analytics);

  @override
  final String privacyPolicyUrl;

  final AnalyticsService _analytics;

  @override
  bool get available => true;

  @override
  void applyConsent({required bool granted}) {
    if (TelemetrySupport.analytics) {
      unawaited(
        FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(granted).catchError((Object _) {}),
      );
      _analytics.setConsent(granted: granted);
    }
    if (TelemetrySupport.crashlytics) {
      unawaited(
        FirebaseCrashlytics.instance
            .setCrashlyticsCollectionEnabled(granted && !kDebugMode)
            .catchError((Object _) {}),
      );
    }
    if (TelemetrySupport.performance) {
      unawaited(
        FirebasePerformance.instance
            .setPerformanceCollectionEnabled(granted && !kDebugMode)
            .catchError((Object _) {}),
      );
    }
  }
}

/// Routes uncaught Flutter-framework and async errors to Crashlytics while
/// preserving the existing Talker logging (chained, not replaced), and returns a
/// [CrashReporter] for custom keys + non-fatal errors.
CrashReporter _wireCrashlytics() {
  // Whether anything is sent is the consent control's decision (see
  // [_FirebaseTelemetryControl]); this only routes errors to the SDK.
  final crashlytics = FirebaseCrashlytics.instance;

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
