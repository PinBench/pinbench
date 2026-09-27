import 'package:flutter/foundation.dart';

/// Which Firebase telemetry SDKs are usable on the current platform.
///
/// The Firebase Flutter SDKs don't cover every target this app builds for:
/// desktop Windows/Linux have no Firebase support at all, Crashlytics has no web
/// implementation, and Performance Monitoring has no macOS implementation. These
/// flags gate every telemetry call so unsupported platforms cleanly no-op
/// instead of crashing at startup.
///
/// Uses [kIsWeb] / [defaultTargetPlatform] only (no `dart:io`), so it is safe to
/// evaluate on the web.
abstract final class TelemetrySupport {
  static bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;
  static bool get _isIOS => defaultTargetPlatform == TargetPlatform.iOS;
  static bool get _isMacOS => defaultTargetPlatform == TargetPlatform.macOS;

  /// Analytics: Android, iOS, macOS, Web. (No Windows/Linux.)
  static bool get analytics => kIsWeb || _isMacOS || _isAndroid || _isIOS;

  /// Crashlytics: Android, iOS, macOS. (No Web/Windows/Linux implementation.)
  static bool get crashlytics => !kIsWeb && (_isMacOS || _isAndroid || _isIOS);

  /// Performance Monitoring: Android, iOS, Web. (No macOS/Windows/Linux
  /// implementation — `firebase_performance_web` covers the web target.)
  static bool get performance => kIsWeb || _isAndroid || _isIOS;

  /// Remote Config: Android, iOS, macOS, Web. (No Windows/Linux
  /// implementation.)
  static bool get remoteConfig => kIsWeb || _isMacOS || _isAndroid || _isIOS;

  /// Whether Firebase can be initialized at all here (any product is usable).
  /// If false, `Firebase.initializeApp` is skipped entirely.
  ///
  /// [remoteConfig] supports the same platform set as [analytics] (Android,
  /// iOS, macOS, Web), so it doesn't widen this beyond what [analytics]
  /// already covers.
  static bool get firebase => analytics || crashlytics || performance;
}
