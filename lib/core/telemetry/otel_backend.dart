// Selects the OpenTelemetry backend at compile time.
//
// `dartastic_opentelemetry`'s OTLP exporters import `dart:io`, so they can only
// compile for native targets. Native builds use the real backend; the web (and
// wasm) build overrides to the stub, which never references the package —
// keeping `dart:io` out of the web compilation (native default, web
// override).
//
// Both variants expose `Future<TracingService> initOpenTelemetry(OtelConfig)`.
export 'otel_backend_io.dart' if (dart.library.js_interop) 'otel_backend_stub.dart';
