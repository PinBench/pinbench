import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart' show BrowserContextMenu;

import 'package:multiview_desktop/multiview_desktop.dart';
import 'package:pinbench_ui/theme/app_icons.dart';

import 'app/bootstrap.dart';
import 'core/routing/url_strategy.dart';
import 'core/remote_config/remote_config_bootstrap.dart';
import 'core/services/feedback_service.dart';
import 'core/telemetry/analytics_milestones.dart';
import 'core/telemetry/telemetry_consent.dart';
import 'core/utils/logger.dart';
import 'shell/window.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Resolve the icon library's module before anything builds a widget; see
  // AppIcons.resolveModule for why this is load-bearing on debug web.
  AppIcons.resolveModule();
  initAppLogger();
  installSimulationLogSink();
  installCloudLogSink();

  // Telemetry + auth bootstrap (see app/bootstrap.dart) — each step is
  // best-effort and degrades to a disabled/no-op handle on failure.
  final edition = loadEdition();
  final storage = await setupLocalStorage();
  final consent = readTelemetryConsent(storage.sharedPreferences);
  final granted = consent == TelemetryConsent.granted;
  final firebase = await setupFirebase(config: edition?.telemetry, consent: consent);
  // Independent of one another, so together: startup waits for the slowest
  // (a Remote Config fetch, a cloud session restore), not for the sum.
  final (featureFlags, tracingSetup, editionSetup) = await (
    setupRemoteConfig(firebaseReady: firebase.initialized, granted: granted),
    setupTracing(granted: granted),
    setupEdition(edition),
  ).wait;
  final tracing = tracingSetup.tracing;
  FeedbackService.onFeedbackSent = firebase.analytics.feedbackSent;

  // Fire-once activation events (GA4 key events) need persistence + analytics.
  final milestones = Milestones(storage.sharedPreferences, firebase.analytics);

  final globalScope = buildGlobalScope(
    sharedPreferences: storage.sharedPreferences,
    appTempDir: storage.appTempDir,
    firebase: firebase,
    tracing: tracing,
    telemetryControl: CombinedTelemetryControl([firebase.control, ?tracingSetup.control]),
    milestones: milestones,
    cloud: editionSetup.cloud,
    panel: editionSetup.panel,
    featureFlags: featureFlags,
  );

  // The web preview has no native multi-window support: `multiview_desktop`
  // calls `Platform.operatingSystem` at startup, which is unsupported on the
  // web and crashes before the first frame. Bootstrap a single root window with
  // a plain `runApp` instead, reusing the same provider scope and overrides.
  if (kIsWeb) {
    // Clean, path-based URLs (e.g. `/t/blink`, no `#`) for browser navigation.
    configurePathUrlStrategy();
    // The canvas, the file tree and the editor tabs all open their own menu on
    // right-click. Without this the browser's menu opens on top of ours, and
    // the one you get is decided by the browser rather than by the app.
    //
    // It is a whole-document switch, so it also takes away the browser's
    // cut/copy/paste menu inside text fields. The app's own Edit menu and the
    // usual keystrokes still do all of it.
    await BrowserContextMenu.disableContextMenu();
    runApp(globalScope(const Window(windowId: 0)));
    return;
  }

  runMultiApp(
    config: buildMultiAppConfig(),
    globalScope: globalScope,
    home: (context, id) => Window(windowId: id),
  );
}
