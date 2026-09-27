import 'package:flutter/foundation.dart';

/// How much a [SimLogRecord] matters.
enum SimLogLevel { trace, debug, info, warning, error }

/// One diagnostic from the simulation.
@immutable
class SimLogRecord {
  final SimLogLevel level;

  /// Dotted source, e.g. `app.simulation.spice`.
  final String category;
  final String message;
  final Object? error;
  final StackTrace? stackTrace;

  const SimLogRecord({
    required this.level,
    required this.category,
    required this.message,
    this.error,
    this.stackTrace,
  });

  @override
  String toString() => '[$category] $message${error == null ? '' : ' — $error'}';
}

/// Where the simulation's diagnostics go.
typedef SimLogSink = void Function(SimLogRecord record);

/// The simulation's logger, and the seam that keeps a logging framework out of
/// the engine.
///
/// The engine used to call `AppLogger` directly, which meant seven files
/// reaching into the app for `talker_flutter` — the same weight the part
/// painters were carrying before `FlutterError.reportError` replaced it there.
/// This is the same fix with the structure kept: levels, categories and stack
/// traces still travel, the host just decides where they land.
///
/// **Errors are never silently dropped.** With no [sink] installed they go to
/// `FlutterError.reportError`, which the app already chains to both its logger
/// and Crashlytics. That default matters more than it looks: the engine also
/// runs inside a background isolate, and statics do not cross isolates, so a
/// sink installed in `main()` does not exist there. Anything below a warning
/// is dropped in that case, which is the right trade — a trace nobody can read
/// is not worth an isolate message.
class SimLog {
  const SimLog(this.category);

  final String category;

  /// Installed once by the host. Null in a background isolate, and in tests.
  static SimLogSink? sink;

  void trace(String message) => _emit(SimLogLevel.trace, message);
  void debug(String message) => _emit(SimLogLevel.debug, message);
  void info(String message) => _emit(SimLogLevel.info, message);
  void warning(String message) => _emit(SimLogLevel.warning, message);

  void error(String message, {Object? error, StackTrace? stackTrace}) =>
      _emit(SimLogLevel.error, message, error: error, stackTrace: stackTrace);

  void _emit(SimLogLevel level, String message, {Object? error, StackTrace? stackTrace}) {
    final record = SimLogRecord(
      level: level,
      category: category,
      message: message,
      error: error,
      stackTrace: stackTrace,
    );

    final installed = sink;
    if (installed != null) {
      installed(record);
      return;
    }

    if (level == SimLogLevel.error) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error ?? message,
          stack: stackTrace,
          library: 'simulation',
          context: ErrorDescription(record.toString()),
        ),
      );
    }
  }
}
