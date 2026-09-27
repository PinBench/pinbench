import 'package:flutter/foundation.dart' show PlatformDispatcher, kIsWeb;
import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:multiview_desktop/multiview_desktop.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:talker_riverpod_logger/talker_riverpod_logger_observer.dart';
import 'package:talker_riverpod_logger/talker_riverpod_logger_settings.dart';
import 'package:pinbench_sim/core/sim_log.dart';
import 'package:pinbench_cloud/cloud_backend.dart';
import 'package:pinbench_cloud/cloud_log.dart';
import 'package:pinbench_cloud/auth/auth_service.dart';
import 'package:pinbench_edition/pinbench_edition.dart';
import 'package:pinbench_edition_api/side_panel.dart';
import 'package:pinbench_entitlements/pinbench_entitlements.dart';
import 'package:pinbench_ui/ui/app_page_route.dart';

import '../core/auth/auth_provider.dart';
import '../core/cloud/project_providers.dart';
import '../core/edition/edition_provider.dart';
import '../core/remote_config/feature_flags.dart';
import '../core/remote_config/feature_flags_provider.dart';
import '../core/telemetry/analytics_milestones.dart';
import '../core/telemetry/firebase_bootstrap.dart';
import '../core/telemetry/otel_backend.dart';
import '../core/telemetry/otel_config.dart';
import '../core/telemetry/telemetry_context.dart';
import '../core/telemetry/telemetry_listener.dart';
import '../core/telemetry/telemetry_providers.dart';
import '../core/telemetry/tracing_service.dart';
import '../core/utils/logger.dart';
import '../core/utils/shared_preferences_provider.dart';
import '../features/workspace/providers/recent_workspaces_provider.dart';
import '../shell/menus/global_menu_wrapper.dart';
import 'canvas_sync_bindings.dart';
import 'chrome_bindings.dart';
import 'edition_host_bindings.dart';
import 'simulation/simulation_bindings.dart';

/// Everything `main()` needs to bring up before the first frame: telemetry,
/// auth, and local storage. Each step is independently best-effort — a
/// failure degrades to a disabled/no-op handle rather than blocking startup —
/// so this file has no single "if anything fails, abort" path.

/// Brings up Firebase (Crashlytics/Performance/Analytics) where supported.
const _log = AppLogger('app.bootstrap');

/// Points the simulation engine's log port at the app's logger.
///
/// Lives here rather than beside `initAppLogger` because the engine is a
/// feature and `core/` may not depend on one — `layering_test.dart` fails the
/// build if it does, which is how this ended up in the right place.
///
/// Only the UI isolate gets this. The engine also runs in a background
/// isolate where statics do not cross, and there `SimLog` falls back to
/// `FlutterError.reportError` for errors and drops the rest — a trace nobody
/// can read is not worth an isolate message.
void installSimulationLogSink() {
  SimLog.sink = (record) {
    final message = '[${record.category}] ${record.message}';
    switch (record.level) {
      case SimLogLevel.trace:
        talker.verbose(message);
      case SimLogLevel.debug:
        talker.debug(message);
      case SimLogLevel.info:
        talker.info(message);
      case SimLogLevel.warning:
        talker.warning(message);
      case SimLogLevel.error:
        talker.error(message, record.error, foldStackTrace(record.stackTrace));
    }
  };
}

/// Points the cloud backend's log port at the app's logger.
///
/// Same seam as [installSimulationLogSink] and installed beside it, for the
/// same reason: `package:pinbench_cloud` is plain Dart around an SDK and has no
/// business carrying a logging framework. Errors reach Crashlytics either way
/// — with no sink they fall back to `FlutterError.reportError` — but only a
/// sink gets the info and warning lines into the log view.
void installCloudLogSink() {
  CloudLog.sink = (record) {
    final message = '[${record.category}] ${record.message}';
    switch (record.level) {
      case CloudLogLevel.info:
        talker.info(message);
      case CloudLogLevel.warning:
        talker.warning(message);
      case CloudLogLevel.error:
        talker.error(message, record.error, foldStackTrace(record.stackTrace));
    }
  };
}

/// Must run after `initAppLogger()` so the Talker error handler is chained
/// ahead of Crashlytics; no-ops on unsupported platforms and returns disabled
/// handles, so the rest of startup is unaffected.
Future<FirebaseTelemetry> setupFirebase() async {
  final firebase = await initFirebaseTelemetry();
  firebase.analytics
    ..setAppContext(platform: runPlatform)
    ..setAppVersion(appVersion)
    // Preserves current behaviour; a consent banner should drive this to
    // `granted: false` until the user opts in (esp. on the EU web build).
    ..setConsent(granted: true);
  return firebase;
}

/// Brings up OpenTelemetry (native only — its OTLP exporter needs `dart:io`).
/// This is the cross-platform tracing/metrics layer that also covers
/// Windows/Linux, where Firebase has no support. Dormant unless the Grafana
/// Cloud OTLP endpoint is supplied via `--dart-define` (see
/// the telemetry setup); chains its error handlers after Firebase's so both
/// reporters see every error. No-op on the web.
Future<TracingService> setupTracing() async {
  final tracing = await initOpenTelemetry(OtelConfig.fromEnvironment(platform: runPlatform));
  if (tracing.enabled) _chainTracingErrorHandlers(tracing);
  return tracing;
}

