import 'package:firebase_remote_config/firebase_remote_config.dart';

import '../telemetry/telemetry_support.dart';
import '../utils/logger.dart';
import 'feature_flags.dart';

/// Fetches and activates Firebase Remote Config, returning the resulting
/// [FeatureFlags]. Best-effort like the rest of `app/bootstrap.dart`: on an
/// unsupported platform, or if the fetch fails (offline, throttled, no
/// Firebase project configured), this returns [FeatureFlags.disabled] and the
/// app runs with every placeholder feature hidden — exactly as before this
/// existed. [firebaseReady] is whether `setupFirebase()` initialised Firebase —
/// a build without telemetry never does, and Remote Config cannot run then.
Future<FeatureFlags> setupRemoteConfig({required bool firebaseReady}) async {
  if (!firebaseReady || !TelemetrySupport.remoteConfig) return const FeatureFlags.disabled();

  try {
    final remoteConfig = FirebaseRemoteConfig.instance;
    await remoteConfig.setConfigSettings(
      RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 10),
        // Placeholder flags change rarely; a short interval just wastes
        // fetches. Force a fresh fetch during development with
        // `remoteConfig.setConfigSettings` set to `Duration.zero` locally if
        // you need to see a change immediately.
        minimumFetchInterval: const Duration(hours: 1),
      ),
    );
    await remoteConfig.setDefaults(RemoteFeatureFlags.defaults);
    await remoteConfig.fetchAndActivate();
    return RemoteFeatureFlags(remoteConfig);
  } catch (e) {
    talker.warning('Remote Config disabled (init skipped): $e');
    return const FeatureFlags.disabled();
  }
}
