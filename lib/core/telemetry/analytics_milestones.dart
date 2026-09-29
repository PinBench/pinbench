import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import 'analytics_service.dart';

/// Fires "first time" activation events at most once per install — the raw
/// material for a GA4 activation funnel / key events (e.g.
/// `first_simulation_success`, `first_file_save`). A flag is persisted in
/// [SharedPreferences] so the event isn't re-emitted on later runs.
///
/// Obtain via `milestonesProvider` (overridden in `main`).
class Milestones {
  const new(this._prefs, this._analytics);

  /// A disabled instance (no persistence) — every call is a no-op. Used as the
  /// provider default and in tests.
  const new disabled() : _prefs = null, _analytics = const AnalyticsService.disabled();

  final SharedPreferences? _prefs;
  final AnalyticsService _analytics;

  /// Emits [milestone] as an analytics event the first time it occurs for this
  /// install; later calls are ignored.
  ///
  /// Only counted as fired when it was actually sent: a milestone reached while
  /// analytics is off (the user has not agreed, or declined) stays unfired, so
  /// it can still be reported after they agree.
  void fireOnce(String milestone) {
    final prefs = _prefs;
    if (prefs == null || !_analytics.enabled) return;
    final key = 'milestone.$milestone';
    if (prefs.getBool(key) ?? false) return;
    unawaited(prefs.setBool(key, true));
    _analytics.logEvent(milestone);
  }
}
