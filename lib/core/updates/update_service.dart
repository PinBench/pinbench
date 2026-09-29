import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:auto_updater/auto_updater.dart';
import 'package:http/http.dart' as http;

import '../utils/logger.dart';
import 'release_manifest.dart';
import 'release_version.dart';
import 'update_config.dart';
import 'update_status.dart';

const _log = AppLogger('core.updates');

/// Asks "is there a newer build?" and, where the platform can, installs it.
///
/// Three implementations behind one interface, picked by [UpdateService.forPlatform]:
/// Sparkle/WinSparkle on macOS and Windows, a manifest poll on Linux, and a
/// no-op everywhere else. The web has nothing to update — a reload *is* the
/// update — and a debug desktop build has no release to compare against.
abstract class UpdateService {
  /// Whether this build can update at all. False turns the whole feature off
  /// in the UI rather than showing a button that always says "up to date".
  bool get isSupported;

  /// Whether the platform installs updates itself, as opposed to pointing at
  /// the download page.
  bool get canInstall;

  /// Runs a check. [inBackground] suppresses the platform's own UI, so the
  /// launch-time check does not throw a Sparkle window in front of a user who
  /// did not ask for one; the app's banner speaks instead.
  Future<UpdateStatus> check({required bool inBackground});

  /// Turns the platform's own periodic check on or off. Sparkle owns the
  /// timer — reimplementing it in Dart would mean two schedules disagreeing
  /// about when they last ran.
  Future<void> setAutomaticChecks({required bool enabled});

  void dispose() {}

  /// The right service for [platform], or a disabled one where updating makes
  /// no sense. [currentVersion] is only consulted by the Linux path; Sparkle
  /// reads the bundle itself.
  static UpdateService forPlatform(TargetPlatform platform, {required String? currentVersion}) {
    if (kIsWeb) return const DisabledUpdateService();
    return switch (platform) {
      TargetPlatform.macOS || TargetPlatform.windows => SparkleUpdateService(platform),
      TargetPlatform.linux => ManifestUpdateService(currentVersion: currentVersion),
      _ => const DisabledUpdateService(),
    };
  }
}

/// The no-op: web, mobile, anywhere without a signed desktop build.
class const DisabledUpdateService() implements UpdateService {
  @override
  bool get isSupported => false;

  @override
  bool get canInstall => false;

  @override
  Future<UpdateStatus> check({required bool inBackground}) async => const UpdateIdle();

  @override
  Future<void> setAutomaticChecks({required bool enabled}) async {}

  @override
  void dispose() {}
}

