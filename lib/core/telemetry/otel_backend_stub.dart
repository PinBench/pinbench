import 'otel_config.dart';
import 'tracing_service.dart';

/// Web/wasm stub: OpenTelemetry's OTLP exporters need `dart:io`, so there is no
/// export on the web. Web telemetry is covered by Firebase (Analytics +
/// Performance); this returns the no-op tracer so shared call sites just work.
Future<TracingService> initOpenTelemetry(OtelConfig config) async =>
    const TracingService.disabled();
