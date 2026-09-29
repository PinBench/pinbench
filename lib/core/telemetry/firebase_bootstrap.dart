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
class const FirebaseTelemetry({
  required final AnalyticsService analytics,
  required final CrashReporter crashReporter,
  required final TelemetryControl control,

  /// Whether `Firebase.initializeApp` ran, which Remote Config depends on.
  required final bool initialized,
}) {
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
/// initialised and every handle is a no-op. With one, nothing is collected
/// unless [granted]: native builds start with collection off (see the
/// `*_COLLECTION_ENABLED` keys in `macos/Runner/Info.plist`), the Analytics and
/// Performance SDKs are not even created until the user agrees, and
/// [FirebaseTelemetry.control] switches everything when they answer or change
/// their mind. [onAnalyticsOn] runs each time analytics starts sending, to set
/// its user properties then rather than while it is off.
///
/// Best-effort throughout: a failure here returns disabled handles and the app
/// runs exactly as before. Call **after** [initAppLogger] so the existing
/// Talker error handler is chained ahead of Crashlytics.
Future<FirebaseTelemetry> initFirebaseTelemetry({
  required TelemetryConfig? config,
  required bool granted,
  required void Function(AnalyticsService analytics) onAnalyticsOn,
}) async {
  if (config == null || !TelemetrySupport.firebase) return FirebaseTelemetry.disabled;

  try {
    await Firebase.initializeApp(options: config.firebase);
  } catch (e) {
    talker.warning('Firebase telemetry disabled (init skipped): $e');
    return FirebaseTelemetry.disabled;
  }

  final control = _FirebaseTelemetryControl(config.privacyPolicyUrl, onAnalyticsOn);

  var crashReporter = const CrashReporter.disabled();
  if (TelemetrySupport.crashlytics) {
    crashReporter = _GatedCrashReporter(_wireCrashlytics(() => control.collecting), control);
  }

  control.applyConsent(granted: granted);

  return FirebaseTelemetry(
    analytics: control.analytics,
    crashReporter: crashReporter,
    control: control,
    initialized: true,
  );
}

/// Switches every Firebase SDK's collection on or off together.
///
/// Crash reports and performance traces are never sent from a debug build,
/// whatever the answer — they would be noise from the developer's machine.
class _FirebaseTelemetryControl(
  @override final String privacyPolicyUrl,
  final void Function(AnalyticsService analytics) _onAnalyticsOn,
) implements TelemetryControl {
  final _analyticsSlot = AnalyticsSlot();
  late final analytics = AnalyticsService.switchable(_analyticsSlot);

  /// The answer in force, or null before the first [applyConsent] (startup).
  bool? _granted;
  var _performanceStarted = false;

  /// Whether errors may be recorded for Crashlytics right now.
  bool get collecting => _granted ?? false;

  @override
  bool get available => true;

  @override
  void applyConsent({required bool granted}) {
    final before = _granted;
    _granted = granted;
    _analyticsConsent(granted);
    _crashlyticsConsent(granted, before: before);
    _performanceConsent(granted);
  }

  /// The SDK instance is created only once the user agrees: on the web,
  /// creating it is what starts collecting (page views), so an install that has
  /// not answered, or declined, never touches it.
  void _analyticsConsent(bool granted) {
    if (!TelemetrySupport.analytics) return;
    if (granted) {
      final instance = _analyticsSlot.instance ??= FirebaseAnalytics.instance;
      unawaited(instance.setAnalyticsCollectionEnabled(true).catchError((Object _) {}));
      analytics.setConsent(granted: true);
      _onAnalyticsOn(analytics);
    } else if (_analyticsSlot.instance case final instance?) {
      analytics.setConsent(granted: false);
      unawaited(instance.setAnalyticsCollectionEnabled(false).catchError((Object _) {}));
      _analyticsSlot.instance = null;
    }
  }

  /// Crash reports gathered without consent are deleted, never sent later. A
  /// report left from an earlier session *with* consent is kept — Crashlytics
  /// uploads a crash on the launch after it — which is why startup with consent
  /// deletes nothing.
  void _crashlyticsConsent(bool granted, {required bool? before}) {
    if (!TelemetrySupport.crashlytics) return;
    final crashlytics = FirebaseCrashlytics.instance;
    final send = granted && !kDebugMode;
    final discardBacklog = !granted || before == false;
    unawaited(
      () async {
        if (!send) await crashlytics.setCrashlyticsCollectionEnabled(false);
        if (discardBacklog) await crashlytics.deleteUnsentReports();
        if (send) await crashlytics.setCrashlyticsCollectionEnabled(true);
      }().catchError((Object _) {}),
    );
  }

  /// Like analytics, the SDK is only touched once there is something to turn on
  /// — or off again after it was on.
  void _performanceConsent(bool granted) {
    if (!TelemetrySupport.performance) return;
    final on = granted && !kDebugMode;
    if (!on && !_performanceStarted) return;
    _performanceStarted = true;
    unawaited(
      FirebasePerformance.instance.setPerformanceCollectionEnabled(on).catchError((Object _) {}),
    );
  }
}

/// A [CrashReporter] that records nothing while the user has not agreed.
class _GatedCrashReporter(final CrashReporter _inner, final _FirebaseTelemetryControl _control)
    implements CrashReporter {
  @override
  void setKey(String key, Object value) {
    if (_control.collecting) _inner.setKey(key, value);
  }

  @override
  void log(String message) {
    if (_control.collecting) _inner.log(message);
  }

  @override
  void recordError(Object error, StackTrace? stack, {bool fatal = false}) {
    if (_control.collecting) _inner.recordError(error, stack, fatal: fatal);
  }
}

/// Routes uncaught Flutter-framework and async errors to Crashlytics — only
/// while [collecting] — while preserving the existing Talker logging (chained,
/// not replaced), and returns a [CrashReporter] for custom keys + non-fatal
/// errors.
CrashReporter _wireCrashlytics(bool Function() collecting) {
  final crashlytics = FirebaseCrashlytics.instance;

  final previousOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    previousOnError?.call(details); // keep Talker's handler
    if (collecting()) unawaited(crashlytics.recordFlutterFatalError(details));
  };

  // Errors outside the Flutter callstack (e.g. unawaited futures).
  PlatformDispatcher.instance.onError = (error, stack) {
    if (collecting()) unawaited(crashlytics.recordError(error, stack, fatal: true));
    return true;
  };

  return FirebaseCrashReporter(crashlytics);
}
