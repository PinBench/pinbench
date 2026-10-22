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
  /// remote config belong to. Null on a platform Firebase has no SDK for.
  final FirebaseOptions? firebase,

  /// Where analytics goes on Windows and Linux, which have no Firebase SDK:
  /// the same Google Analytics property, reached over the Measurement
  /// Protocol. Null leaves those platforms without analytics.
  final MeasurementProtocolConfig? measurementProtocol,

  /// Linked wherever the app asks for consent.
  required final String privacyPolicyUrl,
});

/// A Google Analytics 4 web data stream that takes events over the
/// Measurement Protocol.
@immutable
class const MeasurementProtocolConfig({
  /// The stream's measurement ID, `G-…`.
  required final String measurementId,

  /// A Measurement Protocol API secret created on that stream (Admin ▸ Data
  /// streams ▸ the stream ▸ Measurement Protocol API secrets).
  required final String apiSecret,
});
