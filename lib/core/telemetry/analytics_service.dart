import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';

import '../utils/logger.dart';

/// Thin wrapper over [FirebaseAnalytics] that logs the app's meaningful
/// interactions — navigation, feature usage, and button/menu actions.
///
/// When Firebase is unavailable (unsupported platform, or `flutterfire
/// configure` hasn't been run yet) [_analytics] is null and every method is a
/// safe no-op, so call sites never need their own guards. All logging is
/// fire-and-forget and swallows errors: telemetry must never break the app.
///
/// Event/parameter names follow Firebase Analytics limits (snake_case, event
/// name ≤ 40 chars, string values ≤ 100 chars). Parameter values must be
/// `String` or `num` (booleans are encoded as 0/1).
class AnalyticsService {
  const AnalyticsService(this._analytics);

  /// A disabled instance: every call is a no-op. Used as the provider default
  /// and whenever Firebase init is skipped or fails.
  const AnalyticsService.disabled() : _analytics = null;

  final FirebaseAnalytics? _analytics;

  bool get enabled => _analytics != null;

  // ── Generic primitives ─────────────────────────────────────────────────────

  /// Logs a custom event. [params] values must be `String` or `num`.
  void logEvent(String name, [Map<String, Object>? params]) {
    final analytics = _analytics;
    if (analytics == null) return;
    _guard(() => analytics.logEvent(name: name, parameters: params));
  }

  /// Logs a screen/route view. [screenName] must be a normalized name (e.g.
  /// `editor`, `canvas`, `welcome`) — never a file path (see [tabSwitched]).
  void logScreen(String screenName) {
    final analytics = _analytics;
    if (analytics == null) return;
    _guard(() => analytics.logScreenView(screenName: screenName));
  }

  /// Sets a user property for segmentation (persists across events for the
  /// install). [value] is truncated to 36 chars per Firebase limits.
  void setUserProperty(String name, String value) {
    final analytics = _analytics;
    if (analytics == null) return;
    final trimmed = value.length <= 36 ? value : value.substring(0, 36);
    _guard(() => analytics.setUserProperty(name: name, value: trimmed));
  }

  /// Records which app the user is running against (web vs desktop, etc.).
  void setAppContext({required String platform}) => setUserProperty('run_platform', platform);

  /// Sets the consent state (GDPR/consent mode). Call `granted: false` until the
  /// user opts in via a consent banner; applies to analytics + ad storage.
  void setConsent({required bool granted}) {
    final analytics = _analytics;
    if (analytics == null) return;
    _guard(
      () => analytics.setConsent(
        analyticsStorageConsentGranted: granted,
        adStorageConsentGranted: granted,
      ),
    );
  }

  // ── Segmentation user properties ────────────────────────────────────────────

  /// Current UI theme (`light` / `dark` / `system`).
  void setTheme(String theme) => setUserProperty('theme', theme);

  /// How the current project was entered (`template` / `workspace` / `blank`).
  void setEntryMode(String mode) => setUserProperty('entry_mode', mode);

  /// The app version, so behaviour can be sliced across releases.
  void setAppVersion(String version) => setUserProperty('app_version', version);

  // ── Named feature events (the app's vocabulary) ─────────────────────────────

  /// A top-level UI action: button, menu item, toolbar control, etc.
  /// [control] identifies what was activated (e.g. `run_button`, `menu_save`).
  void action(String control, [Map<String, Object>? extra]) =>
      logEvent('ui_action', {'control': control, ...?extra});

  /// The simulation was started or stopped from the run/stop control.
  void simulationToggled({required bool started}) =>
      logEvent('simulation_toggle', {'action': started ? 'start' : 'stop'});

  /// The simulation was paused or resumed.
  void simulationPaused({required bool paused}) =>
      logEvent('simulation_pause', {'action': paused ? 'pause' : 'resume'});

  /// A bundled example template was opened.
  void templateOpened(String template) => logEvent('open_template', {'template': template});

  /// A workspace file was saved. [scope] is e.g. `current`, `as`, or `all`.
  void fileSaved(String scope) => logEvent('file_save', {'scope': scope});

  /// A layout pane/panel was toggled (left/bottom/right).
  void panelToggled(String panel) => logEvent('panel_toggle', {'panel': panel});

  /// The user navigated to a [screen] (a normalized name like `editor`,
  /// `canvas`, `welcome` — never a file path, to avoid leaking PII). Optional
  /// [fileType] is the file extension for editor screens.
  void tabSwitched(String screen, {String? fileType}) =>
      logEvent('tab_switch', {'screen': screen, 'file_type': ?fileType});

  /// The outcome of a compile+launch attempt (the app's core action).
  void compileResult({
    required bool success,
    required int durationMs,
    required int errorCount,
    int? codeBytes,
    String? errorType,
  }) => logEvent('compile_result', {
    // Firebase params must be String/num, so the boolean is encoded as 0/1.
    'success': success ? 1 : 0,
    'duration_ms': durationMs,
    'error_count': errorCount,
    'code_bytes': ?codeBytes,
    'error_type': ?errorType,
  });

  /// A simulation run ended. [reason] is e.g. `user_stop` / `self_stop`.
  void simulationEnded(String reason) => logEvent('simulation_end', {'reason': reason});

  /// A component was placed on the canvas. [type] is the component definition id
  /// (e.g. `led`, `resistor`).
  void componentAdded(String type) => logEvent('component_added', {'type': type});

  // ── Canvas interactions ──────────────────────────────────────────────────────

  /// A canvas editing action. [action] is e.g. `undo`, `redo`, `wire_start`,
  /// `wire_complete`, `wire_cancel`, `component_delete`, `component_rotate`,
  /// `component_flip`, `zoom_in`, `zoom_out`, `grid_toggle`.
  void canvasAction(String action) => logEvent('canvas_action', {'action': action});

  // ── File operations ──────────────────────────────────────────────────────────

  /// A new file was created. [extension] is the file extension without the dot.
  void fileCreated(String extension) => logEvent('file_create', {'extension': extension});

  /// A file was deleted. [extension] is the file extension without the dot.
  void fileDeleted(String extension) => logEvent('file_delete', {'extension': extension});

  /// A file was renamed from [oldExtension] to [newExtension].
  void fileRenamed(String oldExtension, String newExtension) =>
      logEvent('file_rename', {'old_ext': oldExtension, 'new_ext': newExtension});

  /// A file or project was duplicated.
  void fileDuplicated() => logEvent('file_duplicate');

  // ── Circuit diagnostics ──────────────────────────────────────────────────────

  /// A circuit validation error was detected (e.g. short circuit, reversed LED).
  /// [type] is the error category (e.g. `short_circuit`, `led_reversed`).
  void circuitError(String type) => logEvent('circuit_error', {'type': type});

  // ── Serial monitor ───────────────────────────────────────────────────────────

  /// The user sent input through the serial monitor (not the simulation itself).
  void serialInputSent() => logEvent('serial_input');

  // ── Feedback ─────────────────────────────────────────────────────────────────

  /// User feedback was submitted via the feedback dialog.
  void feedbackSent() => logEvent('feedback_sent');

  void _guard(Future<void> Function() call) {
    // Analytics failures (offline, quota, transport) must not surface to the UI.
    unawaited(
      call().catchError((Object e, StackTrace st) {
        talker.warning('Analytics event failed: $e');
      }),
    );
  }
}
