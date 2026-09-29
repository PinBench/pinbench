import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pinbench/core/telemetry/analytics_milestones.dart';
import 'package:pinbench/core/telemetry/analytics_service.dart';
import 'package:pinbench/core/telemetry/consent_gated_tracing.dart';
import 'package:pinbench/core/telemetry/telemetry_consent.dart';
import 'package:pinbench/core/telemetry/tracing_service.dart';

/// Counts what reached the real tracing backend.
class _RecordingTracing implements TracingService {
  var spans = 0;
  var errors = 0;
  var metrics = 0;
  var flushes = 0;

  @override
  bool get enabled => true;

  @override
  Future<T> trace<T>(
    String name,
    Future<T> Function() body, {
    Map<String, Object>? attributes,
    TraceKind kind = TraceKind.internal,
  }) {
    spans++;
    return body();
  }

  @override
  Future<T> traceRequest<T>(
    String name,
    Future<T> Function(Map<String, String> traceHeaders) body, {
    Map<String, Object>? attributes,
  }) {
    spans++;
    return body(const {'traceparent': 'x'});
  }

  @override
  void recordError(Object error, StackTrace? stackTrace, {bool fatal = false}) => errors++;

  @override
  void gauge(String name, num value, {Map<String, Object>? attributes}) => metrics++;

  @override
  void increment(String name, {int by = 1, Map<String, Object>? attributes}) => metrics++;

  @override
  Future<void> flush() async => flushes++;
}

class _Control({@override required final bool available, @override final String? privacyPolicyUrl})
    implements TelemetryControl {
  final applied = <bool>[];

  @override
  void applyConsent({required bool granted}) => applied.add(granted);
}

void main() {
  group('tracing', () {
    test('records nothing without consent, but the traced work still runs', () async {
      final inner = _RecordingTracing();
      final tracing = ConsentGatedTracing(inner, granted: false);

      expect(await tracing.trace('op', () async => 42), 42);
      expect(await tracing.traceRequest('req', (headers) async => headers), isEmpty);
      tracing
        ..recordError(StateError('x'), null)
        ..gauge('fps', 60)
        ..increment('runs');

      expect(tracing.enabled, isFalse);
      expect((inner.spans, inner.errors, inner.metrics), (0, 0, 0));
    });

    test('withdrawing consent stops recording at once', () async {
      final inner = _RecordingTracing();
      final tracing = ConsentGatedTracing(inner, granted: true);
      await tracing.trace('before', () async {});

      tracing.applyConsent(granted: false);
      await tracing.trace('after', () async {});
      tracing.recordError(StateError('x'), null);

      expect(inner.spans, 1);
      expect(inner.errors, 0);
    });
  });

  group('combined control', () {
    test('is available if any backend is, and switches every one', () {
      final firebase = _Control(available: false);
      final otel = _Control(available: true, privacyPolicyUrl: 'https://example.com/p');
      final combined = CombinedTelemetryControl([firebase, otel])..applyConsent(granted: true);

      expect(combined.available, isTrue);
      expect(combined.privacyPolicyUrl, 'https://example.com/p');
      expect(firebase.applied, [true]);
      expect(otel.applied, [true]);
    });
  });

  group('analytics', () {
    test('a switchable service is off until something fills its slot', () {
      expect(AnalyticsService.switchable(AnalyticsSlot()).enabled, isFalse);
    });

    test('a milestone reached while analytics is off stays unfired', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      Milestones(prefs, AnalyticsService.switchable(AnalyticsSlot())).fireOnce('first_run');

      expect(prefs.getBool('milestone.first_run'), isNull);
    });
  });
}
