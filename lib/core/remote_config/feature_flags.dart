import 'package:firebase_remote_config/firebase_remote_config.dart';

/// Remote-controlled visibility for UI that isn't finished yet (currently the
/// title bar's global search), so a placeholder can ship hidden and be turned
/// on later without an app update.
///
/// A flag here is for *unfinished* UI. When the feature ships, delete its flag
/// rather than defaulting it on — leaving one behind means the feature is off
/// on Windows/Linux, where Remote Config does not exist at all. That is what
/// happened to the agent chat: it stayed invisible on those platforms until
/// the flag was removed.
///
/// Firebase Remote Config only exists on Android/iOS/macOS/Web; on
/// Windows/Linux and where Remote Config fails to fetch, [FeatureFlags.disabled]
/// keeps every flag off — the same "not implemented yet" behavior as before
/// this existed. Obtain via `featureFlagsProvider`.
abstract interface class FeatureFlags {
  /// All flags off — the provider default and the fallback when Remote
  /// Config is unavailable or hasn't fetched yet.
  const factory disabled() = _DisabledFeatureFlags;

  /// The title bar's global workspace search (placeholder UI, not yet
  /// implemented).
  bool get globalSearchEnabled;
}

class const _DisabledFeatureFlags() implements FeatureFlags {
  @override
  bool get globalSearchEnabled => false;
}

/// [FeatureFlags] backed by [FirebaseRemoteConfig]. Reads are synchronous —
/// values already sit in the SDK's local cache once [FirebaseRemoteConfig.activate]
/// has run during startup (see `remote_config_bootstrap.dart`) — and fall back
/// to the defaults passed to [FirebaseRemoteConfig.setDefaults] if a fetch
/// never lands.
class RemoteFeatureFlags(final FirebaseRemoteConfig _remoteConfig) implements FeatureFlags {
  static const keyGlobalSearchEnabled = 'feature_global_search_enabled';

  /// Ship every flag off by default — enabling one is an explicit decision
  /// made later from the Firebase console, not a side effect of this file.
  static const defaults = <String, Object>{keyGlobalSearchEnabled: false};

  @override
  bool get globalSearchEnabled => _remoteConfig.getBool(keyGlobalSearchEnabled);
}
