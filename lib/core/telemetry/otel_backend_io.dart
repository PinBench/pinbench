import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';

import '../utils/logger.dart';
import 'otel_config.dart';
import 'tracing_service.dart';

/// Native OpenTelemetry backend. Exports traces + metrics over OTLP/HTTP to the
/// configured endpoint (Grafana Cloud). Returns a no-op service when the
/// endpoint isn't configured or initialization fails, so startup is never
/// blocked by telemetry.
Future<TracingService> initOpenTelemetry(OtelConfig config) async {
  if (!config.isConfigured) return const TracingService.disabled();

  try {
    await OTel.initialize(
      serviceName: config.serviceName,
      serviceVersion: config.serviceVersion,
      endpoint: config.endpoint,
      resourceAttributes: OTel.attributesFromMap({'run.platform': config.platform}),
      spanProcessor: BatchSpanProcessor(
        OtlpHttpSpanExporter(
          OtlpHttpExporterConfig(
            endpoint: config.endpoint,
            headers: config.headers,
            compression: true,
          ),
        ),
      ),
      metricExporter: OtlpHttpMetricExporter(
        OtlpHttpMetricExporterConfig(
          endpoint: config.endpoint,
          headers: config.headers,
          compression: true,
        ),
      ),
    );
    return _OtelTracingService(OTel.tracer(), OTel.meter());
  } catch (e) {
    talker.warning('OpenTelemetry init failed; tracing disabled: $e');
    return const TracingService.disabled();
  }
}

class _OtelTracingService implements TracingService {
  _OtelTracingService(this._tracer, this._meter);

  final Tracer _tracer;
  final Meter _meter;

  // Instruments are created lazily and reused (OTel expects one per name).
  // `createCounter`/`createGauge` are statically typed as the (non-exported)
  // API interfaces but return the concrete SDK instruments, so we cast.
  final _counters = <String, Counter<int>>{};
  final _gauges = <String, Gauge<double>>{};

  @override
  bool get enabled => true;

  @override
  Future<T> trace<T>(
    String name,
    Future<T> Function() body, {
    Map<String, Object>? attributes,
    TraceKind kind = TraceKind.internal,
  }) async {
    final span = _tracer.startSpan(name, kind: _spanKind(kind), attributes: _attrs(attributes));
    try {
      final result = await body();
      span.end();
      return result;
    } catch (e, st) {
      span
        ..recordException(e, stackTrace: st)
        ..setStatus(SpanStatusCode.Error, e.toString())
        ..end();
      rethrow;
    }
  }

  @override
  Future<T> traceRequest<T>(
    String name,
    Future<T> Function(Map<String, String> traceHeaders) body, {
    Map<String, Object>? attributes,
  }) async {
    final span = _tracer.startSpan(name, kind: SpanKind.client, attributes: _attrs(attributes));
    try {
      final result = await body(_traceHeaders(span));
      span.end();
      return result;
    } catch (e, st) {
      span
        ..recordException(e, stackTrace: st)
        ..setStatus(SpanStatusCode.Error, e.toString())
        ..end();
      rethrow;
    }
  }

  @override
  void recordError(Object error, StackTrace? stackTrace, {bool fatal = false}) {
    final span = _tracer.startSpan('app.error', attributes: _attrs({'error.fatal': fatal}));
    span
      ..recordException(error, stackTrace: stackTrace)
      ..setStatus(SpanStatusCode.Error, error.toString())
      ..end();
  }

  @override
  void gauge(String name, num value, {Map<String, Object>? attributes}) {
    final instrument = _gauges.putIfAbsent(
      name,
      () => _meter.createGauge<double>(name: name) as Gauge<double>,
    );
    instrument.record(value.toDouble(), _attrs(attributes));
  }

  @override
  void increment(String name, {int by = 1, Map<String, Object>? attributes}) {
    final instrument = _counters.putIfAbsent(
      name,
      () => _meter.createCounter<int>(name: name) as Counter<int>,
    );
    instrument.add(by, _attrs(attributes));
  }

  @override
  Future<void> flush() async {
    try {
      await OTel.tracerProvider().forceFlush();
    } catch (e) {
      talker.warning('OpenTelemetry flush failed: $e');
    }
  }

  /// W3C `traceparent` for the given span so a remote service can continue the
  /// trace. Best-effort: any failure yields no headers rather than throwing.
  Map<String, String> _traceHeaders(Span span) {
    try {
      final ctx = span.spanContext;
      final flags = ctx.traceFlags.toString().padLeft(2, '0');
      return {'traceparent': '00-${ctx.traceId.hexString}-${ctx.spanId.hexString}-$flags'};
    } catch (_) {
      return const {};
    }
  }

  Attributes? _attrs(Map<String, Object>? attributes) =>
      attributes == null ? null : OTel.attributesFromMap(attributes);

  SpanKind _spanKind(TraceKind kind) => switch (kind) {
    TraceKind.internal => SpanKind.internal,
    TraceKind.client => SpanKind.client,
    TraceKind.server => SpanKind.server,
  };
}
