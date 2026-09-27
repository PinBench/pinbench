/// Platform-neutral tracing/metrics facade backed by OpenTelemetry on native
/// platforms and a no-op everywhere else (see `otel_backend.dart`).
///
/// This file deliberately imports **no** OpenTelemetry code so it is safe to
/// reference from any platform, including web/wasm (the `dartastic_opentelemetry`
/// OTLP exporters import `dart:io` and can't compile for the web). Call sites
/// depend only on this interface; the concrete OTel implementation is swapped in
/// via conditional import and provider override.
library;

/// The span roles we expose, mapped to OTel `SpanKind` in the native backend.
enum TraceKind { internal, client, server }

/// Records traces and metrics. Obtain via `tracingProvider`.
abstract interface class TracingService {
  /// A no-op instance: every method does nothing. Used as the provider default,
  /// on the web, and whenever OpenTelemetry isn't configured.
  const factory TracingService.disabled() = _DisabledTracingService;

  /// Whether telemetry is actually being recorded/exported.
  bool get enabled;

  /// Runs [body] inside a span named [name], recording exceptions and ending the
  /// span when it completes. Returns whatever [body] returns.
  Future<T> trace<T>(
    String name,
    Future<T> Function() body, {
    Map<String, Object>? attributes,
    TraceKind kind,
  });

  /// Like [trace] but passes W3C trace-context headers (`traceparent`) for an
  /// outbound request, so a remote service can continue the same distributed
  /// trace. On the disabled backend the map is empty.
  Future<T> traceRequest<T>(
    String name,
    Future<T> Function(Map<String, String> traceHeaders) body, {
    Map<String, Object>? attributes,
  });

  /// Records an error against the active span (or a standalone error span).
  void recordError(Object error, StackTrace? stackTrace, {bool fatal});

  /// Records a gauge sample (last-value metric), e.g. current FPS.
  void gauge(String name, num value, {Map<String, Object>? attributes});

  /// Increments a counter metric, e.g. simulation runs.
  void increment(String name, {int by, Map<String, Object>? attributes});

  /// Flushes buffered telemetry (best-effort; e.g. before shutdown).
  Future<void> flush();
}

/// No-op implementation — see [TracingService.disabled].
class _DisabledTracingService implements TracingService {
  const _DisabledTracingService();

  @override
  bool get enabled => false;

  @override
  Future<T> trace<T>(
    String name,
    Future<T> Function() body, {
    Map<String, Object>? attributes,
    TraceKind kind = TraceKind.internal,
  }) => body();

  @override
  Future<T> traceRequest<T>(
    String name,
    Future<T> Function(Map<String, String> traceHeaders) body, {
    Map<String, Object>? attributes,
  }) => body(const {});

  @override
  void recordError(Object error, StackTrace? stackTrace, {bool fatal = false}) {}

  @override
  void gauge(String name, num value, {Map<String, Object>? attributes}) {}

  @override
  void increment(String name, {int by = 1, Map<String, Object>? attributes}) {}

  @override
  Future<void> flush() async {}
}
