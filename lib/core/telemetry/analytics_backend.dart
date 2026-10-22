import 'package:firebase_analytics/firebase_analytics.dart';

/// Where an `AnalyticsService` sends: the Firebase SDK where there is one, and
/// the Measurement Protocol on Windows and Linux, where there is not (see
/// `measurement_protocol.dart`). Both land in the same Google Analytics
/// property, so users on every platform are counted together.
abstract interface class AnalyticsBackend {
  Future<void> logEvent(String name, Map<String, Object>? params);

  Future<void> logScreenView(String screenName);

  Future<void> setUserProperty(String name, String value);

  /// Consent mode. Ad storage is always denied: the app shows no ads.
  Future<void> setConsent({required bool granted});

  /// Sends anything buffered. Called before the app exits.
  Future<void> flush();
}

/// [AnalyticsBackend] over the Firebase Analytics SDK.
class const FirebaseAnalyticsBackend(final FirebaseAnalytics _analytics)
    implements AnalyticsBackend {
  @override
  Future<void> logEvent(String name, Map<String, Object>? params) =>
      _analytics.logEvent(name: name, parameters: params);

  @override
  Future<void> logScreenView(String screenName) => _analytics.logScreenView(screenName: screenName);

  @override
  Future<void> setUserProperty(String name, String value) =>
      _analytics.setUserProperty(name: name, value: value);

  @override
  Future<void> setConsent({required bool granted}) => _analytics.setConsent(
    analyticsStorageConsentGranted: granted,
    adStorageConsentGranted: false,
    adUserDataConsentGranted: false,
    adPersonalizationSignalsConsentGranted: false,
  );

  /// The SDK batches and sends on its own, and persists what it has not sent.
  @override
  Future<void> flush() async {}
}