/// macOS and Windows, via Sparkle and WinSparkle respectively.
///
/// The native side owns the whole update: it fetches the appcast, compares
/// versions against the bundle, verifies the signature, downloads, and swaps
/// the app on quit. This class exists to start it and to translate its
/// callbacks into an [UpdateStatus] the app's own UI can render — the point
/// being that "an update is ready" should be visible in the app's language,
/// not only in Sparkle's window.
class SparkleUpdateService(final TargetPlatform platform)
    with UpdaterListener
    implements UpdateService {
  this {
    autoUpdater.addListener(this);
  }

  /// Completed by whichever callback resolves the in-flight check. Sparkle's
  /// `checkForUpdates` future returns as soon as the native call is *made*,
  /// not when the answer arrives, so the result has to come from the events.
  Completer<UpdateStatus>? _pending;

  var _feedConfigured = false;

  @override
  bool get isSupported => UpdateConfig.appcastUrlFor(platform) != null;

  @override
  bool get canInstall => true;

  Future<bool> _ensureFeed() async {
    if (_feedConfigured) return true;
    final url = UpdateConfig.appcastUrlFor(platform);
    if (url == null) return false;
    try {
      await autoUpdater.setFeedURL(url);
      _feedConfigured = true;
      _log.info('appcast feed set to $url');
      return true;
    } catch (e, s) {
      // A missing plugin implementation is the expected failure in a debug
      // build on a machine where the native side was never built — worth a
      // log line, not worth a crash.
      _log.error('could not set the appcast feed', error: e, stackTrace: s);
      return false;
    }
  }

  @override
  Future<UpdateStatus> check({required bool inBackground}) async {
    if (!await _ensureFeed()) {
      return const UpdateFailed('The updater is not available in this build.');
    }
    // A second press while a check is running joins the first rather than
    // starting a race whose two answers would overwrite each other.
    final existing = _pending;
    if (existing != null) return existing.future;

    final completer = Completer<UpdateStatus>();
    _pending = completer;
    try {
      await autoUpdater.checkForUpdates(inBackground: inBackground);
    } catch (e, s) {
      _log.error('update check failed to start', error: e, stackTrace: s);
      _resolve(const UpdateFailed('Could not check for updates.'));
      return completer.future;
    }

    // Sparkle is not obliged to call anything back — a network stall inside
    // the framework simply goes quiet — and a check that never resolves would
    // leave the spinner up forever.
    return completer.future.timeout(
      const Duration(seconds: 60),
      onTimeout: () {
        _pending = null;
        return const UpdateFailed('The update check timed out.');
      },
    );
  }

  void _resolve(UpdateStatus status) {
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) pending.complete(status);
  }

  @override
  Future<void> setAutomaticChecks({required bool enabled}) async {
    if (!await _ensureFeed()) return;
    try {
      await autoUpdater.setScheduledCheckInterval(
        enabled ? UpdateConfig.scheduledCheckInterval : 0,
      );
    } catch (e, s) {
      _log.error('could not change the update schedule', error: e, stackTrace: s);
    }
  }

  @override
  void onUpdaterCheckingForUpdate(Appcast? appcast) {}

  @override
  void onUpdaterUpdateAvailable(AppcastItem? appcastItem) {
    _resolve(
      UpdateAvailable(
        version: ReleaseVersion.tryParse(
          appcastItem?.displayVersionString ?? appcastItem?.versionString,
        ),
        installable: true,
        notesUrl: appcastItem?.releaseNotesURL,
      ),
    );
  }

  @override
  void onUpdaterUpdateNotAvailable(UpdaterError? error) => _resolve(UpdateUpToDate(DateTime.now()));

  @override
  void onUpdaterUpdateDownloaded(AppcastItem? appcastItem) {
    _log.info('update downloaded; it installs on quit');
  }

  @override
  void onUpdaterBeforeQuitForUpdate(AppcastItem? appcastItem) {
    _log.info('quitting to install the update');
  }

  @override
  void onUpdaterError(UpdaterError? error) {
    _log.error('updater error: ${error?.message}');
    _resolve(UpdateFailed(error?.message ?? 'The update check failed.'));
  }

  @override
  void dispose() {
    autoUpdater.removeListener(this);
    _resolve(const UpdateIdle());
  }
}

/// Linux: fetch `latest.json`, compare, and link out.
///
/// Notify-only on purpose. See `UpdateConfig.linuxManifestUrl`.
class ManifestUpdateService({
  /// The running build's version, as `CFBundleShortVersionString` and friends
  /// report it. Null when it could not be read, which disables the check —
  /// with nothing to compare against, every manifest would look newer.
  required final String? currentVersion,
  http.Client? client,
}) implements UpdateService {
  final http.Client _client = client ?? http.Client();

  @override
  bool get isSupported => ReleaseVersion.tryParse(currentVersion) != null;

  @override
  bool get canInstall => false;

  @override
  Future<UpdateStatus> check({required bool inBackground}) async {
    final current = ReleaseVersion.tryParse(currentVersion);
    if (current == null) {
      return const UpdateFailed('This build does not report a version to compare.');
    }

    final http.Response response;
    try {
      response = await _client
          .get(Uri.parse(UpdateConfig.linuxManifestUrl))
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      _log.warning('update manifest unreachable: $e');
      return const UpdateFailed('Could not reach the update server.');
    }

    if (response.statusCode != 200) {
      // A 404 is the normal state before the first release is cut, not a bug.
      _log.warning('update manifest returned HTTP ${response.statusCode}');
      return UpdateFailed('The update server returned HTTP ${response.statusCode}.');
    }

    final ReleaseManifest? manifest;
    try {
      manifest = ReleaseManifest.fromJson(jsonDecode(response.body));
    } catch (e) {
      _log.warning('update manifest could not be parsed: $e');
      return const UpdateFailed('The update server returned something unreadable.');
    }
    if (manifest == null) {
      return const UpdateFailed('The update server returned something unreadable.');
    }

    if (manifest.version <= current) return UpdateUpToDate(DateTime.now());

    return UpdateAvailable(
      version: manifest.version,
      installable: false,
      notesUrl: manifest.notesUrl,
      downloadUrl: manifest.assets['linux']?.url,
    );
  }

  @override
  Future<void> setAutomaticChecks({required bool enabled}) async {}

  @override
  void dispose() => _client.close();
}
