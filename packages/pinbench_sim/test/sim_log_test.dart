import 'package:flutter/foundation.dart';
import 'package:pinbench_sim/core/sim_log.dart';
import 'package:flutter_test/flutter_test.dart';

/// The simulation's logging port.
///
/// It exists so the engine carries no logging framework — seven files used to
/// reach into the app for `talker_flutter`. The property that matters is the
/// *fallback*: the engine also runs in a background isolate, where a sink
/// installed in `main()` does not exist, so an unrouted error must still go
/// somewhere rather than vanish.
void main() {
  tearDown(() => SimLog.sink = null);

  test('records reach an installed sink with their level and category intact', () {
    final seen = <SimLogRecord>[];
    SimLog.sink = seen.add;

    const log = SimLog('app.simulation.test');
    log.trace('t');
    log.debug('d');
    log.info('i');
    log.warning('w');
    log.error('e');

    expect(seen.map((r) => r.level), [
      SimLogLevel.trace,
      SimLogLevel.debug,
      SimLogLevel.info,
      SimLogLevel.warning,
      SimLogLevel.error,
    ]);
    expect(seen.every((r) => r.category == 'app.simulation.test'), isTrue);
  });

  test('an error carries its cause and stack through', () {
    SimLogRecord? seen;
    SimLog.sink = (r) => seen = r;

    final cause = StateError('boom');
    final stack = StackTrace.current;
    const SimLog('x').error('failed', error: cause, stackTrace: stack);

    expect(seen!.error, same(cause));
    expect(seen!.stackTrace, same(stack));
  });

  group('with no sink — the background isolate case', () {
    test('an error still reaches FlutterError rather than vanishing', () {
      final reported = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = reported.add;
      addTearDown(() => FlutterError.onError = previous);

      final cause = StateError('boom');
      const SimLog('app.simulation.spice').error('op failed', error: cause);

      expect(reported, hasLength(1));
      expect(reported.single.exception, same(cause));
      expect(reported.single.library, 'simulation');
      expect(
        reported.single.context.toString(),
        contains('app.simulation.spice'),
        reason: 'the category should survive into the report',
      );
    });

    test('an error with no cause still reports its message', () {
      final reported = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = reported.add;
      addTearDown(() => FlutterError.onError = previous);

      const SimLog('x').error('something went wrong');
      expect(reported.single.exception, 'something went wrong');
    });

    test('everything below error is dropped, not reported', () {
      // Deliberate: a trace nobody can read is not worth an isolate message,
      // and routing them all through FlutterError would flood crash reporting.
      final reported = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = reported.add;
      addTearDown(() => FlutterError.onError = previous);

      const log = SimLog('x');
      log
        ..trace('t')
        ..debug('d')
        ..info('i')
        ..warning('w');
      expect(reported, isEmpty);
    });
  });
}
