import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'analytics_milestones.dart';
import 'analytics_service.dart';
import 'crash_reporter.dart';
import 'tracing_service.dart';

/// The telemetry override placeholders.
///
/// Each defaults to a disabled no-op instance so tests, the web and
/// unsupported platforms just work, and each is replaced in
/// `app/bootstrap.dart` once its backend is up. Plain [Provider]s rather than
/// generated ones — see `sharedPreferencesProvider` for why.

/// App-wide analytics entry point. Overridden with a live [AnalyticsService]
/// once Firebase has initialized.
final analyticsProvider = Provider<AnalyticsService>((ref) => const AnalyticsService.disabled());

/// App-wide OpenTelemetry tracing/metrics entry point (native platforms).
/// Overridden with the live OTel backend when configured.
final tracingProvider = Provider<TracingService>((ref) => const TracingService.disabled());

/// Crashlytics context + non-fatal error reporting (native platforms).
final crashReporterProvider = Provider<CrashReporter>((ref) => const CrashReporter.disabled());

/// Fire-once activation milestones (GA4 key events). Overridden with a
/// `SharedPreferences`-backed instance.
final milestonesProvider = Provider<Milestones>((ref) => const Milestones.disabled());
