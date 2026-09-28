import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/shared_preferences_provider.dart';

/// Whether the user agreed to share usage statistics and crash reports.
///
/// [unknown] until they are asked, and nothing is collected while it is: the
/// app asks once (on the welcome screen), and Settings can change the answer.
enum TelemetryConsent { unknown, granted, denied }

const _prefsKey = 'telemetry.consent';

/// The stored answer. Read at startup, before telemetry is initialised, so the
/// SDKs start with collection already in the right state.
TelemetryConsent readTelemetryConsent(SharedPreferences prefs) =>
    switch (prefs.getString(_prefsKey)) {
      'granted' => TelemetryConsent.granted,
      'denied' => TelemetryConsent.denied,
      _ => TelemetryConsent.unknown,
    };

/// What the consent UI can ask of telemetry.
abstract interface class TelemetryControl {
  /// Whether this build has telemetry at all. A build from source does not,
  /// and then there is nothing to ask about and no consent UI.
  bool get available;

  /// The policy the consent UI links to, when [available].
  String? get privacyPolicyUrl;

  /// Turns collection on or off in every telemetry SDK, now.
  void applyConsent({required bool granted});
}

/// [TelemetryControl] for a build with no telemetry.
class NoTelemetry implements TelemetryControl {
  const NoTelemetry();

  @override
  bool get available => false;

  @override
  String? get privacyPolicyUrl => null;

  @override
  void applyConsent({required bool granted}) {}
}

/// Overridden in `app/bootstrap.dart` with the live telemetry's control.
final telemetryControlProvider = Provider<TelemetryControl>((ref) => const NoTelemetry());

/// The user's answer, persisted, and applied to the SDKs as it changes.
final telemetryConsentProvider = NotifierProvider<TelemetryConsentController, TelemetryConsent>(
  TelemetryConsentController.new,
);

class TelemetryConsentController extends Notifier<TelemetryConsent> {
  @override
  TelemetryConsent build() => readTelemetryConsent(ref.read(sharedPreferencesProvider));

  /// Records the answer and applies it immediately.
  Future<void> choose({required bool granted}) async {
    state = granted ? TelemetryConsent.granted : TelemetryConsent.denied;
    ref.read(telemetryControlProvider).applyConsent(granted: granted);
    await ref.read(sharedPreferencesProvider).setString(_prefsKey, state.name);
  }
}