/// Brings up the edition this build runs as — see `package:pinbench_edition`.
///
/// A build from source has none: the free tier, no cloud backend and no side
/// panel, i.e. the full local app. A hosted build's edition registers its
/// entitlements, connects its cloud backend and hands over its side panel.
Future<({CloudSession cloud, SidePanel? panel})> setupEdition() async {
  final edition = createEdition();
  if (edition?.gateway case final gateway?) Pro.register(gateway);
  return (cloud: await _connectCloud(edition?.cloud), panel: edition?.panel);
}

/// Connects [backend] for the account and cloud-project features. The app
/// works offline without signing in, so no backend — or a failure here —
/// degrades to [DisabledAuthService] rather than stopping startup.
///
/// Async because the session has to be restored before the first frame. On web
/// sign-in can redirect the whole page, so the app that resumes afterwards is a
/// fresh instance; without awaiting the restore here, a signed-in user would
/// see the signed-out UI until something else happened to re-check.
Future<CloudSession> _connectCloud(CloudBackend? backend) async {
  const CloudSession offline = (auth: DisabledAuthService(), projects: null);
  if (backend == null) return offline;
  try {
    return await backend.connect();
  } catch (e, st) {
    _log.error('Cloud backend init failed; continuing signed out', error: e, stackTrace: st);
    return offline;
  }
}

/// Brings up local persistence: the app's OS temp directory and
/// [SharedPreferences] (used for settings and fire-once milestones).
Future<({String? appTempDir, SharedPreferences sharedPreferences})> setupLocalStorage() async {
  // path_provider has no web implementation; the web preview has no OS temp
  // directory, so skip it there and leave the app temp dir unset.
  final appTempDir = kIsWeb ? null : (await getTemporaryDirectory()).path;
  final sharedPreferences = await SharedPreferences.getInstance();
  return (appTempDir: appTempDir, sharedPreferences: sharedPreferences);
}

/// Builds the root [ProviderScope] wrapper shared by every window: overrides
/// every telemetry/auth/storage provider-placeholder with its live instance,
/// and wraps the window in the global menu + telemetry listener.
///
/// Returns [ProviderScope] rather than [Widget] on purpose. `runApp` is handed
/// the result of calling this, and `missing_provider_scope` checks the static
/// type of what `runApp` is given — a `Widget` tells it nothing, so it reports
/// an app with no scope at all. The narrower type is also simply truer, and
/// costs nothing: a function returning `ProviderScope` is a subtype of one
/// returning `Widget`, so `runMultiApp(globalScope:)` still accepts it.
ProviderScope Function(Widget child) buildGlobalScope({
  required SharedPreferences sharedPreferences,
  required String? appTempDir,
  required FirebaseTelemetry firebase,
  required TracingService tracing,
  required Milestones milestones,
  required CloudSession cloud,
  required SidePanel? panel,
  required FeatureFlags featureFlags,
}) =>
    (child) => ProviderScope(
      child: GlobalMenuWrapper(child: TelemetryListener(child: child)),
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sharedPreferences),
        appTempDirProvider.overrideWithValue(appTempDir),
        analyticsProvider.overrideWithValue(firebase.analytics),
        crashReporterProvider.overrideWithValue(firebase.crashReporter),
        milestonesProvider.overrideWithValue(milestones),
        tracingProvider.overrideWithValue(tracing),
        authServiceProvider.overrideWithValue(cloud.auth),
        projectRepositoryProvider.overrideWithValue(cloud.projects),
        editionPanelProvider.overrideWithValue(panel),
        featureFlagsProvider.overrideWithValue(featureFlags),
        // What the simulation runs on, runs, and reports to. See
        // `app/simulation/` — the ports have no default binding.
        ...simulationBindings,
        // What a feature may ask the chrome to do. Same deal: no default.
        ...chromeBindings,
        // What the `.cdl` sync reads and writes. Likewise.
        ...canvasSyncBindings,
        // What an edition's side panel can see of the app, and ask it to do.
        ...editionHostBindings,
      ],
      observers: [
        TalkerRiverpodObserver(
          talker: talker,
          settings: const TalkerRiverpodLoggerSettings(printStateFullData: false),
        ),
      ],
    );

/// Desktop multi-window configuration: a frameless window (custom title bar)
/// whose routes use the standard Material page transition.
MultiAppConfig buildMultiAppConfig() => MultiAppConfig(
  globalWindowOptions: WindowOptions(
    windowButtonVisibility: true,
    titleBarStyle: TitleBarStyle.hidden,
    shellOverrides: ViewShellOverrides(
      // Also set on the app's own `MaterialApp`, and set here as well because
      // the shell keeps its own copy of that flag: it snapshots whichever app
      // it finds in the view tree and falls back to showing the banner. Only
      // non-null fields of a patch override, so this settles that one flag and
      // leaves the snapshot's theme and locales alone.
      appearance: const AppShellPatch(debugShowCheckedModeBanner: false),
      pageRouteBuilder: <T>(settings, builder) =>
          AppPageRoute<T>(settings: settings, builder: builder),
    ),
  ),
);

/// Forwards uncaught Flutter-framework and async errors to OpenTelemetry,
/// chained after any existing handler (Talker, and Crashlytics on supported
/// platforms) rather than replacing it. This is how Windows/Linux — where
/// Crashlytics doesn't exist — still get error reporting.
void _chainTracingErrorHandlers(TracingService tracing) {
  final previousOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    previousOnError?.call(details);
    tracing.recordError(details.exception, details.stack, fatal: true);
  };

  final previousPlatformOnError = PlatformDispatcher.instance.onError;
  PlatformDispatcher.instance.onError = (error, stack) {
    tracing.recordError(error, stack, fatal: true);
    return previousPlatformOnError?.call(error, stack) ?? true;
  };
}
