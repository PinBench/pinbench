import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show immutable;

/// Where a build's telemetry goes, and the policy that covers it.
///
/// Supplied by an `Edition`; a build from source has none, so it initialises no
/// Firebase project and sends nothing anywhere. Even with a config, nothing is
/// collected until the user agrees — the app asks once, and Settings can change
/// the answer.
@immutable
class const TelemetryConfig({
  /// The Firebase project analytics, crash reports, performance traces and
  /// remote config belong to.
  required final FirebaseOptions firebase,

  /// Linked wherever the app asks for consent.
  required final String privacyPolicyUrl,
});
