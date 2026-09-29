import 'telemetry_consent.dart';
import 'tracing_service.dart';

/// A [TracingService] that records and exports nothing unless the user agreed.
///
/// OpenTelemetry is started at launch only if they already had, so agreeing
/// later takes effect on the next launch; withdrawing takes effect at once —
/// this stops every span, error and metric immediately.
class ConsentGatedTracing(final TracingService _inner, {required var bool _granted})
    implements TracingService, TelemetryControl {
  // ── TelemetryControl ─────────────────────────────────────────────────────

  @override
  bool get available => true;

  @override
  String? get privacyPolicyUrl => null;

  @override
  void applyConsent({required bool granted}) => _granted = granted;

  // ── TracingService ───────────────────────────────────────────────────────

  @override
  bool get enabled => _granted && _inner.enabled;

  @override
  Future<T> trace<T>(
    String name,
    Future<T> Function() body, {
    Map<String, Object>? attributes,
    TraceKind kind = TraceKind.internal,
  }) => _granted ? _inner.trace(name, body, attributes: attributes, kind: kind) : body();

  @override
  Future<T> traceRequest<T>(
    String name,
    Future<T> Function(Map<String, String> traceHeaders) body, {
    Map<String, Object>? attributes,
  }) => _granted ? _inner.traceRequest(name, body, attributes: attributes) : body(const {});

  @override
  void recordError(Object error, StackTrace? stackTrace, {bool fatal = false}) {
    if (_granted) _inner.recordError(error, stackTrace, fatal: fatal);
  }

  @override
  void gauge(String name, num value, {Map<String, Object>? attributes}) {
    if (_granted) _inner.gauge(name, value, attributes: attributes);
  }

  @override
  void increment(String name, {int by = 1, Map<String, Object>? attributes}) {
    if (_granted) _inner.increment(name, by: by, attributes: attributes);
  }

  @override
  Future<void> flush() => _inner.flush();
}
