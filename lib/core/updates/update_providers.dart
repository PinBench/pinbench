import 'package:flutter/foundation.dart';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../utils/logger.dart';
import '../utils/shared_preferences_provider.dart';
import 'update_service.dart';
import 'update_status.dart';

part 'update_providers.g.dart';

const _log = AppLogger('core.updates');

/// The running build's `major.minor.patch`, or null before it resolves.
///
/// `PackageInfo` is a plugin call, so it is async and it is unavailable in a
/// plain `flutter test` — both of which are why this is a provider rather
/// than a constant read at the point of use.
@Riverpod(keepAlive: true)
Future<String?> appVersion(Ref ref) async {
  try {
    return (await PackageInfo.fromPlatform()).version;
  } catch (e) {
    _log.warning('could not read the app version: $e');
    return null;
  }
}

/// The platform's updater, disposed with the provider so Sparkle does not
/// keep a listener pointing at a controller that is gone.
@Riverpod(keepAlive: true)
UpdateService updateService(Ref ref) {
  final version = ref.watch(appVersionProvider).value;
  final service = UpdateService.forPlatform(defaultTargetPlatform, currentVersion: version);
  ref.onDispose(service.dispose);
  return service;
}

/// Whether the app checks for updates on its own.
///
/// Defaults to on. An update the user never hears about is the failure mode
/// that matters for a signed build people paid for — but it is a preference,
/// because "this app phoned home without asking" is a fair complaint and the
/// answer to it should be a switch rather than an argument.
@Riverpod(keepAlive: true)
class AutomaticUpdateChecks extends _$AutomaticUpdateChecks {
  static const _prefsKey = 'updates.automatic';

  @override
  bool build() => ref.read(sharedPreferencesProvider).getBool(_prefsKey) ?? true;

  Future<void> set({required bool enabled}) async {
    state = enabled;
    await ref.read(sharedPreferencesProvider).setBool(_prefsKey, enabled);
    await ref.read(updateServiceProvider).setAutomaticChecks(enabled: enabled);
  }
}

/// The state of the most recent update check, and the thing that starts one.
///
/// Nothing runs on construction: the launch-time check is kicked off by
/// `UpdateBootstrap` once the window is up, so a slow or hostile network
/// cannot sit between the user and the first frame.
@Riverpod(keepAlive: true)
class UpdateController extends _$UpdateController {
  @override
  UpdateStatus build() => const UpdateIdle();

  /// Runs a check the user asked for: shows the spinner, and reports failure
  /// rather than swallowing it.
  Future<void> checkNow() => _check(inBackground: false);

  /// The launch-time check. Silent about everything except an actual update —
  /// being told "you are up to date" every single launch is noise, and being
  /// told "the check failed" for a check nobody requested is worse.
  Future<void> checkInBackground() async {
    if (!ref.read(automaticUpdateChecksProvider)) return;
    final before = state;
    await _check(inBackground: true);
    if (state is UpdateFailed) state = before;
  }

  Future<void> _check({required bool inBackground}) async {
    final service = ref.read(updateServiceProvider);
    if (!service.isSupported) return;
    state = const UpdateChecking();
    state = await service.check(inBackground: inBackground);
  }

  /// Puts the banner away. The next check finds the same update again, which
  /// is the point — dismissing is "not now", not "never".
  void dismiss() => state = const UpdateIdle();
}
