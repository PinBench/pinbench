// Credentials are supplied via --dart-define (the standard OTEL_* mechanism), so
// String.fromEnvironment is intentional here.
// ignore_for_file: do_not_use_environment
import 'telemetry_context.dart';

/// Configuration for the OpenTelemetry (Grafana Cloud) exporter.
///
/// Values come from `--dart-define`s at build/run time so credentials never live
/// in the repo (mirrors the standard `OTEL_*` env-var names):
///
/// ```sh
/// flutter run \
///   --dart-define=OTEL_EXPORTER_OTLP_ENDPOINT=https://otlp-gateway-<region>.grafana.net/otlp \
///   --dart-define=OTEL_EXPORTER_OTLP_HEADERS='Authorization=Basic <base64(instanceId:token)>'
/// ```
///
/// If the endpoint is empty (no dart-define), OpenTelemetry stays disabled and
/// the app uses the no-op tracing backend — same "dormant until configured"
/// behaviour as Firebase's placeholder options.
class OtelConfig {
  const OtelConfig({
    required this.endpoint,
    required this.headers,
    required this.serviceName,
    required this.serviceVersion,
    required this.platform,
  });

  /// Builds config from `--dart-define` values. [platform] is a coarse label
  /// (e.g. `macos`, `windows`) recorded as a resource attribute.
  factory OtelConfig.fromEnvironment({
    required String platform,
    String serviceVersion = appVersion,
  }) {
    const endpoint = String.fromEnvironment('OTEL_EXPORTER_OTLP_ENDPOINT');
    const rawHeaders = String.fromEnvironment('OTEL_EXPORTER_OTLP_HEADERS');
    const serviceName = String.fromEnvironment('OTEL_SERVICE_NAME', defaultValue: 'pinbench');
    return OtelConfig(
      endpoint: endpoint,
      headers: _parseHeaders(rawHeaders),
      serviceName: serviceName,
      serviceVersion: serviceVersion,
      platform: platform,
    );
  }

  /// OTLP HTTP endpoint (e.g. Grafana Cloud `.../otlp`).
  final String endpoint;

  /// Exporter headers (typically `Authorization`).
  final Map<String, String> headers;

  final String serviceName;
  final String serviceVersion;

  /// Coarse run-platform label, recorded as a resource attribute.
  final String platform;

  /// Whether an endpoint was supplied; if false, telemetry stays disabled.
  bool get isConfigured => endpoint.isNotEmpty;

  /// Parses the OTLP header spec: comma-separated `key=value` pairs, e.g.
  /// `Authorization=Basic abc,x-scope-orgid=123`.
  static Map<String, String> _parseHeaders(String raw) {
    final headers = <String, String>{};
    if (raw.isEmpty) return headers;
    for (final pair in raw.split(',')) {
      final eq = pair.indexOf('=');
      if (eq <= 0) continue;
      final key = pair.substring(0, eq).trim();
      final value = pair.substring(eq + 1).trim();
      if (key.isNotEmpty) headers[key] = value;
    }
    return headers;
  }
}
