import 'package:flutter/foundation.dart';

/// How much a [CloudLogRecord] matters.
enum CloudLogLevel() {
  info,
  warning,
  error,
}

/// One diagnostic from the cloud backend.
@immutable
class const CloudLogRecord({
  required final CloudLogLevel level,

  /// Dotted source, e.g. `app.cloud`.
  required final String category,
  required final String message,
  final Object? error,
  final StackTrace? stackTrace,
}) {
  @override
  String toString() => '[$category] $message${error == null ? '' : ' — $error'}';
}

/// Where this package's diagnostics go.
typedef CloudLogSink = void Function(CloudLogRecord record);

/// The cloud backend's logger, and the seam that keeps a logging framework out
/// of it.
///
/// These files used to call the app's `AppLogger`, which meant reaching into
/// `talker_flutter` from what is otherwise plain Dart around an SDK. Levels,
/// categories and stack traces still travel; the host just decides where they
/// land, and installs a [sink] in `app/bootstrap.dart`.
///
/// **Errors are never silently dropped.** With no sink installed they go to
/// `FlutterError.reportError`, which the app already chains to both its logger
/// and Crashlytics. Anything below an error is dropped in that case, which is
/// the right trade for a diagnostic nobody is listening to.
///
/// This is the second copy of a shape `pinbench_sim`'s `SimLog` already has. Two is
/// tolerable and three is not: if a third package needs it, the answer is a
/// shared `pinbench_log` rather than another of these.
class const CloudLog(final String category) {
  /// Installed once by the host. Null in tests.
  static CloudLogSink? sink;

  void info(String message) => _emit(CloudLogLevel.info, message);
  void warning(String message) => _emit(CloudLogLevel.warning, message);

  void error(String message, {Object? error, StackTrace? stackTrace}) =>
      _emit(CloudLogLevel.error, message, error: error, stackTrace: stackTrace);

  void _emit(CloudLogLevel level, String message, {Object? error, StackTrace? stackTrace}) {
    final record = CloudLogRecord(
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

    if (level == CloudLogLevel.error) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error ?? message,
          stack: stackTrace,
          library: 'cloud',
          context: ErrorDescription(record.toString()),
        ),
      );
    }
  }
}
